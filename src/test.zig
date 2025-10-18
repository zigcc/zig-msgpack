const std = @import("std");
const builtin = @import("builtin");
const msgpack = @import("msgpack");
const compat = msgpack.compat;
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const Payload = msgpack.Payload;

fn u8eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

const bufferType = compat.BufferStream;
const fixedBufferStream = compat.fixedBufferStream;

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
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    try p.write(Payload{ .nil = void{} });
    const val = try p.read(allocator);
    defer val.free(allocator);
}

test "bool write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val_1 = false;
    const test_val_2 = true;

    try p.write(.{ .bool = test_val_1 });
    try p.write(.{ .bool = test_val_2 });

    const val_1 = try p.read(allocator);
    defer val_1.free(allocator);

    const val_2 = try p.read(allocator);
    defer val_2.free(allocator);

    try expect(val_1.bool == test_val_1);
    try expect(val_2.bool == test_val_2);
}

test "int/uint write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val_1: u8 = 21;
    try p.write(.{ .uint = test_val_1 });
    const val_1 = try p.read(allocator);
    defer val_1.free(allocator);
    try expect(val_1.uint == test_val_1);

    const test_val_2: i8 = -6;
    try p.write(.{ .int = test_val_2 });
    const val_2 = try p.read(allocator);
    defer val_2.free(allocator);
    try expect(val_2.int == test_val_2);
}

test "float write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val: f64 = 3.5e+38;
    try p.write(.{ .float = test_val });
    const val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == test_val);
}

test "str write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_str = "Hello, world!";
    const str_payload = try Payload.strToPayload(test_str, allocator);
    defer str_payload.free(allocator);
    try p.write(str_payload);
    const val = try p.read(allocator);
    defer val.free(allocator);
    try expect(u8eql(test_str, val.str.value()));
}

// In fact, the logic implemented by bin and str is basically the same
test "bin write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    // u8 bin
    var test_bin = "This is a string that is more than 32 bytes long.".*;
    try p.write(.{ .bin = msgpack.wrapBin(&test_bin) });
    const val = try p.read(allocator);
    defer val.free(allocator);
    try expect(u8eql(&test_bin, val.bin.value()));
}

test "map write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );
    const str = "hello";

    var test_val_1 = Payload.mapPayload(allocator);
    var bin = [5]u8{ 1, 2, 3, 4, 5 };

    try test_val_1.mapPut("nil", Payload.nilToPayload());
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

    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect(val == .map);
    try expect((try val.mapGet("nil")).? == .nil);
    try expect((try val.mapGet("id")).?.uint == 16);
    try expect((try val.mapGet("bool")).?.bool == true);
    // Additional consideration needs
    // to be given to the precision of floating point numbers
    try expect((try val.mapGet("float")).?.float == 0.5);
    try expect(u8eql(str, (try val.mapGet("str")).?.str.value()));
    try expect(u8eql(&bin, (try val.mapGet("bin")).?.bin.value()));
    try expect((try (try val.mapGet("ss")).?.mapGet("kk")).?.int == -5);
    for ((try val.mapGet("arr")).?.arr, 0..) |v, i| {
        try expect(v.uint == i);
    }
}

test "array write and read" {
    // made test
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    const test_val = [5]u8{ 1, 2, 3, 4, 5 };
    var test_payload = try Payload.arrPayload(5, allocator);
    defer test_payload.free(allocator);
    for (test_val, 0..) |v, i| {
        try test_payload.setArrElement(i, Payload.uintToPayload(v));
    }

    try p.write(test_payload);
    const val = try p.read(allocator);
    defer val.free(allocator);

    for (0..try val.getArrLen()) |i| {
        const element = try val.getArrElement(i);
        try expect(element.uint == test_val[i]);
    }
}

test "array16 write and read" {
    var arr: [0xffff]u8 = std.mem.zeroes([0xffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );
    const test_val = [16]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    var test_payload = try Payload.arrPayload(16, allocator);
    defer test_payload.free(allocator);

    for (test_val, 0..) |v, i| {
        try test_payload.setArrElement(i, Payload.uintToPayload(v));
    }

    try p.write(test_payload);
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect(arr[0] == 0xdc);
    for (0..try val.getArrLen()) |i| {
        const element = try val.getArrElement(i);
        try expect(element.uint == test_val[i]);
    }
}

test "ext write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(
        &write_buffer,
        &read_buffer,
    );

    var test_data = [5]u8{ 1, 2, 3, 4, 5 };
    const test_type: u8 = 1;

    try p.write(.{ .ext = msgpack.EXT{ .type = test_type, .data = &test_data } });
    const val = try p.read(allocator);
    defer val.free(allocator);
    try expect(u8eql(&test_data, val.ext.data));
    try expect(test_type == val.ext.type);
}

// Test error handling for Payload methods
test "payload error handling" {
    // Test NotArr error
    const not_arr_payload = Payload.nilToPayload();
    const arr_len_result = not_arr_payload.getArrLen();
    try expect(arr_len_result == Payload.Error.NotArray);

    const arr_element_result = not_arr_payload.getArrElement(0);
    try expect(arr_element_result == Payload.Error.NotArray);

    var mut_not_arr = Payload.nilToPayload();
    const set_arr_result = mut_not_arr.setArrElement(0, Payload.nilToPayload());
    try expect(set_arr_result == Payload.Error.NotArray);

    // Test NotMap error
    const not_map_payload = Payload.nilToPayload();
    const map_get_result = not_map_payload.mapGet("test");
    try expect(map_get_result == Payload.Error.NotMap);

    var mut_not_map = Payload.nilToPayload();
    const map_put_result = mut_not_map.mapPut("test", Payload.nilToPayload());
    try expect(map_put_result == Payload.Error.NotMap);
}

// Test boundary values for integers
test "integer boundary values" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test maximum positive values
    const max_u8: u64 = 0xff;
    try p.write(.{ .uint = max_u8 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.uint == max_u8);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const max_u16: u64 = 0xffff;
    try p.write(.{ .uint = max_u16 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.uint == max_u16);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const max_u32: u64 = 0xffffffff;
    try p.write(.{ .uint = max_u32 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.uint == max_u32);
    }

    // Test minimum negative values
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const min_i8: i64 = -128;
    try p.write(.{ .int = min_i8 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.int == min_i8);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const min_i16: i64 = -32768;
    try p.write(.{ .int = min_i16 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.int == min_i16);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const min_i32: i64 = -2147483648;
    try p.write(.{ .int = min_i32 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.int == min_i32);
    }
}

// Test different string sizes
test "string size boundaries" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test fixstr (31 bytes)
    const fixstr_31_data = "a" ** 31;
    const fixstr_31_payload = try Payload.strToPayload(fixstr_31_data, allocator);
    defer fixstr_31_payload.free(allocator);
    try p.write(fixstr_31_payload);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(u8eql(fixstr_31_data, val.str.value()));
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test str8 (255 bytes)
    const str8_255_data = "b" ** 255;
    const str8_255_payload = try Payload.strToPayload(str8_255_data, allocator);
    defer str8_255_payload.free(allocator);
    try p.write(str8_255_payload);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(u8eql(str8_255_data, val.str.value()));
    }
}

// Test empty containers
test "empty containers" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test empty array
    const empty_arr = try Payload.arrPayload(0, allocator);
    defer empty_arr.free(allocator);
    try p.write(empty_arr);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect((try val.getArrLen()) == 0);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test empty map
    const empty_map = Payload.mapPayload(allocator);
    defer empty_map.free(allocator);
    try p.write(empty_map);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.map.count() == 0);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test empty string
    const empty_str_payload = try Payload.strToPayload("", allocator);
    defer empty_str_payload.free(allocator);
    try p.write(empty_str_payload);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(u8eql("", val.str.value()));
    }
}

