const std = @import("std");

const gtk = @cImport({
    @cInclude("gtk_shim.h");
});

const KeyBinding = struct {
    shortcut: []const u8,
    action: []const u8,
};

const AppData = struct {
    text: [:0]const u8,
};

// ---------- JSON types ----------

const BindJson = struct {
    key: []const u8,
    description: []const u8,
    // options is optional and ignored for display
};

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn isIdentifierStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentifierChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isIdentifier(value: []const u8) bool {
    if (value.len == 0 or !isIdentifierStart(value[0])) return false;
    for (value[1..]) |c| {
        if (!isIdentifierChar(c)) return false;
    }
    return true;
}

fn readLuaVariables(
    allocator: std.mem.Allocator,
    source: []const u8,
) !std.StringHashMap([]const u8) {
    var variables = std.StringHashMap([]const u8).init(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const local_pos = std.mem.indexOf(u8, line, "local") orelse continue;
        const rest = trim(line[local_pos + 5 ..]);

        var name_end: usize = 0;
        while (name_end < rest.len and isIdentifierChar(rest[name_end])) {
            name_end += 1;
        }
        if (name_end == 0) continue;

        const name = rest[0..name_end];
        if (!isIdentifier(name)) continue;

        const after_name = trim(rest[name_end..]);
        if (after_name.len == 0 or after_name[0] != '=') continue;

        const expression = trim(after_name[1..]);
        if (expression.len < 2 or expression[0] != '"') continue;

        const closing_quote = std.mem.indexOfScalar(u8, expression[1..], '"') orelse continue;
        const value = expression[1 .. closing_quote + 1];

        try variables.put(
            try allocator.dupe(u8, name),
            try allocator.dupe(u8, value),
        );
    }

    return variables;
}

fn expandPart(
    allocator: std.mem.Allocator,
    part: []const u8,
    variables: *const std.StringHashMap([]const u8),
) ![]const u8 {
    const value = trim(part);

    if (variables.get(value)) |replacement| {
        return allocator.dupe(u8, replacement);
    }

    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return allocator.dupe(u8, value[1 .. value.len - 1]);
    }

    return allocator.dupe(u8, std.mem.trim(u8, value, "\"'"));
}

fn commonKeyName(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    const value = trim(key);

    var upper = try allocator.alloc(u8, value.len);
    defer allocator.free(upper);

    for (value, 0..) |c, i| {
        upper[i] = std.ascii.toUpper(c);
    }

    const result =
        if (std.mem.eql(u8, upper, "SUPER"))
            "Super"
        else if (std.mem.eql(u8, upper, "ALT") or std.mem.eql(u8, upper, "OPTION"))
            "Alt"
        else if (std.mem.eql(u8, upper, "CTRL") or std.mem.eql(u8, upper, "CONTROL"))
            "Ctrl"
        else if (std.mem.eql(u8, upper, "SHIFT"))
            "Shift"
        else if (std.mem.eql(u8, upper, "RETURN") or std.mem.eql(u8, upper, "ENTER"))
            "Enter"
        else if (std.mem.eql(u8, upper, "ESC") or std.mem.eql(u8, upper, "ESCAPE"))
            "Esc"
        else if (std.mem.eql(u8, upper, "TAB"))
            "Tab"
        else if (std.mem.eql(u8, upper, "SPACE"))
            "Space"
        else if (std.mem.eql(u8, upper, "BACKSPACE"))
            "Backspace"
        else if (std.mem.eql(u8, upper, "DELETE") or std.mem.eql(u8, upper, "DEL"))
            "Delete"
        else if (std.mem.eql(u8, upper, "UP"))
            "Up"
        else if (std.mem.eql(u8, upper, "DOWN"))
            "Down"
        else if (std.mem.eql(u8, upper, "LEFT"))
            "Left"
        else if (std.mem.eql(u8, upper, "RIGHT"))
            "Right"
        else
            value;

    return allocator.dupe(u8, result);
}

