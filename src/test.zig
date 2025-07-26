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
    const val = try p.read(allocator);
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

    const val_1 = try p.read(allocator);
    defer val_1.free(allocator);

    const val_2 = try p.read(allocator);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    try expect(arr_len_result == Payload.Errors.NotArr);

    const arr_element_result = not_arr_payload.getArrElement(0);
    try expect(arr_element_result == Payload.Errors.NotArr);

    var mut_not_arr = Payload.nilToPayload();
    const set_arr_result = mut_not_arr.setArrElement(0, Payload.nilToPayload());
    try expect(set_arr_result == Payload.Errors.NotArr);

    // Test NotMap error
    const not_map_payload = Payload.nilToPayload();
    const map_get_result = not_map_payload.mapGet("test");
    try expect(map_get_result == Payload.Errors.NotMap);

    var mut_not_map = Payload.nilToPayload();
    const map_put_result = mut_not_map.mapPut("test", Payload.nilToPayload());
    try expect(map_put_result == Payload.Errors.NotMap);
}

// Test boundary values for integers
test "integer boundary values" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test all values in negative fixint range (-32 to -1)
    for (1..33) |i| {
        const val: i64 = -@as(i64, @intCast(i));
        try p.write(.{ .int = val });
    }

    // Reset read buffer
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test zero
    try p.write(.{ .float = 0.0 });
    var val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == 0.0);

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test negative zero
    try p.write(.{ .float = -0.0 });
    val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == -0.0);

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    // Test very small positive number
    const small_pos: f64 = 1e-100;
    try p.write(.{ .float = small_pos });
    val = try p.read(allocator);
    defer val.free(allocator);
    try expect(val.float == small_pos);

    // Reset buffers
    arr = std.mem.zeroes([0xffff_f]u8);
    write_buffer = std.io.fixedBufferStream(&arr);
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
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
    var write_buffer = std.io.fixedBufferStream(&arr);
    var read_buffer = std.io.fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var large_map = Payload.mapPayload(allocator);
    defer large_map.free(allocator);

    // Store allocated keys to free them later
    var keys = std.ArrayList([]u8).init(allocator);
    defer {
        for (keys.items) |key| {
            allocator.free(key);
        }
        keys.deinit();
    }

    // Create a map with 20 entries (more than fixmap limit of 15)
    for (0..20) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        try keys.append(key);
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