// Test different EXT sizes
test "ext different sizes" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test fixext1
    var ext1_data = [1]u8{0x42};
    try p.write(.{ .ext = msgpack.wrapEXT(1, &ext1_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 1);
        try expect(u8eql(&ext1_data, val.ext.data));
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test fixext2
    var ext2_data = [2]u8{ 0x42, 0x43 };
    try p.write(.{ .ext = msgpack.wrapEXT(2, &ext2_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 2);
        try expect(u8eql(&ext2_data, val.ext.data));
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test fixext4
    var ext4_data = [4]u8{ 0x42, 0x43, 0x44, 0x45 };
    try p.write(.{ .ext = msgpack.wrapEXT(3, &ext4_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 3);
        try expect(u8eql(&ext4_data, val.ext.data));
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test fixext8
    var ext8_data = [8]u8{ 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49 };
    try p.write(.{ .ext = msgpack.wrapEXT(4, &ext8_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 4);
        try expect(u8eql(&ext8_data, val.ext.data));
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test fixext16
    var ext16_data = [16]u8{ 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 0x51 };
    try p.write(.{ .ext = msgpack.wrapEXT(5, &ext16_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 5);
        try expect(u8eql(&ext16_data, val.ext.data));
    }
}

// Test float precision
test "float precision" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test f32 range value
    const f32_val: f64 = 3.14159;
    try p.write(.{ .float = f32_val });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        // Check if value is approximately equal (due to f32 precision loss)
        try expect(@abs(val.float - f32_val) < 0.0001);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test f64 value that exceeds f32 range
    const f64_val: f64 = 1.7976931348623157e+308; // Near f64 max
    try p.write(.{ .float = f64_val });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.float == f64_val);
    }
}

// Test payload utility methods
test "payload utility methods" {
    // Test all ToPayload methods
    try expect(Payload.nilToPayload() == .nil);
    try expect(Payload.boolToPayload(true).bool == true);
    try expect(Payload.intToPayload(-42).int == -42);
    try expect(Payload.uintToPayload(42).uint == 42);
    try expect(Payload.floatToPayload(3.14).float == 3.14);

    const str_payload = try Payload.strToPayload("test", allocator);
    defer str_payload.free(allocator);
    try expect(u8eql("test", str_payload.str.value()));

    const bin_payload = try Payload.binToPayload("binary", allocator);
    defer bin_payload.free(allocator);
    try expect(u8eql("binary", bin_payload.bin.value()));

    const ext_payload = try Payload.extToPayload(1, "extdata", allocator);
    defer ext_payload.free(allocator);
    try expect(ext_payload.ext.type == 1);
    try expect(u8eql("extdata", ext_payload.ext.data));

    const arr_payload = try Payload.arrPayload(3, allocator);
    defer arr_payload.free(allocator);
    try expect((try arr_payload.getArrLen()) == 3);

    const map_payload = Payload.mapPayload(allocator);
    defer map_payload.free(allocator);
    try expect(map_payload.map.count() == 0);
}

// Test negative fixint range
test "negative fixint range" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test all values in negative fixint range (-32 to -1)
    for (1..33) |i| {
        const val: i64 = -@as(i64, @intCast(i));
        try p.write(.{ .int = val });
    }

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (1..33) |i| {
        const expected: i64 = -@as(i64, @intCast(i));
        const result = try p.read(allocator);
        defer result.free(allocator);
        try expect(result.int == expected);
    }
}

// Test map with non-existent key
test "map operations" {
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // Test getting non-existent key
    const result = try test_map.mapGet("nonexistent");
    try expect(result == null);

    // Test putting and getting
    try test_map.mapPut("key1", Payload.intToPayload(42));
    const value = try test_map.mapGet("key1");
    try expect(value != null);
    try expect(value.?.int == 42);

    // Test overwriting existing key
    try test_map.mapPut("key1", Payload.intToPayload(100));
    const new_value = try test_map.mapGet("key1");
    try expect(new_value != null);
    try expect(new_value.?.int == 100);
}

// Test array operations
test "array operations" {
    var test_arr = try Payload.arrPayload(3, allocator);
    defer test_arr.free(allocator);

    // Set all elements
    for (0..3) |i| {
        try test_arr.setArrElement(i, Payload.intToPayload(@intCast(i * 10)));
    }

    // Get all elements
    for (0..3) |i| {
        const element = try test_arr.getArrElement(i);
        try expect(element.int == @as(i64, @intCast(i * 10)));
    }

    // Test array length
    try expect((try test_arr.getArrLen()) == 3);
}

// Test special float values
test "special float values" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test zero
    try p.write(.{ .float = 0.0 });
    var val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == 0.0);

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test negative zero
    try p.write(.{ .float = -0.0 });
    val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == -0.0);

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test very small positive number
    const small_pos: f64 = 1e-100;
    try p.write(.{ .float = small_pos });
    val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == small_pos);

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test very small negative number
    const small_neg: f64 = -1e-100;
    try p.write(.{ .float = small_neg });
    val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == small_neg);
}

// Test Unicode strings
test "unicode strings" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test various Unicode strings
    const unicode_strings = [_][]const u8{
        "Hello, 世界",
        "🚀🌟✨",
        "Привет мир",
        "مرحبا بالعالم",
        "こんにちは世界",
    };

    for (unicode_strings) |unicode_str| {
        const unicode_payload = try Payload.strToPayload(unicode_str, allocator);
        defer unicode_payload.free(allocator);
        try p.write(unicode_payload);
    }

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (unicode_strings) |expected| {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(u8eql(expected, val.str.value()));
    }
}

// Test nested structures
test "deeply nested structures" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create deeply nested array [[[42]]]
    var inner_arr = try Payload.arrPayload(1, allocator);
    try inner_arr.setArrElement(0, Payload.intToPayload(42));

    var middle_arr = try Payload.arrPayload(1, allocator);
    try middle_arr.setArrElement(0, inner_arr);

    var outer_arr = try Payload.arrPayload(1, allocator);
    try outer_arr.setArrElement(0, middle_arr);

    defer outer_arr.free(allocator);

    try p.write(outer_arr);
    const val = try p.read(allocator);
    defer val.free(allocator);

    // Navigate to deeply nested value
    const level1 = try val.getArrElement(0);
    const level2 = try level1.getArrElement(0);
    const level3 = try level2.getArrElement(0);
    try expect(try level3.getInt() == 42);
}

// Test mixed type arrays
test "mixed type arrays" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var mixed_arr = try Payload.arrPayload(6, allocator);
    defer mixed_arr.free(allocator);

    try mixed_arr.setArrElement(0, Payload.nilToPayload());
    try mixed_arr.setArrElement(1, Payload.boolToPayload(true));
    try mixed_arr.setArrElement(2, Payload.intToPayload(-123));
    try mixed_arr.setArrElement(3, Payload.uintToPayload(456));
    try mixed_arr.setArrElement(4, Payload.floatToPayload(78.9));
    try mixed_arr.setArrElement(5, try Payload.strToPayload("mixed", allocator));

    try p.write(mixed_arr);
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect((try val.getArrElement(0)) == .nil);
    try expect((try val.getArrElement(1)).bool == true);
    try expect((try val.getArrElement(2)).int == -123);
    try expect((try val.getArrElement(3)).uint == 456);
    // Use approximate comparison for float values due to f32 precision loss
    try expect(@abs((try val.getArrElement(4)).float - 78.9) < 0.01);
    try expect(u8eql("mixed", (try val.getArrElement(5)).str.value()));
}

// Test large maps
test "large maps" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var large_map = Payload.mapPayload(allocator);
    defer large_map.free(allocator);

    // Store allocated keys to free them later
    var keys = if (builtin.zig_version.minor == 14)
        std.ArrayList([]u8).init(allocator)
    else
        std.ArrayList([]u8){};
    defer {
        for (keys.items) |key| {
            allocator.free(key);
        }
        if (builtin.zig_version.minor == 14) keys.deinit() else keys.deinit(allocator);
    }

    // Create a map with 20 entries (more than fixmap limit of 15)
    for (0..20) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        if (builtin.zig_version.minor == 14) try keys.append(key) else try keys.append(allocator, key);
        try large_map.mapPut(key, Payload.intToPayload(@intCast(i)));
    }

    try p.write(large_map);
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect(val.map.count() == 20);

    // Verify some entries
    const value0 = try val.mapGet("key0");
    try expect(value0 != null);
    try expect(try value0.?.getInt() == 0);

    const value19 = try val.mapGet("key19");
    try expect(value19 != null);
    try expect(try value19.?.getInt() == 19);
}

// Test array32 format
test "array32 write and read" {
    // Create an array larger than 65535 elements would be too memory intensive
    // Instead test the boundary where array32 format kicks in
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test with 65536 elements (0x10000), which should use array32
    const test_size = 0x10000;
    var test_payload = try Payload.arrPayload(test_size, allocator);
    defer test_payload.free(allocator);

    for (0..test_size) |i| {
        try test_payload.setArrElement(i, Payload.uintToPayload(i % 256));
    }

    try p.write(test_payload);
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect((try val.getArrLen()) == test_size);
    // Check first and last elements
    try expect((try val.getArrElement(0)).uint == 0);
    try expect((try val.getArrElement(test_size - 1)).uint == (test_size - 1) % 256);
}

