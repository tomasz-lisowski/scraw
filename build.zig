const std = @import("std");

// When using scraw in your project add these lines:
//
// exe.linkLibC();
// if (target.isWindows()) {
//     exe.linkSystemLibrary("winscard");
// } else if (target.isLinux()) {
//     exe.linkSystemLibrary("pcsclite");
// } else {
//     @panic("Platform unsupported.");
// }

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("scraw", .{
        .source_file = .{ .path = "src/lib.zig" },
        .dependencies = &[_]std.Build.ModuleDependency{},
    });

    const lib = b.addStaticLibrary(.{
        .name = "scraw",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const main_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_main_tests = b.addRunArtifact(main_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_main_tests.step);
}