fn friendlyKeyName(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    const k = trim(raw);

    // Mouse buttons
    if (std.mem.eql(u8, k, "mouse:272") or std.mem.eql(u8, k, "mouse_left"))
        return allocator.dupe(u8, "Left Click");
    if (std.mem.eql(u8, k, "mouse:273") or std.mem.eql(u8, k, "mouse_right"))
        return allocator.dupe(u8, "Right Click");
    if (std.mem.eql(u8, k, "mouse_down"))
        return allocator.dupe(u8, "Mouse Down");
    if (std.mem.eql(u8, k, "mouse_up"))
        return allocator.dupe(u8, "Mouse Up");

    // Drop pure XF86 media keys
    if (std.mem.startsWith(u8, k, "XF86"))
        return allocator.dupe(u8, "");

    return commonKeyName(allocator, k);
}

// ---------- JSON loading ----------

fn loadBindingsFromJson(
    allocator: std.mem.Allocator,
    json_path: []const u8,
    io: std.Io, // ← add this parameter
) !std.ArrayList(KeyBinding) {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        io,
        json_path,
        allocator,
        .limited(10 * 1024 * 1024),
    );
    defer allocator.free(source);

    // Parse as an array of BindJson
    const parsed = try std.json.parseFromSlice(
        []BindJson,
        allocator,
        source,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    var bindings: std.ArrayList(KeyBinding) = .empty;

    for (parsed.value) |item| {
        const shortcut = try normalizeShortcut(allocator, item.key);
        const action = try allocator.dupe(u8, item.description);

        // Optional: skip empty shortcuts
        if (shortcut.len == 0) {
            allocator.free(shortcut);
            allocator.free(action);
            continue;
        }

        try bindings.append(allocator, .{
            .shortcut = shortcut,
            .action = action,
        });
    }

    return bindings;
}

fn bindingsAsText(
    allocator: std.mem.Allocator,
    bindings: []const KeyBinding,
) ![:0]const u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    if (bindings.len == 0) {
        try output.appendSlice(allocator, "No keybindings found.");
    } else {
        for (bindings) |binding| {
            try output.appendSlice(allocator, binding.shortcut);
            try output.appendSlice(allocator, "    →    ");
            try output.appendSlice(allocator, binding.action);
            try output.append(allocator, '\n');
        }
    }

    return try allocator.dupeZ(u8, output.items);
}

fn normalizeShortcut(
    allocator: std.mem.Allocator,
    shortcut: []const u8,
) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);

    var parts = std.mem.splitScalar(u8, shortcut, '+');
    var first = true;

    while (parts.next()) |part| {
        const key = try friendlyKeyName(allocator, part);
        defer allocator.free(key);

        if (key.len == 0) continue;

        if (!first) {
            try output.appendSlice(allocator, " + ");
        }
        try output.appendSlice(allocator, key);
        first = false;
    }

    return output.toOwnedSlice(allocator);
}

fn parseShortcut(
    allocator: std.mem.Allocator,
    expression: []const u8,
    variables: *const std.StringHashMap([]const u8),
) ![]const u8 {
    var expanded: std.ArrayList(u8) = .empty;
    defer expanded.deinit(allocator);

    var parts = std.mem.splitSequence(u8, expression, "..");
    var first = true;

    while (parts.next()) |part| {
        const value = try expandPart(allocator, part, variables);
        defer allocator.free(value);

        if (!first) {
            try expanded.appendSlice(allocator, " + ");
        }
        try expanded.appendSlice(allocator, value);
        first = false;
    }

    return normalizeShortcut(allocator, expanded.items);
}

