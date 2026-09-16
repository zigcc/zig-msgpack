const std = @import("std");

const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const msgpack = b.addModule("msgpack", .{
        .root_source_file = b.path(b.pathJoin(&.{ "src", "msgpack.zig" })),
    });

    generateDocs(b, optimize, target);

    const test_step = b.step("test", "Run unit tests");

    const bench_step = b.step("bench", "Run benchmarks");

    const msgpack_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ "src", "test.zig" })),
            .target = target,
            .optimize = optimize,
        }),
    });
    msgpack_unit_tests.root_module.addImport("msgpack", msgpack);
    const run_msgpack_tests = b.addRunArtifact(msgpack_unit_tests);
    test_step.dependOn(&run_msgpack_tests.step);

    // Add benchmark executable
    const benchmark = b.addExecutable(.{
        .name = "msgpack-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ "src", "bench.zig" })),
            .target = target,
            .optimize = optimize,
        }),
    });
    benchmark.root_module.addImport("msgpack", msgpack);

    // Install benchmark binary to zig-out/bin
    b.installArtifact(benchmark);

    const run_benchmark = b.addRunArtifact(benchmark);
    bench_step.dependOn(&run_benchmark.step);
}

fn generateDocs(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget) void {
    const lib = b.addObject(.{
        .name = "zig-msgpack",
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.pathJoin(&.{ "src", "msgpack.zig" })),
            .target = target,
            .optimize = optimize,
        }),
    });

    const docs_step = b.step("docs", "Emit docs");

    const docs_install = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    docs_step.dependOn(&docs_install.step);
}
