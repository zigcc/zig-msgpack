# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml)

Zig 编程语言的 MessagePack 实现。此库提供了一种简单高效的方式来使用 MessagePack 格式序列化和反序列化数据。

相关介绍文章: [Zig Msgpack](https://blog.nvimer.org/2025/05/03/zig-msgpack/)

## 特性

- **完整的 MessagePack 支持**: 实现了所有 MessagePack 类型，包括时间戳扩展类型。
- **时间戳支持**: 完整实现 MessagePack 时间戳扩展类型 (-1)，支持所有三种格式（32位、64位和96位）。
- **高效**: 设计追求高性能，内存开销最小。
- **类型安全**: 利用 Zig 的类型系统确保序列化和反序列化期间的安全性。
- **简单的 API**: 提供直观易用的编码和解码 API。

## 安装

> 对于 Zig 0.13 及更早版本，请使用本库的 `0.0.6` 版本。

对于 Zig `0.14.0` 和 `nightly` 版本，请按以下步骤操作：

1. **添加为依赖项**:
   将库添加到您的 `build.zig.zon` 文件中。您可以获取特定的提交或分支。

   ```sh
   zig fetch --save https://github.com/zigcc/zig-msgpack/archive/{COMMIT_OR_BRANCH}.tar.gz
   ```

2. **配置您的 `build.zig`**:
   将 `zig-msgpack` 模块添加到您的可执行文件中。

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

## 使用方法

### 基础用法

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

    // 创建和编码数据
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("姓名", try msgpack.Payload.strToPayload("小明", allocator));
    try map.mapPut("年龄", msgpack.Payload.uintToPayload(25));
    try packer.write(map);

    // 解码
    stream.pos = 0;
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);
    
    const name = (try decoded.mapGet("姓名")).?.str.value();
    const age = (try decoded.mapGet("年龄")).?.uint;
    std.debug.print("姓名: {s}, 年龄: {d}\n", .{ name, age });
}
```

### 数据类型

```zig
// 基础类型
const nil_val = msgpack.Payload.nilToPayload();
const bool_val = msgpack.Payload.boolToPayload(true);
const int_val = msgpack.Payload.intToPayload(-42);
const uint_val = msgpack.Payload.uintToPayload(42);
const float_val = msgpack.Payload.floatToPayload(3.14);

// 字符串和二进制数据
const str_val = try msgpack.Payload.strToPayload("你好", allocator);
const bin_val = try msgpack.Payload.binToPayload(&[_]u8{1, 2, 3}, allocator);

// 数组
var arr = try msgpack.Payload.arrPayload(2, allocator);
try arr.setArrElement(0, msgpack.Payload.intToPayload(1));
try arr.setArrElement(1, msgpack.Payload.intToPayload(2));

// 扩展类型
const ext_val = try msgpack.Payload.extToPayload(5, &[_]u8{0xaa, 0xbb}, allocator);
```

### 时间戳用法

```zig
// 创建时间戳
const ts1 = msgpack.Payload.timestampFromSeconds(1234567890);
const ts2 = msgpack.Payload.timestampToPayload(1234567890, 123456789);

// 写入和读取时间戳
try packer.write(ts2);
stream.pos = 0;
const decoded_ts = try packer.read(allocator);
defer decoded_ts.free(allocator);

std.debug.print("时间戳: {}秒 + {}纳秒\n", 
    .{ decoded_ts.timestamp.seconds, decoded_ts.timestamp.nanoseconds });
std.debug.print("浮点数形式: {d}\n", .{ decoded_ts.timestamp.toFloat() });
```

### 错误处理

```zig
// 类型转换与错误处理
const int_payload = msgpack.Payload.intToPayload(-42);
const uint_result = int_payload.getUint() catch |err| switch (err) {
    msgpack.MsGPackError.INVALID_TYPE => {
        std.debug.print("无法将负数转换为无符号整数\n");
        return;
    },
    else => return err,
};
```

## API 概览

- **`msgpack.Pack`**: 用于打包和解包 MessagePack 数据的主要结构体。使用读写上下文进行初始化。
- **`msgpack.Payload`**: 表示任何 MessagePack 类型的联合体。提供创建和与不同数据类型交互的方法（例如，`mapPayload`、`strToPayload`、`mapGet`）。

## 测试

要运行此库的单元测试，请使用以下命令：

```sh
zig build test
```

## 贡献

欢迎贡献！请随时提出问题或提交拉取请求。

## 相关项目

- [getty-msgpack](https://git.mzte.de/LordMZTE/getty-msgpack)
- [znvim](https://github.com/jinzhongjia/znvim)

## 许可证

此项目在 MIT 许可证下许可。详情请参阅 [LICENSE](LICENSE) 文件。

