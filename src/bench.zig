const std = @import("std");
const builtin = @import("builtin");
const msgpack = @import("msgpack");
const compat = msgpack.compat;
const Payload = msgpack.Payload;

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

/// Benchmark timer helper
/// Run a benchmark and print results
fn benchmark(
    comptime name: []const u8,
    comptime iterations: usize,
    comptime func: fn (allocator: std.mem.Allocator) anyerror!void,
) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Warmup
    for (0..10) |_| {
        try func(allocator);
    }

    // Actual benchmark
    var timer = try std.time.Timer.start();
    for (0..iterations) |_| {
        try func(allocator);
    }
    const elapsed_ns = timer.read();

    const avg_ns = elapsed_ns / iterations;
    const ops_per_sec = if (avg_ns > 0) (1_000_000_000 / avg_ns) else 0;

    std.debug.print(
        "{s:40} | {d:8} iterations | {d:8} ns/op | {d:8} ops/sec\n",
        .{ name, iterations, avg_ns, ops_per_sec },
    );
}

// ============================================================================
// Basic Type Benchmarks
// ============================================================================

fn benchNilWrite(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [100]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    try p.write(Payload.nilToPayload());
}

fn benchNilRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 100;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);
        try p.write(Payload.nilToPayload());
        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchBoolWrite(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [100]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    try p.write(Payload.boolToPayload(true));
}

fn benchBoolRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 100;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);
        try p.write(Payload.boolToPayload(true));
        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchSmallIntWrite(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [100]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    try p.write(Payload.intToPayload(42));
}

fn benchSmallIntRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 100;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);
        try p.write(Payload.intToPayload(42));
        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchLargeIntWrite(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [100]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    try p.write(Payload.intToPayload(9223372036854775807));
}

fn benchLargeIntRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 100;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);
        try p.write(Payload.intToPayload(9223372036854775807));
        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchFloatWrite(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [100]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    try p.write(Payload.floatToPayload(3.14159265359));
}

fn benchFloatRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 100;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);
        try p.write(Payload.floatToPayload(3.14159265359));
        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// String Benchmarks
// ============================================================================

fn benchShortStrWrite(allocator: std.mem.Allocator) !void {
    var arr: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    const str = try Payload.strToPayload("hello", allocator);
    defer str.free(allocator);
    try p.write(str);
}

