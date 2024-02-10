//! MessagePack RPC implemention with zig
//! https://github.com/msgpack-rpc/msgpack-rpc

const std = @import("std");
const builtin = @import("builtin");
const msgpack = @import("msgpack");
const Allocator = std.mem.Allocator;
const net = std.net;

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

pub const TcpServer = struct {
    allocator: Allocator,
    id: u32 = 0,
    server: net.StreamServer,

    /// init TcpServer
    pub fn init(allocator: Allocator) TcpServer {
        const server = net.StreamServer.init(net.StreamServer.Options{
            .reuse_port = true,
        });

        return TcpServer{
            .allocator = allocator,
            .server = server,
        };
    }

    /// deinit
    pub fn deinit(self: *TcpServer) void {
        self.server.deinit();
    }

    pub fn listen(self: *TcpServer, address: []const u8, port: u16) !void {
        const loopback = try net.Ip4Address.parse(address, port);
        const host = net.Address{ .in = loopback };

        try self.server.listen(host);
    }
};

pub const UnixSocket = struct {
    allocator: Allocator,
    id: u32 = 0,
    stream: std.net.Stream,

    /// init to create unix socket
    /// this is only useful for unix
    pub fn init(allocator: Allocator, path: []const u8) !UnixSocket {
        const stream = try std.net.connectUnixSocket(path);

        return UnixSocket{
            .allocator = allocator,
            .stream = stream,
        };
    }
};
