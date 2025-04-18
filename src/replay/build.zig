const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "replay",
        .root_source_file = b.path("./main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Setup clay dependency.
    const clay_dep = b.dependency("clay", .{
        .target = target,
        .optimize = optimize,
    });
    const clay = clay_dep.module("clay");
    exe.root_module.addImport("clay", clay);

    // Setup Raylib dep.
    const raylib = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("raylib", raylib.module("raylib"));

    const raylib_artifact = raylib.artifact("raylib");
    exe.linkLibrary(raylib_artifact);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
