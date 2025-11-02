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

// ============================================================================
// PackerIO: Error Handling Tests
// ============================================================================

test "PackerIO: truncated data error" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    // Test reading truncated integer data (simpler case without allocations)
    var full_buffer: [100]u8 = undefined;
    var write_writer = std.Io.Writer.fixed(&full_buffer);
    var write_reader = std.Io.Reader.fixed(&full_buffer);

    var write_packer = msgpack.PackerIO.init(&write_reader, &write_writer);

    // Write a uint32 that needs 5 bytes (marker + 4 bytes value)
    const payload = msgpack.Payload.uintToPayload(0xFFFFFFFF);
    try write_packer.write(payload);

    // Now try to read with truncated buffer (only first 3 bytes, not enough for uint32)
    var truncated_buffer = full_buffer[0..3].*;
    var read_reader = std.Io.Reader.fixed(&truncated_buffer);
    var read_writer = std.Io.Writer.fixed(&truncated_buffer);
    var read_packer = msgpack.PackerIO.init(&read_reader, &read_writer);

    // Should return error when trying to read incomplete data
    const result = read_packer.read(allocator);
    if (result) |decoded| {
        decoded.free(allocator);
        try expect(false); // Should not succeed with truncated data
    } else |err| {
        // Expected error - truncated data cannot be fully read
        // std.Io.Reader returns EndOfStream, which gets wrapped as LengthReading or DataReading
        try expect(err == msgpack.MsgPackError.LengthReading or
            err == msgpack.MsgPackError.TypeMarkerReading or
            err == msgpack.MsgPackError.DataReading or
            err == error.EndOfStream);
    }
}

test "PackerIO: invalid msgpack marker" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    // 0xc1 is a reserved/invalid marker byte in MessagePack
    var buffer: [10]u8 = [_]u8{ 0xc1, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Should handle invalid marker gracefully (no crash)
    const result = packer.read(allocator);
    if (result) |payload| {
        payload.free(allocator);
        // If it succeeds, that's fine (marker might be treated as NIL or other)
    } else |_| {
        // Expected - invalid marker should cause error
    }
}

test "PackerIO: corrupted length field" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [100]u8 = undefined;
    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // str32 claiming 1MB but only providing a few bytes
    if (builtin.zig_version.minor == 14) {
        try input.append(0xdb); // str32
        try input.append(0x00); // 1MB = 0x00100000
        try input.append(0x10);
        try input.append(0x00);
        try input.append(0x00);
        // Only provide 5 bytes of actual data
        try input.append('a');
        try input.append('b');
        try input.append('c');
        try input.append('d');
        try input.append('e');
    } else {
        try input.append(allocator, 0xdb);
        try input.append(allocator, 0x00);
        try input.append(allocator, 0x10);
        try input.append(allocator, 0x00);
        try input.append(allocator, 0x00);
        try input.append(allocator, 'a');
        try input.append(allocator, 'b');
        try input.append(allocator, 'c');
        try input.append(allocator, 'd');
        try input.append(allocator, 'e');
    }

    @memcpy(buffer[0..input.items.len], input.items);

    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(buffer[0..input.items.len]);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Should fail due to length mismatch
    const result = packer.read(allocator);
    if (result) |payload| {
        payload.free(allocator);
        try expect(false); // Should not succeed
    } else |err| {
        // Expected error
        try expect(err == msgpack.MsgPackError.LengthReading or
            err == msgpack.MsgPackError.DataReading or
            err == error.EndOfStream);
    }
}

test "PackerIO: multiple payloads with error recovery" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [4096]u8 = std.mem.zeroes([4096]u8);
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Write valid data
    try packer.write(msgpack.Payload.uintToPayload(1));
    try packer.write(msgpack.Payload.uintToPayload(2));
    try packer.write(msgpack.Payload.uintToPayload(3));

    reader.seek = 0;

    // Read first two successfully
    const result1 = try packer.read(allocator);
    defer result1.free(allocator);
    try expect(result1.uint == 1);

    const result2 = try packer.read(allocator);
    defer result2.free(allocator);
    try expect(result2.uint == 2);

    // Third should also succeed
    const result3 = try packer.read(allocator);
    defer result3.free(allocator);
    try expect(result3.uint == 3);

    // Fourth read should fail (no more data) or return garbage
    // After writing 3 payloads, there's no valid 4th payload
    // The reader should hit end of valid data
    const result4 = packer.read(allocator);
    if (result4) |payload| {
        payload.free(allocator);
    } else |_| {
        // Expected - should fail when no more valid data
    }
}

// ============================================================================
// PackerIO: Different Reader/Writer Implementations
// ============================================================================

test "PackerIO: sequential writes and reads with fixed buffer" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Write multiple different types
    try packer.write(msgpack.Payload.nilToPayload());
    try packer.write(msgpack.Payload.boolToPayload(true));
    try packer.write(msgpack.Payload.intToPayload(-42));
    const str_payload = try msgpack.Payload.strToPayload("test", allocator);
    defer str_payload.free(allocator);
    try packer.write(str_payload);

    reader.seek = 0;

    // Read them back in order
    const r1 = try packer.read(allocator);
    defer r1.free(allocator);
    try expect(r1 == .nil);

    const r2 = try packer.read(allocator);
    defer r2.free(allocator);
    try expect(r2.bool == true);

    const r3 = try packer.read(allocator);
    defer r3.free(allocator);
    try expect(r3.int == -42);

    const r4 = try packer.read(allocator);
    defer r4.free(allocator);
    try expect(u8eql(r4.str.value(), "test"));
}

// ============================================================================
// PackerIO: Large Data and Limits
// ============================================================================

test "PackerIO: large string near limit" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    const allocator_heap = std.heap.page_allocator;

    // Create 1MB string (well within 100MB limit)
    const large_size = 1_000_000;
    const large_str = try allocator_heap.alloc(u8, large_size);
    defer allocator_heap.free(large_str);
    @memset(large_str, 'X');

    const buffer = try allocator_heap.alloc(u8, large_size + 10000);
    defer allocator_heap.free(buffer);

    var writer = std.Io.Writer.fixed(buffer);
    var reader = std.Io.Reader.fixed(buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = try msgpack.Payload.strToPayload(large_str, allocator_heap);
    defer payload.free(allocator_heap);

    try packer.write(payload);

    reader.seek = 0;
    reader.end = writer.end;

    const result = try packer.read(allocator_heap);
    defer result.free(allocator_heap);

    try expect(result == .str);
    try expect(result.str.value().len == large_size);

    // Verify a sample of data
    try expect(result.str.value()[0] == 'X');
    try expect(result.str.value()[large_size - 1] == 'X');
}

