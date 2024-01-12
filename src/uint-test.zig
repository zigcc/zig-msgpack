const std = @import("std");
const msgpack = @import("msgpack.zig");
const expect = std.testing.expect;

const Buffer = msgpack.Buffer;
const packType = msgpack.MsgPack(
    Buffer,
    Buffer.ErrorSet,
    Buffer.write,
    Buffer.read,
);

test "nil write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    try p.write_nil();
    try p.read_nil();
}

test "bool write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val_1 = false;
    const test_val_2 = true;

    try p.write_bool(test_val_1);
    try p.write_bool(test_val_2);

    const val_1 = try p.read_bool();
    const val_2 = try p.read_bool();

    try expect(val_1 == test_val_1);
    try expect(val_2 == test_val_2);
}

test "pfix int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: u8 = 21;
    try p.write_uint(test_val);
    const val = try p.read_uint();

    try expect(val == test_val);
}

test "nfix int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: i8 = -6;
    try p.write_int(test_val);
    const val = try p.read_int();

    try expect(val == test_val);
}

test "u8 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: u8 = 233;
    try p.write_uint(test_val);
    const val = try p.read_uint();

    try expect(val == test_val);
}

test "i8 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: i8 = -66;
    try p.write_int(test_val);
    const val = try p.read_int();

    try expect(val == test_val);
}

test "u16 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: u16 = 0xfff;
    try p.write_uint(test_val);
    const val = try p.read_uint();

    try expect(val == test_val);
}

test "i16 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: i16 = -666;
    try p.write_int(test_val);
    const val = try p.read_int();

    try expect(val == test_val);
}

test "u32 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: u32 = 0xffff_f;
    try p.write_uint(test_val);
    const val = try p.read_uint();

    try expect(val == test_val);
}

test "i32 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: i32 = 0 - 0xffff_f;
    try p.write_int(test_val);
    const val = try p.read_int();

    try expect(val == test_val);
}

test "u64 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: u64 = 0xffff_ffff_f;
    try p.write_uint(test_val);
    const val = try p.read_uint();

    try expect(val == test_val);
}

test "i64 int write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: i64 = 0 - 0xffff_ffff_f;
    try p.write_int(test_val);
    const val = try p.read_int();

    try expect(val == test_val);
}

test "f32 write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: f32 = 3.14;
    try p.write_float(test_val);
    const val = try p.read_float();

    try expect(val == test_val);
}

test "f64 write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val: f64 = 3.5e+38;
    try p.write_float(test_val);
    const val = try p.read_float();

    try expect(val == test_val);
}
