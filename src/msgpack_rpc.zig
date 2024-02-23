//! MessagePack RPC implementation with zig
//! https://github.com/msgpack-rpc/msgpack-rpc

const std = @import("std");
const builtin = @import("builtin");
const msgpack = @import("msgpack.zig");
const comptimePrint = std.fmt.comptimePrint;
const wrapStr = msgpack.wrapStr;
const Allocator = std.mem.Allocator;
const net = std.net;

const streamPack = msgpack.Pack(
    net.Stream,
    net.Stream,
    net.Stream.WriteError,
    net.Stream.ReadError,
    net.Stream.write,
    net.Stream.read,
);

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

pub const TcpClient = Peer(std.net.Stream);

/// ResponseMessage for Job
const RequestMessage = struct {
    msgid: u32,
    method: []const u8,
    /// this is a buffer which store param data
    params: []const u8,
};

/// ResponseMessage for Job
const ResponseMessage = struct {
    msgid: u32,
    /// this is a buffer which store err data
    err: []const u8,
    /// this is a buffer which store result data
    result: []const u8,
};

/// NotificationMessage for Job
const NotificationMessage = struct {
    method: []const u8,
    params: []const u8,
};

/// Job for the JobQueue
const Job = union(enum) {
    request: RequestMessage,
    response: ResponseMessage,
    notification: NotificationMessage,
};

/// JobQueue
const JobQueue = std.fifo.LinearFifo(Job, .Dynamic);

/// Peer to Peer
pub fn Peer(comptime streamT: type) type {

    // TODO: whether add context ?

    // detect the declarations
    comptime {
        detectDecl(streamT, "WriteError");
        detectDecl(streamT, "ReadError");
        detectDecl(streamT, "write");
        detectDecl(streamT, "read");
    }

    // build the steamT
    const streamPackT = msgpack.Pack(
        streamT,
        streamT,
        streamT.WriteError,
        streamT.ReadError,
        streamT.write,
        streamT.read,
    );

    return struct {
        const Self = @This();

        allocator: Allocator,
        id: u32 = 0,
        stream: streamT,
        pack: streamPackT,
        job_queue: JobQueue,

        /// init
        pub fn init(allocator: Allocator, stream: streamT) Self {
            return Self{
                .allocator = allocator,
                .stream = stream,
                .pack = streamPack.init(stream, stream),
                .job_queue = JobQueue.init(allocator),
            };
        }

        /// deinit for Peer
        /// NOTE: you need to deinit stream yourself
        pub fn deinit(self: Self) void {
            self.job_queue.deinit();
        }

        // TODO:
        /// register method
        pub fn register(name: []const u8, callback: anytype) !void {
            _ = name;
            _ = callback;
        }

        // TODO:
        /// unregister method
        pub fn unregister(name: []const u8) !void {
            _ = name;
        }

        // TODO:
        /// this will call method
        fn call_method() !void {}

        // TODO:
        /// event loop
        pub fn loop(self: Self) !void {
            _ = self;
        }

        /// request
        /// https://github.com/msgpack-rpc/msgpack-rpc/blob/master/spec.md#response-message
        pub fn call(self: *Self, method: []const u8, params: anytype) !u32 {
            try self.pack.write(.{ @intFromEnum(MessageType.Request), self.id, wrapStr(method), params });
            const res: u32 = self.id;
            self.id += 1;
            return res;
        }

        /// Notification
        /// https://github.com/msgpack-rpc/msgpack-rpc/blob/master/spec.md#notification-message
        pub fn notify(self: Self, method: []const u8, params: anytype) !void {
            try self.pack.write(.{ @intFromEnum(MessageType.Notification), wrapStr(method), params });
        }

        /// Response
        /// https://github.com/msgpack-rpc/msgpack-rpc/blob/master/spec.md#response-message
        pub fn response(self: Self, id: u32, err: anytype, result: anytype) !void {
            try self.pack.write(.{ @intFromEnum(MessageType.Response), id, err, result });
        }

        /// get response
        pub fn getResponse(self: Self, comptime errorType: type, comptime resultType: type) !resultType {
            if (@typeInfo(errorType) != .Optional) {
                const err_msg = comptimePrint("errorType ({}) must be optional type!", .{errorType});
                @compileError(err_msg);
            }
            const resType = makeResTupleT(errorType, resultType);

            const res = try self.pack.read(resType, self.allocator);
            return res[3];
        }
    };
}

/// Checks whether a type contains a specified declaration
fn detectDecl(comptime T: type, comptime name: []const u8) void {
    if (!@hasDecl(T, name)) {
        @compileError(comptimePrint("sorry, type T  ({}) must have decl called {s}", .{ T, name }));
    }
}

/// make res tuple type
fn makeResTupleT(comptime errorType: type, comptime resType: type) type {
    return @Type(std.builtin.Type.Struct{
        .layout = .Auto,
        .fields = &.{
            .{
                .alignment = @alignOf(u8),
                .name = "0",
                .type = u8,
                .is_comptime = false,
                .default_value = null,
            },
            .{
                .alignment = @alignOf(u32),
                .name = "1",
                .type = u32,
                .is_comptime = false,
                .default_value = null,
            },
            .{
                .alignment = @alignOf(errorType),
                .name = "2",
                .type = errorType,
                .is_comptime = false,
                .default_value = null,
            },
            .{
                .alignment = @alignOf(resType),
                .name = "3",
                .type = resType,
                .is_comptime = false,
                .default_value = null,
            },
        },
        .decls = &.{},
        .is_tuple = true,
    });
}
