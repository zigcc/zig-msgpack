const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.11.0";

const current_zig = builtin.zig_version;

comptime {
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        const err_msg = std.fmt.comptimePrint(
            "Your Zig version v{} does not meet the minimum build requirement of v{}",
            .{ current_zig, min_zig },
        );
        @compileError(err_msg);
    }
}

pub fn build(b: *std.Build) void {
    switch (current_zig.minor) {
        11 => version_11.build(b),
        12, 13, 14 => version_12.build(b),
        else => @compileError("unknown version!"),
    }
}

const version_11 = struct {
    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const msgpack = b.addModule("msgpack", .{
            .source_file = .{
                .path = "src/msgpack.zig",
            },
        });

        const test_step = b.step("test", "Run unit tests");

        const msgpack_unit_tests = b.addTest(.{
            .root_source_file = .{
                .path = "src/test.zig",
            },
            .target = target,
            .optimize = optimize,
        });

        msgpack_unit_tests.addModule("msgpack", msgpack);
        const run_msgpack_tests = b.addRunArtifact(msgpack_unit_tests);
        test_step.dependOn(&run_msgpack_tests.step);
    }
};

const version_12 = struct {
    const Build = std.Build;
    const Module = Build.Module;
    const OptimizeMode = std.builtin.OptimizeMode;

    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const msgpack = b.addModule("msgpack", .{
            .root_source_file = b.path(b.pathJoin(&.{ "src", "msgpack.zig" })),
        });

        generateDocs(b, optimize, target);

        const test_step = b.step("test", "Run unit tests");

        const msgpack_unit_tests = b.addTest(.{
            .root_source_file = b.path(b.pathJoin(&.{ "src", "test.zig" })),
            .target = target,
            .optimize = optimize,
        });
        msgpack_unit_tests.root_module.addImport("msgpack", msgpack);
        const run_msgpack_tests = b.addRunArtifact(msgpack_unit_tests);
        test_step.dependOn(&run_msgpack_tests.step);
    }

    fn generateDocs(b: *Build, optimize: OptimizeMode, target: Build.ResolvedTarget) void {
        const lib = b.addObject(.{
            .name = "zig-msgpack",
            .root_source_file = b.path(b.pathJoin(&.{ "src", "msgpack.zig" })),
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
};