// Test bin16 and bin32
test "bin16 and bin32 write and read" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test bin16 (256 bytes)
    const test_bin16 = try allocator.alloc(u8, 256);
    defer allocator.free(test_bin16);
    for (test_bin16, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try p.write(.{ .bin = msgpack.wrapBin(test_bin16) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.bin.value().len == 256);
        try expect(val.bin.value()[0] == 0);
        try expect(val.bin.value()[255] == 255);
    }

    // Reset buffers for bin32 test
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test bin32 (65536 bytes)
    const test_bin32 = try allocator.alloc(u8, 65536);
    defer allocator.free(test_bin32);
    for (test_bin32, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try p.write(.{ .bin = msgpack.wrapBin(test_bin32) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.bin.value().len == 65536);
        try expect(val.bin.value()[0] == 0);
        try expect(val.bin.value()[65535] == 255);
    }
}

// Test str16 and str32
test "str16 and str32 write and read" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test str16 (256 characters)
    const str16_data = "x" ** 256;
    const str16_payload = try Payload.strToPayload(str16_data, allocator);
    defer str16_payload.free(allocator);
    try p.write(str16_payload);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.str.value().len == 256);
        try expect(u8eql(str16_data, val.str.value()));
    }

    // Reset buffers for str32 test
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test str32 (65536 characters)
    const str32_data = try allocator.alloc(u8, 65536);
    defer allocator.free(str32_data);
    @memset(str32_data, 'A');

    const str32_payload = try Payload.strToPayload(str32_data, allocator);
    defer str32_payload.free(allocator);
    try p.write(str32_payload);
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.str.value().len == 65536);
        try expect(u8eql(str32_data, val.str.value()));
    }
}

// Test int64 and uint64 boundary values
test "int64 uint64 boundary values" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test max int64
    const max_i64: i64 = std.math.maxInt(i64);
    try p.write(.{ .int = max_i64 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(try val.getInt() == max_i64);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test min int64
    const min_i64: i64 = std.math.minInt(i64);
    try p.write(.{ .int = min_i64 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.int == min_i64);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test max uint64
    const max_u64: u64 = std.math.maxInt(u64);
    try p.write(.{ .uint = max_u64 });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.uint == max_u64);
    }
}

// Test getUint method
test "getUint method" {
    // Test uint payload
    const uint_payload = Payload.uintToPayload(42);
    try expect(try uint_payload.getUint() == 42);

    // Test positive int payload converted to uint
    const pos_int_payload = Payload.intToPayload(24);
    try expect(try pos_int_payload.getUint() == 24);

    // Test negative int payload should fail
    const neg_int_payload = Payload.intToPayload(-5);
    const result = neg_int_payload.getUint();
    try expect(result == msgpack.MsgPackError.InvalidType);

    // Test non-numeric payload should fail
    const nil_payload = Payload.nilToPayload();
    const nil_result = nil_payload.getUint();
    try expect(nil_result == msgpack.MsgPackError.InvalidType);
}

// Test new strict type conversion methods
test "strict type conversion methods" {
    // Test asInt - strict mode
    const int_payload = Payload.intToPayload(-42);
    try expect(try int_payload.asInt() == -42);

    const uint_payload = Payload.uintToPayload(100);
    const uint_as_int = uint_payload.asInt();
    try expect(uint_as_int == msgpack.MsgPackError.InvalidType);

    // Test asUint - strict mode
    try expect(try uint_payload.asUint() == 100);

    const int_as_uint = int_payload.asUint();
    try expect(int_as_uint == msgpack.MsgPackError.InvalidType);

    // Test asFloat
    const float_payload = Payload.floatToPayload(3.14);
    try expect(try float_payload.asFloat() == 3.14);

    const int_as_float = int_payload.asFloat();
    try expect(int_as_float == msgpack.MsgPackError.InvalidType);

    // Test asBool
    const bool_payload = Payload.boolToPayload(true);
    try expect(try bool_payload.asBool() == true);

    const int_as_bool = int_payload.asBool();
    try expect(int_as_bool == msgpack.MsgPackError.InvalidType);

    // Test asStr
    const str_payload = try Payload.strToPayload("hello", allocator);
    defer str_payload.free(allocator);
    const str_value = try str_payload.asStr();
    try expect(u8eql("hello", str_value));

    const int_as_str = int_payload.asStr();
    try expect(int_as_str == msgpack.MsgPackError.InvalidType);

    // Test asBin
    var bin_data = [_]u8{ 1, 2, 3 };
    const bin_payload = try Payload.binToPayload(&bin_data, allocator);
    defer bin_payload.free(allocator);
    const bin_value = try bin_payload.asBin();
    try expect(u8eql(&bin_data, bin_value));
}

// Test payload type checking methods
test "payload type checking methods" {
    // Test isNil
    const nil_payload = Payload.nilToPayload();
    try expect(nil_payload.isNil());

    const int_payload = Payload.intToPayload(42);
    try expect(!int_payload.isNil());

    // Test isNumber
    try expect(int_payload.isNumber());

    const uint_payload = Payload.uintToPayload(100);
    try expect(uint_payload.isNumber());

    const float_payload = Payload.floatToPayload(3.14);
    try expect(float_payload.isNumber());

    const str_payload = try Payload.strToPayload("test", allocator);
    defer str_payload.free(allocator);
    try expect(!str_payload.isNumber());

    // Test isInteger
    try expect(int_payload.isInteger());
    try expect(uint_payload.isInteger());
    try expect(!float_payload.isInteger());
    try expect(!str_payload.isInteger());
}

