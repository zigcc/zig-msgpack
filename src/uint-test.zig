const std = @import("std");
const msgpack = @import("msgpack.zig");
const allocator = std.testing.allocator;
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

test "fix_str write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val = "Hello, world!";
    try p.write_str(test_val);
    const val = try p.read_str(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, test_val, val));
}

test "u8 str write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val = "This is a string that is more than 32 bytes long.";
    try p.write_str(test_val);
    const val = try p.read_str(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, test_val, val));
}

test "u16 str write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val = "When the zig test tool is building a test runner, only resolved test declarations are included in the build. Initially, only the given Zig source file's top-level declarations are resolved. Unless nested containers are referenced from a top-level test declaration, nested container tests will not be resolved.";
    try p.write_str(test_val);
    const val = try p.read_str(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, test_val, val));
}

test "u32 str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var buf = Buffer{ .arr = &arr };
    const p = packType{ .context = &buf };

    const default_str = "0123456789564562";
    const test_val = @as([16:0]u8, default_str.*) ** (0xfff * 2);
    try p.write_str(&test_val);
    const val = try p.read_str(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, &test_val, val));
}

test "bin8 write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val = "This is a string that is more than 32 bytes long.";
    try p.write_bin(test_val);
    const val = try p.read_bin(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, test_val, val));
}

test "bin16 write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var buf = Buffer{ .arr = &arr };
    var p = packType{ .context = &buf };

    const test_val = "When the zig test tool is building a test runner, only resolved test declarations are included in the build. Initially, only the given Zig source file's top-level declarations are resolved. Unless nested containers are referenced from a top-level test declaration, nested container tests will not be resolved.";
    try p.write_bin(test_val);
    const val = try p.read_bin(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, test_val, val));
}

test "bin32 write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var buf = Buffer{ .arr = &arr };
    const p = packType{ .context = &buf };

    const default_str = "0123456789564562";
    const test_val = @as([16:0]u8, default_str.*) ** (0xfff * 2);
    try p.write_bin(&test_val);
    const val = try p.read_bin(allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, &test_val, val));
}
