# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/test.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/test.yml)

A MessagePack implementation for the Zig programming language. This library provides a simple and efficient way to serialize and deserialize data using the MessagePack format.

An article introducing it: [Zig Msgpack](https://blog.nvimer.org/2025/09/20/zig-msgpack/)

## Features

- **Full MessagePack Support:** Implements all MessagePack types including the timestamp extension.
- **Timestamp Support:** Complete implementation of MessagePack timestamp extension type (-1) with support for all three formats (32-bit, 64-bit, and 96-bit).
- **Production-Safe Parser:** Iterative parser prevents stack overflow on deeply nested or malicious input.
- **Security Hardened:** Configurable limits protect against DoS attacks (depth bombs, size bombs, etc.).
- **Efficient:** Designed for high performance with minimal memory overhead.
- **Type-Safe:** Leverages Zig's type system to ensure safety during serialization and deserialization.
- **Simple API:** Offers a straightforward and easy-to-use API for encoding and decoding.
- **Generic Map Keys:** Supports any Payload type as map keys, not limited to strings (uses efficient HashMap implementation).
- **Performance Optimized:** Advanced optimizations including CPU cache prefetching, branch prediction hints, and SIMD operations for maximum throughput.
- **Cross-Platform:** Tested and optimized for all major platforms (Windows, macOS, Linux) and architectures (x86_64, ARM64, etc.) with platform-specific optimizations.

## Platform Support

This library is tested and optimized for all major platforms and architectures:

| Platform | Architecture | CI Status | SIMD Optimizations |
|----------|--------------|-----------|-------------------|
| **Windows** | x86_64 | ✅ Tested | SSE2/AVX2 prefetch |
| **macOS** | ARM64 (Apple Silicon) | ✅ Tested | ARM NEON + PRFM |
| **Linux** | x86_64 | ✅ Tested | SSE2/AVX2 prefetch |
| **Linux** | ARM64/aarch64 | ✅ Tested | ARM NEON + PRFM |
| **Other** | RISC-V, MIPS, etc. | ✅ Tested | Graceful fallback |

### Architecture-Specific Optimizations

- **x86/x64**: Utilizes SSE/AVX prefetch instructions (`PREFETCHT0/1/2`, `PREFETCHNTA`) for cache-aware memory access
- **ARM64**: Uses ARM PRFM (Prefetch Memory) instructions for optimal performance on Apple Silicon and ARM servers
- **Cross-platform**: Automatically detects CPU features at compile-time with zero runtime overhead
- **Safe fallback**: Gracefully degrades to standard operations on unsupported architectures

## Installation

### Version Compatibility

| Zig Version          | Library Version | Status                                |
| -------------------- | --------------- | ------------------------------------- |
| 0.13 and older       | 0.0.6           | Legacy support                        |
| 0.14.0               | Current         | ✅ Fully supported                    |
| 0.15.x               | Current         | ✅ Fully supported                    |
| 0.16.0-dev (nightly) | Current         | ✅ Supported with compatibility layer |

> **Note:** For Zig 0.13 and older versions, please use version `0.0.6` of this library.
> **Note:** Zig 0.16+ removes `std.io.FixedBufferStream`, but this library provides a compatibility layer to maintain the same API across all supported versions.

For Zig `0.14.0`, `0.15.x`, and `0.16.0-dev`, follow these steps:

1.  **Add as a dependency:**
    Add the library to your `build.zig.zon` file. You can fetch a specific commit or branch.

    ```sh
    zig fetch --save https://github.com/zigcc/zig-msgpack/archive/{COMMIT_OR_BRANCH}.tar.gz
    ```

2.  **Configure your `build.zig`:**
    Add the `zig-msgpack` module to your executable.

### Using std.io.Reader and std.io.Writer (Zig 0.15+)

For Zig 0.15 and later, you can use the convenient `PackerIO` API with standard I/O interfaces:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;

    // Create Reader and Writer
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    // Create packer using the convenient PackerIO
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Create and encode data
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("name", try msgpack.Payload.strToPayload("Alice", allocator));
    try map.mapPut("age", msgpack.Payload.uintToPayload(30));
    try packer.write(map);

    // Decode
    reader.seek = 0;
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const name = (try decoded.mapGet("name")).?.str.value();
    const age = (try decoded.mapGet("age")).?.uint;
    std.debug.print("Name: {s}, Age: {d}\n", .{ name, age });
}
```

You can also use the convenience function:

```zig
var packer = msgpack.packIO(&reader, &writer);
```

### Working with Files

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Open file for reading and writing
    var file = try std.fs.cwd().createFile("data.msgpack", .{ .read = true });
    defer file.close();

    // Create reader and writer with buffers
    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(&reader_buf);
    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Serialize data
    var payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);
    try payload.mapPut("message", try msgpack.Payload.strToPayload("Hello, MessagePack!", allocator));
    try packer.write(payload);

    // Flush and seek back to start
    try writer.flush();
    try file.seekTo(0);
    reader.seek = 0;
    reader.end = 0;

    // Deserialize
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const message = (try decoded.mapGet("message")).?.str.value();
    std.debug.print("Message: {s}\n", .{message});
}
```