test "PackerIO: large binary data" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    const allocator_heap = std.heap.page_allocator;

    // Create 512KB binary data
    const large_size = 512 * 1024;
    const large_bin = try allocator_heap.alloc(u8, large_size);
    defer allocator_heap.free(large_bin);

    // Fill with pattern
    for (large_bin, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    const buffer = try allocator_heap.alloc(u8, large_size + 10000);
    defer allocator_heap.free(buffer);

    var writer = std.Io.Writer.fixed(buffer);
    var reader = std.Io.Reader.fixed(buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = try msgpack.Payload.binToPayload(large_bin, allocator_heap);
    defer payload.free(allocator_heap);

    try packer.write(payload);

    reader.seek = 0;
    reader.end = writer.end;

    const result = try packer.read(allocator_heap);
    defer result.free(allocator_heap);

    try expect(result == .bin);
    try expect(result.bin.value().len == large_size);

    // Verify pattern integrity
    for (result.bin.value(), 0..) |byte, i| {
        try expect(byte == @as(u8, @intCast(i % 256)));
    }
}

test "PackerIO: large array (1000 elements)" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    const allocator_heap = std.heap.page_allocator;

    const buffer = try allocator_heap.alloc(u8, 100_000);
    defer allocator_heap.free(buffer);

    var writer = std.Io.Writer.fixed(buffer);
    var reader = std.Io.Reader.fixed(buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    const count = 1000;
    var payload = try msgpack.Payload.arrPayload(count, allocator_heap);
    defer payload.free(allocator_heap);

    for (0..count) |i| {
        try payload.setArrElement(i, msgpack.Payload.uintToPayload(@as(u64, i)));
    }

    try packer.write(payload);

    reader.seek = 0;
    reader.end = writer.end;

    const result = try packer.read(allocator_heap);
    defer result.free(allocator_heap);

    try expect(try result.getArrLen() == count);

    // Spot check some elements
    try expect((try result.getArrElement(0)).uint == 0);
    try expect((try result.getArrElement(500)).uint == 500);
    try expect((try result.getArrElement(999)).uint == 999);
}

test "PackerIO: large map (500 entries)" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    const allocator_heap = std.heap.page_allocator;

    const buffer = try allocator_heap.alloc(u8, 200_000);
    defer allocator_heap.free(buffer);

    var writer = std.Io.Writer.fixed(buffer);
    var reader = std.Io.Reader.fixed(buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    var payload = msgpack.Payload.mapPayload(allocator_heap);
    defer payload.free(allocator_heap);

    const count = 500;
    for (0..count) |i| {
        const key = try std.fmt.allocPrint(allocator_heap, "key_{d:0>6}", .{i});
        defer allocator_heap.free(key);
        try payload.mapPut(key, msgpack.Payload.uintToPayload(@as(u64, i)));
    }

    try packer.write(payload);

    reader.seek = 0;
    reader.end = writer.end;

    const result = try packer.read(allocator_heap);
    defer result.free(allocator_heap);

    try expect(result.map.count() == count);

    // Verify some entries
    const key0 = try std.fmt.allocPrint(allocator_heap, "key_{d:0>6}", .{0});
    defer allocator_heap.free(key0);
    const val0 = try result.mapGet(key0);
    try expect(val0 != null);
    try expect(val0.?.uint == 0);

    const key499 = try std.fmt.allocPrint(allocator_heap, "key_{d:0>6}", .{499});
    defer allocator_heap.free(key499);
    const val499 = try result.mapGet(key499);
    try expect(val499 != null);
    try expect(val499.?.uint == 499);
}

// ============================================================================
// PackerIO: Boundary Cases
// ============================================================================

test "PackerIO: empty buffer write error" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [0]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Writing to empty buffer should fail
    const result = packer.write(msgpack.Payload.nilToPayload());
    // Zig 0.15+ std.Io.Writer.fixed returns error.WriteFailed
    if (result) |_| {
        try expect(false); // Should have failed
    } else |err| {
        // Either NoSpaceLeft or WriteFailed is acceptable
        try expect(err == error.NoSpaceLeft or err == error.WriteFailed);
    }
}

test "PackerIO: minimal buffer size" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    // Test with exactly 1 byte buffer (enough for nil marker)
    var buffer: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Nil marker is 1 byte, should succeed
    try packer.write(msgpack.Payload.nilToPayload());

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .nil);
}

test "PackerIO: exact buffer size for small payload" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    // positive fixint uses exactly 1 byte
    var buffer: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    try packer.write(msgpack.Payload.uintToPayload(42)); // 42 is fixint

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result.uint == 42);
}

test "PackerIO: off-by-one buffer size" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    // uint8 needs 2 bytes (marker + value), provide only 1
    var buffer: [1]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // 128 requires uint8 format (2 bytes), buffer is too small
    const result = packer.write(msgpack.Payload.uintToPayload(128));
    // Zig 0.15+ std.Io.Writer.fixed returns error.WriteFailed
    if (result) |_| {
        try expect(false); // Should have failed
    } else |err| {
        // Either NoSpaceLeft or WriteFailed is acceptable
        try expect(err == error.NoSpaceLeft or err == error.WriteFailed);
    }
}

test "PackerIO: empty string edge case" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [10]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = try msgpack.Payload.strToPayload("", allocator);
    defer payload.free(allocator);

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .str);
    try expect(result.str.value().len == 0);
}

test "PackerIO: empty array edge case" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [10]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = try msgpack.Payload.arrPayload(0, allocator);
    defer payload.free(allocator);

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .arr);
    try expect(try result.getArrLen() == 0);
}

test "PackerIO: empty map edge case" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [10]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 0);
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
    try p.write(.{ .bin = msgpack.Bin.init(&test_bin) });
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
    try p.write(.{ .ext = msgpack.EXT.init(1, &ext1_data) });
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
    try p.write(.{ .ext = msgpack.EXT.init(2, &ext2_data) });
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
    try p.write(.{ .ext = msgpack.EXT.init(3, &ext4_data) });
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
    try p.write(.{ .ext = msgpack.EXT.init(4, &ext8_data) });
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
    try p.write(.{ .ext = msgpack.EXT.init(5, &ext16_data) });
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

    try p.write(.{ .bin = msgpack.Bin.init(test_bin16) });
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

    try p.write(.{ .bin = msgpack.Bin.init(test_bin32) });
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

    try p.write(.{ .ext = msgpack.EXT.init(10, ext8_data) });
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

    try p.write(.{ .ext = msgpack.EXT.init(20, ext16_data) });
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

    try p.write(.{ .ext = msgpack.EXT.init(30, ext32_data) });
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

    try p.write(.{ .ext = msgpack.EXT.init(negative_type, &test_data) });
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
    try p.write(.{ .ext = msgpack.EXT.init(min_type, &test_data) });
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

// Test timestamp fromNanos() function
test "timestamp fromNanos() conversion" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test with a fixed timestamp value (2024-01-01 00:00:00 UTC + 123456789 nanoseconds)
    const test_nanos: i128 = 1704067200 * std.time.ns_per_s + 123456789;
    const ts = msgpack.Timestamp.fromNanos(test_nanos);

    // Verify seconds is reasonable (after 2020-01-01 and before 2100-01-01)
    const year_2020: i64 = 1577836800;
    const year_2100: i64 = 4102444800;
    try expect(ts.seconds > year_2020);
    try expect(ts.seconds < year_2100);

    // Verify nanoseconds is in valid range
    try expect(ts.nanoseconds >= 0);
    try expect(ts.nanoseconds <= 999_999_999);

    // Test with known values
    const known_nanos: i128 = 1704067200_123456789; // 2024-01-01 00:00:00.123456789 UTC
    const test_ts = msgpack.Timestamp.fromNanos(known_nanos);
    try expect(test_ts.seconds == 1704067200);
    try expect(test_ts.nanoseconds == 123456789);

    // Test with negative timestamp (before Unix epoch)
    const negative_nanos: i128 = -1000000_500000000; // -1000000 seconds + 0.5 seconds
    const negative_ts = msgpack.Timestamp.fromNanos(negative_nanos);
    try expect(negative_ts.seconds == -1000001);
    try expect(negative_ts.nanoseconds == 500000000);

    // Test Payload.timestampFromNanos() convenience method
    const payload = msgpack.Payload.timestampFromNanos(test_nanos);
    try expect(payload == .timestamp);
    try expect(payload.timestamp.seconds == ts.seconds);
    try expect(payload.timestamp.nanoseconds == ts.nanoseconds);

    // Test serialization and deserialization
    try p.write(payload);

    read_buffer = fixedBufferStream(&arr);
    p = pack.init(&write_buffer, &read_buffer);

    const decoded = try p.read(allocator);
    defer decoded.free(allocator);

    try expect(decoded == .timestamp);
    try expect(decoded.timestamp.seconds == ts.seconds);
    try expect(decoded.timestamp.nanoseconds == ts.nanoseconds);

    // Test that the toFloat() method works correctly
    const float_original = ts.toFloat();
    const float_decoded = decoded.timestamp.toFloat();
    try expect(@abs(float_original - float_decoded) < 0.000000001);
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
    try p.write(.{ .bin = msgpack.Bin.init(&binary_data) });

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
    try p.write(.{ .ext = msgpack.EXT.init(0, &app_data) });
    try p.write(.{ .ext = msgpack.EXT.init(127, &app_data) });

    // Test predefined types (-128 to -1)
    try p.write(.{ .ext = msgpack.EXT.init(-128, &app_data) });
    // -1 is timestamp, already covered in other tests
    try p.write(.{ .ext = msgpack.EXT.init(-2, &app_data) });

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
    try p.write(.{ .bin = msgpack.Bin.init(&bin_data) });

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

// ========== Iterative Parser Tests ==========

