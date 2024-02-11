//! MessagePack RPC implemention with zig
//! https://github.com/msgpack-rpc/msgpack-rpc

const std = @import("std");
const builtin = @import("builtin");
const msgpack = @import("msgpack.zig");
const wrapStr = msgpack.wrapStr;
const Allocator = std.mem.Allocator;
const net = std.net;

const streamPack = msgpack.Pack(net.Stream, net.Stream, net.Stream.WriteError, net.Stream.ReadError, net.Stream.write, net.Stream.read);

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

pub const TcpClient = struct {
    allocator: Allocator,
    id: u32 = 1,
    stream: net.Stream,
    pack: streamPack,

    pub fn init(allocator: Allocator, address: []const u8, port: u16) !TcpClient {
        const peer = try net.Address.parseIp4(address, port);
        const stream = try net.tcpConnectToAddress(peer);
        return TcpClient{
            .allocator = allocator,
            .stream = stream,
            .pack = streamPack.init(stream, stream),
        };
    }

    pub fn deinit(client: *TcpClient) void {
        client.stream.close();
    }

    pub fn call(client: *TcpClient, method: []const u8, params: anytype) !void {
        try client.pack.write(.{ @intFromEnum(MessageType.Request), client.id, wrapStr(method), params });
        client.id += 1;
    }
};

/// this may be merged to tcpclient
pub const UnixSocket = struct {
    allocator: Allocator,
    id: u32 = 0,
    stream: std.net.Stream,
    pack: streamPack,

    /// init to create unix socket
    /// this is only useful for unix
    pub fn init(allocator: Allocator, path: []const u8) !UnixSocket {
        const stream = try std.net.connectUnixSocket(path);

        return UnixSocket{
            .allocator = allocator,
            .stream = stream,
            .pack = streamPack.init(stream, stream),
        };
    }

    pub fn deinit(client: *UnixSocket) void {
        client.stream.close();
    }

    pub fn call(client: *UnixSocket, method: []const u8, params: anytype) !void {
        try client.pack.write(.{ @intFromEnum(MessageType.Request), client.id, wrapStr(method), params });
        client.id += 1;
    }
};