fn benchShortStrRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 1000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        const str = try Payload.strToPayload("hello", allocator);
        defer str.free(allocator);
        try p.write(str);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchMediumStrWrite(allocator: std.mem.Allocator) !void {
    var arr: [2000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    const test_str = "This is a medium length string for benchmarking MessagePack performance. " ** 4;
    const str = try Payload.strToPayload(test_str, allocator);
    defer str.free(allocator);
    try p.write(str);
}

fn benchMediumStrRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 2000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        const test_str = "This is a medium length string for benchmarking MessagePack performance. " ** 4;
        const str = try Payload.strToPayload(test_str, allocator);
        defer str.free(allocator);
        try p.write(str);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Binary Data Benchmarks
// ============================================================================

fn benchSmallBinWrite(allocator: std.mem.Allocator) !void {
    var arr: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var data = [_]u8{1} ** 32;
    const bin = try Payload.binToPayload(&data, allocator);
    defer bin.free(allocator);
    try p.write(bin);
}

fn benchSmallBinRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 1000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var data = [_]u8{1} ** 32;
        const bin = try Payload.binToPayload(&data, allocator);
        defer bin.free(allocator);
        try p.write(bin);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchLargeBinWrite(allocator: std.mem.Allocator) !void {
    var arr: [2000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    const data = try allocator.alloc(u8, 1024);
    defer allocator.free(data);
    @memset(data, 0x42);

    const bin = try Payload.binToPayload(data, allocator);
    defer bin.free(allocator);
    try p.write(bin);
}

fn benchLargeBinRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 2000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        const data = try allocator.alloc(u8, 1024);
        defer allocator.free(data);
        @memset(data, 0x42);

        const bin = try Payload.binToPayload(data, allocator);
        defer bin.free(allocator);
        try p.write(bin);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Array Benchmarks
// ============================================================================

fn benchSmallArrayWrite(allocator: std.mem.Allocator) !void {
    var arr: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var array = try Payload.arrPayload(10, allocator);
    defer array.free(allocator);
    for (0..10) |i| {
        try array.setArrElement(i, Payload.intToPayload(@intCast(i)));
    }
    try p.write(array);
}

fn benchSmallArrayRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 1000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var array = try Payload.arrPayload(10, allocator);
        defer array.free(allocator);
        for (0..10) |i| {
            try array.setArrElement(i, Payload.intToPayload(@intCast(i)));
        }
        try p.write(array);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchMediumArrayWrite(allocator: std.mem.Allocator) !void {
    var arr: [5000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var array = try Payload.arrPayload(100, allocator);
    defer array.free(allocator);
    for (0..100) |i| {
        try array.setArrElement(i, Payload.intToPayload(@intCast(i)));
    }
    try p.write(array);
}

fn benchMediumArrayRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 5000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var array = try Payload.arrPayload(100, allocator);
        defer array.free(allocator);
        for (0..100) |i| {
            try array.setArrElement(i, Payload.intToPayload(@intCast(i)));
        }
        try p.write(array);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Map Benchmarks
// ============================================================================

fn benchSmallMapWrite(allocator: std.mem.Allocator) !void {
    var arr: [2000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var map = Payload.mapPayload(allocator);
    defer map.free(allocator);

    for (0..10) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        defer allocator.free(key);
        try map.mapPut(key, Payload.intToPayload(@intCast(i)));
    }

    try p.write(map);
}

fn benchSmallMapRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 2000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var map = Payload.mapPayload(allocator);
        defer map.free(allocator);

        for (0..10) |i| {
            const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
            defer allocator.free(key);
            try map.mapPut(key, Payload.intToPayload(@intCast(i)));
        }

        try p.write(map);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchMediumMapWrite(allocator: std.mem.Allocator) !void {
    var arr: [10000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var map = Payload.mapPayload(allocator);
    defer map.free(allocator);

    for (0..50) |i| {
        const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
        defer allocator.free(key);
        try map.mapPut(key, Payload.intToPayload(@intCast(i)));
    }

    try p.write(map);
}

fn benchMediumMapRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 10000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var map = Payload.mapPayload(allocator);
        defer map.free(allocator);

        for (0..50) |i| {
            const key = try std.fmt.allocPrint(allocator, "key{d}", .{i});
            defer allocator.free(key);
            try map.mapPut(key, Payload.intToPayload(@intCast(i)));
        }

        try p.write(map);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Extension Type Benchmarks
// ============================================================================

fn benchExtWrite(allocator: std.mem.Allocator) !void {
    var arr: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var data = [_]u8{1} ** 16;
    const ext = try Payload.extToPayload(42, &data, allocator);
    defer ext.free(allocator);
    try p.write(ext);
}

fn benchExtRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 1000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var data = [_]u8{1} ** 16;
        const ext = try Payload.extToPayload(42, &data, allocator);
        defer ext.free(allocator);
        try p.write(ext);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Timestamp Benchmarks
// ============================================================================

fn benchTimestamp32Write(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    const ts = Payload.timestampFromSeconds(1234567890);
    try p.write(ts);
}

fn benchTimestamp32Read(allocator: std.mem.Allocator) !void {
    const BufferLen = 1000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        const ts = Payload.timestampFromSeconds(1234567890);
        try p.write(ts);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchTimestamp64Write(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var arr: [1000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    const ts = Payload.timestampToPayload(1234567890, 123456789);
    try p.write(ts);
}

fn benchTimestamp64Read(allocator: std.mem.Allocator) !void {
    const BufferLen = 1000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        const ts = Payload.timestampToPayload(1234567890, 123456789);
        try p.write(ts);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Complex Structure Benchmarks
// ============================================================================

fn benchNestedStructureWrite(allocator: std.mem.Allocator) !void {
    var arr: [10000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // Create: {"users": [{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}]}
    var root = Payload.mapPayload(allocator);
    defer root.free(allocator);

    var users = try Payload.arrPayload(2, allocator);

    var user1 = Payload.mapPayload(allocator);
    try user1.mapPut("id", Payload.intToPayload(1));
    try user1.mapPut("name", try Payload.strToPayload("Alice", allocator));
    try users.setArrElement(0, user1);

    var user2 = Payload.mapPayload(allocator);
    try user2.mapPut("id", Payload.intToPayload(2));
    try user2.mapPut("name", try Payload.strToPayload("Bob", allocator));
    try users.setArrElement(1, user2);

    try root.mapPut("users", users);
    try p.write(root);
}

fn benchNestedStructureRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 10000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var root = Payload.mapPayload(allocator);
        defer root.free(allocator);

        var users = try Payload.arrPayload(2, allocator);

        var user1 = Payload.mapPayload(allocator);
        try user1.mapPut("id", Payload.intToPayload(1));
        try user1.mapPut("name", try Payload.strToPayload("Alice", allocator));
        try users.setArrElement(0, user1);

        var user2 = Payload.mapPayload(allocator);
        try user2.mapPut("id", Payload.intToPayload(2));
        try user2.mapPut("name", try Payload.strToPayload("Bob", allocator));
        try users.setArrElement(1, user2);

        try root.mapPut("users", users);
        try p.write(root);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

fn benchMixedTypesWrite(allocator: std.mem.Allocator) !void {
    var arr: [5000]u8 = undefined;
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    var mixed = try Payload.arrPayload(10, allocator);
    defer mixed.free(allocator);

    try mixed.setArrElement(0, Payload.nilToPayload());
    try mixed.setArrElement(1, Payload.boolToPayload(true));
    try mixed.setArrElement(2, Payload.intToPayload(-100));
    try mixed.setArrElement(3, Payload.uintToPayload(200));
    try mixed.setArrElement(4, Payload.floatToPayload(3.14));
    try mixed.setArrElement(5, try Payload.strToPayload("hello", allocator));

    var bin_data = [_]u8{1} ** 8;
    try mixed.setArrElement(6, try Payload.binToPayload(&bin_data, allocator));

    var inner_arr = try Payload.arrPayload(2, allocator);
    try inner_arr.setArrElement(0, Payload.intToPayload(1));
    try inner_arr.setArrElement(1, Payload.intToPayload(2));
    try mixed.setArrElement(7, inner_arr);

    var inner_map = Payload.mapPayload(allocator);
    try inner_map.mapPut("key", Payload.intToPayload(42));
    try mixed.setArrElement(8, inner_map);

    try mixed.setArrElement(9, Payload.timestampFromSeconds(1000000));

    try p.write(mixed);
}

fn benchMixedTypesRead(allocator: std.mem.Allocator) !void {
    const BufferLen = 5000;
    const State = struct {
        var initialized = false;
        var buffer: [BufferLen]u8 = [_]u8{0} ** BufferLen;
    };

    if (!State.initialized) {
        var write_buffer = fixedBufferStream(State.buffer[0..]);
        var read_buffer = fixedBufferStream(State.buffer[0..]);
        var p = pack.init(&write_buffer, &read_buffer);

        var mixed = try Payload.arrPayload(10, allocator);
        defer mixed.free(allocator);

        try mixed.setArrElement(0, Payload.nilToPayload());
        try mixed.setArrElement(1, Payload.boolToPayload(true));
        try mixed.setArrElement(2, Payload.intToPayload(-100));
        try mixed.setArrElement(3, Payload.uintToPayload(200));
        try mixed.setArrElement(4, Payload.floatToPayload(3.14));
        try mixed.setArrElement(5, try Payload.strToPayload("hello", allocator));

        var bin_data = [_]u8{1} ** 8;
        try mixed.setArrElement(6, try Payload.binToPayload(&bin_data, allocator));

        var inner_arr = try Payload.arrPayload(2, allocator);
        try inner_arr.setArrElement(0, Payload.intToPayload(1));
        try inner_arr.setArrElement(1, Payload.intToPayload(2));
        try mixed.setArrElement(7, inner_arr);

        var inner_map = Payload.mapPayload(allocator);
        try inner_map.mapPut("key", Payload.intToPayload(42));
        try mixed.setArrElement(8, inner_map);

        try mixed.setArrElement(9, Payload.timestampFromSeconds(1000000));

        try p.write(mixed);

        State.initialized = true;
    }

    var write_buffer = fixedBufferStream(State.buffer[0..]);
    var read_buffer = fixedBufferStream(State.buffer[0..]);
    var p = pack.init(&write_buffer, &read_buffer);
    const val = try p.read(allocator);
    defer val.free(allocator);
}

// ============================================================================
// Main Benchmark Runner
// ============================================================================

pub fn main() !void {
    std.debug.print("\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});
    std.debug.print("MessagePack Benchmark Suite\n", .{});
    std.debug.print("=" ** 80 ++ "\n\n", .{});

    // Basic Types
    std.debug.print("Basic Types:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Nil Write", 1000000, benchNilWrite);
    try benchmark("Nil Read", 1000000, benchNilRead);
    try benchmark("Bool Write", 1000000, benchBoolWrite);
    try benchmark("Bool Read", 1000000, benchBoolRead);
    try benchmark("Small Int Write", 1000000, benchSmallIntWrite);
    try benchmark("Small Int Read", 1000000, benchSmallIntRead);
    try benchmark("Large Int Write", 1000000, benchLargeIntWrite);
    try benchmark("Large Int Read", 1000000, benchLargeIntRead);
    try benchmark("Float Write", 1000000, benchFloatWrite);
    try benchmark("Float Read", 1000000, benchFloatRead);
    std.debug.print("\n", .{});

    // Strings
    std.debug.print("Strings:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Short String Write (5 bytes)", 500000, benchShortStrWrite);
    try benchmark("Short String Read (5 bytes)", 500000, benchShortStrRead);
    try benchmark("Medium String Write (~300 bytes)", 100000, benchMediumStrWrite);
    try benchmark("Medium String Read (~300 bytes)", 100000, benchMediumStrRead);
    std.debug.print("\n", .{});

    // Binary Data
    std.debug.print("Binary Data:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Small Binary Write (32 bytes)", 500000, benchSmallBinWrite);
    try benchmark("Small Binary Read (32 bytes)", 500000, benchSmallBinRead);
    try benchmark("Large Binary Write (1KB)", 100000, benchLargeBinWrite);
    try benchmark("Large Binary Read (1KB)", 100000, benchLargeBinRead);
    std.debug.print("\n", .{});

    // Arrays
    std.debug.print("Arrays:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Small Array Write (10 elements)", 100000, benchSmallArrayWrite);
    try benchmark("Small Array Read (10 elements)", 100000, benchSmallArrayRead);
    try benchmark("Medium Array Write (100 elements)", 50000, benchMediumArrayWrite);
    try benchmark("Medium Array Read (100 elements)", 50000, benchMediumArrayRead);
    std.debug.print("\n", .{});

    // Maps
    std.debug.print("Maps:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Small Map Write (10 entries)", 100000, benchSmallMapWrite);
    try benchmark("Small Map Read (10 entries)", 100000, benchSmallMapRead);
    try benchmark("Medium Map Write (50 entries)", 50000, benchMediumMapWrite);
    try benchmark("Medium Map Read (50 entries)", 50000, benchMediumMapRead);
    std.debug.print("\n", .{});

    // Extension Types
    std.debug.print("Extension Types:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("EXT Write (16 bytes)", 500000, benchExtWrite);
    try benchmark("EXT Read (16 bytes)", 500000, benchExtRead);
    std.debug.print("\n", .{});

    // Timestamps
    std.debug.print("Timestamps:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Timestamp32 Write", 1000000, benchTimestamp32Write);
    try benchmark("Timestamp32 Read", 1000000, benchTimestamp32Read);
    try benchmark("Timestamp64 Write", 1000000, benchTimestamp64Write);
    try benchmark("Timestamp64 Read", 1000000, benchTimestamp64Read);
    std.debug.print("\n", .{});

    // Complex Structures
    std.debug.print("Complex Structures:\n", .{});
    std.debug.print("-" ** 80 ++ "\n", .{});
    try benchmark("Nested Structure Write", 50000, benchNestedStructureWrite);
    try benchmark("Nested Structure Read", 50000, benchNestedStructureRead);
    try benchmark("Mixed Types Write", 50000, benchMixedTypesWrite);
    try benchmark("Mixed Types Read", 50000, benchMixedTypesRead);
    std.debug.print("\n", .{});

    std.debug.print("=" ** 80 ++ "\n", .{});
    std.debug.print("Benchmark Complete\n", .{});
    std.debug.print("=" ** 80 ++ "\n", .{});
}
