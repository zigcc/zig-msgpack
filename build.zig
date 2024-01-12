const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("msgpack", .{
        .root_source_file = .{
            .path = "src/msgpack.zig",
        },
    });

    const lib_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/uint-test.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