// Helper: try to extract a quoted / long-string argument
fn extractStringArg(allocator: std.mem.Allocator, s: []const u8) !?[]const u8 {
    const t = trim(s);
    if (t.len < 2) return null;

    // "..." or '...'
    if (t[0] == '"' or t[0] == '\'') {
        const q = t[0];
        if (std.mem.indexOfScalar(u8, t[1..], q)) |end| {
            return try allocator.dupe(u8, t[1 .. end + 1]);
        }
    }
    // [[...]]
    if (std.mem.startsWith(u8, t, "[[")) {
        if (std.mem.indexOf(u8, t[2..], "]]")) |end| {
            return try allocator.dupe(u8, t[2 .. end + 2]);
        }
    }
    return null;
}

/// Find the position of the comma that separates the *description*
/// (i.e. the first comma that is not inside parentheses or a string).
fn findDescriptionComma(s: []const u8) ?usize {
    var depth: i32 = 0;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        switch (c) {
            '(' => depth += 1,
            ')' => {
                if (depth > 0) depth -= 1;
            },
            '"', '\'' => {
                // skip over the whole string literal
                const quote = c;
                i += 1;
                while (i < s.len and s[i] != quote) {
                    // handle simple escapes \" \'
                    if (s[i] == '\\' and i + 1 < s.len) i += 1;
                    i += 1;
                }
            },
            ',' => {
                if (depth == 0) return i;
            },
            else => {},
        }
    }
    return null;
}

fn extractActionFallback(
    allocator: std.mem.Allocator,
    after_comma: []const u8,
) ![]const u8 {
    if (std.mem.indexOf(u8, after_comma, "hl.dsp.exec_cmd")) |_| {
        if (std.mem.indexOf(u8, after_comma, "exec_cmd(")) |pos| {
            const arg_start = pos + "exec_cmd(".len;
            if (try extractStringArg(allocator, after_comma[arg_start..])) |cmd| {
                return try std.fmt.allocPrint(allocator, "exec: {s}", .{cmd});
            } else {
                const close = std.mem.indexOfScalar(u8, after_comma[arg_start..], ')') orelse after_comma.len - arg_start;
                const expr = trim(after_comma[arg_start .. arg_start + close]);
                return try std.fmt.allocPrint(allocator, "exec: {s}", .{expr});
            }
        } else {
            return try allocator.dupe(u8, "exec_cmd");
        }
    } else if (std.mem.indexOf(u8, after_comma, "send_shortcut_once")) |_| {
        var keys: std.ArrayList(u8) = .empty;
        defer keys.deinit(allocator);

        var search = after_comma;
        var first = true;
        while (std.mem.indexOfScalar(u8, search, '"')) |q1| {
            const after_q1 = search[q1 + 1 ..];
            if (std.mem.indexOfScalar(u8, after_q1, '"')) |q2| {
                const key = after_q1[0..q2];
                const nice = try commonKeyName(allocator, key);
                defer allocator.free(nice);

                if (!first) try keys.appendSlice(allocator, " + ");
                try keys.appendSlice(allocator, nice);
                first = false;

                search = after_q1[q2 + 1 ..];
            } else break;
        }

        if (keys.items.len > 0) {
            return try std.fmt.allocPrint(allocator, "send: {s}", .{keys.items});
        } else {
            return try allocator.dupe(u8, "send_shortcut");
        }
    } else if (std.mem.indexOf(u8, after_comma, "hl.dsp.")) |dsp| {
        const start = dsp + "hl.dsp.".len;
        var end = start;
        while (end < after_comma.len and isIdentifierChar(after_comma[end])) : (end += 1) {}
        return try allocator.dupe(u8, trim(after_comma[start..end]));
    } else {
        const preview = if (after_comma.len > 50) after_comma[0..50] else after_comma;
        return try std.fmt.allocPrint(allocator, "[{s}]", .{preview});
    }
}

