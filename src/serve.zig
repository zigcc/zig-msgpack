const std = @import("std");
const msgpack_rpc = @import("msgpack_rpc.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) @panic("TEST FAIL");
    }
    const address = try std.net.Address.parseIp4("127.0.0.1", 9090);
    const stream = try std.net.tcpConnectToAddress(address);
    defer stream.close();

    var client = msgpack_rpc.TcpClient.init(allocator, stream);
    defer client.deinit();

    _ = try client.call("nvim_get_current_tabpage", .{});

    var arr: [1000]u8 = undefined;

    const len = try client.stream.read(&arr);
    std.debug.print("len is {any}", .{arr[0..len]});
}
