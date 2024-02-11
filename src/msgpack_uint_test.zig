const std = @import("std");
const msgpack = @import("msgpack");
const allocator = std.testing.allocator;
const expect = std.testing.expect;

const bufferType = std.io.FixedBufferStream([]u8);

const pack = msgpack.Pack(
    *bufferType,
    *bufferType,
    bufferType.WriteError,
    bufferType.ReadError,
    bufferType.write,
    bufferType.read,
);

test "nil write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    try p.write_nil();
    try p.read_nil();
}

test "bool wirte and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val_1 = false;
    const test_val_2 = true;

    try p.write(test_val_1);
    try p.write(test_val_2);

    const val_1 = try p.read(bool, allocator);
    const val_2 = try p.read(bool, allocator);

    try expect(val_1 == test_val_1);
    try expect(val_2 == test_val_2);
}

test "pfix int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: u8 = 21;
    try p.write(test_val);
    const val = try p.read(u8, allocator);

    try expect(val == test_val);
}

test "nfix int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: i8 = -6;
    try p.write(test_val);
    const val = try p.read(i8, allocator);

    try expect(val == test_val);
}

test "u8 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: u8 = 233;
    try p.write(test_val);
    const val = try p.read(u8, allocator);

    try expect(val == test_val);
}

test "i8 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: i8 = -66;
    try p.write(test_val);
    const val = try p.read(i8, allocator);

    try expect(val == test_val);
}

test "u16 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: u16 = 0xfff;
    try p.write(test_val);
    const val = try p.read(u16, allocator);

    try expect(val == test_val);
}

test "i16 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: i16 = -666;
    try p.write(test_val);
    const val = try p.read(i16, allocator);

    try expect(val == test_val);
}

test "u32 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: u32 = 0xffff_f;
    try p.write(test_val);
    const val = try p.read(u32, allocator);

    try expect(val == test_val);
}

test "i32 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: i32 = 0 - 0xffff_f;
    try p.write(test_val);
    const val = try p.read(i32, allocator);

    try expect(val == test_val);
}

test "u64 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: u64 = 0xffff_ffff_f;
    try p.write(test_val);
    const val = try p.read(u64, allocator);

    try expect(val == test_val);
}

test "i64 int write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: i64 = 0 - 0xffff_ffff_f;
    try p.write(test_val);
    const val = try p.read(i64, allocator);

    try expect(val == test_val);
}

test "f32 write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: f32 = 3.14;
    try p.write(test_val);
    const val = try p.read(f32, allocator);

    try expect(val == test_val);
}

test "f64 write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: f64 = 3.5e+38;
    try p.write(test_val);
    const val = try p.read(f64, allocator);

    try expect(val == test_val);
}

