//! MessagePack RPC implemention with zig
//! https://github.com/msgpack-rpc/msgpack-rpc

const std = @import("std");
const msgpack = @import("msgpack");
const Allocator = std.mem.Allocator;

/// the types of msssage pack rpc
const MessageType = enum(u2) {
    Request = 0,
    Response = 1,
    Notification = 2,
};

const Header = struct {
    t: MessageType,
    id: ?u32,
};