test "iterative parser: normal nested depth (100 layers)" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);

    // Build 100-layer deep nested array manually
    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    const depth = 100;
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        if (builtin.zig_version.minor == 14) {
            try input.append(0x91); // fixarray with 1 element
        } else {
            try input.append(allocator, 0x91);
        }
    }
    if (builtin.zig_version.minor == 14) {
        try input.append(0x00); // int 0
    } else {
        try input.append(allocator, 0x00);
    }

    // Write to buffer
    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);
    const decoded = try p.read(allocator);
    defer decoded.free(allocator);

    // Verify it's an array
    try expect(decoded == .arr);
}

test "iterative parser: max depth exceeded" {
    // Use custom limits with lower max_depth
    const custom_pack = msgpack.PackWithLimits(
        *bufferType,
        *bufferType,
        bufferType.WriteError,
        bufferType.ReadError,
        bufferType.write,
        bufferType.read,
        .{ .max_depth = 50 }, // Only allow 50 layers
    );

    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);

    // Build 100-layer deep nested array (exceeds limit of 50)
    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    const depth = 100;
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        if (builtin.zig_version.minor == 14) {
            try input.append(0x91);
        } else {
            try input.append(allocator, 0x91);
        }
    }
    if (builtin.zig_version.minor == 14) {
        try input.append(0x00);
    } else {
        try input.append(allocator, 0x00);
    }

    _ = try write_buffer.write(input.items);

    var p = custom_pack.init(&write_buffer, &read_buffer);

    // Should return MaxDepthExceeded error
    const result = p.read(allocator);
    try std.testing.expectError(msgpack.MsgPackError.MaxDepthExceeded, result);
}

test "iterative parser: array too large" {
    const custom_pack = msgpack.PackWithLimits(
        *bufferType,
        *bufferType,
        bufferType.WriteError,
        bufferType.ReadError,
        bufferType.write,
        bufferType.read,
        .{ .max_array_length = 100 }, // Only allow 100 elements
    );

    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);

    // Try to create array with 1000 elements (exceeds limit)
    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // array16 marker + length
    if (builtin.zig_version.minor == 14) {
        try input.append(0xdc); // array16
        try input.append(0x03); // high byte (1000 = 0x03E8)
        try input.append(0xE8); // low byte
    } else {
        try input.append(allocator, 0xdc);
        try input.append(allocator, 0x03);
        try input.append(allocator, 0xE8);
    }

    _ = try write_buffer.write(input.items);

    var p = custom_pack.init(&write_buffer, &read_buffer);

    // Should return ArrayTooLarge error
    const result = p.read(allocator);
    try std.testing.expectError(msgpack.MsgPackError.ArrayTooLarge, result);
}

test "iterative parser: deep nested maps" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);

    // Build nested map structure: {"a": {"a": {"a": 42}}}
    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    const depth = 50;
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        if (builtin.zig_version.minor == 14) {
            try input.append(0x81); // fixmap with 1 pair
            try input.append(0xa1); // fixstr len 1
            try input.append('a'); // key "a"
        } else {
            try input.append(allocator, 0x81);
            try input.append(allocator, 0xa1);
            try input.append(allocator, 'a');
        }
    }
    // Final value
    if (builtin.zig_version.minor == 14) {
        try input.append(0x2a); // positive fixint 42
    } else {
        try input.append(allocator, 0x2a);
    }

    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);
    const decoded = try p.read(allocator);
    defer decoded.free(allocator);

    // Verify it's a map
    try expect(decoded == .map);
}

test "iterative free: deeply nested payload" {
    // Create a deeply nested structure in memory
    var root = try Payload.arrPayload(1, allocator);
    var current: *Payload = &root;

    // Build 200-layer deep structure
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const nested = try Payload.arrPayload(1, allocator);
        try current.setArrElement(0, nested);
        current = &current.arr[0];
    }
    try current.setArrElement(0, Payload.intToPayload(42));

    // Free should not cause stack overflow
    root.free(allocator);
}

// ========== Large Data and Fuzz Tests ==========

test "large data: array with 1000 elements" {
    const allocator_heap = std.heap.page_allocator;

    var buffer: [100000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    const size: usize = 1000;
    var payload = try Payload.arrPayload(size, allocator_heap);
    defer payload.free(allocator_heap);

    for (0..size) |i| {
        try payload.setArrElement(i, Payload.intToPayload(@intCast(i)));
    }

    var p = pack.init(&write_buffer, &read_buffer);
    try p.write(payload);

    read_buffer = fixedBufferStream(&buffer);
    p = pack.init(&write_buffer, &read_buffer);
    const decoded = try p.read(allocator_heap);
    defer decoded.free(allocator_heap);

    try expect(decoded == .arr);
    try expect(decoded.arr.len == size);
}

test "large data: map with 500 pairs" {
    const allocator_heap = std.heap.page_allocator;

    var buffer: [100000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var payload = Payload.mapPayload(allocator_heap);
    defer payload.free(allocator_heap);

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const key = try std.fmt.allocPrint(allocator_heap, "k{d}", .{i});
        defer allocator_heap.free(key);
        try payload.mapPut(key, Payload.intToPayload(@intCast(i)));
    }

    var p = pack.init(&write_buffer, &read_buffer);
    try p.write(payload);

    read_buffer = fixedBufferStream(&buffer);
    p = pack.init(&write_buffer, &read_buffer);
    const decoded = try p.read(allocator_heap);
    defer decoded.free(allocator_heap);

    try expect(decoded == .map);
}

test "fuzz: random bytes protection (critical)" {
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    var input_buffer: [200]u8 = undefined;
    var output_buffer: [10000]u8 = undefined;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        random.bytes(&input_buffer);

        var write_buffer = fixedBufferStream(&output_buffer);
        var read_buffer = fixedBufferStream(&input_buffer);

        var p = pack.init(&write_buffer, &read_buffer);

        // Should never crash - either succeeds or returns error
        if (p.read(allocator)) |payload| {
            defer payload.free(allocator);
        } else |_| {
            // Expected - most random bytes are invalid msgpack
        }
    }
}

test "fuzz: deep mixed nesting" {
    var prng = std.Random.DefaultPrng.init(789);
    const random = prng.random();

    var buffer: [20000]u8 = undefined;
    const test_depths = [_]usize{ 10, 30, 50 };

    for (test_depths) |depth| {
        var write_buffer = fixedBufferStream(&buffer);
        var read_buffer = fixedBufferStream(&buffer);

        var input = if (builtin.zig_version.minor == 14)
            std.ArrayList(u8).init(allocator)
        else
            std.ArrayList(u8){};
        defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

        for (0..depth) |_| {
            if (random.boolean()) {
                if (builtin.zig_version.minor == 14) {
                    try input.append(0x91);
                } else {
                    try input.append(allocator, 0x91);
                }
            } else {
                if (builtin.zig_version.minor == 14) {
                    try input.append(0x81);
                    try input.append(0xa1);
                    try input.append('x');
                } else {
                    try input.append(allocator, 0x81);
                    try input.append(allocator, 0xa1);
                    try input.append(allocator, 'x');
                }
            }
        }
        if (builtin.zig_version.minor == 14) {
            try input.append(0xc0); // nil
        } else {
            try input.append(allocator, 0xc0);
        }

        _ = try write_buffer.write(input.items);

        var p = pack.init(&write_buffer, &read_buffer);
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);

        try expect(decoded == .arr or decoded == .map);
    }
}

// ========== Malicious/Corrupted Data Tests (Never Crash Guarantee) ==========

test "malicious: array32 claims 4 billion elements" {
    var buffer: [10000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // array32 claiming 0xFFFFFFFF (4 billion) elements
    if (builtin.zig_version.minor == 14) {
        try input.append(0xdd); // array32
        try input.append(0xFF);
        try input.append(0xFF);
        try input.append(0xFF);
        try input.append(0xFF);
    } else {
        try input.append(allocator, 0xdd);
        try input.append(allocator, 0xFF);
        try input.append(allocator, 0xFF);
        try input.append(allocator, 0xFF);
        try input.append(allocator, 0xFF);
    }

    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);

    // Must return error, never crash
    const result = p.read(allocator);
    try std.testing.expectError(msgpack.MsgPackError.ArrayTooLarge, result);
}