### Basic Usage (All Zig Versions)

For maximum compatibility or when you need more control, use the generic `Pack` API:

    ```zig
    const std = @import("std");

    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});

        const exe = b.addExecutable(.{
            .name = "my-app",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
        });

        const msgpack_dep = b.dependency("zig_msgpack", .{
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("msgpack", msgpack_dep.module("msgpack"));

        b.installArtifact(exe);
    }
    ```

## Usage

### Using std.io.Reader and std.io.Writer (Zig 0.15+)

For Zig 0.15 and later, you can use the convenient `PackerIO` API with standard I/O interfaces:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;

    // Create Reader and Writer
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    // Create packer using the convenient PackerIO
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Create and encode data
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("name", try msgpack.Payload.strToPayload("Alice", allocator));
    try map.mapPut("age", msgpack.Payload.uintToPayload(30));
    try packer.write(map);

    // Decode
    reader.seek = 0;
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const name = (try decoded.mapGet("name")).?.str.value();
    const age = (try decoded.mapGet("age")).?.uint;
    std.debug.print("Name: {s}, Age: {d}\n", .{ name, age });
}
```

You can also use the convenience function:

```zig
var packer = msgpack.packIO(&reader, &writer);
```

### Working with Files

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Open file for reading and writing
    var file = try std.fs.cwd().createFile("data.msgpack", .{ .read = true });
    defer file.close();

    // Create reader and writer with buffers
    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(&reader_buf);
    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // Serialize data
    var payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);
    try payload.mapPut("message", try msgpack.Payload.strToPayload("Hello, MessagePack!", allocator));
    try packer.write(payload);

    // Flush and seek back to start
    try writer.flush();
    try file.seekTo(0);
    reader.seek = 0;
    reader.end = 0;

    // Deserialize
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const message = (try decoded.mapGet("message")).?.str.value();
    std.debug.print("Message: {s}\n", .{message});
}
```

### Basic Usage (All Zig Versions)

For maximum compatibility or when you need more control, use the generic `Pack` API:

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var buffer: [1024]u8 = undefined;

    // Use the compatibility layer for cross-version support
    const compat = msgpack.compat;
    var write_buffer = compat.fixedBufferStream(&buffer);
    var read_buffer = compat.fixedBufferStream(&buffer);

    const BufferType = compat.BufferStream;
    var packer = msgpack.Pack(
        *BufferType, *BufferType,
        BufferType.WriteError, BufferType.ReadError,
        BufferType.write, BufferType.read,
    ).init(&write_buffer, &read_buffer);

    // Create and encode data
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("name", try msgpack.Payload.strToPayload("Alice", allocator));
    try map.mapPut("age", msgpack.Payload.uintToPayload(30));
    try packer.write(map);

    // Decode
    read_buffer.pos = 0;
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const name = (try decoded.mapGet("name")).?.str.value();
    const age = (try decoded.mapGet("age")).?.uint;
    std.debug.print("Name: {s}, Age: {d}\n", .{ name, age });
}
```

### Data Types

```zig
// Basic types
const nil_val = msgpack.Payload.nilToPayload();
const bool_val = msgpack.Payload.boolToPayload(true);
const int_val = msgpack.Payload.intToPayload(-42);
const uint_val = msgpack.Payload.uintToPayload(42);
const float_val = msgpack.Payload.floatToPayload(3.14);

// String and binary
const str_val = try msgpack.Payload.strToPayload("hello", allocator);
const bin_val = try msgpack.Payload.binToPayload(&[_]u8{1, 2, 3}, allocator);

// Array
var arr = try msgpack.Payload.arrPayload(2, allocator);
try arr.setArrElement(0, msgpack.Payload.intToPayload(1));
try arr.setArrElement(1, msgpack.Payload.intToPayload(2));

// Extension type
const ext_val = try msgpack.Payload.extToPayload(5, &[_]u8{0xaa, 0xbb}, allocator);

