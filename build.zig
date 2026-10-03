const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    module.addIncludePath(b.path("."));

    const exe = b.addExecutable(.{
        .name = "keybind_viewer",
        .root_module = module,
    });

    module.addCSourceFiles(.{
        .files = &.{
            "gtk_shim.c",
        },
        .flags = &.{
            "-std=c11",
            "-DGTK_DISABLE_AUTOPTR_SUPPORT",
            "-DG_DISABLE_AUTOPTR_SUPPORT",
        },
    });

    module.linkSystemLibrary("gtk+-3.0", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the keybinding viewer");
    run_step.dependOn(&run_cmd.step);
}
