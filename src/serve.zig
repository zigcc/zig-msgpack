const std = @import("std");
const msgpack_rpc = @import("msgpack_rpc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }
    var client = try msgpack_rpc.TcpClient.init(allocator, "127.0.0.1", 9090);

    defer client.deinit();

    try client.call("nvim_get_api_info", .{});

    var arr: [1000]u8 = undefined;


    const len = try client.stream.read(&arr);
    std.debug.print("len is {any}", .{arr[0..len]});
}