// Map with string keys (backward compatible)
var map = msgpack.Payload.mapPayload(allocator);
try map.mapPut("key1", msgpack.Payload.intToPayload(42));

// Map with any type keys (new feature)
var generic_map = msgpack.Payload.mapPayload(allocator);
try generic_map.mapPutGeneric(msgpack.Payload.intToPayload(1), msgpack.Payload.strToPayload("value1", allocator));
try generic_map.mapPutGeneric(msgpack.Payload.boolToPayload(true), msgpack.Payload.strToPayload("true_value", allocator));
```

### Using Organized Constants

The library provides semantic constant structures for better code clarity:

```zig
// MessagePack format limits
const max_fixstr = msgpack.FixLimits.STR_LEN_MAX;  // 31
const max_fixarray = msgpack.FixLimits.ARRAY_LEN_MAX;  // 15

// Integer bounds
const uint8_max = msgpack.IntBounds.UINT8_MAX;  // 0xff
const int8_min = msgpack.IntBounds.INT8_MIN;  // -128

// Fixed extension lengths
const ext4_len = msgpack.FixExtLen.EXT4;  // 4

// Timestamp constants
const ts_type = msgpack.TimestampExt.TYPE_ID;  // -1
const ts32_len = msgpack.TimestampExt.FORMAT32_LEN;  // 4
const max_nano = msgpack.TimestampExt.NANOSECONDS_MAX;  // 999_999_999

// Marker base values
const fixarray_base = msgpack.MarkerBase.FIXARRAY;  // 0x90
const fixstr_mask = msgpack.MarkerBase.FIXSTR_LEN_MASK;  // 0x1f
```

### Timestamp Usage

```zig
// Create timestamps
const ts1 = msgpack.Payload.timestampFromSeconds(1234567890);
const ts2 = msgpack.Payload.timestampToPayload(1234567890, 123456789);

// Write and read timestamp
try packer.write(ts2);
read_buffer.pos = 0;
const decoded_ts = try packer.read(allocator);
defer decoded_ts.free(allocator);

std.debug.print("Timestamp: {}s + {}ns\n",
    .{ decoded_ts.timestamp.seconds, decoded_ts.timestamp.nanoseconds });
std.debug.print("As float: {d}\n", .{ decoded_ts.timestamp.toFloat() });
```

### Error Handling

```zig
// Type conversion with error handling
const int_payload = msgpack.Payload.intToPayload(-42);
const uint_result = int_payload.getUint() catch |err| switch (err) {
    msgpack.MsgPackError.InvalidType => {
        std.debug.print("Cannot convert negative to unsigned\n");
        return;
    },
    else => return err,
};

// Strict type conversion (no auto-conversion)
const strict_int = payload.asInt() catch |err| {
    // Only accepts .int type, rejects .uint even if it fits
    return err;
};

// Type checking
if (payload.isNil()) {
    std.debug.print("Value is nil\n", .{});
}
if (payload.isNumber()) {
    std.debug.print("Value is a number (int/uint/float)\n", .{});
}
if (payload.isInteger()) {
    std.debug.print("Value is an integer (int/uint)\n", .{});
}
```

### Security Features (Parsing Untrusted Data)

The library includes configurable safety limits to protect against malicious or corrupted MessagePack data:

```zig
// Default limits (recommended for most use cases)
const Packer = msgpack.Pack(
    *Writer, *Reader,
    Writer.Error, Reader.Error,
    Writer.write, Reader.read,
);
// Automatically protected against:
// - Deep nesting attacks (max 1000 layers)
// - Large array/map attacks (max 1M elements)
// - Memory exhaustion (max 100MB strings)

