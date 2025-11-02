# zig-msgpack

[![CI](https://github.com/zigcc/zig-msgpack/actions/workflows/test.yml/badge.svg)](https://github.com/zigcc/zig-msgpack/actions/workflows/test.yml)

Zig 编程语言的 MessagePack 实现。此库提供了一种简单高效的方式来使用 MessagePack 格式序列化和反序列化数据。

相关介绍文章: [Zig Msgpack](https://blog.nvimer.org/2025/09/20/zig-msgpack/)

## 特性

- **完整的 MessagePack 支持**: 实现了所有 MessagePack 类型，包括时间戳扩展类型。
- **时间戳支持**: 完整实现 MessagePack 时间戳扩展类型 (-1)，支持所有三种格式（32位、64位和96位）。
- **生产级安全解析器**: 迭代式解析器防止深度嵌套或恶意输入导致的栈溢出。
- **安全加固**: 可配置的限制保护，防御 DoS 攻击（深度炸弹、大小炸弹等）。
- **高效**: 设计追求高性能，内存开销最小。
- **类型安全**: 利用 Zig 的类型系统确保序列化和反序列化期间的安全性。
- **简单的 API**: 提供直观易用的编码和解码 API。
- **泛型 Map 键**: 支持任意 Payload 类型作为 map 键，不仅限于字符串（使用高效的 HashMap 实现）。
- **性能优化**: 高级优化包括 CPU 缓存预取、分支预测提示和 SIMD 操作，实现最大吞吐量。
- **跨平台**: 在所有主流平台（Windows、macOS、Linux）和架构（x86_64、ARM64等）上测试和优化，具有平台特定的优化。

## 平台支持

本库在所有主流平台和架构上经过测试和优化：

| 平台 | 架构 | CI 状态 | SIMD 优化 |
|----------|--------------|-----------|-------------------|
| **Windows** | x86_64 | ✅ 已测试 | SSE2/AVX2 预取 |
| **macOS** | x86_64 (Intel) | ✅ 已测试 | SSE2/AVX2 预取 |
| **macOS** | ARM64 (Apple Silicon) | ✅ 已测试 | ARM NEON + PRFM |
| **Linux** | x86_64 | ✅ 已测试 | SSE2/AVX2 预取 |
| **Linux** | ARM64/aarch64 | ✅ 已测试 | ARM NEON + PRFM |
| **其他** | RISC-V、MIPS 等 | ✅ 已测试 | 优雅降级 |

### 架构特定优化

- **x86/x64**: 利用 SSE/AVX 预取指令（`PREFETCHT0/1/2`、`PREFETCHNTA`）实现缓存感知的内存访问
- **ARM64**: 使用 ARM PRFM（预取内存）指令在 Apple Silicon 和 ARM 服务器上实现最佳性能
- **跨平台**: 编译时自动检测 CPU 特性，零运行时开销
- **安全降级**: 在不支持的架构上优雅地降级为标准操作

## 安装

### 版本兼容性

| Zig 版本             | 库版本   | 状态              |
| -------------------- | -------- | ----------------- |
| 0.13 及更早版本      | 0.0.6    | 旧版支持          |
| 0.14.0               | 当前版本 | ✅ 完全支持       |
| 0.15.x               | 当前版本 | ✅ 完全支持       |
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

### 使用 std.io.Reader 和 std.io.Writer（Zig 0.15+）

对于 Zig 0.15 及更高版本，您可以使用便捷的 `PackerIO` API 配合标准 I/O 接口：

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buffer: [1024]u8 = undefined;

    // 创建 Reader 和 Writer
    var writer = std.Io.Writer.fixed(&buffer);
    var reader = std.Io.Reader.fixed(&buffer);

    // 使用便捷的 PackerIO 创建 packer
    var packer = msgpack.PackerIO.init(&reader, &writer);

    // 创建和编码数据
    var map = msgpack.Payload.mapPayload(allocator);
    defer map.free(allocator);
    try map.mapPut("姓名", try msgpack.Payload.strToPayload("小明", allocator));
    try map.mapPut("年龄", msgpack.Payload.uintToPayload(25));
    try packer.write(map);

    // 解码
    reader.seek = 0;
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const name = (try decoded.mapGet("姓名")).?.str.value();
    const age = (try decoded.mapGet("年龄")).?.uint;
    std.debug.print("姓名: {s}, 年龄: {d}\n", .{ name, age });
}
```

您也可以使用便捷函数：

```zig
var packer = msgpack.packIO(&reader, &writer);
```

### 文件操作

```zig
const std = @import("std");
const msgpack = @import("msgpack");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 打开文件进行读写
    var file = try std.fs.cwd().createFile("data.msgpack", .{ .read = true });
    defer file.close();

    // 创建带缓冲区的 reader 和 writer
    var reader_buf: [4096]u8 = undefined;
    var reader = file.reader(&reader_buf);
    var writer_buf: [4096]u8 = undefined;
    var writer = file.writer(&writer_buf);

    var packer = msgpack.PackerIO.init(&reader, &writer);

    // 序列化数据
    var payload = msgpack.Payload.mapPayload(allocator);
    defer payload.free(allocator);
    try payload.mapPut("消息", try msgpack.Payload.strToPayload("你好，MessagePack！", allocator));
    try packer.write(payload);

    // 刷新并回到文件开始位置
    try writer.flush();
    try file.seekTo(0);
    reader.seek = 0;
    reader.end = 0;

    // 反序列化
    const decoded = try packer.read(allocator);
    defer decoded.free(allocator);

    const message = (try decoded.mapGet("消息")).?.str.value();
    std.debug.print("消息: {s}\n", .{message});
}
```

### 基础用法（所有 Zig 版本）

为了最大兼容性或需要更多控制时，使用泛型 `Pack` API：

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

// 使用字符串键的 Map（向后兼容）
var map = msgpack.Payload.mapPayload(allocator);
try map.mapPut("键1", msgpack.Payload.intToPayload(42));

// 使用任意类型键的 Map（新特性）
var generic_map = msgpack.Payload.mapPayload(allocator);
try generic_map.mapPutGeneric(msgpack.Payload.intToPayload(1), msgpack.Payload.strToPayload("值1", allocator));
try generic_map.mapPutGeneric(msgpack.Payload.boolToPayload(true), msgpack.Payload.strToPayload("真值", allocator));
```

### 使用组织化的常量

库提供了语义化的常量结构，提高代码清晰度：

```zig
// MessagePack 格式限制
const max_fixstr = msgpack.FixLimits.STR_LEN_MAX;  // 31
const max_fixarray = msgpack.FixLimits.ARRAY_LEN_MAX;  // 15

// 整数边界
const uint8_max = msgpack.IntBounds.UINT8_MAX;  // 0xff
const int8_min = msgpack.IntBounds.INT8_MIN;  // -128

// 固定扩展类型长度
const ext4_len = msgpack.FixExtLen.EXT4;  // 4

// 时间戳常量
const ts_type = msgpack.TimestampExt.TYPE_ID;  // -1
const ts32_len = msgpack.TimestampExt.FORMAT32_LEN;  // 4
const max_nano = msgpack.TimestampExt.NANOSECONDS_MAX;  // 999_999_999

// 标记基础值
const fixarray_base = msgpack.MarkerBase.FIXARRAY;  // 0x90
const fixstr_mask = msgpack.MarkerBase.FIXSTR_LEN_MASK;  // 0x1f
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
    msgpack.MsgPackError.InvalidType => {
        std.debug.print("无法将负数转换为无符号整数\n", .{});
        return;
    },
    else => return err,
};

// 严格类型转换（无自动转换）
const strict_int = payload.asInt() catch |err| {
    // 只接受 .int 类型，即使 .uint 值适合也会拒绝
    return err;
};

// 类型检查
if (payload.isNil()) {
    std.debug.print("值是 nil\n", .{});
}
if (payload.isNumber()) {
    std.debug.print("值是数字（int/uint/float）\n", .{});
}
if (payload.isInteger()) {
    std.debug.print("值是整数（int/uint）\n", .{});
}
```

### 安全特性（解析不可信数据）

本库包含可配置的安全限制，用于防护恶意或损坏的 MessagePack 数据：

```zig
// 默认限制（推荐用于大多数场景）
const Packer = msgpack.Pack(
    *Writer, *Reader,
    Writer.Error, Reader.Error,
    Writer.write, Reader.read,
);
// 自动防护：
// - 深度嵌套攻击（最大 1000 层）
// - 大数组/Map 攻击（最大 100 万元素）
// - 内存耗尽（最大 100MB 字符串）

// 针对特定环境的自定义限制
const StrictPacker = msgpack.PackWithLimits(
    *Writer, *Reader,
    Writer.Error, Reader.Error,
    Writer.write, Reader.read,
    .{
        .max_depth = 50,                      // 限制嵌套到 50 层
        .max_array_length = 10_000,           // 最大 1 万个数组元素
        .max_map_size = 10_000,               // 最大 1 万个 map 键值对
        .max_string_length = 1024 * 1024,     // 最大 1MB 字符串
        .max_bin_length = 1024 * 1024,        // 最大 1MB 二进制数据
        .max_ext_length = 512 * 1024,         // 最大 512KB 扩展类型数据
    },
);
```

**安全保证**:

- ✅ **永不崩溃** - 任何畸形或恶意输入都不会导致崩溃
- ✅ **无栈溢出** - 无论嵌套深度如何（迭代式解析器）
- ✅ **内存可控** - 通过可配置限制控制内存使用
- ✅ **快速拒绝** - 无效数据被立即拒绝（无资源耗尽）

可能的安全错误：

```zig
msgpack.MsgPackError.MaxDepthExceeded    // 嵌套过深
msgpack.MsgPackError.ArrayTooLarge       // 数组声称过多元素
msgpack.MsgPackError.MapTooLarge         // Map 声称过多键值对
msgpack.MsgPackError.StringTooLong       // 字符串过长
msgpack.MsgPackError.BinDataLengthTooLong // 二进制数据过大
msgpack.MsgPackError.ExtDataTooLarge     // 扩展类型数据过大
```

## API 概览

- **`msgpack.Pack`**: 用于打包和解包 MessagePack 数据的主要结构体，带默认安全限制。
- **`msgpack.PackWithLimits`**: 创建带自定义安全限制的 packer，满足特定安全需求。
- **`msgpack.Payload`**: 表示任何 MessagePack 类型的联合体。提供创建和与不同数据类型交互的方法（例如 `mapPayload`、`strToPayload`、`mapGet`）。
- **`msgpack.PackerIO`**:（Zig 0.15+）用于处理 `std.io.Reader` 和 `std.io.Writer` 的便捷包装器。
- **`msgpack.packIO`**:（Zig 0.15+）创建 `PackerIO` 实例的便捷函数。
- **`msgpack.ParseLimits`**: 解析器安全限制的配置结构体。
- **常量结构体**: `FixLimits`、`IntBounds`、`FixExtLen`、`TimestampExt`、`MarkerBase` - 组织化的常量，提高代码清晰度。

### 类型转换方法

**宽松转换**（允许类型转换）：
- `getInt()` - uint 可以转换为 i64（如果在范围内）
- `getUint()` - 正数 int 可以转换为 u64

**严格转换**（不允许类型转换）：
- `asInt()`、`asUint()`、`asFloat()`、`asBool()`、`asStr()`、`asBin()`

**类型检查**：
- `isNil()`、`isNumber()`、`isInteger()`

### Map 操作

**字符串键**（向后兼容）：
- `mapPut(key: []const u8, value: Payload)`
- `mapGet(key: []const u8) ?Payload`

**泛型键**（任意 Payload 类型）：
- `mapPutGeneric(key: Payload, value: Payload)`
- `mapGetGeneric(key: Payload) ?Payload`

## 实现说明

### 安全架构

本库使用**迭代式解析器**（非递归）提供强大的安全保证：

**迭代式解析**：

- 解析器使用显式栈（堆上）而非递归函数调用
- 栈深度恒定，与输入嵌套深度无关
- 完全防止栈溢出攻击

**安全限制**：

- 所有限制在内存分配**之前**强制执行
- 无效输入被立即拒绝，不消耗资源
- 可配置限制允许针对特定环境调整（嵌入式、服务器等）

**内存安全**：

- 所有错误路径包含完整清理（`errdefer` + `cleanupParseStack`）
- 零内存泄漏（测试中由 GPA 验证）
- 可安全解析来自网络、文件或用户输入的不可信数据

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

综合测试套件包括：

- **87 个测试** 覆盖所有功能
- **恶意数据测试**：验证针对精心构造的攻击（数十亿元素数组、极端嵌套等）的防护
- **模糊测试**：随机输入验证，确保任意数据都不会崩溃
- **大数据测试**：1000+ 元素的数组、500+ 键值对的 map
- **内存安全**：严格分配器测试验证零泄漏

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

## 性能

本库在所有支持的平台上都经过深度性能优化。优化是架构感知的，在编译时自动适应您的目标平台。

### 优化特性

1. **CPU 缓存预取**
   - 平台特定的预取指令（x86: `PREFETCH*`，ARM: `PRFM`）
   - 智能预取 ≥256 字节的容器数据
   - 多级缓存提示（L1/L2/L3）实现最佳缓存利用
   - 非时序数据访问的流式预取

2. **SIMD 操作**
   - 自动检测可用的 SIMD 特性（AVX-512、AVX2、SSE2、NEON）
   - 向量化字符串比较（16-64 字节块）
   - 向量化内存拷贝与对齐优化
   - 向量化字节序转换（大端 ↔ 小端）
   - 批量整数数组转换（u32/u64）

3. **内存对齐优化**
   - 自动对齐检测和快速路径选择
   - 支持类型的对齐内存读写
   - 更好 SIMD 性能的内存对齐预处理
   - 大数据拷贝优化（≥64 字节）

4. **分支预测优化**
   - 常见情况的热路径注解
   - O(1) 标记字节转换的查找表（256 项预计算表）
   - 使用 switch 表达式而非 if-else 链（跳转表优化）
   - 优化的错误处理路径

5. **基于 HashMap 的 Map**
   - O(1) 平均情况的键查找（vs O(n) 线性搜索）
   - 高效的哈希函数与深度限制
   - 支持任意 Payload 类型作为键
   - `getOrPut` 优化（单次哈希计算）

### 性能特征

相对于基线实现的测量性能提升：

| 操作类型                  | 性能提升    | 吞吐量                   | 关键优化                                  |
| ------------------------- | ----------- | ------------------------ | ----------------------------------------- |
| 小型/简单数据             | 5-10%       | ~2000万 次操作/秒        | 分支预测、查找表                          |
| 大字符串（≥256B）         | 15-25%      | ~2-5 GB/秒               | 预取、SIMD 比较                           |
| 大二进制（≥256B）         | 15-25%      | ~3-6 GB/秒               | 预取、SIMD memcpy                         |
| 整数数组（100+）          | 10-20%      | ~50-100万 数组/秒        | 批量转换、预取                            |
| Map 查找（100+ 键）       | 50-90%      | ~500-1000万 查找/秒      | HashMap O(1) vs 线性 O(n)                 |
| 嵌套结构                  | 8-15%       | ~10-50万 结构/秒         | 组合优化                                  |
| 混合类型数据              | 10-15%      | 根据数据变化             | 自适应优化                                |

> **注意**: 性能因平台、CPU 型号、数据大小和编译器优化级别（`ReleaseFast` vs `ReleaseSafe`）而异。
> 测量数据基于现代 CPU（Intel Core i7/i9、Apple M1/M2、AMD Ryzen）。

### 平台特定优化

| 平台 | SIMD 特性 | 预取指令 | 字符串比较 | 内存拷贝 |
|----------|---------------|----------------------|-------------------|-------------|
| **x86_64 (AVX-512)** | 512 位向量 | `PREFETCHT0/1/2/NTA` | 64 字节块 | 64 字节块 |
| **x86_64 (AVX2)** | 256 位向量 | `PREFETCHT0/1/2/NTA` | 32 字节块 | 32 字节块 |
| **x86_64 (SSE2)** | 128 位向量 | `PREFETCHT0/1/2/NTA` | 16 字节块 | 16 字节块 |
| **ARM64 (NEON)** | 128 位向量 | `PRFM PLD/PST` | 16 字节块 | 16 字节块 |
| **其他** | 标量回退 | 无预取 | 标准 `memcmp` | 标准 `memcpy` |

所有优化都是**编译时检测**的，零运行时开销。库自动使用目标平台的最佳可用特性。

### 运行性能测试

```sh
# 标准基准测试套件
zig build bench -Doptimize=ReleaseFast

# 示例输出：
# 基准测试名称                             | 迭代次数   | ns/操作  | 操作/秒
# ------------------------------------------------------------------------
# Nil 写入                                 |  1000000   |       45 |  22222222
# 小整数写入                               |  1000000   |       52 |  19230769
# 大字符串写入（1KB）                      |   100000   |     1250 |    800000
# Map 查找（100 键）                       |   500000   |      180 |   5555555
```

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
