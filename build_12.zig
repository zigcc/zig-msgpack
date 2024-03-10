const std = @import("std");
const Build = std.Build;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack = b.addModule("msgpack", .{
        .root_source_file = .{
            .path = "src/msgpack.zig",
        },
    });

    const rpc = b.addModule("msgpack_rpc", .{
        .root_source_file = .{
            .path = "src/rpc.zig",
        },
        .imports = &.{
            .{
                .name = "msgpack",
                .module = msgpack,
            },
        },
    });

    generateDocs(b, optimize, target);

    const test_step = b.step("test", "Run unit tests");

    const msgpack_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/msgpack_unit_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    msgpack_unit_tests.root_module.addImport("msgpack", msgpack);
    const run_msgpack_tests = b.addRunArtifact(msgpack_unit_tests);
    test_step.dependOn(&run_msgpack_tests.step);

    const msgpack_rpc_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/rpc_unit_test.zig" },
        .target = target,
        .optimize = optimize,
    });
    msgpack_rpc_unit_tests.root_module.addImport("msgpack_rpc", rpc);
    const run_msgpack_rpc_tests = b.addRunArtifact(msgpack_rpc_unit_tests);
    test_step.dependOn(&run_msgpack_rpc_tests.step);
}

fn generateDocs(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget) void {
    const lib = b.addStaticLibrary(.{
        .name = "zig-msgpack",
        .root_source_file = .{
            .path = "src/msgpack.zig",
        },
        .target = target,
        .optimize = optimize,
    });

    const docs_step = b.step("docs", "Emit docs");

    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}