// Custom limits for specific environments
const StrictPacker = msgpack.PackWithLimits(
    *Writer, *Reader,
    Writer.Error, Reader.Error,
    Writer.write, Reader.read,
    .{
        .max_depth = 50,              // Limit nesting to 50 layers
        .max_array_length = 10_000,   // Max 10K array elements
        .max_map_size = 10_000,       // Max 10K map pairs
        .max_string_length = 1024 * 1024,  // Max 1MB strings
        .max_bin_length = 1024 * 1024,     // Max 1MB binary blobs
        .max_ext_length = 512 * 1024,      // Max 512KB extension data
    },
);
```

**Security Guarantees:**

- ✅ **Never crashes** on malformed or malicious input
- ✅ **No stack overflow** regardless of nesting depth (iterative parser)
- ✅ **Bounded memory usage** with configurable limits
- ✅ **Fast rejection** of invalid data (no resource exhaustion)

Possible security errors:

```zig
msgpack.MsgPackError.MaxDepthExceeded    // Nesting too deep
msgpack.MsgPackError.ArrayTooLarge       // Array claims too many elements
msgpack.MsgPackError.MapTooLarge         // Map claims too many pairs
msgpack.MsgPackError.StringTooLong       // String data too large
msgpack.MsgPackError.BinDataLengthTooLong // Binary blob too large
msgpack.MsgPackError.ExtDataTooLarge     // Extension payload too large
```

## API Overview

- **`msgpack.Pack`**: The main struct for packing and unpacking MessagePack data with default safety limits.
- **`msgpack.PackWithLimits`**: Create a packer with custom safety limits for specific security requirements.
- **`msgpack.Payload`**: A union that represents any MessagePack type. It provides methods for creating and interacting with different data types (e.g., `mapPayload`, `strToPayload`, `mapGet`).
- **`msgpack.PackerIO`**: (Zig 0.15+) Convenient wrapper for working with `std.io.Reader` and `std.io.Writer`.
- **`msgpack.packIO`**: (Zig 0.15+) Convenience function to create a `PackerIO` instance.
- **`msgpack.ParseLimits`**: Configuration struct for parser safety limits.
- **Constant Structures**: `FixLimits`, `IntBounds`, `FixExtLen`, `TimestampExt`, `MarkerBase` - organized constants for better code clarity.

### Type Conversion Methods

**Lenient conversion** (allows type conversion):
- `getInt()` - uint can be converted to i64 if it fits
- `getUint()` - positive int can be converted to u64

**Strict conversion** (no type conversion):
- `asInt()`, `asUint()`, `asFloat()`, `asBool()`, `asStr()`, `asBin()`

**Type checking**:
- `isNil()`, `isNumber()`, `isInteger()`

### Map Operations

**String keys** (backward compatible):
- `mapPut(key: []const u8, value: Payload)`
- `mapGet(key: []const u8) ?Payload`

**Generic keys** (any Payload type):
- `mapPutGeneric(key: Payload, value: Payload)`
- `mapGetGeneric(key: Payload) ?Payload`

## Implementation Notes

### Security Architecture

This library uses an **iterative parser** (not recursive) to provide strong security guarantees:

**Iterative Parsing:**

- Parser uses an explicit stack (on heap) instead of recursive function calls
- Stack depth remains constant regardless of input nesting depth
- Prevents stack overflow attacks completely

**Safety Limits:**

- All limits are enforced **before** memory allocation
- Invalid input is rejected immediately without resource consumption
- Configurable limits allow tuning for specific environments (embedded, server, etc.)

**Memory Safety:**

- All error paths include complete cleanup (`errdefer` + `cleanupParseStack`)
- Zero memory leaks verified by GPA (General Purpose Allocator) in tests
- Safe to parse untrusted data from network, files, or user input

### Zig 0.16 Compatibility

Starting from Zig 0.16, the standard library underwent significant changes to the I/O subsystem. The `std.io.FixedBufferStream` was removed as part of a broader redesign. This library includes a compatibility layer (`src/compat.zig`) that:

- Provides a `BufferStream` implementation for Zig 0.16+ that mimics the behavior of the old `FixedBufferStream`
- Uses conditional compilation to maintain backward compatibility with Zig 0.14 and 0.15
- Ensures all existing functionality works seamlessly across different Zig versions

This means you can use the same API regardless of your Zig version, and the library will handle the differences internally.

## Testing

To run the unit tests for this library, use the following command:

```sh
zig build test

# For more detailed test output
zig build test --summary all
```

The comprehensive test suite includes:

- **87 tests** covering all functionality
- **Malicious data tests:** Verify protection against crafted attacks (billion-element arrays, extreme nesting, etc.)
- **Fuzz tests:** Random input validation ensures no crashes on arbitrary data
- **Large data tests:** Arrays with 1000+ elements, maps with 500+ pairs
- **Memory safety:** Zero leaks verified by strict allocator testing

## Benchmarks

To run performance benchmarks:

```sh
# Run benchmarks (default build mode)
zig build bench

