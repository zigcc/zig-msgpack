const std = @import("std");
const types = @import("types.zig");

const msgpack_version: u8 = 5;

allocator: std.mem.Allocator,
