# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml)

A MessagePack implementation for the Zig programming language. This library provides a simple and efficient way to serialize and deserialize data using the MessagePack format.

An article introducing it: [Zig Msgpack](https://blog.nvimer.org/2025/05/03/zig-msgpack/)

## Features

- **Full MessagePack Support:** Implements all MessagePack types including the timestamp extension.
- **Timestamp Support:** Complete implementation of MessagePack timestamp extension type (-1) with support for all three formats (32-bit, 64-bit, and 96-bit).
- **Efficient:** Designed for high performance with minimal memory overhead.
- **Type-Safe:** Leverages Zig's type system to ensure safety during serialization and deserialization.
- **Simple API:** Offers a straightforward and easy-to-use API for encoding and decoding.

## Installation

> For Zig 0.13 and older versions, please use version `0.0.6` of this library.

For Zig `0.14.0` and `nightly`, follow these steps:

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
    var stream = std.io.fixedBufferStream(&buffer);

    var packer = msgpack.Pack(
        *std.io.FixedBufferStream([]u8), *std.io.FixedBufferStream([]u8),
        std.io.FixedBufferStream([]u8).WriteError, std.io.FixedBufferStream([]u8).ReadError,
        std.io.FixedBufferStream([]u8).write, std.io.FixedBufferStream([]u8).read,
    ).init(&stream, &stream);

    // Create and encode data
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("name", try msgpack.Payload.strToPayload("Alice", allocator));
    try map.mapPut("age", msgpack.Payload.uintToPayload(30));
    try packer.write(map);

    // Decode
    stream.pos = 0;
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
stream.pos = 0;
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
    msgpack.MsGPackError.INVALID_TYPE => {
        std.debug.print("Cannot convert negative to unsigned\n");
        return;
    },
    else => return err,
};
```

## API Overview

- **`msgpack.Pack`**: The main struct for packing and unpacking MessagePack data. It is initialized with read and write contexts.
- **`msgpack.Payload`**: A union that represents any MessagePack type. It provides methods for creating and interacting with different data types (e.g., `mapPayload`, `strToPayload`, `mapGet`).

## Testing

To run the unit tests for this library, use the following command:

```sh
zig build test
```

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.

## Related Projects

- [getty-msgpack](https://git.mzte.de/LordMZTE/getty-msgpack)
- [znvim](https://github.com/jinzhongjia/znvim)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