# Run with optimizations for accurate performance measurements
zig build bench -Doptimize=ReleaseFast
```

The benchmark suite includes:

- Basic types (nil, bool, integers, floats)
- Strings and binary data of various sizes
- Arrays and maps (small, medium, large)
- Extension types and timestamps
- Nested structures and mixed-type payloads

Output provides throughput (ops/sec) and latency (ns/op) metrics for each operation.

## Documentation

To generate documentation for this library:

```sh
zig build docs
```

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.

## Performance

This library is heavily optimized for performance across all supported platforms. The optimizations are architecture-aware and automatically adapt to your target platform at compile time.

### Optimization Features

1. **CPU Cache Prefetching**
   - Platform-specific prefetch instructions (x86: `PREFETCH*`, ARM: `PRFM`)
   - Intelligently prefetches data before it's needed for containers ≥256 bytes
   - Multi-level cache hints (L1/L2/L3) for optimal cache utilization
   - Streaming prefetch for non-temporal data access

2. **SIMD Operations**
   - Automatic detection of available SIMD features (AVX-512, AVX2, SSE2, NEON)
   - Vectorized string comparison (16-64 byte chunks)
   - Vectorized memory copying with alignment optimization
   - Vectorized byte order conversion (big-endian ↔ little-endian)
   - Batch integer array conversions (u32/u64)

3. **Memory Alignment Optimization**
   - Automatic alignment detection and fast path selection
   - Aligned memory reads/writes for supported types
   - Memory alignment preprocessing for better SIMD performance
   - Large data copy optimization (≥64 bytes)

4. **Branch Prediction Optimization**
   - Hot path annotations for common cases
   - Lookup tables for O(1) marker byte conversion (256-entry precomputed table)
   - Switch expressions instead of if-else chains (jump table optimization)
   - Optimized error handling paths

5. **HashMap-Based Maps**
   - O(1) average-case key lookups (vs O(n) linear search)
   - Efficient hash function with depth limiting
   - Support for any Payload type as keys
   - `getOrPut` optimization (single hash computation)

### Performance Characteristics

Measured performance improvements over baseline implementations:

| Operation Type           | Performance Gain | Throughput              | Key Optimizations                        |
| ------------------------ | ---------------- | ----------------------- | ---------------------------------------- |
| Small/Simple Data        | 5-10%            | ~20M ops/sec            | Branch prediction, lookup tables         |
| Large Strings (≥256B)    | 15-25%           | ~2-5 GB/s               | Prefetching, SIMD comparison             |
| Large Binary (≥256B)     | 15-25%           | ~3-6 GB/s               | Prefetching, SIMD memcpy                 |
| Integer Arrays (100+)    | 10-20%           | ~500K-1M arrays/sec     | Batch conversion, prefetching            |
| Map Lookups (100+ keys)  | 50-90%           | ~5-10M lookups/sec      | HashMap O(1) vs linear O(n)              |
| Nested Structures        | 8-15%            | ~100K-500K structs/sec  | Combined optimizations                   |
| Mixed Type Data          | 10-15%           | Varies by data          | Adaptive optimizations                   |

> **Note:** Performance varies by platform, CPU model, data size, and compiler optimization level (`ReleaseFast` vs `ReleaseSafe`).
> Measurements taken on modern CPUs (Intel Core i7/i9, Apple M1/M2, AMD Ryzen).

### Platform-Specific Optimizations

| Platform | SIMD Features | Prefetch Instructions | String Comparison | Memory Copy |
|----------|---------------|----------------------|-------------------|-------------|
| **x86_64 (AVX-512)** | 512-bit vectors | `PREFETCHT0/1/2/NTA` | 64-byte chunks | 64-byte chunks |
| **x86_64 (AVX2)** | 256-bit vectors | `PREFETCHT0/1/2/NTA` | 32-byte chunks | 32-byte chunks |
| **x86_64 (SSE2)** | 128-bit vectors | `PREFETCHT0/1/2/NTA` | 16-byte chunks | 16-byte chunks |
| **ARM64 (NEON)** | 128-bit vectors | `PRFM PLD/PST` | 16-byte chunks | 16-byte chunks |
| **Other** | Scalar fallback | No prefetch | Standard `memcmp` | Standard `memcpy` |

All optimizations are **compile-time detected** with zero runtime overhead. The library automatically uses the best available features for your target platform.

### Running Performance Tests

```sh
# Standard benchmark suite
zig build bench -Doptimize=ReleaseFast

# Sample output:
# Benchmark Name                           | Iterations | ns/op    | ops/sec
# ------------------------------------------------------------------------
# Nil Write                                |  1000000   |       45 |  22222222
# Small Int Write                          |  1000000   |       52 |  19230769
# Large String Write (1KB)                 |   100000   |     1250 |    800000
# Map Lookup (100 keys)                    |   500000   |      180 |   5555555
```

## Related Projects

- [getty-msgpack](https://git.mzte.de/LordMZTE/getty-msgpack)
- [znvim](https://github.com/jinzhongjia/znvim)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
