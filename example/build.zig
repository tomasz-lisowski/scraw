const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep__scraw = b.dependency("scraw", .{});
    const mod__scraw = dep__scraw.module("scraw");

    const exe = b.addExecutable(.{
        .name = "scraw__example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "scraw", .module = mod__scraw },
            },
            .link_libc = true,
        }),
    });
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("winscard");
    } else if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("pcsclite");
    } else {
        @panic("Platform unsupported.");
    }
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);
}