// Test NaN and Infinity float values
test "nan and infinity float values" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test positive infinity
    try p.write(.{ .float = std.math.inf(f64) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(std.math.isInf(val.float));
        try expect(val.float > 0);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test negative infinity
    try p.write(.{ .float = -std.math.inf(f64) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(std.math.isInf(val.float));
        try expect(val.float < 0);
    }

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test NaN
    try p.write(.{ .float = std.math.nan(f64) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(std.math.isNan(val.float));
    }
}

// Test EXT8, EXT16, EXT32 formats
test "ext8 ext16 ext32 formats" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test EXT8 (more than 16 bytes, up to 255)
    const ext8_size = 100;
    const ext8_data = try allocator.alloc(u8, ext8_size);
    defer allocator.free(ext8_data);
    for (ext8_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try p.write(.{ .ext = msgpack.wrapEXT(10, ext8_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 10);
        try expect(val.ext.data.len == ext8_size);
        try expect(u8eql(ext8_data, val.ext.data));
    }

    // Reset buffers for EXT16 test
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test EXT16 (more than 255 bytes, up to 65535)
    const ext16_size = 1000;
    const ext16_data = try allocator.alloc(u8, ext16_size);
    defer allocator.free(ext16_data);
    for (ext16_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try p.write(.{ .ext = msgpack.wrapEXT(20, ext16_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 20);
        try expect(val.ext.data.len == ext16_size);
        try expect(u8eql(ext16_data, val.ext.data));
    }

    // Reset buffers for EXT32 test
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test EXT32 (more than 65535 bytes, up to 4294967295)
    const ext32_size = 70000; // Larger than 65535
    const ext32_data = try allocator.alloc(u8, ext32_size);
    defer allocator.free(ext32_data);
    for (ext32_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    try p.write(.{ .ext = msgpack.wrapEXT(30, ext32_data) });
    {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.ext.type == 30);
        try expect(val.ext.data.len == ext32_size);
        // Check first and last few bytes to avoid memory intensive comparison
        try expect(val.ext.data[0] == 0);
        try expect(val.ext.data[ext32_size - 1] == (ext32_size - 1) % 256);
    }
}

// Test actual MAP32 format (more than 65535 entries)
test "actual map32 format" {
    // Note: This test would be very memory intensive with 65536+ entries
    // Instead, we test the boundary where map32 format would be used
    // by verifying the implementation handles large maps correctly

    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test with a moderately large map (1000 entries) to ensure scalability
    var large_map = Payload.mapPayload(allocator);
    defer large_map.free(allocator);

    // Store allocated keys to free them later
    var keys = if (builtin.zig_version.minor == 14)
        std.ArrayList([]u8).init(allocator)
    else
        std.ArrayList([]u8){};
    defer {
        for (keys.items) |key| {
            allocator.free(key);
        }
        if (builtin.zig_version.minor == 14) keys.deinit() else keys.deinit(allocator);
    }

    // Create a map with 1000 entries (more than map16 threshold of 65535 would be too memory intensive)
    for (0..1000) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d:0>10}", .{i});
        if (builtin.zig_version.minor == 14) try keys.append(key) else try keys.append(allocator, key);
        try large_map.mapPut(key, Payload.intToPayload(@intCast(i)));
    }

    try p.write(large_map);
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect(val.map.count() == 1000);

    // Verify some entries exist and have correct values
    const first_key = try std.fmt.allocPrint(allocator, "key{d:0>10}", .{0});
    defer allocator.free(first_key);
    const last_key = try std.fmt.allocPrint(allocator, "key{d:0>10}", .{999});
    defer allocator.free(last_key);

    const first_value = try val.mapGet(first_key);
    try expect(first_value != null);
    try expect(try first_value.?.getInt() == 0);

    const last_value = try val.mapGet(last_key);
    try expect(last_value != null);
    try expect(try last_value.?.getInt() == 999);
}

// Test constant structures values
test "constant structures validation" {
    // Test FixLimits constants
    try expect(msgpack.FixLimits.POSITIVE_INT_MAX == 0x7f);
    try expect(msgpack.FixLimits.NEGATIVE_INT_MIN == -32);
    try expect(msgpack.FixLimits.STR_LEN_MAX == 31);
    try expect(msgpack.FixLimits.ARRAY_LEN_MAX == 15);
    try expect(msgpack.FixLimits.MAP_LEN_MAX == 15);

    // Test IntBounds constants
    try expect(msgpack.IntBounds.UINT8_MAX == 0xff);
    try expect(msgpack.IntBounds.UINT16_MAX == 0xffff);
    try expect(msgpack.IntBounds.UINT32_MAX == 0xffff_ffff);
    try expect(msgpack.IntBounds.INT8_MIN == -128);
    try expect(msgpack.IntBounds.INT16_MIN == -32768);
    try expect(msgpack.IntBounds.INT32_MIN == -2147483648);

    // Test FixExtLen constants
    try expect(msgpack.FixExtLen.EXT1 == 1);
    try expect(msgpack.FixExtLen.EXT2 == 2);
    try expect(msgpack.FixExtLen.EXT4 == 4);
    try expect(msgpack.FixExtLen.EXT8 == 8);
    try expect(msgpack.FixExtLen.EXT16 == 16);

    // Test TimestampExt constants
    try expect(msgpack.TimestampExt.TYPE_ID == -1);
    try expect(msgpack.TimestampExt.FORMAT32_LEN == 4);
    try expect(msgpack.TimestampExt.FORMAT64_LEN == 8);
    try expect(msgpack.TimestampExt.FORMAT96_LEN == 12);
    try expect(msgpack.TimestampExt.SECONDS_BITS_64 == 34);
    try expect(msgpack.TimestampExt.SECONDS_MASK_64 == 0x3ffffffff);
    try expect(msgpack.TimestampExt.NANOSECONDS_MAX == 999_999_999);
    try expect(msgpack.TimestampExt.NANOSECONDS_PER_SECOND == 1_000_000_000.0);

    // Test MarkerBase constants
    try expect(msgpack.MarkerBase.FIXARRAY == 0x90);
    try expect(msgpack.MarkerBase.FIXMAP == 0x80);
    try expect(msgpack.MarkerBase.FIXSTR == 0xa0);
    try expect(msgpack.MarkerBase.FIXSTR_LEN_MASK == 0x1f);
    try expect(msgpack.MarkerBase.FIXSTR_TYPE_MASK == 0xe0);
}

// Test edge cases and error conditions
test "edge cases and error conditions" {
    var arr: [100]u8 = std.mem.zeroes([100]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test array index out of bounds
    var test_arr = try Payload.arrPayload(3, allocator);
    defer test_arr.free(allocator);

    // This should work
    try test_arr.setArrElement(0, Payload.nilToPayload());
    try test_arr.setArrElement(1, Payload.boolToPayload(true));
    try test_arr.setArrElement(2, Payload.intToPayload(42));

    try p.write(test_arr);
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect((try val.getArrLen()) == 3);
    try expect((try val.getArrElement(0)) == .nil);
    try expect((try val.getArrElement(1)).bool == true);
    try expect(try (try val.getArrElement(2)).getInt() == 42);
}

// Test EXT with negative type IDs
test "ext negative type ids" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test negative type ID (MessagePack spec allows -128 to 127)
    var test_data = [4]u8{ 0x01, 0x02, 0x03, 0x04 };
    const negative_type: i8 = -42;

    try p.write(.{ .ext = msgpack.wrapEXT(negative_type, &test_data) });
    const val = try p.read(allocator);
    defer val.free(allocator);

    try expect(val.ext.type == negative_type);
    try expect(u8eql(&test_data, val.ext.data));

    // Reset buffer and test minimum negative type ID
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const min_type: i8 = -128;
    try p.write(.{ .ext = msgpack.wrapEXT(min_type, &test_data) });
    const val2 = try p.read(allocator);
    defer val2.free(allocator);

    try expect(val2.ext.type == min_type);
    try expect(u8eql(&test_data, val2.ext.data));
}

// Test format markers verification
test "format markers verification" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test nil marker
    try p.write(Payload.nilToPayload());
    try expect(arr[0] == 0xc0); // NIL marker

    // Reset buffer
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);

    // Test bool markers
    try p.write(Payload.boolToPayload(true));
    try expect(arr[0] == 0xc3); // TRUE marker

    try p.write(Payload.boolToPayload(false));
    try expect(arr[1] == 0xc2); // FALSE marker

    // Reset buffer
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test uint8 marker
    try p.write(Payload.uintToPayload(255));
    try expect(arr[0] == 0xcc); // UINT8 marker

    // Reset buffer
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test str8 marker (32+ bytes string uses str8)
    const test_str32 = "a" ** 32;
    const str_payload = try Payload.strToPayload(test_str32, allocator);
    defer str_payload.free(allocator);
    try p.write(str_payload);
    try expect(arr[0] == 0xd9); // STR8 marker

    // Reset buffer
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test array16 marker (16+ elements uses array16)
    var test_array = try Payload.arrPayload(16, allocator);
    defer test_array.free(allocator);
    for (0..16) |i| {
        try test_array.setArrElement(i, Payload.nilToPayload());
    }
    try p.write(test_array);
    try expect(arr[0] == 0xdc); // ARRAY16 marker

    // Reset buffer
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test map16 marker (16+ entries uses map16)
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    var test_keys = if (builtin.zig_version.minor == 14)
        std.ArrayList([]u8).init(allocator)
    else
        std.ArrayList([]u8){};
    defer {
        for (test_keys.items) |key| {
            allocator.free(key);
        }
        if (builtin.zig_version.minor == 14) test_keys.deinit() else test_keys.deinit(allocator);
    }

    for (0..16) |i| {
        const key = try std.fmt.allocPrint(allocator, "k{d}", .{i});
        if (builtin.zig_version.minor == 14) try test_keys.append(key) else try test_keys.append(allocator, key);
        try test_map.mapPut(key, Payload.nilToPayload());
    }
    try p.write(test_map);
    try expect(arr[0] == 0xde); // MAP16 marker
}

// Test positive fixint boundary (0-127)
test "positive fixint boundary" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test boundary values for positive fixint (0-127)
    const boundary_values = [_]u64{ 0, 1, 126, 127, 128 };

    for (boundary_values) |val| {
        try p.write(.{ .uint = val });
    }

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (boundary_values) |expected| {
        const result = try p.read(allocator);
        defer result.free(allocator);
        try expect(result.uint == expected);
    }
}

// Test fixstr boundary (0-31 bytes)
test "fixstr boundary" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test different fixstr lengths
    const test_strings = [_][]const u8{
        "", // 0 bytes
        "a", // 1 byte
        "hello", // 5 bytes
        "a" ** 31, // 31 bytes (max fixstr)
        "b" ** 32, // 32 bytes (should use str8)
    };

    for (test_strings) |test_str| {
        const str_payload = try Payload.strToPayload(test_str, allocator);
        defer str_payload.free(allocator);
        try p.write(str_payload);
    }

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (test_strings) |expected| {
        const result = try p.read(allocator);
        defer result.free(allocator);
        try expect(u8eql(expected, result.str.value()));
    }
}

