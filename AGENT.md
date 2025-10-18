# AGENT.md - LLM 代码阅读规范

本文档为 AI 助手提供 zig-msgpack 项目的结构化指南，便于理解代码库并进行开发协助。

## 文档目的

- 为 LLM 提供项目快速索引
- 规范代码理解和修改流程
- 定义关键概念和术语
- 说明代码规约和最佳实践

---

## 1. 项目核心概念

### 1.1 项目定位
- **类型**：Zig 语言的 MessagePack 序列化/反序列化库
- **规范**：完整实现 MessagePack specification (https://msgpack.org)
- **特性**：支持所有 MessagePack 类型，包括 timestamp 扩展类型 (-1)

### 1.2 MessagePack 类型系统映射

| MessagePack 类型 | Zig 实现 | 说明 |
|-----------------|---------|------|
| nil | `Payload.nil: void` | 空值 |
| bool | `Payload.bool: bool` | 布尔值 |
| int | `Payload.int: i64` | 有符号整数 |
| uint | `Payload.uint: u64` | 无符号整数 |
| float | `Payload.float: f64` | 浮点数 |
| str | `Payload.str: Str` | UTF-8 字符串 |
| bin | `Payload.bin: Bin` | 二进制数据 |
| array | `Payload.arr: []Payload` | 数组 |
| map | `Payload.map: Map` | 键值对 |
| ext | `Payload.ext: EXT` | 扩展类型 |
| timestamp | `Payload.timestamp: Timestamp` | 时间戳（ext type -1） |

---

## 2. 文件结构

```
src/
├── msgpack.zig      # 核心实现（主文件）
├── test.zig         # 完整测试套件
└── compat.zig       # 跨版本兼容层
```

### 2.1 各文件职责

#### `src/msgpack.zig` (核心实现)
- 定义 `Payload` 联合类型
- 实现 `Pack()` 泛型序列化器
- 提供包装类型：`Str`, `Bin`, `EXT`, `Timestamp`
- 导出工具函数：`wrapStr()`, `wrapBin()`, `wrapEXT()`
- 导出常量结构体：`FixLimits`, `IntBounds`, `FixExtLen`, `TimestampExt`, `MarkerBase`

#### `src/compat.zig` (兼容层)
- 提供 `BufferStream` 跨版本实现
- 处理 Zig 0.14-0.16 API 差异
- 导出 `fixedBufferStream` 兼容函数

#### `src/test.zig` (测试套件)
- 覆盖所有 MessagePack 类型
- 测试边界条件和错误处理
- 验证格式选择逻辑（最小编码原则）

---

## 3. 核心 API 规范

### 3.0 常量组织

### 9.4 性能优化指南

1. **使用内联函数**：频繁调用的小函数添加 `inline` 关键字
2. **利用泛型**：避免为每个类型重复相似代码
3. **使用 switch**：比 if-else 链更高效（编译器可优化为跳转表）
4. **减少分支**：简化控制流，提升分支预测准确性
5. **复用辅助函数**：如 `writeIntRaw`, `readIntRaw`, `writeDataWithLength`
库提供了组织化的常量结构体，方便使用和理解：

```zig
// MessagePack 格式限制
msgpack.FixLimits.POSITIVE_INT_MAX  // 127
msgpack.FixLimits.STR_LEN_MAX       // 31
msgpack.FixLimits.ARRAY_LEN_MAX     // 15
msgpack.FixLimits.MAP_LEN_MAX       // 15

// 整数类型边界
msgpack.IntBounds.UINT8_MAX   // 0xff
msgpack.IntBounds.UINT16_MAX  // 0xffff
msgpack.IntBounds.INT8_MIN    // -128

// 固定扩展类型长度
msgpack.FixExtLen.EXT4   // 4
msgpack.FixExtLen.EXT8   // 8

// Timestamp 相关常量
msgpack.TimestampExt.TYPE_ID        // -1
msgpack.TimestampExt.FORMAT32_LEN   // 4
msgpack.TimestampExt.NANOSECONDS_MAX // 999_999_999
```

### 3.1 Payload 创建方法

#### 基本类型（栈分配，无需 free）
```zig
Payload.nilToPayload() -> Payload
Payload.boolToPayload(val: bool) -> Payload
Payload.intToPayload(val: i64) -> Payload
Payload.uintToPayload(val: u64) -> Payload
Payload.floatToPayload(val: f64) -> Payload
Payload.timestampFromSeconds(seconds: i64) -> Payload
Payload.timestampToPayload(seconds: i64, nanoseconds: u32) -> Payload
```

#### 堆分配类型（需要 `payload.free(allocator)`）
```zig
Payload.strToPayload(val: []const u8, allocator: Allocator) !Payload
Payload.binToPayload(val: []const u8, allocator: Allocator) !Payload
Payload.extToPayload(t: i8, data: []const u8, allocator: Allocator) !Payload
Payload.arrPayload(len: usize, allocator: Allocator) !Payload
Payload.mapPayload(allocator: Allocator) Payload
```

### 3.2 Payload 操作方法

#### 数组操作
```zig
payload.getArrLen() !usize                           // 获取数组长度
payload.getArrElement(index: usize) !Payload         // 获取元素
payload.setArrElement(index: usize, val: Payload) !void  // 设置元素
```

#### Map 操作
```zig
payload.mapGet(key: []const u8) !?Payload           // 获取值（可能为 null）
payload.mapPut(key: []const u8, val: Payload) !void // 插入/更新键值对
```

#### 类型转换
```zig
 // 宽松转换（允许类型转换）
 payload.getInt() !i64   // uint 可转换为 i64（如果在范围内）
 payload.getUint() !u64  // 正数 int 可转换为 u64
 
 // 严格转换（不允许类型转换）
 payload.asInt() !i64     // 只接受 .int 类型
 payload.asUint() !u64    // 只接受 .uint 类型
 payload.asFloat() !f64   // 只接受 .float 类型
 payload.asBool() !bool   // 只接受 .bool 类型
 payload.asStr() ![]const u8   // 只接受 .str 类型
 payload.asBin() ![]u8         // 只接受 .bin 类型
 
 // 类型检查
 payload.isNil() bool       // 检查是否为 nil
 payload.isNumber() bool    // 检查是否为数字（int/uint/float）
 payload.isInteger() bool   // 检查是否为整数（int/uint）
```

### 3.3 序列化/反序列化

#### 创建 Pack 实例
```zig
const pack = msgpack.Pack(
    *BufferStream,          // WriteContext 类型
    *BufferStream,          // ReadContext 类型
    BufferStream.WriteError,
    BufferStream.ReadError,
    BufferStream.write,     // writeFn
    BufferStream.read,      // readFn
);

var p = pack.init(&write_buffer, &read_buffer);
```

#### 基本操作
```zig
try p.write(payload);                    // 序列化
const result = try p.read(allocator);   // 反序列化
defer result.free(allocator);           // 释放内存
```

---

## 4. 编码规范

### 4.1 最小编码原则

序列化器**必须**使用最小格式：

| 值范围 | 格式选择 |
|--------|---------|
| 0-127 | positive fixint (1 byte) |
| -32 to -1 | negative fixint (1 byte) |
| 128-255 | uint8 (2 bytes) |
| 字符串 0-31 字节 | fixstr |
| 数组 0-15 元素 | fixarray |
| Map 0-15 条目 | fixmap |

### 4.2 Timestamp 格式选择

```zig
// timestamp 32: nanoseconds == 0 && seconds 在 [0, 2^32-1]
// 格式: fixext4 + type(-1) + 4 bytes seconds

// timestamp 64: seconds 在 [0, 2^34-1] && nanoseconds <= 999999999
// 格式: fixext8 + type(-1) + 8 bytes (nano<<34 | seconds)

// timestamp 96: 其他情况（负秒数或大秒数）
// 格式: ext8 + len(12) + type(-1) + 4 bytes nano + 8 bytes seconds
```

### 4.3 字节序

- **MessagePack 规范**：大端序（Big Endian）
- **实现方式**：`std.mem.writeInt(T, buffer, value, .big)`

---

## 5. 版本兼容性处理

### 5.1 支持的 Zig 版本

- ✅ **完全支持**：Zig 0.14.x, 0.15.x
- ⚠️ **部分支持**：Zig 0.16 (nightly)

### 5.2 关键差异点

#### Endianness 枚举
```zig
// Zig 0.14-0.15
std.builtin.Endian.big

// Zig 0.16+
std.builtin.Endian.Big  // 注意大小写变化
```

#### ArrayList API
```zig
// Zig 0.14
var list = ArrayList(T).init(allocator);
try list.append(item);
list.deinit();

// Zig 0.15+
var list = ArrayList(T){};  // 或 init(allocator)
try list.append(allocator, item);  // 需要传递 allocator
list.deinit(allocator);
```

#### BufferStream
```zig
// Zig 0.14-0.15
std.io.FixedBufferStream([]u8)
std.io.fixedBufferStream(buffer)

// Zig 0.16+
自定义 compat.BufferStream 实现
compat.fixedBufferStream(buffer)
```

### 5.3 版本检测模式

```zig
const current_zig = builtin.zig_version;

if (current_zig.minor >= 16) {
    // Zig 0.16+ 代码
} else if (current_zig.minor == 15) {
    // Zig 0.15 代码
} else {
    // Zig 0.14 代码
}
```

---

## 6. 内存管理规范

### 6.1 分配规则

#### 需要分配的类型
- `str`: 复制输入字符串
- `bin`: 复制输入二进制数据
- `ext`: 复制扩展数据
- `arr`: 分配 `[]Payload` 切片
- `map`: 分配 `StringHashMap` 和键字符串

#### 不需要分配的类型
- `nil`, `bool`, `int`, `uint`, `float`, `timestamp`

### 6.2 释放规则

```zig
// 单个 Payload
defer payload.free(allocator);

// 嵌套结构会递归释放
// 例如：Map 中的所有值，Array 中的所有元素
```

### 6.3 错误处理中的内存管理

```zig
const str_payload = try Payload.strToPayload(data, allocator);
errdefer str_payload.free(allocator);  // 后续失败时自动清理

try some_operation(str_payload);
```

---

## 7. 错误类型

 ### 7.1 MsgPackError 枚举

```zig
error {
     StrDataLengthTooLong,    // 字符串超过格式限制
     BinDataLengthTooLong,    // 二进制数据超长
     ArrayLengthTooLong,      // 数组超长
     MapLengthTooLong,        // Map 超长
     InputValueTooLarge,      // 输入值超出范围
     TypeMarkerReading,       // 类型标记读取错误
     DataReading,             // 数据读取错误
     LengthReading,           // 长度读取错误
     ExtTypeLength,           // 扩展类型长度不匹配
     InvalidType,             // 类型不匹配/无效
    // ... 其他错误
}
```

 ### 7.2 Payload.Error 枚举

```zig
error {
    NotMap,   // 不是 Map 类型
     NotArray, // 不是 Array 类型
}
```

---

## 8. 测试指南

### 8.1 运行测试

```bash
# 运行所有测试
zig build test

# 详细输出
zig build test --summary all
```

### 8.2 测试覆盖范围

- ✅ 所有 MessagePack 类型编码/解码
- ✅ 边界值测试（fixint, fixstr, fixarray, fixmap）
- ✅ 格式选择逻辑（8/16/32 位变体）
- ✅ Unicode 字符串处理
- ✅ 深度嵌套结构
- ✅ 错误条件和异常处理
- ✅ 内存泄漏验证（通过 testing.allocator）
- ✅ Timestamp 三种格式（32/64/96 位）

### 8.3 测试模式

```zig
test "描述性测试名称" {
    // 1. 准备缓冲区
    var arr: [size]u8 = std.mem.zeroes([size]u8);
    var write_buffer = fixedBufferStream(&arr);
    var read_buffer = fixedBufferStream(&arr);
    var p = pack.init(&write_buffer, &read_buffer);

    // 2. 写入数据
    try p.write(payload);

    // 3. 读取验证
    const result = try p.read(allocator);
    defer result.free(allocator);
    try expect(result.xxx == expected);
}
```

---

## 9. 开发最佳实践

### 9.1 添加新功能

1. **检查规范**：确认 MessagePack 规范要求
2. **更新类型**：修改 `Payload` 或添加新类型
3. **实现编码**：在 `Pack` 中添加 `writeXxx()` 方法
4. **实现解码**：在 `Pack` 中添加 `readXxx()` 方法
5. **添加测试**：在 `test.zig` 中覆盖所有情况
6. **版本兼容**：检查是否需要 `compat.zig` 支持

### 9.2 修复 Bug

1. **添加失败测试**：先写能重现问题的测试
2. **定位问题**：检查编码/解码/内存管理
3. **修复代码**：最小化改动范围
4. **验证测试**：确保新旧测试都通过
5. **检查内存**：运行 `zig build test` 确认无泄漏

### 9.3 代码审查检查项

- [ ] 是否遵循最小编码原则？
- [ ] 是否正确处理大端序？
- [ ] 是否正确管理内存（free/errdefer）？
- [ ] 是否添加了测试用例？
- [ ] 是否兼容 Zig 0.14-0.15？
- [ ] 是否更新了相关文档？
- [ ] 是否使用了适当的 inline 提示？
- [ ] 是否避免了代码重复？

---

## 10. 常见操作模式

### 10.1 创建复杂嵌套结构

```zig
// 创建：{"name": "Alice", "scores": [95, 87, 92]}
var root = Payload.mapPayload(allocator);
defer root.free(allocator);

try root.mapPut("name", try Payload.strToPayload("Alice", allocator));

var scores = try Payload.arrPayload(3, allocator);
try scores.setArrElement(0, Payload.uintToPayload(95));
try scores.setArrElement(1, Payload.uintToPayload(87));
try scores.setArrElement(2, Payload.uintToPayload(92));

try root.mapPut("scores", scores);
```

### 10.2 安全的类型转换

```zig
// 获取可能是 int 或 uint 的值
const value = try payload.getInt();  // 如果是 uint 且 <= i64::MAX，会自动转换

// 获取 uint（拒绝负数）
const positive_value = try payload.getUint();  // 负数 int 会返回 INVALID_TYPE
```

### 10.3 遍历 Map

```zig
var iterator = payload.map.iterator();
while (iterator.next()) |entry| {
    const key: []const u8 = entry.key_ptr.*;
    const value: Payload = entry.value_ptr.*;
    // 处理键值对
}
```

---

## 11. 性能考虑

### 11.1 序列化优化

- 使用 `fixedBufferStream` 避免动态分配
- 预分配足够大的缓冲区
- 批量写入时重用 Pack 实例

### 11.2 反序列化优化

- 使用 Arena Allocator 批量释放
- 避免不必要的深拷贝
- 考虑使用 `std.testing.allocator` 检测泄漏

---

## 12. 调试技巧

### 12.1 查看序列化字节

```zig
var arr: [1000]u8 = std.mem.zeroes([1000]u8);
// ... 写入数据 ...
std.debug.print("Bytes: {x}\n", .{arr[0..10]});  // 打印前 10 字节（十六进制）
```

### 12.2 验证格式标记

```zig
try expect(arr[0] == 0xc0);  // 检查是否为 NIL 标记
try expect(arr[0] == 0xd6);  // 检查是否为 FIXEXT4
```

---

## 13. LLM 协助规范

### 13.1 理解代码时

1. 先阅读本文档第 1-2 节，了解整体架构
2. 查看 `Payload` 定义，理解类型系统
3. 查看 `Pack` 泛型实现，理解序列化流程
4. 参考 `test.zig` 了解使用模式

### 13.2 回答问题时

1. 引用具体的类型/函数名称
2. 提供可运行的代码示例
3. 说明内存管理需求（是否需要 free）
4. 标注 Zig 版本兼容性（如果相关）

### 13.3 建议修改时

1. 提供完整的上下文（patch 格式）
2. 说明修改原因和影响范围
3. 包含测试用例建议
4. 提醒版本兼容性检查

---

## 14. 快速参考

### 14.1 文件定位

| 需求 | 文件位置 |
|------|---------|
| 修改核心逻辑 | `src/msgpack.zig` |
| 添加测试 | `src/test.zig` |
| 修复版本兼容 | `src/compat.zig` |
| 更新构建配置 | `build.zig` |

### 14.2 常用常量

```zig
MAX_POSITIVE_FIXINT: u8 = 0x7f      // 127
MIN_NEGATIVE_FIXINT: i8 = -32
MAX_FIXSTR_LEN: u8 = 31
MAX_FIXARRAY_LEN: u8 = 15
MAX_FIXMAP_LEN: u8 = 15
TIMESTAMP_EXT_TYPE: i8 = -1
```

### 14.3 格式标记快查

| 类型 | 标记值 | 说明 |
|------|-------|------|
| NIL | 0xc0 | 空值 |
| TRUE | 0xc3 | 真 |
| FALSE | 0xc2 | 假 |
| UINT8 | 0xcc | 8 位无符号整数 |
| INT8 | 0xd0 | 8 位有符号整数 |
| FLOAT32 | 0xca | 32 位浮点 |
| FLOAT64 | 0xcb | 64 位浮点 |
| STR8 | 0xd9 | 8 位长度字符串 |
| BIN8 | 0xc4 | 8 位长度二进制 |
| ARRAY16 | 0xdc | 16 位长度数组 |
| MAP16 | 0xde | 16 位长度 Map |
| FIXEXT4 | 0xd6 | 4 字节扩展 |
| FIXEXT8 | 0xd7 | 8 字节扩展 |
| EXT8 | 0xc7 | 8 位长度扩展 |

---

## 15. 更新日志追踪

修改代码时，请在此记录重要变更：

### 格式
```
[日期] [修改类型] 简要描述
- 详细说明 1
- 详细说明 2
```

### 示例
```
[2025-10-03] [Feature] 添加 Timestamp 支持
- 实现三种 timestamp 格式（32/64/96 位）
- 添加 Timestamp.toFloat() 转换方法
- 完整测试覆盖所有边界情况

[2025-10-18] [Optimization] 高优先级性能优化
- markerU8To 改用 switch 表达式（+10-20% 解析性能）
- 整数读写泛型化（减少150行重复代码）
- 添加 inline 提示到25+个热点函数（+5-15% 性能）

[2025-10-18] [Refactor] 中优先级代码重构
- 常量重组为语义化结构体（FixLimits, IntBounds 等）
- 拆分 readExtValueOrTimestamp 为多个小函数
- 统一数据写入逻辑（writeDataWithLength）
- 添加严格类型转换 API（asInt, asUint, asFloat 等）
- 添加类型检查方法（isNil, isNumber, isInteger）
```

---

## 16. 附录

### 16.1 相关链接

- MessagePack 官方规范: https://msgpack.org/
- Zig 语言文档: https://ziglang.org/documentation/master/
- 项目仓库: [填写实际 URL]

### 16.2 术语表

| 术语 | 英文 | 说明 |
|------|------|------|
| 载荷 | Payload | 核心数据容器类型 |
| 序列化 | Serialization | 将数据转为字节流 |
| 反序列化 | Deserialization | 将字节流转为数据 |
| 大端序 | Big Endian | 高位字节在前的存储方式 |
| 固定格式 | Fix Format | 单字节编码的紧凑格式 |
| 扩展类型 | Extension Type | 用户自定义类型（-128 到 127） |

---

**文档版本**: 1.0  
**最后更新**: 2025-10-03  
**维护者**: AI Assistant
