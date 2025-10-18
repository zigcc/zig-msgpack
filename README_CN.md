# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/ci.yml)

Zig 编程语言的 MessagePack 实现。此库提供了一种简单高效的方式来使用 MessagePack 格式序列化和反序列化数据。

相关介绍文章: [Zig Msgpack](https://blog.nvimer.org/2025/09/20/zig-msgpack/)

## 特性

- **完整的 MessagePack 支持**: 实现了所有 MessagePack 类型，包括时间戳扩展类型。
- **时间戳支持**: 完整实现 MessagePack 时间戳扩展类型 (-1)，支持所有三种格式（32位、64位和96位）。
- **高效**: 设计追求高性能，内存开销最小。
- **类型安全**: 利用 Zig 的类型系统确保序列化和反序列化期间的安全性。
- **简单的 API**: 提供直观易用的编码和解码 API。

## 安装

### 版本兼容性

| Zig 版本 | 库版本 | 状态 |
|-------------|----------------|---------|
| 0.13 及更早版本 | 0.0.6 | 旧版支持 |
| 0.14.0 | 当前版本 | ✅ 完全支持 |
| 0.15.x | 当前版本 | ✅ 完全支持 |
| 0.16.0-dev (nightly) | 当前版本 | ✅ 通过兼容层支持 |

> **注意**: 对于 Zig 0.13 及更早版本，请使用本库的 `0.0.6` 版本。
> **注意**: Zig 0.16+ 移除了 `std.io.FixedBufferStream`，但本库提供了兼容层以在所有支持的版本中维持相同的 API。

对于 Zig `0.14.0`、`0.15.x` 和 `0.16.0-dev` 版本，请按以下步骤操作：

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
    
    // 使用兼容层实现跨版本支持
    const compat = msgpack.compat;
    var write_buffer = compat.fixedBufferStream(&buffer);
    var read_buffer = compat.fixedBufferStream(&buffer);

    const BufferType = compat.BufferStream;
    var packer = msgpack.Pack(
        *BufferType, *BufferType,
        BufferType.WriteError, BufferType.ReadError,
        BufferType.write, BufferType.read,
    ).init(&write_buffer, &read_buffer);

    // 创建和编码数据
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("姓名", try msgpack.Payload.strToPayload("小明", allocator));
    try map.mapPut("年龄", msgpack.Payload.uintToPayload(25));
    try packer.write(map);

    // 解码
    read_buffer.pos = 0;
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
read_buffer.pos = 0;
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

## 实现说明

### Zig 0.16 兼容性

从 Zig 0.16 开始，标准库的 I/O 子系统经历了重大变更。作为更广泛重新设计的一部分，`std.io.FixedBufferStream` 被移除。本库包含一个兼容层（`src/compat.zig`），它：

- 为 Zig 0.16+ 提供了一个 `BufferStream` 实现，模拟旧版 `FixedBufferStream` 的行为
- 使用条件编译来保持与 Zig 0.14 和 0.15 的向后兼容性
- 确保所有现有功能在不同 Zig 版本间无缝工作

这意味着无论您使用哪个 Zig 版本，都可以使用相同的 API，库会在内部处理差异。

## 测试

要运行此库的单元测试，请使用以下命令：

```sh
zig build test

# 获取更详细的测试输出
zig build test --summary all
```

## 性能基准测试

运行性能基准测试：

```sh
# 运行基准测试（默认构建模式）
zig build bench

# 使用优化模式运行以获得准确的性能测量结果
zig build bench -Doptimize=ReleaseFast
```

基准测试套件包括：
- 基本类型（nil、bool、整数、浮点数）
- 不同大小的字符串和二进制数据
- 数组和映射表（小型、中型、大型）
- 扩展类型和时间戳
- 嵌套结构和混合类型载荷

输出提供每个操作的吞吐量（ops/sec）和延迟（ns/op）指标。

## 文档

要生成此库的文档：

```sh
zig build docs
```

## 贡献

欢迎贡献！请随时提出问题或提交拉取请求。

## 相关项目

- [getty-msgpack](https://git.mzte.de/LordMZTE/getty-msgpack)
- [znvim](https://github.com/jinzhongjia/znvim)

## 许可证

此项目在 MIT 许可证下许可。详情请参阅 [LICENSE](LICENSE) 文件。