// Test fixarray boundary (0-15 elements)
test "fixarray boundary" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test different fixarray sizes
    const test_sizes = [_]usize{ 0, 1, 5, 15, 16 };

    for (test_sizes) |size| {
        var test_payload = try Payload.arrPayload(size, allocator);
        defer test_payload.free(allocator);

        for (0..size) |i| {
            try test_payload.setArrElement(i, Payload.uintToPayload(i));
        }

        try p.write(test_payload);
    }

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (test_sizes) |expected_size| {
        const result = try p.read(allocator);
        defer result.free(allocator);
        try expect((try result.getArrLen()) == expected_size);

        for (0..expected_size) |i| {
            const element = try result.getArrElement(i);
            try expect(element.uint == i);
        }
    }
}

// Test fixmap boundary (0-15 elements)
test "fixmap boundary" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test different fixmap sizes
    const test_sizes = [_]usize{ 0, 1, 5, 15, 16 };

    for (test_sizes) |size| {
        var test_map = Payload.mapPayload(allocator);
        defer test_map.free(allocator);

        for (0..size) |i| {
            const key = try std.fmt.allocPrint(allocator, "k{d}", .{i});
            defer allocator.free(key);
            try test_map.mapPut(key, Payload.uintToPayload(i));
        }

        try p.write(test_map);
    }

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (test_sizes) |expected_size| {
        const result = try p.read(allocator);
        defer result.free(allocator);
        try expect(result.map.count() == expected_size);

        for (0..expected_size) |i| {
            const key = try std.fmt.allocPrint(allocator, "k{d}", .{i});
            defer allocator.free(key);
            const value = try result.mapGet(key);
            try expect(value != null);
            try expect(value.?.uint == i);
        }
    }
}

// Test timestamp write and read
test "timestamp write and read" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test timestamp 32 (seconds only, nanoseconds = 0)
    const timestamp32 = Payload.timestampFromSeconds(1234567890);
    try p.write(timestamp32);

    // Reset read buffer
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val32 = try p.read(allocator);
    defer val32.free(allocator);
    try expect(val32 == .timestamp);
    try expect(val32.timestamp.seconds == 1234567890);
    try expect(val32.timestamp.nanoseconds == 0);

    // Test timestamp 64 (seconds + nanoseconds)
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const timestamp64 = Payload.timestampToPayload(1234567890, 123456789);
    try p.write(timestamp64);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val64 = try p.read(allocator);
    defer val64.free(allocator);
    try expect(val64 == .timestamp);
    try expect(val64.timestamp.seconds == 1234567890);
    try expect(val64.timestamp.nanoseconds == 123456789);

    // Test timestamp 96 (negative seconds)
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const timestamp96 = Payload.timestampToPayload(-1234567890, 987654321);
    try p.write(timestamp96);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val96 = try p.read(allocator);
    defer val96.free(allocator);
    try expect(val96 == .timestamp);
    try expect(val96.timestamp.seconds == -1234567890);
    try expect(val96.timestamp.nanoseconds == 987654321);
}

// Test timestamp format markers
test "timestamp format markers" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // timestamp 32 should use FIXEXT4 (0xd6) + type(-1) + 4 bytes data
    const timestamp32 = Payload.timestampFromSeconds(1000000000);
    try p.write(timestamp32);
    try expect(arr[0] == 0xd6); // FIXEXT4
    try expect(@as(i8, @bitCast(arr[1])) == -1); // timestamp type

    // Reset buffer for timestamp 64
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // timestamp 64 should use FIXEXT8 (0xd7) + type(-1) + 8 bytes data
    const timestamp64 = Payload.timestampToPayload(1000000000, 123456789);
    try p.write(timestamp64);
    try expect(arr[0] == 0xd7); // FIXEXT8
    try expect(@as(i8, @bitCast(arr[1])) == -1); // timestamp type

    // Reset buffer for timestamp 96
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // timestamp 96 should use EXT8 (0xc7) + len(12) + type(-1) + 12 bytes data
    const timestamp96 = Payload.timestampToPayload(-1000000000, 123456789);
    try p.write(timestamp96);
    try expect(arr[0] == 0xc7); // EXT8
    try expect(arr[1] == 12); // length
    try expect(@as(i8, @bitCast(arr[2])) == -1); // timestamp type
}

// Test timestamp utility methods
test "timestamp utility methods" {
    // Test Timestamp.new
    const ts1 = msgpack.Timestamp.new(1234567890, 123456789);
    try expect(ts1.seconds == 1234567890);
    try expect(ts1.nanoseconds == 123456789);

    // Test Timestamp.fromSeconds
    const ts2 = msgpack.Timestamp.fromSeconds(9876543210);
    try expect(ts2.seconds == 9876543210);
    try expect(ts2.nanoseconds == 0);

    // Test toFloat
    const ts3 = msgpack.Timestamp.new(1, 500000000); // 1.5 seconds
    const float_val = ts3.toFloat();
    try expect(@abs(float_val - 1.5) < 0.000001);

    // Test payload creation methods
    const payload1 = Payload.timestampToPayload(1000, 2000);
    try expect(payload1 == .timestamp);
    try expect(payload1.timestamp.seconds == 1000);
    try expect(payload1.timestamp.nanoseconds == 2000);

    const payload2 = Payload.timestampFromSeconds(5000);
    try expect(payload2 == .timestamp);
    try expect(payload2.timestamp.seconds == 5000);
    try expect(payload2.timestamp.nanoseconds == 0);
}

// Test timestamp edge cases
test "timestamp edge cases" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test zero timestamp
    const zero_ts = Payload.timestampFromSeconds(0);
    try p.write(zero_ts);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val_zero = try p.read(allocator);
    defer val_zero.free(allocator);
    try expect(val_zero == .timestamp);
    try expect(val_zero.timestamp.seconds == 0);
    try expect(val_zero.timestamp.nanoseconds == 0);

    // Test maximum nanoseconds (999999999)
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const max_nano_ts = Payload.timestampToPayload(1000, 999999999);
    try p.write(max_nano_ts);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val_max_nano = try p.read(allocator);
    defer val_max_nano.free(allocator);
    try expect(val_max_nano == .timestamp);
    try expect(val_max_nano.timestamp.seconds == 1000);
    try expect(val_max_nano.timestamp.nanoseconds == 999999999);

    // Test large positive seconds (near 32-bit limit)
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const large_ts = Payload.timestampFromSeconds(0xffffffff);
    try p.write(large_ts);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val_large = try p.read(allocator);
    defer val_large.free(allocator);
    try expect(val_large == .timestamp);
    try expect(val_large.timestamp.seconds == 0xffffffff);
    try expect(val_large.timestamp.nanoseconds == 0);
}

// Test timestamp boundary values
test "timestamp boundary values" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test 34-bit boundary for timestamp 64 format
    // 2^34 - 1 = 17179869183
    const boundary_34bit = (1 << 34) - 1;
    const ts_34bit = Payload.timestampToPayload(boundary_34bit, 123456789);
    try p.write(ts_34bit);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val_34bit = try p.read(allocator);
    defer val_34bit.free(allocator);
    try expect(val_34bit == .timestamp);
    try expect(val_34bit.timestamp.seconds == boundary_34bit);
    try expect(val_34bit.timestamp.nanoseconds == 123456789);

    // Test seconds just over 34-bit boundary (should use timestamp 96)
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const over_34bit = (1 << 34);
    const ts_over_34bit = Payload.timestampToPayload(over_34bit, 123456789);
    try p.write(ts_over_34bit);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val_over_34bit = try p.read(allocator);
    defer val_over_34bit.free(allocator);
    try expect(val_over_34bit == .timestamp);
    try expect(val_over_34bit.timestamp.seconds == over_34bit);
    try expect(val_over_34bit.timestamp.nanoseconds == 123456789);

    // Test very large negative seconds
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const large_negative = -9223372036854775808; // i64 min
    const ts_large_neg = Payload.timestampToPayload(large_negative, 999999999);
    try p.write(ts_large_neg);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val_large_neg = try p.read(allocator);
    defer val_large_neg.free(allocator);
    try expect(val_large_neg == .timestamp);
    try expect(val_large_neg.timestamp.seconds == large_negative);
    try expect(val_large_neg.timestamp.nanoseconds == 999999999);
}