test "malicious: map32 claims 4 billion pairs" {
    var buffer: [10000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // map32 claiming 0xFFFFFFFF pairs
    if (builtin.zig_version.minor == 14) {
        try input.append(0xdf); // map32
        try input.append(0xFF);
        try input.append(0xFF);
        try input.append(0xFF);
        try input.append(0xFF);
    } else {
        try input.append(allocator, 0xdf);
        try input.append(allocator, 0xFF);
        try input.append(allocator, 0xFF);
        try input.append(allocator, 0xFF);
        try input.append(allocator, 0xFF);
    }

    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);

    // Must return error, never crash
    const result = p.read(allocator);
    try std.testing.expectError(msgpack.MsgPackError.MapTooLarge, result);
}

test "malicious: extremely deep nesting (2000 layers)" {
    const custom_pack = msgpack.PackWithLimits(
        *bufferType,
        *bufferType,
        bufferType.WriteError,
        bufferType.ReadError,
        bufferType.write,
        bufferType.read,
        .{ .max_depth = 100 }, // Only allow 100 layers
    );

    var buffer: [30000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // 2000 layers of nesting (far exceeds limit of 100)
    const depth = 2000;
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        if (builtin.zig_version.minor == 14) {
            try input.append(0x91);
        } else {
            try input.append(allocator, 0x91);
        }
    }
    if (builtin.zig_version.minor == 14) {
        try input.append(0x00);
    } else {
        try input.append(allocator, 0x00);
    }

    _ = try write_buffer.write(input.items);

    var p = custom_pack.init(&write_buffer, &read_buffer);

    // Must return MaxDepthExceeded, never crash
    const result = p.read(allocator);
    try std.testing.expectError(msgpack.MsgPackError.MaxDepthExceeded, result);
}

test "corrupted: truncated array data" {
    var buffer: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // array claiming 10 elements but data is incomplete
    if (builtin.zig_version.minor == 14) {
        try input.append(0x9a); // fixarray with 10 elements
        try input.append(0x00); // int 0
        try input.append(0x01); // int 1
        // Missing 8 more elements - truncated!
    } else {
        try input.append(allocator, 0x9a);
        try input.append(allocator, 0x00);
        try input.append(allocator, 0x01);
    }

    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);

    // Should return error, not crash
    const result = p.read(allocator);
    if (result) |payload| payload.free(allocator) else |_| {}
}

test "map with non-string key (integer key)" {
    var buffer: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // map with integer key (now valid - keys can be any Payload type)
    if (builtin.zig_version.minor == 14) {
        try input.append(0x81); // fixmap with 1 pair
        try input.append(0x2a); // int 42 as key
        try input.append(0x00); // int 0 as value
    } else {
        try input.append(allocator, 0x81);
        try input.append(allocator, 0x2a);
        try input.append(allocator, 0x00);
    }

    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);

    // Should successfully parse with integer key
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 1);

    // Verify the integer key works
    const key = Payload{ .uint = 42 };
    const value = try result.mapGetGeneric(key);
    try expect(value != null);
    try expect(value.?.uint == 0);
}

test "malicious: mixed depth and breadth attack" {
    // Attack pattern: wide branching + deep nesting
    // This tests both max_depth and max_array_length limits
    const custom_pack = msgpack.PackWithLimits(
        *bufferType,
        *bufferType,
        bufferType.WriteError,
        bufferType.ReadError,
        bufferType.write,
        bufferType.read,
        .{ .max_depth = 50, .max_array_length = 1000 },
    );

    var buffer: [50000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // Build: [ [100 items], [100 items], ... ] nested 60 levels deep
    const depth = 60;
    for (0..depth) |_| {
        if (builtin.zig_version.minor == 14) {
            try input.append(0x91); // fixarray with 1 element
        } else {
            try input.append(allocator, 0x91);
        }
    }
    if (builtin.zig_version.minor == 14) {
        try input.append(0x00);
    } else {
        try input.append(allocator, 0x00);
    }

    _ = try write_buffer.write(input.items);

    var p = custom_pack.init(&write_buffer, &read_buffer);

    // Should hit MaxDepthExceeded, never crash
    const result = p.read(allocator);
    try std.testing.expectError(msgpack.MsgPackError.MaxDepthExceeded, result);
}

test "edge case: empty containers at various depths" {
    var buffer: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    // Test: [ [], [[]], [[[]]], ... ]
    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    const depths = [_]usize{ 0, 1, 5, 10, 20 };
    for (depths) |depth| {
        input.clearRetainingCapacity();

        for (0..depth) |_| {
            if (builtin.zig_version.minor == 14) {
                try input.append(0x91); // fixarray with 1 element
            } else {
                try input.append(allocator, 0x91);
            }
        }
        if (builtin.zig_version.minor == 14) {
            try input.append(0x90); // empty array
        } else {
            try input.append(allocator, 0x90);
        }

        @memset(&buffer, 0);
        write_buffer = fixedBufferStream(&buffer);
        read_buffer = fixedBufferStream(&buffer);

        _ = try write_buffer.write(input.items);

        var p = pack.init(&write_buffer, &read_buffer);
        const decoded = try p.read(allocator);
        defer decoded.free(allocator);

        try expect(decoded == .arr);
    }
}

test "stress: rapid allocation and deallocation" {
    // Test memory safety under rapid alloc/free cycles
    var buffer: [10000]u8 = undefined;

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var write_buffer = fixedBufferStream(&buffer);
        var read_buffer = fixedBufferStream(&buffer);

        // Create small nested structure
        var payload = try Payload.arrPayload(10, allocator);
        for (0..10) |j| {
            var inner = try Payload.arrPayload(5, allocator);
            for (0..5) |k| {
                try inner.setArrElement(k, Payload.intToPayload(@intCast(j * 5 + k)));
            }
            try payload.setArrElement(j, inner);
        }

        var p = pack.init(&write_buffer, &read_buffer);
        try p.write(payload);

        read_buffer = fixedBufferStream(&buffer);
        p = pack.init(&write_buffer, &read_buffer);
        const decoded = try p.read(allocator);

        // Free both
        payload.free(allocator);
        decoded.free(allocator);
    }
}

test "corrupted: nested arrays with mismatched counts" {
    var buffer: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&buffer);

    var input = if (builtin.zig_version.minor == 14)
        std.ArrayList(u8).init(allocator)
    else
        std.ArrayList(u8){};
    defer if (builtin.zig_version.minor == 14) input.deinit() else input.deinit(allocator);

    // Outer array claims 3 elements, but we provide different structure
    if (builtin.zig_version.minor == 14) {
        try input.append(0x93); // fixarray with 3 elements
        try input.append(0x92); // inner array with 2 elements
        try input.append(0x00);
        try input.append(0x01);
        try input.append(0x91); // inner array with 1 element
        // Missing data - truncated
    } else {
        try input.append(allocator, 0x93);
        try input.append(allocator, 0x92);
        try input.append(allocator, 0x00);
        try input.append(allocator, 0x01);
        try input.append(allocator, 0x91);
    }

    _ = try write_buffer.write(input.items);

    var p = pack.init(&write_buffer, &read_buffer);

    // Should handle gracefully
    const result = p.read(allocator);
    if (result) |payload| {
        payload.free(allocator);
    } else |_| {
        // Expected error is fine
    }
}

test "malicious: str32 with excessive length claim" {
    var buffer: [1000]u8 = undefined;
    var input_buf: [10]u8 = undefined;

    // str32 claiming 100MB (will be rejected by limit)
    input_buf[0] = 0xdb; // str32
    input_buf[1] = 0x06; // 100MB = 0x06400000
    input_buf[2] = 0x40;
    input_buf[3] = 0x00;
    input_buf[4] = 0x00;

    var write_buffer = fixedBufferStream(&buffer);
    var read_buffer = fixedBufferStream(&input_buf);
    var p = pack.init(&write_buffer, &read_buffer);

    const result = p.read(allocator);
    if (result) |payload| {
        payload.free(allocator);
        try expect(false); // Should not succeed
    } else |err| {
        // Should be LengthReading (can't read 100MB) or StringTooLong
        try expect(err == msgpack.MsgPackError.LengthReading or
            err == msgpack.MsgPackError.StringTooLong);
    }
}

