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
        const bind_pos = std.mem.indexOf(u8, line, "hl.bind") orelse continue;

        const open_paren =
            std.mem.indexOfScalarPos(u8, line, bind_pos, '(') orelse continue;

        const comma =
            std.mem.indexOfScalarPos(u8, line, open_paren + 1, ',') orelse continue;

        const shortcut_expression = trim(line[open_paren + 1 .. comma]);
        const after_comma = trim(line[comma + 1 ..]);

        // ---------- build the action string ----------
        var action: []const u8 = undefined;

        if (std.mem.indexOf(u8, after_comma, "hl.dsp.exec_cmd")) |_| {
            if (std.mem.indexOf(u8, after_comma, "exec_cmd(")) |pos| {
                const arg_start = pos + "exec_cmd(".len;
                if (try extractStringArg(allocator, after_comma[arg_start..])) |cmd| {
                    action = try std.fmt.allocPrint(allocator, "exec: {s}", .{cmd});
                } else {
                    // fallback for concatenations: ipc .. "screenshot-..."
                    const close = std.mem.indexOfScalar(u8, after_comma[arg_start..], ')') orelse after_comma.len - arg_start;
                    const expr = trim(after_comma[arg_start .. arg_start + close]);
                    action = try std.fmt.allocPrint(allocator, "exec: {s}", .{expr});
                }
            } else {
                action = try allocator.dupe(u8, "exec_cmd");
            }
        } else if (std.mem.indexOf(u8, after_comma, "send_shortcut_once")) |_| {
            // send_shortcut_once("CTRL", "b")  →  send: Ctrl + B
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
                action = try std.fmt.allocPrint(allocator, "send: {s}", .{keys.items});
            } else {
                action = try allocator.dupe(u8, "send_shortcut");
            }
        } else if (std.mem.indexOf(u8, after_comma, "hl.dsp.")) |dsp| {
            const start = dsp + "hl.dsp.".len;
            var end = start;
            while (end < after_comma.len and isIdentifierChar(after_comma[end])) : (end += 1) {}
            action = try allocator.dupe(u8, trim(after_comma[start..end]));
        } else {
            // unknown form – short preview
            const preview = if (after_comma.len > 50) after_comma[0..50] else after_comma;
            action = try std.fmt.allocPrint(allocator, "[{s}]", .{preview});
        }

        // ---------- shortcut ----------
        const shortcut = try parseShortcut(allocator, shortcut_expression, &variables);

        // Filter empty / XF86 leftovers
        if (shortcut.len == 0 or std.mem.startsWith(u8, shortcut, "XF86")) {
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

    if (args.len < 2) {
        std.debug.print("Usage: keybind_viewer <keybinds.lua>\n", .{});
        return error.InvalidArguments;
    }

    const lua_path = args[1];

    const source = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        lua_path,
        allocator,
        .limited(10 * 1024 * 1024),
    );
    defer allocator.free(source);

    var bindings = try extractKeyBindings(allocator, source);
    defer {
        for (bindings.items) |binding| {
            allocator.free(binding.shortcut);
            allocator.free(binding.action);
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