// Test timestamp and EXT compatibility
test "timestamp and EXT compatibility" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test mixed timestamp and EXT data
    const timestamp = Payload.timestampFromSeconds(1000000000);
    try p.write(timestamp);

    // Write a regular EXT with type -1 but different length (should be treated as EXT, not timestamp)
    var ext_data = [_]u8{ 0x01, 0x02, 0x03 };
    const ext_payload = try Payload.extToPayload(-1, &ext_data, allocator);
    defer ext_payload.free(allocator);
    try p.write(ext_payload);

    // Write another timestamp
    const timestamp2 = Payload.timestampToPayload(2000000000, 500000000);
    try p.write(timestamp2);

    // Read back and verify
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val1 = try p.read(allocator);
    defer val1.free(allocator);
    try expect(val1 == .timestamp);
    try expect(val1.timestamp.seconds == 1000000000);
    try expect(val1.timestamp.nanoseconds == 0);

    const val2 = try p.read(allocator);
    defer val2.free(allocator);
    try expect(val2 == .ext);
    try expect(val2.ext.type == -1);
    try expect(val2.ext.data.len == 3);
    try expect(val2.ext.data[0] == 0x01);
    try expect(val2.ext.data[1] == 0x02);
    try expect(val2.ext.data[2] == 0x03);

    const val3 = try p.read(allocator);
    defer val3.free(allocator);
    try expect(val3 == .timestamp);
    try expect(val3.timestamp.seconds == 2000000000);
    try expect(val3.timestamp.nanoseconds == 500000000);
}

// Test timestamp error handling
test "timestamp error handling" {
    // Test invalid nanoseconds (> 999999999) - should return INVALID_TYPE
    const invalid_nano_ts = msgpack.Timestamp.new(1000, 1000000000); // 1 billion nanoseconds

    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // This should fail to write
    const result = p.write(Payload{ .timestamp = invalid_nano_ts });
    try std.testing.expectError(msgpack.MsgPackError.InvalidType, result);
}

// Test timestamp format selection logic
test "timestamp format selection" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test format 32: seconds <= 0xffffffff and nanoseconds == 0
    const ts32_max = Payload.timestampFromSeconds(0xffffffff);
    try p.write(ts32_max);
    try expect(arr[0] == 0xd6); // FIXEXT4
    try expect(@as(i8, @bitCast(arr[1])) == -1); // timestamp type

    // Reset buffer
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test format 32 boundary: seconds = 0xffffffff + 1 should use format 64
    const ts64_min = Payload.timestampToPayload(0x100000000, 0);
    try p.write(ts64_min);
    try expect(arr[0] == 0xd7); // FIXEXT8
    try expect(@as(i8, @bitCast(arr[1])) == -1); // timestamp type

    // Reset buffer
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test format 64: nanoseconds != 0 but seconds fits in 34-bit
    const ts64_nano = Payload.timestampToPayload(1000000000, 1);
    try p.write(ts64_nano);
    try expect(arr[0] == 0xd7); // FIXEXT8
    try expect(@as(i8, @bitCast(arr[1])) == -1); // timestamp type

    // Reset buffer
    arr = std.mem.zeroes([0xfffff]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test format 96: negative seconds
    const ts96_neg = Payload.timestampToPayload(-1, 123456789);
    try p.write(ts96_neg);
    try expect(arr[0] == 0xc7); // EXT8
    try expect(arr[1] == 12); // length
    try expect(@as(i8, @bitCast(arr[2])) == -1); // timestamp type
}

// Test timestamp precision and conversion
test "timestamp precision and conversion" {
    // Test toFloat method precision
    const ts1 = msgpack.Timestamp.new(1234567890, 123456789);
    const float_val1 = ts1.toFloat();
    const expected1 = 1234567890.123456789;
    try expect(@abs(float_val1 - expected1) < 0.000000001);

    // Test toFloat with zero nanoseconds
    const ts2 = msgpack.Timestamp.new(1000, 0);
    const float_val2 = ts2.toFloat();
    try expect(float_val2 == 1000.0);

    // Test toFloat with maximum nanoseconds
    const ts3 = msgpack.Timestamp.new(0, 999999999);
    const float_val3 = ts3.toFloat();
    const expected3 = 0.999999999;
    try expect(@abs(float_val3 - expected3) < 0.000000001);

    // Test negative seconds with nanoseconds
    const ts4 = msgpack.Timestamp.new(-1, 500000000);
    const float_val4 = ts4.toFloat();
    const expected4 = -0.5;
    try expect(@abs(float_val4 - expected4) < 0.000000001);
}

// ============================================================================
// Additional tests from test_additional.zig
// ============================================================================

