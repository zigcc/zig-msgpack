
# MessagePack for Zig
This is an implementation of [MessagePack](https://msgpack.org/index.html) for [Zig](https://ziglang.org/).

an article introducing it: [Zig Msgpack](https://nvimer.org/posts/zig-msgpack/)

## Features

- Supports all MessagePack types(except timestamp)
- Efficient encoding and decoding
- Simple and easy-to-use API

## NOTE

The current protocol implementation has been completed, but it has not been fully tested.
Only limited unit testing has been conducted, which does not cover everything.

## Getting Started

### `0.11`

1. Add to `build.zig.zon`

```zig
.@"zig-msgpack" = .{
        // It is recommended to replace the following branch with commit id
        .url = "https://github.com/zigcc/zig-msgpack/archive/{commit or branch}.tar.gz",
        .hash = <hash value>,
    },
```

2. Config `build.zig`

```zig
const msgpack = b.dependency("zig-msgpack", .{
    .target = target,
    .optimize = optimize,
});

// add module
exe.addModule("msgpack", msgpack.module("msgpack"));
```

### `nightly`

1. Add to `build.zig.zon`

```sh
zig fetch --save https://github.com/zigcc/zig-msgpack/archive/{commit or branch}.tar.gz
```

2. Config `build.zig`

```zig
const msgpack = b.dependency("zig-msgpack", .{
    .target = target,
    .optimize = optimize,
});

// add module
exe.root_module.addImport("msgpack", msgpack.module("msgpack"));
```

## Related projects

- [znvim](https://github.com/jinzhongjia/znvim)