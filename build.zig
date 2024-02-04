const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack = b.addModule("msgpack", .{
        .root_source_file = .{
            .path = "src/msgpack.zig",
        },
    });

    const msgpack_rpc = b.addModule("msgpack_rpc", .{
        .root_source_file = .{
            .path = "src/msgpack_rpc.zig",
        },
        .imports = &.{
            .{
                .name = "msgpack",
                .module = msgpack,
            },
        },
    });

    const test_step = b.step("test", "Run unit tests");

    const msgpack_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/msgpack_uint_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    msgpack_unit_tests.root_module.addImport("msgpack", msgpack);
    const run_msgpack_tests = b.addRunArtifact(msgpack_unit_tests);
    test_step.dependOn(&run_msgpack_tests.step);

    const msgpack_rpc_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/msgpack_rpc_unit_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    msgpack_rpc_unit_tests.root_module.addImport("msgpack_rpc", msgpack_rpc);
    const run_msgpack_rpc_tests = b.addRunArtifact(msgpack_rpc_unit_tests);
    test_step.dependOn(&run_msgpack_rpc_tests.step);
}
