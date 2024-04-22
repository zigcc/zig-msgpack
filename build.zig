const std = @import("std");
const builtin = @import("builtin");
const build_11 = @import("build_11.zig").build;
const build_12 = @import("build_12.zig").build;
const build_13 = @import("build_13.zig").build;

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
        11 => build_11(b),
        12 => build_12(b),
        13 => build_13(b),
        else => @compileError("unknown version!"),
    }
}
