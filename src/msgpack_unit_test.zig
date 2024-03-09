const std = @import("std");
const msgpack = @import("msgpack");
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const Payload = msgpack.Payload;

fn u8eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

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

    try p.write(Payload{ .nil = void{} });
    var val = try p.read(allocator);
    defer val.free(allocator);
}

test "bool write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val_1 = false;
    const test_val_2 = true;

    try p.write(.{ .bool = test_val_1 });
    try p.write(.{ .bool = test_val_2 });

    var val_1 = try p.read(allocator);
    defer val_1.free(allocator);

    var val_2 = try p.read(allocator);
    defer val_2.free(allocator);

    try expect(val_1.bool == test_val_1);
    try expect(val_2.bool == test_val_2);
}

test "int/uint write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val_1: u8 = 21;
    try p.write(.{ .uint = test_val_1 });
    var val_1 = try p.read(allocator);
    defer val_1.free(allocator);
    try expect(val_1.uint == test_val_1);

    const test_val_2: i8 = -6;
    try p.write(.{ .int = test_val_2 });
    var val_2 = try p.read(allocator);
    defer val_2.free(allocator);
    try expect(val_2.int == test_val_2);
}

test "float write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: f64 = 3.5e+38;
    try p.write(.{ .float = test_val });
    var val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == test_val);
}

test "str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_str = "Hello, world!";
    try p.write(.{ .str = msgpack.wrapStr(test_str) });
    var val = try p.read(allocator);
    defer val.free(allocator);
    try expect(u8eql(test_str, val.str.value()));
}

// In fact, the logic implemented by bin and str is basically the same
test "bin write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    // u8 bin
    var test_bin = "This is a string that is more than 32 bytes long.".*;
    try p.write(.{ .bin = msgpack.wrapBin(&test_bin) });
    var val_1 = try p.read(allocator);
    defer val_1.free(allocator);
    try expect(u8eql(&test_bin, val_1.bin.value()));
}

test "map write and read" {
    // TODO: made test
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );
    const str = "hello";

    var test_val_1 = Payload.mapPayload(allocator);
    var bin = [5]u8{ 1, 2, 3, 4, 5 };

    try test_val_1.mapPut("id", Payload.uintToPayload(16));
    try test_val_1.mapPut("bool", Payload.boolToPayload(true));
    try test_val_1.mapPut("float", Payload.floatToPayload(0.5));
    try test_val_1.mapPut("str", try Payload.strToPayload(str, allocator));
    try test_val_1.mapPut("bin", try Payload.binToPayload(&bin, allocator));

    var test_val_2 = Payload.mapPayload(allocator);
    try test_val_2.mapPut("kk", Payload.intToPayload(-5));

    try test_val_1.mapPut("ss", test_val_2);

    const test_val_3 = try Payload.arrPayload(5, allocator);
    for (test_val_3.arr, 0..) |*v, i| {
        v.* = Payload.uintToPayload(i);
    }

    try test_val_1.mapPut("arr", test_val_3);

    defer test_val_1.free(allocator);

    try p.write(test_val_1);

    var val = try p.read(allocator);
    defer val.free(allocator);

    try expect(val == .map);
    try expect(val.map.get("id").?.uint == 16);
    try expect(val.map.get("bool").?.bool == true);
    // Additional consideration needs
    // to be given to the precision of floating point numbers
    try expect(val.map.get("float").?.float == 0.5);
    try expect(u8eql(str, val.map.get("str").?.str.value()));
    try expect(u8eql(&bin, val.map.get("bin").?.bin.value()));
    try expect(val.map.get("ss").?.map.get("kk").?.int == -5);
    for (val.map.get("arr").?.arr, 0..) |v, i| {
        try expect(v.uint == i);
    }
}

test "array write and read" {
    // made test
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val = [5]u8{ 1, 2, 3, 4, 5 };
    var test_payload: [5]Payload = undefined;
    for (test_val, 0..) |v, i| {
        test_payload[i] = Payload{
            .uint = v,
        };
    }

    try p.write(.{ .arr = &test_payload });
    var val = try p.read(allocator);
    defer val.free(allocator);

    for (val.arr, 0..) |v, i| {
        try expect(v.uint == test_val[i]);
    }
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

    try p.write(.{ .ext = msgpack.EXT{ .type = test_type, .data = &test_data } });
    var val = try p.read(allocator);
    defer val.free(allocator);
    try expect(u8eql(&test_data, val.ext.data));
    try expect(test_type == val.ext.type);
}
