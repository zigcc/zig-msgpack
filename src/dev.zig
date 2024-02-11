const std = @import("std");
const msgpack = @import("msgpack.zig");

const bufferType = std.io.FixedBufferStream([]u8);

const pack = msgpack.Pack(
    *bufferType,
    *bufferType,
    bufferType.WriteError,
    bufferType.ReadError,
    bufferType.write,
    bufferType.read,
);

pub fn main() !void {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    // try p.write(.{"test"});
    //
    // std.debug.print("{any}\n", .{arr[0..write_buffer.pos]});
    // const arr1 = [_]u8{ 0x91, 0xA4, 0x74, 0x65, 0x73, 0x74 };
    // std.debug.print("{any}\n", .{arr1});

    try p.write(.{ 0, 1, msgpack.wrapStr("nvim_get_api_info"), .{} });
    const arr1 = [_]u8{
        0x94,
        0x00,
        0x01,
        0xB1,
        0x6E,
        0x76,
        0x69,
        0x6D,
        0x5F,
        0x67,
        0x65,
        0x74,
        0x5F,
        0x61,
        0x70,
        0x69,
        0x5F,
        0x69,
        0x6E,
        0x66,
        0x6F,
        0x90,
    };

    for (arr1, 0..) |value, i| {
        if (value != arr[i]) {
            std.debug.print("not eql index is {}, arr1 is {x}, arr is {x}\n", .{ i, value, arr[i] });
        }
    }

    std.debug.print("{any}\n", .{arr1});
    std.debug.print("{any}\n", .{arr[0..24]});

    std.debug.print("index is {}", .{write_buffer.pos});
}
