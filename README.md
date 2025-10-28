# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml)

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

### Basic Usage

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
- **`msgpack.ParseLimits`**: Configuration struct for parser safety limits.

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

## Related Projects

- [getty-msgpack](https://git.mzte.de/LordMZTE/getty-msgpack)
- [znvim](https://github.com/jinzhongjia/znvim)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