test "fix_str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_str = "Hello, world!";
    const test_val = msgpack.wrapStr(test_str);
    try p.write(test_val);
    const val: msgpack.Str = try p.read(msgpack.Str, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "u8 str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_str = "This is a string that is more than 32 bytes long.";
    const test_val = msgpack.wrapStr(test_str);
    try p.write(test_val);
    const val: msgpack.Str = try p.read(msgpack.Str, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "u16 str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_str = "When the zig test tool is building a test runner, only resolved test declarations are included in the build. Initially, only the given Zig source file's top-level declarations are resolved. Unless nested containers are referenced from a top-level test declaration, nested container tests will not be resolved.";
    const test_val = msgpack.wrapStr(test_str);
    try p.write(test_val);
    const val: msgpack.Str = try p.read(msgpack.Str, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "u32 str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_str = "0123456789564562";

    const test_val = msgpack.wrapStr(test_str);
    try p.write(test_val);
    const val: msgpack.Str = try p.read(msgpack.Str, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "bin8 write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_bin = "This is a string that is more than 32 bytes long.";
    const test_val = msgpack.wrapBin(@constCast(test_bin));
    try p.write(test_val);
    const val: msgpack.Bin = try p.read(msgpack.Bin, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "bin16 write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_bin = "When the zig test tool is building a test runner, only resolved test declarations are included in the build. Initially, only the given Zig source file's top-level declarations are resolved. Unless nested containers are referenced from a top-level test declaration, nested container tests will not be resolved.";
    const test_val = msgpack.wrapBin(@constCast(test_bin));
    try p.write(test_val);
    const val: msgpack.Bin = try p.read(msgpack.Bin, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "bin32 write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_bin = @as([16:0]u8, "0123456789564562".*) ** (0xfff * 2);
    const test_val = msgpack.wrapBin(@constCast(&test_bin));
    try p.write_bin(test_val);
    const val: msgpack.Bin = try p.read(msgpack.Bin, allocator);
    defer allocator.free(val.value());
    try expect(std.mem.eql(u8, test_val.value(), val.value()));
}

test "map write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const other_type = struct { kk: i8 };
    const test_type = struct { id: u8, bo: bool, float: f32, str: msgpack.Str, bin: msgpack.Bin, ss: other_type, arr: []u8 };

    const str = "hello";
    var bin = [5]u8{ 1, 2, 3, 4, 5 };
    var kkk = [5]u8{ 1, 2, 3, 4, 5 };

    const test_val = test_type{
        .id = 16,
        .bo = true,
        .float = 3.14,
        .str = msgpack.wrapStr(str),
        .bin = msgpack.wrapBin(&bin),
        .ss = .{ .kk = -5 },
        .arr = &kkk,
    };

    try p.write(test_val);
    const val = try p.read(test_type, allocator);
    defer allocator.free(val.str.value());
    defer allocator.free(val.bin.value());
    defer allocator.free(val.arr);
    try expect(std.meta.eql(val.ss, test_val.ss));
    try expect(std.mem.eql(u8, val.str.value(), test_val.str.value()));
    try expect(std.mem.eql(u8, val.bin.value(), test_val.bin.value()));
    try expect(std.mem.eql(u8, val.arr, test_val.arr));
    try expect(val.id == test_val.id);
    try expect(val.bo == test_val.bo);
    try expect(val.float == test_val.float);
}

test "slice write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val = [5]u8{ 1, 2, 3, 4, 5 };

    try p.write(&test_val);
    const val = try p.read([]u8, allocator);
    defer allocator.free(val);
    try expect(std.mem.eql(u8, &test_val, val));
}

test "array write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val = [5]u8{ 1, 2, 3, 4, 5 };

    try p.write(&test_val);
    const val: [5]u8 = try p.readNoAlloc([5]u8);
    try expect(std.mem.eql(u8, &test_val, &val));
}

test "tuple wirte and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const tuple = struct { u8, u8 };
    const test_val = tuple{ 1, 2 };

    try p.write_tuple(tuple, test_val);
    const val = try p.read_tuple(tuple, allocator);
    try expect(std.meta.eql(val, test_val));
}

test "enum write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_enum = enum { A, B, C, D };

    try p.write(test_enum.A);
    const val: test_enum = try p.read(test_enum, allocator);
    try expect(val == test_enum.A);
}

test "ext write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    var test_data = [5]u8{ 1, 2, 3, 4, 5 };
    const test_type: u8 = 1;

    try p.write(msgpack.EXT{ .type = test_type, .data = &test_data });
    const val: msgpack.EXT = try p.read(msgpack.EXT, allocator);
    defer allocator.free(val.data);
    try expect(std.mem.eql(u8, &test_data, val.data));
    try expect(test_type == val.type);
}

test "write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val = [5]u8{ 1, 2, 3, 4, 5 };

    try p.write(&test_val);
    const val = try p.read([]u8, allocator);

    defer allocator.free(val);
    try expect(std.mem.eql(u8, &test_val, val));
}

test "optional type write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: ?u8 = null;

    try p.write(test_val);
    const val = try p.read(?u8, allocator);

    try expect(val == test_val);
}

test "test" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    try p.write(.{ 0, 1, "nvim_get_api_info", .{} });
    const arr1 = [_]u8{ 0x94, 0x00, 0x01, 0xB1, 0x6E, 0x76, 0x69, 0x6D, 0x5F, 0x67, 0x65, 0x74, 0x5F, 0x61, 0x70, 0x69, 0x5F, 0x69, 0x6E, 0x66, 0x6F, 0x90 };

    try expect(std.mem.eql(u8, arr[0..arr1.len], &arr1));
}
