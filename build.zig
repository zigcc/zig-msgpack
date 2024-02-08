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

    {
        //// build test cli
        const build_step = b.step("build_cli", "build cli test");
        const exe = b.addExecutable(.{
            .name = "msgpack_rpc",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("msgpack_rpc", msgpack_rpc);

        const install = b.addInstallArtifact(exe, .{});

        build_step.dependOn(&install.step);

        const run_exe = b.addRunArtifact(exe);

        run_exe.step.dependOn(&install.step);

        // 指定一个 step 为 run
        const run_step = b.step("run_cli", "Run the cli");

        // 指定该 step 依赖于 run_exe，即实际的运行
        run_step.dependOn(&run_exe.step);
    }
}