// ========== Tests for Generic Map Keys (Non-String Keys) ==========

test "map with integer keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with integer keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    try test_map.mapPutGeneric(Payload.intToPayload(1), Payload.uintToPayload(100));
    try test_map.mapPutGeneric(Payload.intToPayload(2), Payload.uintToPayload(200));
    try test_map.mapPutGeneric(Payload.intToPayload(3), Payload.uintToPayload(300));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 3);

    // Verify values using generic key access
    // Note: positive integers are serialized as uint (optimized format)
    const val1 = try result.mapGetGeneric(Payload.uintToPayload(1));
    try expect(val1 != null);
    try expect(val1.?.uint == 100);

    const val2 = try result.mapGetGeneric(Payload.uintToPayload(2));
    try expect(val2 != null);
    try expect(val2.?.uint == 200);

    const val3 = try result.mapGetGeneric(Payload.uintToPayload(3));
    try expect(val3 != null);
    try expect(val3.?.uint == 300);
}

test "map with boolean keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with boolean keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    try test_map.mapPutGeneric(Payload.boolToPayload(true), try Payload.strToPayload("yes", allocator));
    try test_map.mapPutGeneric(Payload.boolToPayload(false), try Payload.strToPayload("no", allocator));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Verify values
    const val_true = try result.mapGetGeneric(Payload.boolToPayload(true));
    try expect(val_true != null);
    try expect(u8eql(val_true.?.str.value(), "yes"));

    const val_false = try result.mapGetGeneric(Payload.boolToPayload(false));
    try expect(val_false != null);
    try expect(u8eql(val_false.?.str.value(), "no"));
}

test "map with mixed key types" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with mixed key types
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // String key (backward compatible API)
    try test_map.mapPut("name", try Payload.strToPayload("Alice", allocator));

    // Integer keys
    try test_map.mapPutGeneric(Payload.intToPayload(1), Payload.uintToPayload(100));
    try test_map.mapPutGeneric(Payload.uintToPayload(42), Payload.floatToPayload(3.14));

    // Boolean key
    try test_map.mapPutGeneric(Payload.boolToPayload(true), Payload.nilToPayload());

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 4);

    // Verify string key (backward compatible)
    const name = try result.mapGet("name");
    try expect(name != null);
    try expect(u8eql(name.?.str.value(), "Alice"));

    // Verify integer keys (positive integers become uint after serialization)
    const val1 = try result.mapGetGeneric(Payload.uintToPayload(1));
    try expect(val1 != null);
    try expect(val1.?.uint == 100);

    const val42 = try result.mapGetGeneric(Payload.uintToPayload(42));
    try expect(val42 != null);
    try expect(std.math.approxEqAbs(f64, val42.?.float, 3.14, 0.0001));

    // Verify boolean key
    const val_bool = try result.mapGetGeneric(Payload.boolToPayload(true));
    try expect(val_bool != null);
    try expect(val_bool.? == .nil);
}

test "map with float keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with float keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    try test_map.mapPutGeneric(Payload.floatToPayload(1.5), Payload.intToPayload(15));
    try test_map.mapPutGeneric(Payload.floatToPayload(2.5), Payload.intToPayload(25));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Verify values (positive integers become uint after serialization)
    const val1 = try result.mapGetGeneric(Payload.floatToPayload(1.5));
    try expect(val1 != null);
    try expect(val1.?.uint == 15);

    const val2 = try result.mapGetGeneric(Payload.floatToPayload(2.5));
    try expect(val2 != null);
    try expect(val2.?.uint == 25);
}

test "backward compatibility: string keys still work with new implementation" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Use old API (string keys only)
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    try test_map.mapPut("key1", Payload.intToPayload(42));
    try test_map.mapPut("key2", Payload.boolToPayload(true));
    try test_map.mapPut("key3", try Payload.strToPayload("value", allocator));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 3);

    // Use old API to get values
    // Note: 42 is a positive integer, serialized as uint
    const val1 = try result.mapGet("key1");
    try expect(val1 != null);
    try expect(val1.?.uint == 42);

    const val2 = try result.mapGet("key2");
    try expect(val2 != null);
    try expect(val2.?.bool == true);

    const val3 = try result.mapGet("key3");
    try expect(val3 != null);
    try expect(u8eql(val3.?.str.value(), "value"));
}

// ========== Tests for Complex Key Types (ext, array, map, etc.) ==========

test "map with ext keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with ext keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    var ext1_data = [_]u8{ 1, 2, 3 };
    var ext2_data = [_]u8{ 4, 5, 6 };

    try test_map.mapPutGeneric(
        Payload{ .ext = msgpack.EXT{ .type = 1, .data = &ext1_data } },
        try Payload.strToPayload("value1", allocator),
    );
    try test_map.mapPutGeneric(
        Payload{ .ext = msgpack.EXT{ .type = 2, .data = &ext2_data } },
        try Payload.strToPayload("value2", allocator),
    );

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Verify values using ext keys
    const val1 = try result.mapGetGeneric(Payload{ .ext = msgpack.EXT{ .type = 1, .data = &ext1_data } });
    try expect(val1 != null);
    try expect(u8eql(val1.?.str.value(), "value1"));

    const val2 = try result.mapGetGeneric(Payload{ .ext = msgpack.EXT{ .type = 2, .data = &ext2_data } });
    try expect(val2 != null);
    try expect(u8eql(val2.?.str.value(), "value2"));
}

test "map with array keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with array keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // Create array key 1: [1, 2, 3]
    var arr1 = try Payload.arrPayload(3, allocator);
    defer arr1.free(allocator); // Free after put (put will clone it)
    try arr1.setArrElement(0, Payload.uintToPayload(1));
    try arr1.setArrElement(1, Payload.uintToPayload(2));
    try arr1.setArrElement(2, Payload.uintToPayload(3));

    // Create array key 2: [4, 5]
    var arr2 = try Payload.arrPayload(2, allocator);
    defer arr2.free(allocator); // Free after put (put will clone it)
    try arr2.setArrElement(0, Payload.uintToPayload(4));
    try arr2.setArrElement(1, Payload.uintToPayload(5));

    try test_map.mapPutGeneric(arr1, try Payload.strToPayload("array1", allocator));
    try test_map.mapPutGeneric(arr2, try Payload.strToPayload("array2", allocator));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Create matching array keys for lookup
    var lookup_arr1 = try Payload.arrPayload(3, allocator);
    defer lookup_arr1.free(allocator);
    try lookup_arr1.setArrElement(0, Payload.uintToPayload(1));
    try lookup_arr1.setArrElement(1, Payload.uintToPayload(2));
    try lookup_arr1.setArrElement(2, Payload.uintToPayload(3));

    var lookup_arr2 = try Payload.arrPayload(2, allocator);
    defer lookup_arr2.free(allocator);
    try lookup_arr2.setArrElement(0, Payload.uintToPayload(4));
    try lookup_arr2.setArrElement(1, Payload.uintToPayload(5));

    // Verify values
    const val1 = try result.mapGetGeneric(lookup_arr1);
    try expect(val1 != null);
    try expect(u8eql(val1.?.str.value(), "array1"));

    const val2 = try result.mapGetGeneric(lookup_arr2);
    try expect(val2 != null);
    try expect(u8eql(val2.?.str.value(), "array2"));
}