fn extractKeyBindings(
    allocator: std.mem.Allocator,
    source: []const u8,
) !std.ArrayList(KeyBinding) {
    var variables = try readLuaVariables(allocator, source);
    defer {
        var iterator = variables.iterator();
        while (iterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        variables.deinit();
    }

    var bindings: std.ArrayList(KeyBinding) = .empty;

    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        // Prefer the new helper, still accept the old name
        const bind_pos =
            std.mem.indexOf(u8, line, "bindWithDescription") orelse
            std.mem.indexOf(u8, line, "hl.bind") orelse
            continue;

        const open_paren =
            std.mem.indexOfScalarPos(u8, line, bind_pos, '(') orelse continue;

        // First comma → end of shortcut expression
        const comma1 =
            std.mem.indexOfScalarPos(u8, line, open_paren + 1, ',') orelse continue;

        const shortcut_expression = trim(line[open_paren + 1 .. comma1]);
        const after_comma1 = trim(line[comma1 + 1 ..]);

        var action: []const u8 = undefined;

        if (findDescriptionComma(after_comma1)) |comma2_rel| {
            const after_comma2 = trim(after_comma1[comma2_rel + 1 ..]);

            // Description is the first string argument after that comma
            if (try extractStringArg(allocator, after_comma2)) |desc| {
                action = desc;
            } else {
                action = try extractActionFallback(allocator, after_comma1);
            }
        } else {
            // No description argument → old-style call
            action = try extractActionFallback(allocator, after_comma1);
        }

        // Try to find a second comma (description starts after it)
        if (std.mem.indexOfScalar(u8, after_comma1, ',')) |comma2_rel| {
            const after_comma2 = trim(after_comma1[comma2_rel + 1 ..]);

            // Description is the first string argument after the second comma
            if (try extractStringArg(allocator, after_comma2)) |desc| {
                action = desc; // already allocated
            } else {
                // No usable description → fall back to old logic
                action = try extractActionFallback(allocator, after_comma1);
            }
        } else {
            // No second comma at all → old-style call
            action = try extractActionFallback(allocator, after_comma1);
        }

        // ---------- shortcut ----------
        const shortcut = try parseShortcut(allocator, shortcut_expression, &variables);

        // Filter empty / XF86 leftovers (same as before)
        if (shortcut.len == 0) {
            allocator.free(shortcut);
            allocator.free(action);
            continue;
        }

        try bindings.append(allocator, .{
            .shortcut = shortcut,
            .action = action,
        });
    }

    return bindings;
}

fn activate(
    app: ?*gtk.GtkApplication,
    user_data: ?*anyopaque,
) callconv(.c) void {
    const data: *AppData = @ptrCast(@alignCast(user_data.?));

    const window = gtk.kb_create_window(app);
    const text_view = gtk.kb_create_text_view(data.text.ptr);
    const scrolled_window = gtk.kb_create_scrolled_window(text_view);

    gtk.kb_window_set_child(window, scrolled_window);
    gtk.kb_window_show(window);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const args = try init.minimal.args.toSlice(allocator);
    // optional: defer allocator.free(args);  // only if toSlice allocates

    if (args.len < 2) {
        std.debug.print("Usage: keybind_viewer <binds.json>\n", .{});
        return error.InvalidArguments;
    }

    const json_path = args[1]; // ← fixed

    var bindings = try loadBindingsFromJson(allocator, json_path, init.io);

    defer {
        for (bindings.items) |b| {
            allocator.free(b.shortcut);
            allocator.free(b.action);
        }
        bindings.deinit(allocator);
    }

    const display_text = try bindingsAsText(allocator, bindings.items);
    defer allocator.free(display_text);

    var app_data = AppData{
        .text = display_text,
    };

    const app = gtk.kb_application_new("com.example.LuaKeybindViewer");

    gtk.kb_application_connect_activate(
        app,
        @ptrCast(&activate),
        @ptrCast(&app_data),
    );

    const status = gtk.kb_application_run(app);
    gtk.kb_application_unref(app);

    if (status != 0) {
        return error.ApplicationFailed;
    }
}
