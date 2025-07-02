# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml)

A MessagePack implementation for the Zig programming language. This library provides a simple and efficient way to serialize and deserialize data using the MessagePack format.

An article introducing it: [Zig Msgpack](https://blog.nvimer.org/2025/05/03/zig-msgpack/)

## Features

- **Full MessagePack Support:** Implements all MessagePack types (except for the timestamp extension).
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

Here is a simple example of how to encode and decode a `Payload`:

```zig
const std = @import("std");
const msgpack = @import("msgpack");
const allocator = std.testing.allocator;

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);

    var packer = msgpack.Pack(
        *std.io.FixedBufferStream([]u8),
        *std.io.FixedBufferStream([]u8),
        std.io.FixedBufferStream([]u8).WriteError,
        std.io.FixedBufferStream([]u8).ReadError,
        std.io.FixedBufferStream([]u8).write,
        std.io.FixedBufferStream([]u8).read,
    ).init(&stream, &stream);

    // Create a map payload
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);

    try map.mapPut("message", try msgpack.Payload.strToPayload("Hello, MessagePack!", allocator));
    try map.mapPut("version", msgpack.Payload.uintToPayload(1));

    // Encode
    try packer.write(map);

    // Reset stream for reading
    stream.pos = 0;

    // Decode
    const decoded_payload = try packer.read(allocator);
    defer decoded_payload.free(allocator);

    // Use the decoded data
    const message = (try decoded_payload.mapGet("message")).?.str.value();
    const version = (try decoded_payload.mapGet("version")).?.uint;

    std.debug.print("Message: {s}, Version: {d}
", .{ message, version });
}
```

## API Overview

-   **`msgpack.Pack`**: The main struct for packing and unpacking MessagePack data. It is initialized with read and write contexts.
-   **`msgpack.Payload`**: A union that represents any MessagePack type. It provides methods for creating and interacting with different data types (e.g., `mapPayload`, `strToPayload`, `mapGet`).

## Testing

To run the unit tests for this library, use the following command:

```sh
zig build test
```

## Contributing

Contributions are welcome! Please feel free to open an issue or submit a pull request.

## Related Projects

-   [getty-msgpack](https://git.mzte.de/LordMZTE/getty-msgpack)
-   [znvim](https://github.com/jinzhongjia/znvim)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.