
# MessagePack for Zig
This is an implementation of [MessagePack](https://msgpack.org/index.html) for [Zig](https://ziglang.org/).

an article introducing it: [Zig Msgpack](https://nvimer.org/blog/zig-msgpack/)

## Features

- Supports all MessagePack types(except timestamp)
- Efficient encoding and decoding
- Simple and easy-to-use API

## NOTE

The current protocol implementation has been completed, but it has not been fully tested.
Only limited unit testing has been conducted, which does not cover everything.

## Getting Started

> About 0.13 and previous versions, please use `0.0.6`

### `0.14.0`  \ `nightly`

1. Add to `build.zig.zon`

```sh
zig fetch --save https://github.com/zigcc/zig-msgpack/archive/{commit or branch}.tar.gz
# Of course, you can also use git+https to fetch this package!
```

2. Config `build.zig`

```zig
// To standardize development, maybe you should use `lazyDependency()` instead of `dependency()`
const msgpack = b.dependency("zig-msgpack", .{
    .target = target,
    .optimize = optimize,
});

// add module
exe.root_module.addImport("msgpack", msgpack.module("msgpack"));
```

## Related projects

- [znvim](https://github.com/jinzhongjia/znvim)
