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

pub const build =
    if (current_zig.minor == 11)
    @import("build_11.zig").build
else
    @import("build_12.zig").build;