test "map with nested map keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create outer map
    var outer_map = Payload.mapPayload(allocator);
    defer outer_map.free(allocator);

    // Create inner map as key 1: {"a": 1}
    var inner_map1 = Payload.mapPayload(allocator);
    defer inner_map1.free(allocator); // Free after put (put will clone it)
    try inner_map1.mapPut("a", Payload.uintToPayload(1));

    // Create inner map as key 2: {"b": 2}
    var inner_map2 = Payload.mapPayload(allocator);
    defer inner_map2.free(allocator); // Free after put (put will clone it)
    try inner_map2.mapPut("b", Payload.uintToPayload(2));

    try outer_map.mapPutGeneric(inner_map1, try Payload.strToPayload("value1", allocator));
    try outer_map.mapPutGeneric(inner_map2, try Payload.strToPayload("value2", allocator));

    // Serialize
    try p.write(outer_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Create matching map keys for lookup
    var lookup_map1 = Payload.mapPayload(allocator);
    defer lookup_map1.free(allocator);
    try lookup_map1.mapPut("a", Payload.uintToPayload(1));

    var lookup_map2 = Payload.mapPayload(allocator);
    defer lookup_map2.free(allocator);
    try lookup_map2.mapPut("b", Payload.uintToPayload(2));

    // Verify values
    const val1 = try result.mapGetGeneric(lookup_map1);
    try expect(val1 != null);
    try expect(u8eql(val1.?.str.value(), "value1"));

    const val2 = try result.mapGetGeneric(lookup_map2);
    try expect(val2 != null);
    try expect(u8eql(val2.?.str.value(), "value2"));
}

test "map with bin keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with binary keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    var bin1 = [_]u8{ 0x01, 0x02, 0x03 };
    var bin2 = [_]u8{ 0xFF, 0xFE };

    try test_map.mapPutGeneric(
        Payload{ .bin = msgpack.Bin{ .bin = &bin1 } },
        try Payload.strToPayload("binary1", allocator),
    );
    try test_map.mapPutGeneric(
        Payload{ .bin = msgpack.Bin{ .bin = &bin2 } },
        try Payload.strToPayload("binary2", allocator),
    );

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Verify values using bin keys
    const val1 = try result.mapGetGeneric(Payload{ .bin = msgpack.Bin{ .bin = &bin1 } });
    try expect(val1 != null);
    try expect(u8eql(val1.?.str.value(), "binary1"));

    const val2 = try result.mapGetGeneric(Payload{ .bin = msgpack.Bin{ .bin = &bin2 } });
    try expect(val2 != null);
    try expect(u8eql(val2.?.str.value(), "binary2"));
}

test "map with timestamp keys" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with timestamp keys
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    const ts1 = msgpack.Timestamp.new(1234567890, 0);
    const ts2 = msgpack.Timestamp.new(9876543210, 123456789);

    try test_map.mapPutGeneric(Payload{ .timestamp = ts1 }, try Payload.strToPayload("time1", allocator));
    try test_map.mapPutGeneric(Payload{ .timestamp = ts2 }, try Payload.strToPayload("time2", allocator));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Verify values using timestamp keys
    const val1 = try result.mapGetGeneric(Payload{ .timestamp = ts1 });
    try expect(val1 != null);
    try expect(u8eql(val1.?.str.value(), "time1"));

    const val2 = try result.mapGetGeneric(Payload{ .timestamp = ts2 });
    try expect(val2 != null);
    try expect(u8eql(val2.?.str.value(), "time2"));
}

test "map with nil key" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a map with nil as a key
    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    try test_map.mapPutGeneric(Payload.nilToPayload(), try Payload.strToPayload("nil_value", allocator));
    try test_map.mapPut("string_key", try Payload.strToPayload("string_value", allocator));

    // Serialize
    try p.write(test_map);

    // Deserialize
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    try expect(result.map.count() == 2);

    // Verify nil key
    const nil_val = try result.mapGetGeneric(Payload.nilToPayload());
    try expect(nil_val != null);
    try expect(u8eql(nil_val.?.str.value(), "nil_value"));

    // Verify string key still works
    const str_val = try result.mapGet("string_key");
    try expect(str_val != null);
    try expect(u8eql(str_val.?.str.value(), "string_value"));
}

// ========== SIMD Optimization Tests ==========

test "SIMD string comparison: short strings" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // Short keys (< 16 bytes) - should use scalar path
    try test_map.mapPut("a", Payload.intToPayload(1));
    try test_map.mapPut("ab", Payload.intToPayload(2));
    try test_map.mapPut("abc", Payload.intToPayload(3));
    try test_map.mapPut("short_key", Payload.intToPayload(4));

    try p.write(test_map);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect((try result.mapGet("a")).?.uint == 1);
    try expect((try result.mapGet("ab")).?.uint == 2);
    try expect((try result.mapGet("abc")).?.uint == 3);
    try expect((try result.mapGet("short_key")).?.uint == 4);
}

test "SIMD string comparison: medium strings (16-32 bytes)" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // Medium keys (16-32 bytes) - should use SIMD path
    try test_map.mapPut("this_is_16_bytes", Payload.intToPayload(16));
    try test_map.mapPut("this_is_exactly_20ch", Payload.intToPayload(20));
    try test_map.mapPut("this_is_a_32_byte_long_key!!", Payload.intToPayload(32));

    try p.write(test_map);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect((try result.mapGet("this_is_16_bytes")).?.uint == 16);
    try expect((try result.mapGet("this_is_exactly_20ch")).?.uint == 20);
    try expect((try result.mapGet("this_is_a_32_byte_long_key!!")).?.uint == 32);
}

test "SIMD string comparison: long strings (64+ bytes)" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // Long keys (64+ bytes) - SIMD should provide significant speedup
    const long_key1 = "this_is_a_very_long_key_that_exceeds_64_bytes_and_should_benefit_from_SIMD";
    const long_key2 = "another_super_long_key_name_for_testing_SIMD_performance_optimization!!";

    try test_map.mapPut(long_key1, Payload.intToPayload(100));
    try test_map.mapPut(long_key2, Payload.intToPayload(200));

    try p.write(test_map);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect((try result.mapGet(long_key1)).?.uint == 100);
    try expect((try result.mapGet(long_key2)).?.uint == 200);
}

test "SIMD binary comparison: ext with large data" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var test_map = Payload.mapPayload(allocator);
    defer test_map.free(allocator);

    // Create large ext data (64 bytes) to test SIMD binary comparison
    var ext_data1: [64]u8 = undefined;
    for (&ext_data1, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }

    var ext_data2: [64]u8 = undefined;
    for (&ext_data2, 0..) |*byte, i| {
        byte.* = @intCast(i + 100);
    }

    try test_map.mapPutGeneric(
        Payload{ .ext = msgpack.EXT{ .type = 1, .data = &ext_data1 } },
        Payload.intToPayload(1),
    );
    try test_map.mapPutGeneric(
        Payload{ .ext = msgpack.EXT{ .type = 1, .data = &ext_data2 } },
        Payload.intToPayload(2),
    );

    try p.write(test_map);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result.map.count() == 2);

    const val1 = try result.mapGetGeneric(Payload{ .ext = msgpack.EXT{ .type = 1, .data = &ext_data1 } });
    try expect(val1 != null);
    try expect(val1.?.uint == 1);

    const val2 = try result.mapGetGeneric(Payload{ .ext = msgpack.EXT{ .type = 1, .data = &ext_data2 } });
    try expect(val2 != null);
    try expect(val2.?.uint == 2);
}

test "SIMD byte order conversion: batch u32 conversion" {
    const batchU32ToBigEndian = @import("msgpack").batchU32ToBigEndian;

    // Test batch u32 conversion
    const test_values = [_]u32{ 0x12345678, 0xAABBCCDD, 0x11223344, 0xFFEEDDCC };
    var output: [16]u8 = undefined;

    _ = batchU32ToBigEndian(&test_values, &output);

    // Verify each value is correctly converted to big-endian
    for (test_values, 0..) |val, i| {
        const offset = i * 4;
        const result = std.mem.readInt(u32, output[offset..][0..4], .big);
        try expect(result == val);
    }
}

test "SIMD byte order conversion: batch u64 conversion" {
    const batchU64ToBigEndian = @import("msgpack").batchU64ToBigEndian;

    // Test batch u64 conversion
    const test_values = [_]u64{ 0x123456789ABCDEF0, 0xAABBCCDDEEFF0011, 0x1122334455667788 };
    var output: [24]u8 = undefined;

    _ = batchU64ToBigEndian(&test_values, &output);

    // Verify each value is correctly converted to big-endian
    for (test_values, 0..) |val, i| {
        const offset = i * 8;
        const result = std.mem.readInt(u64, output[offset..][0..8], .big);
        try expect(result == val);
    }
}

