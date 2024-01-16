//! MessagePack RPC implemention with zig
//! https://github.com/msgpack-rpc/msgpack-rpc

const MessageType = enum(u2) {
    Request = 0,
    Response = 1,
    Notification = 2,
};