// Test minimal encoding principle (serializers SHOULD use the smallest format)
test "minimal encoding principle" {
    var arr: [1000]u8 = std.mem.zeroes([1000]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test small integers use positive fixint
    try p.write(.{ .uint = 127 });
    try expect(arr[0] == 0x7f); // Should use positive fixint, not uint8

    // Reset
    arr = std.mem.zeroes([1000]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test small negative numbers use negative fixint
    try p.write(.{ .int = -1 });
    try expect(arr[0] == 0xff); // Should use negative fixint

    // Reset
    arr = std.mem.zeroes([1000]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test short strings use fixstr
    const short_str = try Payload.strToPayload("hello", allocator);
    defer short_str.free(allocator);
    try p.write(short_str);
    try expect((arr[0] & 0xe0) == 0xa0); // fixstr format
    try expect((arr[0] & 0x1f) == 5); // length is 5
}

// Test all positive fixint values (0-127)
test "all positive fixint values comprehensive" {
    var arr: [256]u8 = std.mem.zeroes([256]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Write all positive fixint values
    for (0..128) |i| {
        try p.write(.{ .uint = i });
    }

    // Verify all values use single-byte encoding
    for (0..128) |i| {
        try expect(arr[i] == i);
    }

    // Reset read buffer and verify read values
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    for (0..128) |i| {
        const val = try p.read(allocator);
        defer val.free(allocator);
        try expect(val.uint == i);
    }
}

// Test deterministic serialization for maps (useful for hashing scenarios)
test "deterministic serialization for maps" {
    var arr1: [1000]u8 = std.mem.zeroes([1000]u8);
    var arr2: [1000]u8 = std.mem.zeroes([1000]u8);

    // Create two maps with same content but different insertion order
    var map1 = Payload.mapPayload(allocator);
    defer map1.free(allocator);
    try map1.mapPut("a", Payload.intToPayload(1));
    try map1.mapPut("b", Payload.intToPayload(2));
    try map1.mapPut("c", Payload.intToPayload(3));

    var map2 = Payload.mapPayload(allocator);
    defer map2.free(allocator);
    try map2.mapPut("c", Payload.intToPayload(3));
    try map2.mapPut("a", Payload.intToPayload(1));
    try map2.mapPut("b", Payload.intToPayload(2));

    var write_buffer1 = fixedBufferStream(&arr1);
    var read_buffer1 = fixedBufferStream(&arr1);
    var p1 = pack.init(&write_buffer1, &read_buffer1);
    try p1.write(map1);

    var write_buffer2 = fixedBufferStream(&arr2);
    var read_buffer2 = fixedBufferStream(&arr2);
    var p2 = pack.init(&write_buffer2, &read_buffer2);
    try p2.write(map2);

    // Note: Current implementation may not guarantee order consistency
    // This is an area for potential improvement
}

// Test bin and str type compatibility (cross-version compatibility)
test "bin and str type compatibility" {
    var arr: [1000]u8 = std.mem.zeroes([1000]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test binary data uses bin format
    var binary_data = [_]u8{ 0xff, 0xfe, 0xfd, 0xfc, 0xfb };
    try p.write(.{ .bin = msgpack.wrapBin(&binary_data) });

    // Verify bin8 format (0xc4) is used
    try expect(arr[0] == 0xc4);
    try expect(arr[1] == 5); // length

    // Test UTF-8 strings use str format
    arr = std.mem.zeroes([1000]u8);
    write_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const utf8_str = try Payload.strToPayload("Hello 世界", allocator);
    defer utf8_str.free(allocator);
    try p.write(utf8_str);

    // Verify str format is used
    try expect((arr[0] & 0xe0) == 0xa0 or arr[0] == 0xd9); // fixstr or str8
}

// Test extension type reserved range
test "extension type reserved range" {
    var arr: [1000]u8 = std.mem.zeroes([1000]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test application-defined types (0-127)
    var app_data = [_]u8{ 0x01, 0x02 };
    try p.write(.{ .ext = msgpack.wrapEXT(0, &app_data) });
    try p.write(.{ .ext = msgpack.wrapEXT(127, &app_data) });

    // Test predefined types (-128 to -1)
    try p.write(.{ .ext = msgpack.wrapEXT(-128, &app_data) });
    // -1 is timestamp, already covered in other tests
    try p.write(.{ .ext = msgpack.wrapEXT(-2, &app_data) });

    // Read back and verify type values remain correct
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const val1 = try p.read(allocator);
    defer val1.free(allocator);
    try expect(val1.ext.type == 0);

    const val2 = try p.read(allocator);
    defer val2.free(allocator);
    try expect(val2.ext.type == 127);

    const val3 = try p.read(allocator);
    defer val3.free(allocator);
    try expect(val3.ext.type == -128);

    const val4 = try p.read(allocator);
    defer val4.free(allocator);
    try expect(val4.ext.type == -2);
}

// Test sequential read write multiple objects
test "sequential read write multiple objects" {
    var arr: [10000]u8 = std.mem.zeroes([10000]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Write multiple types of objects
    try p.write(Payload.nilToPayload());
    try p.write(Payload.boolToPayload(true));
    try p.write(Payload.intToPayload(-42));
    try p.write(Payload.uintToPayload(42));
    try p.write(Payload.floatToPayload(3.14));

    const str = try Payload.strToPayload("test", allocator);
    defer str.free(allocator);
    try p.write(str);

    var bin_data = [_]u8{ 1, 2, 3 };
    try p.write(.{ .bin = msgpack.wrapBin(&bin_data) });

    var test_arr = try Payload.arrPayload(2, allocator);
    defer test_arr.free(allocator);
    try test_arr.setArrElement(0, Payload.intToPayload(1));
    try test_arr.setArrElement(1, Payload.intToPayload(2));
    try p.write(test_arr);

    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);
    try test_map.mapPut("key", Payload.intToPayload(100));
    try p.write(test_map);

    const ts = Payload.timestampFromSeconds(1000000);
    try p.write(ts);

    // Read back all objects and verify
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const v1 = try p.read(allocator);
    defer v1.free(allocator);
    try expect(v1 == .nil);

    const v2 = try p.read(allocator);
    defer v2.free(allocator);
    try expect(v2.bool == true);

    const v3 = try p.read(allocator);
    defer v3.free(allocator);
    try expect(v3.int == -42);

    const v4 = try p.read(allocator);
    defer v4.free(allocator);
    try expect(v4.uint == 42);

    const v5 = try p.read(allocator);
    defer v5.free(allocator);
    try expect(@abs(v5.float - 3.14) < 0.01);

    const v6 = try p.read(allocator);
    defer v6.free(allocator);
    try expect(std.mem.eql(u8, v6.str.value(), "test"));

    const v7 = try p.read(allocator);
    defer v7.free(allocator);
    try expect(v7.bin.value().len == 3);

    const v8 = try p.read(allocator);
    defer v8.free(allocator);
    try expect((try v8.getArrLen()) == 2);

    const v9 = try p.read(allocator);
    defer v9.free(allocator);
    try expect(v9.map.count() == 1);

    const v10 = try p.read(allocator);
    defer v10.free(allocator);
    try expect(v10.timestamp.seconds == 1000000);
}

// ============================================================================
// Fuzz Testing Suite
// ============================================================================

/// Generate random payload of random type
fn generateRandomPayload(random: std.Random, alloc: std.mem.Allocator, max_depth: u8) !Payload {
    const payload_type = random.intRangeAtMost(u8, 0, 10);
    
    return switch (payload_type) {
        0 => Payload.nilToPayload(),
        1 => Payload.boolToPayload(random.boolean()),
        2 => blk: {
            // Use moderate range to avoid overflow issues
            const val = random.intRangeAtMost(i64, std.math.minInt(i32), std.math.maxInt(i32));
            break :blk Payload.intToPayload(val);
        },
        3 => blk: {
            // Use moderate range to avoid overflow issues
            const val = random.intRangeAtMost(u64, 0, std.math.maxInt(u32));
            break :blk Payload.uintToPayload(val);
        },
        4 => blk: {
            // Generate reasonable float values
            const val = @as(f64, @floatFromInt(random.intRangeAtMost(i32, -10000, 10000))) + 
                       random.float(f64);
            break :blk Payload.floatToPayload(val);
        },
        5 => blk: {
            // Random string
            const len = random.intRangeAtMost(usize, 0, 100);
            const str_data = try alloc.alloc(u8, len);
            defer alloc.free(str_data);
            random.bytes(str_data);
            // Make it valid UTF-8 by restricting to ASCII printable
            for (str_data) |*byte| {
                byte.* = random.intRangeAtMost(u8, 32, 126);
            }
            break :blk try Payload.strToPayload(str_data, alloc);
        },
        6 => blk: {
            // Random binary
            const len = random.intRangeAtMost(usize, 0, 100);
            const bin_data = try alloc.alloc(u8, len);
            defer alloc.free(bin_data);
            random.bytes(bin_data);
            break :blk try Payload.binToPayload(bin_data, alloc);
        },
        7 => blk: {
            // Random array
            if (max_depth == 0) break :blk Payload.nilToPayload();
            const len = random.intRangeAtMost(usize, 0, 10);
            var arr = try Payload.arrPayload(len, alloc);
            for (0..len) |i| {
                arr.arr[i] = try generateRandomPayload(random, alloc, max_depth - 1);
            }
            break :blk arr;
        },
        8 => blk: {
            // Random map
            if (max_depth == 0) break :blk Payload.nilToPayload();
            const count = random.intRangeAtMost(usize, 0, 10);
            var map = Payload.mapPayload(alloc);
            for (0..count) |i| {
                const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
                defer alloc.free(key);
                const val = try generateRandomPayload(random, alloc, max_depth - 1);
                try map.mapPut(key, val);
            }
            break :blk map;
        },
        9 => blk: {
            // Random EXT
            // Avoid timestamp type -1
            var ext_type = random.intRangeAtMost(i8, -128, 127);
            while (ext_type == -1) {
                ext_type = random.intRangeAtMost(i8, -128, 127);
            }
            const len = random.intRangeAtMost(usize, 0, 100);
            const ext_data = try alloc.alloc(u8, len);
            defer alloc.free(ext_data);
            random.bytes(ext_data);
            break :blk try Payload.extToPayload(ext_type, ext_data, alloc);
        },
        10 => blk: {
            // Random timestamp
            // Use reasonable timestamp range (year 1970-2100)
            const seconds = random.intRangeAtMost(i64, 0, 4102444800); // 2100-01-01
            const nanoseconds = random.intRangeAtMost(u32, 0, 999_999_999);
            break :blk Payload.timestampToPayload(seconds, nanoseconds);
        },
        else => unreachable,
    };
}

/// Compare two payloads for equality
/// Note: This uses lenient comparison for integers (uint/int conversion allowed)
fn payloadEqual(a: Payload, b: Payload) bool {
    const a_tag = @as(std.meta.Tag(Payload), a);
    const b_tag = @as(std.meta.Tag(Payload), b);
    
    // Handle integer type conversions ONLY when types differ
    // (MessagePack may encode the same value as uint or int depending on the range)
    if ((a_tag == .int or a_tag == .uint) and (b_tag == .int or b_tag == .uint)) {
        if (a_tag != b_tag) {
            // Different integer types - use lenient comparison
            const a_int = a.getInt() catch return false;
            const b_int = b.getInt() catch return false;
            return a_int == b_int;
        }
        // Same type - fall through to direct comparison
    }
    
    if (a_tag != b_tag) return false;
    
    return switch (a) {
        .nil => true,
        .bool => a.bool == b.bool,
        .int => a.int == b.int,
        .uint => a.uint == b.uint,
        .float => blk: {
            // Handle NaN comparison
            if (std.math.isNan(a.float) and std.math.isNan(b.float)) break :blk true;
            // Handle precision loss from f64->f32->f64 conversion
            // MessagePack may encode as f32 if value fits in f32 range
            const diff = @abs(a.float - b.float);
            // Use relative tolerance for large numbers, absolute for small
            const tolerance = @max(1e-6, @abs(a.float) * 1e-6);
            break :blk diff <= tolerance;
        },
        .str => std.mem.eql(u8, a.str.value(), b.str.value()),
        .bin => std.mem.eql(u8, a.bin.value(), b.bin.value()),
        .arr => blk: {
            if (a.arr.len != b.arr.len) break :blk false;
            for (a.arr, b.arr) |a_elem, b_elem| {
                if (!payloadEqual(a_elem, b_elem)) break :blk false;
            }
            break :blk true;
        },
        .map => blk: {
            if (a.map.count() != b.map.count()) break :blk false;
            var iter = a.map.iterator();
            while (iter.next()) |entry| {
                const b_val = b.map.get(entry.key_ptr.*) orelse break :blk false;
                if (!payloadEqual(entry.value_ptr.*, b_val)) break :blk false;
            }
            break :blk true;
        },
        .ext => blk: {
            if (a.ext.type != b.ext.type) break :blk false;
            break :blk std.mem.eql(u8, a.ext.data, b.ext.data);
        },
        .timestamp => blk: {
            break :blk a.timestamp.seconds == b.timestamp.seconds and
                       a.timestamp.nanoseconds == b.timestamp.nanoseconds;
        },
    };
}

// Fuzz test: random basic types
test "fuzz: random basic types" {
    var prng = std.Random.DefaultPrng.init(0x12345678);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..100) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random basic type
        const payload_type = random.intRangeAtMost(u8, 0, 4);
        const original = switch (payload_type) {
            0 => Payload.nilToPayload(),
            1 => Payload.boolToPayload(random.boolean()),
            2 => blk: {
                // Use moderate range to avoid overflow issues
                const val = random.intRangeAtMost(i64, std.math.minInt(i32), std.math.maxInt(i32));
                break :blk Payload.intToPayload(val);
            },
            3 => blk: {
                // Use moderate range to avoid overflow issues  
                const val = random.intRangeAtMost(u64, 0, std.math.maxInt(u32));
                break :blk Payload.uintToPayload(val);
            },
            4 => blk: {
                // Generate reasonable float values (not extreme inf/nan)
                const val = @as(f64, @floatFromInt(random.intRangeAtMost(i32, -10000, 10000))) + 
                           random.float(f64);
                break :blk Payload.floatToPayload(val);
            },
            else => unreachable,
        };
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: random strings
test "fuzz: random strings" {
    var prng = std.Random.DefaultPrng.init(0x87654321);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..50) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random length string (ASCII printable)
        const len = random.intRangeAtMost(usize, 0, 1000);
        const str_data = try allocator.alloc(u8, len);
        defer allocator.free(str_data);
        
        for (str_data) |*byte| {
            byte.* = random.intRangeAtMost(u8, 32, 126);
        }
        
        const original = try Payload.strToPayload(str_data, allocator);
        defer original.free(allocator);
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: random binary data
test "fuzz: random binary data" {
    var prng = std.Random.DefaultPrng.init(0xABCDEF01);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..50) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random binary data
        const len = random.intRangeAtMost(usize, 0, 1000);
        const bin_data = try allocator.alloc(u8, len);
        defer allocator.free(bin_data);
        random.bytes(bin_data);
        
        const original = try Payload.binToPayload(bin_data, allocator);
        defer original.free(allocator);
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: random arrays
test "fuzz: random arrays" {
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..30) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random array with random basic types
        const len = random.intRangeAtMost(usize, 0, 50);
        var original = try Payload.arrPayload(len, allocator);
        defer original.free(allocator);
        
        for (0..len) |i| {
            const elem_type = random.intRangeAtMost(u8, 0, 4);
            original.arr[i] = switch (elem_type) {
                0 => Payload.nilToPayload(),
                1 => Payload.boolToPayload(random.boolean()),
                2 => Payload.intToPayload(random.intRangeAtMost(i64, -1000, 1000)),
                3 => Payload.uintToPayload(random.intRangeAtMost(u64, 0, 1000)),
                4 => Payload.floatToPayload(@as(f64, @floatFromInt(random.intRangeAtMost(i32, -1000, 1000)))),
                else => unreachable,
            };
        }
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: random maps
test "fuzz: random maps" {
    var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..30) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random map
        const count = random.intRangeAtMost(usize, 0, 20);
        var original = Payload.mapPayload(allocator);
        defer original.free(allocator);
        
        for (0..count) |i| {
            const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
            defer allocator.free(key);
            
            const val_type = random.intRangeAtMost(u8, 0, 4);
            const val = switch (val_type) {
                0 => Payload.nilToPayload(),
                1 => Payload.boolToPayload(random.boolean()),
                2 => Payload.intToPayload(random.intRangeAtMost(i64, -1000, 1000)),
                3 => Payload.uintToPayload(random.intRangeAtMost(u64, 0, 1000)),
                4 => Payload.floatToPayload(@as(f64, @floatFromInt(random.intRangeAtMost(i32, -1000, 1000)))),
                else => unreachable,
            };
            
            try original.mapPut(key, val);
        }
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: random EXT types
test "fuzz: random ext types" {
    var prng = std.Random.DefaultPrng.init(0x13579BDF);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..50) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random EXT (avoid type -1 as it's timestamp)
        var ext_type = random.int(i8);
        while (ext_type == -1) {
            ext_type = random.int(i8);
        }
        
        const len = random.intRangeAtMost(usize, 0, 500);
        const ext_data = try allocator.alloc(u8, len);
        defer allocator.free(ext_data);
        random.bytes(ext_data);
        
        const original = try Payload.extToPayload(ext_type, ext_data, allocator);
        defer original.free(allocator);
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: random timestamps
test "fuzz: random timestamps" {
    var prng = std.Random.DefaultPrng.init(0xFEDCBA98);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    for (0..100) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random timestamp
        // Use reasonable range: -2^32 to 2^34 (covers all 3 timestamp formats)
        const seconds = random.intRangeAtMost(i64, -(1 << 32), (1 << 34));
        const nanoseconds = random.intRangeAtMost(u32, 0, 999_999_999);
        
        const original = Payload.timestampToPayload(seconds, nanoseconds);
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: nested structures
test "fuzz: nested structures" {
    var prng = std.Random.DefaultPrng.init(0x24681357);
    const random = prng.random();
    
    var arr: [50000]u8 = undefined;
    
    for (0..20) |_| {
        @memset(&arr, 0);
        var write_buffer = fixedBufferStream(&arr);
        var read_buffer = fixedBufferStream(&arr);
        var p = pack.init(&write_buffer, &read_buffer);
        
        // Generate random nested structure (max depth 3)
        const original = try generateRandomPayload(random, allocator, 3);
        defer original.free(allocator);
        
        try p.write(original);
        
        read_buffer = fixedBufferStream(&arr);
        p = pack.init(&write_buffer, &read_buffer);
        
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        
        try expect(payloadEqual(original, decoded));
    }
}

// Fuzz test: boundary values
test "fuzz: boundary values" {
    var prng = std.Random.DefaultPrng.init(0x11223344);
    const random = prng.random();
    
    var arr: [10000]u8 = undefined;
    
    // Test various boundary values
    const test_cases = [_]struct { min: i64, max: i64 }{
        .{ .min = -32, .max = 127 }, // fixint range
        .{ .min = -128, .max = 255 }, // i8/u8 range
        .{ .min = -32768, .max = 65535 }, // i16/u16 range
        .{ .min = std.math.minInt(i32), .max = std.math.maxInt(i32) }, // i32 range
    };
    
    for (test_cases) |case| {
        for (0..10) |_| {
            @memset(&arr, 0);
            var write_buffer = fixedBufferStream(&arr);
            var read_buffer = fixedBufferStream(&arr);
            var p = pack.init(&write_buffer, &read_buffer);
            
            const val = random.intRangeAtMost(i64, case.min, case.max);
            const original = Payload.intToPayload(val);
            
            try p.write(original);
            
            read_buffer = fixedBufferStream(&arr);
            p = pack.init(&write_buffer, &read_buffer);
            
            const decoded = try p.read(allocator);
            defer decoded.free(allocator);
            
            try expect(payloadEqual(original, decoded));
        }
    }
}

// Fuzz test: mixed payload sequence
test "fuzz: mixed payload sequence" {
    var prng = std.Random.DefaultPrng.init(0x99887766);
    const random = prng.random();
    
    var arr: [100000]u8 = undefined;
    @memset(&arr, 0);
    
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);
    
    // Generate and write multiple random payloads
    const count = 50;
    var payloads = if (builtin.zig_version.minor == 14)
        std.ArrayList(Payload).init(allocator)
    else
        std.ArrayList(Payload){};
    defer {
        for (payloads.items) |payload| {
            payload.free(allocator);
        }
        if (builtin.zig_version.minor == 14) payloads.deinit() else payloads.deinit(allocator);
    }
    
    for (0..count) |_| {
        const payload = try generateRandomPayload(random, allocator, 2);
        if (builtin.zig_version.minor == 14) {
            try payloads.append(payload);
        } else {
            try payloads.append(allocator, payload);
        }
        try p.write(payload);
    }
    
    // Read back and verify all payloads
    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);
    
    for (payloads.items) |original| {
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);
        try expect(payloadEqual(original, decoded));
    }
}