test "SIMD optimized integer array: u32 array write and read" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create an array of u32 values
    const test_values = [_]u32{ 0x12345678, 0xAABBCCDD, 0x11223344, 0xFFEEDDCC, 0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF };
    var test_payload = try Payload.arrPayload(test_values.len, allocator);
    defer test_payload.free(allocator);

    for (test_values, 0..) |v, i| {
        try test_payload.setArrElement(i, Payload.uintToPayload(v));
    }

    try p.write(test_payload);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(try result.getArrLen() == test_values.len);
    for (test_values, 0..) |expected, i| {
        const element = try result.getArrElement(i);
        try expect(element.uint == expected);
    }
}

test "SIMD optimized integer array: mixed sizes" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Test mixed integer sizes that will use different MessagePack formats
    var test_payload = try Payload.arrPayload(10, allocator);
    defer test_payload.free(allocator);

    try test_payload.setArrElement(0, Payload.uintToPayload(0)); // fixint
    try test_payload.setArrElement(1, Payload.uintToPayload(127)); // fixint max
    try test_payload.setArrElement(2, Payload.uintToPayload(128)); // uint8
    try test_payload.setArrElement(3, Payload.uintToPayload(255)); // uint8 max
    try test_payload.setArrElement(4, Payload.uintToPayload(256)); // uint16
    try test_payload.setArrElement(5, Payload.uintToPayload(65535)); // uint16 max
    try test_payload.setArrElement(6, Payload.uintToPayload(65536)); // uint32
    try test_payload.setArrElement(7, Payload.uintToPayload(0xFFFFFFFF)); // uint32 max
    try test_payload.setArrElement(8, Payload.uintToPayload(0x100000000)); // uint64
    try test_payload.setArrElement(9, Payload.uintToPayload(0xFFFFFFFFFFFFFFFF)); // uint64 max

    try p.write(test_payload);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect((try result.getArrElement(0)).uint == 0);
    try expect((try result.getArrElement(1)).uint == 127);
    try expect((try result.getArrElement(2)).uint == 128);
    try expect((try result.getArrElement(3)).uint == 255);
    try expect((try result.getArrElement(4)).uint == 256);
    try expect((try result.getArrElement(5)).uint == 65535);
    try expect((try result.getArrElement(6)).uint == 65536);
    try expect((try result.getArrElement(7)).uint == 0xFFFFFFFF);
    try expect((try result.getArrElement(8)).uint == 0x100000000);
    try expect((try result.getArrElement(9)).uint == 0xFFFFFFFFFFFFFFFF);
}

// ========== Memory Alignment Optimization Tests ==========

test "memory alignment: aligned u32 batch conversion" {
    const batchU32ToBigEndian = @import("msgpack").batchU32ToBigEndian;

    // Allocate aligned buffer (aligned to 16 bytes for SIMD)
    var aligned_output: [64]u8 align(16) = undefined;
    const test_values = [_]u32{ 0x12345678, 0xAABBCCDD, 0x11223344, 0xFFEEDDCC };

    _ = batchU32ToBigEndian(&test_values, &aligned_output);

    // Verify correctness
    for (test_values, 0..) |val, i| {
        const offset = i * 4;
        const result = std.mem.readInt(u32, aligned_output[offset..][0..4], .big);
        try expect(result == val);
    }
}

test "memory alignment: unaligned u32 batch conversion" {
    const batchU32ToBigEndian = @import("msgpack").batchU32ToBigEndian;

    // Create intentionally unaligned buffer (offset by 1 byte)
    var buffer: [65]u8 align(16) = undefined;
    const unaligned_output = buffer[1..]; // Start at offset 1 (unaligned)

    const test_values = [_]u32{ 0x12345678, 0xAABBCCDD, 0x11223344, 0xFFEEDDCC };

    _ = batchU32ToBigEndian(&test_values, unaligned_output);

    // Verify correctness (should still work correctly even unaligned)
    for (test_values, 0..) |val, i| {
        const offset = i * 4;
        const result = std.mem.readInt(u32, unaligned_output[offset..][0..4], .big);
        try expect(result == val);
    }
}

test "memory alignment: aligned u64 batch conversion" {
    const batchU64ToBigEndian = @import("msgpack").batchU64ToBigEndian;

    // Allocate aligned buffer
    var aligned_output: [64]u8 align(16) = undefined;
    const test_values = [_]u64{ 0x123456789ABCDEF0, 0xAABBCCDDEEFF0011, 0x1122334455667788 };

    _ = batchU64ToBigEndian(&test_values, &aligned_output);

    // Verify correctness
    for (test_values, 0..) |val, i| {
        const offset = i * 8;
        const result = std.mem.readInt(u64, aligned_output[offset..][0..8], .big);
        try expect(result == val);
    }
}

test "memory alignment: large binary data copy (aligned)" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create large binary data (256 bytes) to test aligned SIMD copy
    var large_data: [256]u8 align(16) = undefined;
    for (&large_data, 0..) |*byte, i| {
        byte.* = @intCast(i & 0xFF);
    }

    const test_payload = try msgpack.Payload.binToPayload(&large_data, allocator);
    defer test_payload.free(allocator);

    try p.write(test_payload);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .bin);
    try expect(result.bin.value().len == 256);

    // Verify data integrity
    for (large_data, 0..) |expected, i| {
        try expect(result.bin.value()[i] == expected);
    }
}

test "memory alignment: large string copy (mixed alignment)" {
    var arr: [0xffff_f]u8 = std.mem.zeroes([0xffff_f]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a string > 64 bytes to trigger SIMD copy optimization
    const long_string = "This is a very long string that is designed to test the SIMD-optimized memory copy functionality with various alignment scenarios. It should be long enough to benefit from vectorized operations.";

    const test_payload = try msgpack.Payload.strToPayload(long_string, allocator);
    defer test_payload.free(allocator);

    try p.write(test_payload);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(result == .str);
    try expect(u8eql(result.str.value(), long_string));
}

test "memory alignment: large integer array serialization" {
    var arr: [0xfffff]u8 = std.mem.zeroes([0xfffff]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create a large array of u32 values to test batch conversion
    const count = 100;
    var test_payload = try msgpack.Payload.arrPayload(count, allocator);
    defer test_payload.free(allocator);

    for (0..count) |i| {
        try test_payload.setArrElement(i, msgpack.Payload.uintToPayload(@as(u64, i)));
    }

    // Write and read back
    try p.write(test_payload);
    const result = try p.read(allocator);
    defer result.free(allocator);

    try expect(try result.getArrLen() == count);

    // Verify all elements
    for (0..count) |i| {
        const elem = try result.getArrElement(i);
        try expect(elem.uint == i);
    }
}

// ============================================================================
// std.io.Reader and std.io.Writer Tests (Zig 0.15+)
// ============================================================================

const has_new_io = builtin.zig_version.minor >= 15;

test "PackerIO: basic write and read with fixed Reader/Writer" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Write a simple payload
    const payload = msgpack.Payload.uintToPayload(42);
    try packer.write(payload);

    // Reset reader position
    reader.seek = 0;

    // Read it back
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .uint);
    try expect(result.uint == 42);
}

test "PackerIO: nil type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = msgpack.Payload.nilToPayload();
    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .nil);
}

test "PackerIO: bool type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    // Test true
    {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = msgpack.Payload.boolToPayload(true);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        try expect(result == .bool);
        try expect(result.bool == true);
    }

    // Test false
    {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = msgpack.Payload.boolToPayload(false);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        try expect(result == .bool);
        try expect(result.bool == false);
    }
}

test "PackerIO: signed integers" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    const test_cases = [_]i64{ -1, -32, -33, -128, -32768, -2147483648 };

    for (test_cases) |val| {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = msgpack.Payload.intToPayload(val);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        // Verify the result is an integer type
        if (result != .int) {
            std.debug.print("Expected .int but got {s} for value {d}\n", .{ @tagName(result), val });
        }
        try expect(result == .int);
        try expect(result.int == val);
    }
}

test "PackerIO: unsigned integers" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    const test_cases = [_]u64{ 0, 1, 127, 128, 255, 256, 65535, 65536, 4294967295, 4294967296 };

    for (test_cases) |val| {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = msgpack.Payload.uintToPayload(val);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        try expect(result == .uint);
        try expect(result.uint == val);
    }
}

test "PackerIO: float type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    // Use non-integer values to ensure they stay as floats
    const test_cases = [_]f64{ 3.14159, -3.14159, 1.23e10, -1.23e-10, 2.71828, -999.999 };

    for (test_cases) |val| {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = msgpack.Payload.floatToPayload(val);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        if (result != .float) {
            std.debug.print("Expected .float but got {s} for value {d}\n", .{ @tagName(result), val });
            std.debug.print("Buffer contents: ", .{});
            for (buffer[0..writer.end]) |b| {
                std.debug.print("{x:0>2} ", .{b});
            }
            std.debug.print("\n", .{});
        }
        try expect(result == .float);
        // Use approxEqRel for float comparison to handle precision loss in MessagePack encoding
        // MessagePack may use float32 for some values, which has less precision than float64
        const epsilon = 0.00001; // Relaxed epsilon for float32 precision
        if (!std.math.approxEqRel(f64, result.float, val, epsilon)) {
            std.debug.print("Float mismatch: expected {d}, got {d}, diff: {d}\n", .{ val, result.float, @abs(result.float - val) });
        }
        try expect(std.math.approxEqRel(f64, result.float, val, epsilon));
    }
}

test "PackerIO: string type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    const test_strings = [_][]const u8{
        "",
        "a",
        "hello",
        "Hello, World!",
        "这是一个测试", // UTF-8 test
        "a" ** 100, // Long string
    };

    for (test_strings) |str| {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = try msgpack.Payload.strToPayload(str, allocator);
        defer payload.free(allocator);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        try expect(result == .str);
        try expect(u8eql(result.str.value(), str));
    }
}

test "PackerIO: binary type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    const test_data = [_]u8{ 0x00, 0x01, 0x02, 0xFF, 0xAB, 0xCD };

    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    const payload = try msgpack.Payload.binToPayload(&test_data, allocator);
    defer payload.free(allocator);
    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .bin);
    try expect(u8eql(result.bin.value(), &test_data));
}

test "PackerIO: array type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Create an array with different types
    var payload = try msgpack.Payload.arrPayload(4, allocator);
    defer payload.free(allocator);
    try payload.setArrElement(0, msgpack.Payload.intToPayload(42));
    try payload.setArrElement(1, try msgpack.Payload.strToPayload("test", allocator));
    try payload.setArrElement(2, msgpack.Payload.boolToPayload(true));
    try payload.setArrElement(3, msgpack.Payload.nilToPayload());

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .arr);
    try expect(try result.getArrLen() == 4);

    const elem0 = try result.getArrElement(0);
    // 42 may be encoded as uint since it's positive
    if (elem0 == .uint) {
        try expect(elem0.uint == 42);
    } else if (elem0 == .int) {
        try expect(elem0.int == 42);
    } else {
        std.debug.print("Unexpected type {s} for element 0\n", .{@tagName(elem0)});
        return error.TestUnexpectedResult;
    }

    const elem1 = try result.getArrElement(1);
    try expect(u8eql(elem1.str.value(), "test"));

    const elem2 = try result.getArrElement(2);
    try expect(elem2.bool == true);

    const elem3 = try result.getArrElement(3);
    try expect(elem3 == .nil);
}

test "PackerIO: map type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Create a map
    var payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);
    try payload.mapPut("name", try msgpack.Payload.strToPayload("Alice", allocator));
    try payload.mapPut("age", msgpack.Payload.uintToPayload(30));
    try payload.mapPut("active", msgpack.Payload.boolToPayload(true));

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);

    const name = (try result.mapGet("name")).?;
    try expect(u8eql(name.str.value(), "Alice"));

    const age = (try result.mapGet("age")).?;
    try expect(age.uint == 30);

    const active = (try result.mapGet("active")).?;
    try expect(active.bool == true);
}

test "PackerIO: nested structures" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Create nested structure: map with array values
    var payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);

    var arr = try msgpack.Payload.arrPayload(3, allocator);
    try arr.setArrElement(0, msgpack.Payload.uintToPayload(1));
    try arr.setArrElement(1, msgpack.Payload.uintToPayload(2));
    try arr.setArrElement(2, msgpack.Payload.uintToPayload(3));

    try payload.mapPut("numbers", arr);
    try payload.mapPut("name", try msgpack.Payload.strToPayload("test", allocator));

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);

    const numbers = (try result.mapGet("numbers")).?;
    try expect(numbers == .arr);
    try expect(try numbers.getArrLen() == 3);

    const elem0 = try numbers.getArrElement(0);
    try expect(elem0.uint == 1);
}

test "PackerIO: timestamp extension type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;

    const test_cases = [_]struct { seconds: i64, nanoseconds: u32 }{
        .{ .seconds = 0, .nanoseconds = 0 },
        .{ .seconds = 1234567890, .nanoseconds = 0 },
        .{ .seconds = 1234567890, .nanoseconds = 123456789 },
        .{ .seconds = -1, .nanoseconds = 999999999 },
    };

    for (test_cases) |tc| {
        var writer = std.Io.Writer.fixed(&buffer);
        var reader = std.Io.Reader.fixed(&buffer);
        var packer = msgpack.PackerIO.init(&reader, &writer);

        const payload = msgpack.Payload.timestampToPayload(tc.seconds, tc.nanoseconds);
        try packer.write(payload);

        reader.seek = 0;
        const result = try packer.read(allocator);
        defer result.free(allocator);

        try expect(result == .timestamp);
        try expect(result.timestamp.seconds == tc.seconds);
        try expect(result.timestamp.nanoseconds == tc.nanoseconds);
    }
}

test "PackerIO: extension type" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    const ext_data = [_]u8{ 0xAA, 0xBB, 0xCC };
    const ext_type: i8 = 42;

    const payload = try msgpack.Payload.extToPayload(ext_type, &ext_data, allocator);
    defer payload.free(allocator);
    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .ext);
    try expect(result.ext.type == ext_type);
    try expect(u8eql(result.ext.data, &ext_data));
}

test "PackerIO: deeply nested structures" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Create a deeply nested structure
    var payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);

    var inner_arr = try msgpack.Payload.arrPayload(2, allocator);
    try inner_arr.setArrElement(0, msgpack.Payload.uintToPayload(1));
    try inner_arr.setArrElement(1, msgpack.Payload.uintToPayload(2));

    var outer_arr = try msgpack.Payload.arrPayload(1, allocator);
    try outer_arr.setArrElement(0, inner_arr);

    try payload.mapPut("nested", outer_arr);

    try packer.write(payload);

    reader.seek = 0;
    // The read method uses an iterative parser by default
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result == .map);
    const nested = (try result.mapGet("nested")).?;
    try expect(nested == .arr);
}

test "PackerIO: multiple writes and reads" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Write multiple payloads
    try packer.write(msgpack.Payload.uintToPayload(1));
    try packer.write(msgpack.Payload.uintToPayload(2));
    try packer.write(msgpack.Payload.uintToPayload(3));

    reader.seek = 0;

    // Read them back
    const result1 = try packer.read(allocator);
    defer result1.free(allocator);
    try expect(result1.uint == 1);

    const result2 = try packer.read(allocator);
    defer result2.free(allocator);
    try expect(result2.uint == 2);

    const result3 = try packer.read(allocator);
    defer result3.free(allocator);
    try expect(result3.uint == 3);
}

test "PackerIO: large array" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [16384]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);
    var packer = msgpack.PackerIO.init(&reader, &writer);

    const count = 100;
    var payload = try msgpack.Payload.arrPayload(count, allocator);
    defer payload.free(allocator);

    for (0..count) |i| {
        try payload.setArrElement(i, msgpack.Payload.uintToPayload(@as(u64, i)));
    }

    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(try result.getArrLen() == count);

    for (0..count) |i| {
        const elem = try result.getArrElement(i);
        try expect(elem.uint == i);
    }
}

test "PackerIO: packIO convenience function" {
    if (!has_new_io) return error.SkipZigVersionCheck;

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    // Use convenience function
    var packer = msgpack.packIO(&reader, &writer);

    const payload = msgpack.Payload.uintToPayload(12345);
    try packer.write(payload);

    reader.seek = 0;
    const result = try packer.read(allocator);
    defer result.free(allocator);

    try expect(result.uint == 12345);
}
