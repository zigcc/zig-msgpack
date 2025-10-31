//! MessagePack implementation with zig
//! https://msgpack.org/

const std = @import("std");
const builtin = @import("builtin");

const current_zig = builtin.zig_version;
const Allocator = std.mem.Allocator;
const comptimePrint = std.fmt.comptimePrint;
const native_endian = builtin.cpu.arch.endian();

const big_endian = std.builtin.Endian.big;
const little_endian = std.builtin.Endian.little;

/// MessagePack format limits for fix types
pub const FixLimits = struct {
    pub const POSITIVE_INT_MAX: u8 = 0x7f;
    pub const NEGATIVE_INT_MIN: i8 = -32;
    pub const STR_LEN_MAX: u8 = 31;
    pub const ARRAY_LEN_MAX: u8 = 15;
    pub const MAP_LEN_MAX: u8 = 15;
};

/// Integer type boundaries
pub const IntBounds = struct {
    pub const UINT8_MAX: u64 = 0xff;
    pub const UINT16_MAX: u64 = 0xffff;
    pub const UINT32_MAX: u64 = 0xffff_ffff;
    pub const INT8_MIN: i64 = -128;
    pub const INT16_MIN: i64 = -32768;
    pub const INT32_MIN: i64 = -2147483648;
};

/// Fixed extension type data lengths
pub const FixExtLen = struct {
    pub const EXT1: usize = 1;
    pub const EXT2: usize = 2;
    pub const EXT4: usize = 4;
    pub const EXT8: usize = 8;
    pub const EXT16: usize = 16;
};

/// Timestamp extension type constants
pub const TimestampExt = struct {
    pub const TYPE_ID: i8 = -1;
    pub const FORMAT32_LEN: usize = 4;
    pub const FORMAT64_LEN: usize = 8;
    pub const FORMAT96_LEN: usize = 12;
    pub const SECONDS_BITS_64: u6 = 34;
    pub const SECONDS_MASK_64: u64 = 0x3ffffffff;
    pub const NANOSECONDS_MAX: u32 = 999_999_999;
    pub const NANOSECONDS_PER_SECOND: f64 = 1_000_000_000.0;
};

/// Marker byte base values and masks
pub const MarkerBase = struct {
    pub const FIXARRAY: u8 = 0x90;
    pub const FIXMAP: u8 = 0x80;
    pub const FIXSTR: u8 = 0xa0;
    pub const FIXSTR_LEN_MASK: u8 = 0x1f;
    pub const FIXSTR_TYPE_MASK: u8 = 0xe0;
};

// Backward compatibility aliases (will be deprecated)
const MAX_POSITIVE_FIXINT: u8 = FixLimits.POSITIVE_INT_MAX;
const MIN_NEGATIVE_FIXINT: i8 = FixLimits.NEGATIVE_INT_MIN;
const MAX_FIXSTR_LEN: u8 = FixLimits.STR_LEN_MAX;
const MAX_FIXARRAY_LEN: u8 = FixLimits.ARRAY_LEN_MAX;
const MAX_FIXMAP_LEN: u8 = FixLimits.MAP_LEN_MAX;
const TIMESTAMP_EXT_TYPE: i8 = TimestampExt.TYPE_ID;
const MAX_UINT8: u64 = IntBounds.UINT8_MAX;
const MAX_UINT16: u64 = IntBounds.UINT16_MAX;
const MAX_UINT32: u64 = IntBounds.UINT32_MAX;
const MIN_INT8: i64 = IntBounds.INT8_MIN;
const MIN_INT16: i64 = IntBounds.INT16_MIN;
const MIN_INT32: i64 = IntBounds.INT32_MIN;
const FIXEXT1_LEN: usize = FixExtLen.EXT1;
const FIXEXT2_LEN: usize = FixExtLen.EXT2;
const FIXEXT4_LEN: usize = FixExtLen.EXT4;
const FIXEXT8_LEN: usize = FixExtLen.EXT8;
const FIXEXT16_LEN: usize = FixExtLen.EXT16;
const TIMESTAMP32_DATA_LEN: usize = TimestampExt.FORMAT32_LEN;
const TIMESTAMP64_DATA_LEN: usize = TimestampExt.FORMAT64_LEN;
const TIMESTAMP96_DATA_LEN: usize = TimestampExt.FORMAT96_LEN;
const TIMESTAMP64_SECONDS_BITS: u6 = TimestampExt.SECONDS_BITS_64;
const TIMESTAMP64_SECONDS_MASK: u64 = TimestampExt.SECONDS_MASK_64;
const MAX_NANOSECONDS: u32 = TimestampExt.NANOSECONDS_MAX;
const NANOSECONDS_PER_SECOND: f64 = TimestampExt.NANOSECONDS_PER_SECOND;
const FIXARRAY_BASE: u8 = MarkerBase.FIXARRAY;
const FIXMAP_BASE: u8 = MarkerBase.FIXMAP;
const FIXSTR_BASE: u8 = MarkerBase.FIXSTR;
const FIXSTR_MASK: u8 = MarkerBase.FIXSTR_LEN_MASK;
const FIXSTR_TYPE_MASK: u8 = MarkerBase.FIXSTR_TYPE_MASK;

/// Parse safety limits configuration
pub const ParseLimits = struct {
    /// Maximum nesting depth (default 1000 layers)
    max_depth: usize = 1000,

    /// Maximum array length (default 1 million elements)
    max_array_length: usize = 1_000_000,

    /// Maximum map size (default 1 million key-value pairs)
    max_map_size: usize = 1_000_000,

    /// Maximum string data length (default 100MB)
    max_string_length: usize = 100 * 1024 * 1024,

    /// Maximum binary data length (default 100MB)
    max_bin_length: usize = 100 * 1024 * 1024,

    /// Maximum extension data length (default 100MB)
    max_ext_length: usize = 100 * 1024 * 1024,
};

/// Default parse limits
pub const DEFAULT_LIMITS = ParseLimits{};

/// the Str Type
pub const Str = struct {
    str: []const u8,

    /// Initialize a new Str instance
    pub inline fn init(str: []const u8) Str {
        return Str{ .str = str };
    }

    /// get Str values
    pub fn value(self: Str) []const u8 {
        return self.str;
    }
};

/// this is for encode str in struct
pub inline fn wrapStr(str: []const u8) Str {
    return Str.init(str);
}

/// the Bin Type
pub const Bin = struct {
    bin: []u8,

    /// Initialize a new Bin instance
    pub inline fn init(bin: []u8) Bin {
        return Bin{ .bin = bin };
    }

    /// get bin values
    pub fn value(self: Bin) []u8 {
        return self.bin;
    }
};

/// this is wrapping for bin
pub inline fn wrapBin(bin: []u8) Bin {
    return Bin.init(bin);
}

/// the EXT Type
pub const EXT = struct {
    type: i8,
    data: []u8,

    /// Initialize a new EXT instance
    pub inline fn init(t: i8, data: []u8) EXT {
        return EXT{
            .type = t,
            .data = data,
        };
    }
};

/// t is type, data is data
pub inline fn wrapEXT(t: i8, data: []u8) EXT {
    return EXT.init(t, data);
}

/// the Timestamp Type
/// Represents an instantaneous point on the time-line in the world
/// that is independent from time zones or calendars.
/// Maximum precision is nanoseconds.
pub const Timestamp = struct {
    /// seconds since 1970-01-01 00:00:00 UTC
    seconds: i64,
    /// nanoseconds (0-999999999)
    nanoseconds: u32,

    /// Create a new timestamp
    pub inline fn new(seconds: i64, nanoseconds: u32) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanoseconds = nanoseconds,
        };
    }

    /// Create timestamp from seconds only (nanoseconds = 0)
    pub inline fn fromSeconds(seconds: i64) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanoseconds = 0,
        };
    }

    /// Get current timestamp (now)
    pub fn now() Timestamp {
        const ns = std.time.nanoTimestamp();
        const ns_i64: i64 = @intCast(@divFloor(ns, std.time.ns_per_s));
        const nano_remainder: i64 = @intCast(@mod(ns, std.time.ns_per_s));
        const nanoseconds: u32 = @intCast(if (nano_remainder < 0) nano_remainder + std.time.ns_per_s else nano_remainder);
        return Timestamp{
            .seconds = if (nano_remainder < 0) ns_i64 - 1 else ns_i64,
            .nanoseconds = nanoseconds,
        };
    }

    /// Get total seconds as f64 (including fractional nanoseconds)
    pub fn toFloat(self: Timestamp) f64 {
        return @as(f64, @floatFromInt(self.seconds)) + @as(f64, @floatFromInt(self.nanoseconds)) / NANOSECONDS_PER_SECOND;
    }
};

/// the map of payload
pub const Map = std.StringHashMap(Payload);

/// Entity to store msgpack
///
/// Note: The payload and its subvalues must have the same allocator
pub const Payload = union(enum) {
    /// the error for Payload
    pub const Error = error{
        NotMap,
        NotArray,
    };

    nil: void,
    bool: bool,
    int: i64,
    uint: u64,
    float: f64,
    str: Str,
    bin: Bin,
    arr: []Payload,
    map: Map,
    ext: EXT,
    timestamp: Timestamp,

    /// get array element
    pub fn getArrElement(self: Payload, index: usize) !Payload {
        if (self != .arr) {
            return Error.NotArray;
        }
        return self.arr[index];
    }

    /// get array length
    pub fn getArrLen(self: Payload) !usize {
        if (self != .arr) {
            return Error.NotArray;
        }
        return self.arr.len;
    }

    /// get map's element
    pub fn mapGet(self: Payload, key: []const u8) !?Payload {
        if (self != .map) {
            return Error.NotMap;
        }
        return self.map.get(key);
    }

    /// set array element
    pub fn setArrElement(self: *Payload, index: usize, val: Payload) !void {
        if (self.* != .arr) {
            return Error.NotArray;
        }
        self.arr[index] = val;
    }

    /// put a new element to map payload
    pub fn mapPut(self: *Payload, key: []const u8, val: Payload) !void {
        if (self.* != .map) {
            return Error.NotMap;
        }

        // Optimization: Use getOrPut to reduce from two hash lookups to one
        const entry = try self.map.getOrPut(key);
        if (!entry.found_existing) {
            // New key: allocate and copy
            const new_key = try self.map.allocator.alloc(u8, key.len);
            errdefer self.map.allocator.free(new_key);
            @memcpy(new_key, key);
            entry.key_ptr.* = new_key;
        }
        entry.value_ptr.* = val;
    }

    /// get a NIL payload
    pub inline fn nilToPayload() Payload {
        return Payload{
            .nil = void{},
        };
    }

    /// get a bool payload
    pub inline fn boolToPayload(val: bool) Payload {
        return Payload{
            .bool = val,
        };
    }

    /// get a int payload
    pub inline fn intToPayload(val: i64) Payload {
        return Payload{
            .int = val,
        };
    }

    /// get a uint payload
    pub inline fn uintToPayload(val: u64) Payload {
        return Payload{
            .uint = val,
        };
    }

    /// get a float payload
    pub inline fn floatToPayload(val: f64) Payload {
        return Payload{
            .float = val,
        };
    }

    /// get a str payload
    pub fn strToPayload(val: []const u8, allocator: Allocator) !Payload {
        // allocate memory
        const new_str = try allocator.alloc(u8, val.len);
        // copy the value
        @memcpy(new_str, val);
        return Payload{
            .str = Str.init(new_str),
        };
    }

    /// get a bin payload
    pub fn binToPayload(val: []const u8, allocator: Allocator) !Payload {
        // allocate memory
        const new_bin = try allocator.alloc(u8, val.len);
        // copy the value
        @memcpy(new_bin, val);
        return Payload{
            .bin = Bin.init(new_bin),
        };
    }

    /// get an array payload
    pub fn arrPayload(len: usize, allocator: Allocator) !Payload {
        const arr = try allocator.alloc(Payload, len);
        // Initialize with nil to ensure safe memory state for free()
        // Note: While this adds overhead, it prevents undefined behavior
        // when arrays are partially filled or freed before full initialization

        // Optimization: Use pointer arithmetic for faster initialization
        // This is significantly faster than a loop for large arrays
        const nil_payload = Payload.nilToPayload();
        for (arr) |*item| {
            item.* = nil_payload;
        }
        return Payload{
            .arr = arr,
        };
    }

    /// get a map payload
    pub fn mapPayload(allocator: Allocator) Payload {
        return Payload{
            .map = Map.init(allocator),
        };
    }

    /// get an ext payload
    pub fn extToPayload(t: i8, data: []const u8, allocator: Allocator) !Payload {
        // allocate memory
        const new_data = try allocator.alloc(u8, data.len);
        // copy the value
        @memcpy(new_data, data);
        return Payload{
            .ext = EXT.init(t, new_data),
        };
    }

    /// get a timestamp payload
    pub inline fn timestampToPayload(seconds: i64, nanoseconds: u32) Payload {
        return Payload{
            .timestamp = Timestamp.new(seconds, nanoseconds),
        };
    }

    /// get a timestamp payload from seconds only
    pub inline fn timestampFromSeconds(seconds: i64) Payload {
        return Payload{
            .timestamp = Timestamp.fromSeconds(seconds),
        };
    }

    /// free all memory for this payload and sub payloads
    /// the allocator is payload's allocator
    /// This is an iterative implementation that avoids stack overflow from deep nesting
    pub fn free(self: Payload, allocator: Allocator) void {
        // Use explicit stack for iterative freeing
        var stack = if (current_zig.minor == 14)
            std.ArrayList(Payload).init(allocator)
        else
            std.ArrayList(Payload){};
        defer if (current_zig.minor == 14) stack.deinit() else stack.deinit(allocator);

        // Start with self
        if (current_zig.minor == 14) {
            stack.append(self) catch return;
        } else {
            stack.append(allocator, self) catch return;
        }

        while (stack.items.len > 0) {
            const payload_item = stack.pop() orelse break;

            switch (payload_item) {
                .str => |s| allocator.free(s.value()),
                .bin => |b| allocator.free(b.value()),
                .ext => |e| allocator.free(e.data),

                .arr => |arr| {
                    defer allocator.free(arr);
                    // Push children to stack in reverse order
                    var i = arr.len;
                    while (i > 0) {
                        i -= 1;
                        if (current_zig.minor == 14) {
                            stack.append(arr[i]) catch {};
                        } else {
                            stack.append(allocator, arr[i]) catch {};
                        }
                    }
                },

                .map => |map| {
                    var map_copy = map;
                    defer map_copy.deinit();
                    var iter = map_copy.iterator();
                    while (iter.next()) |entry| {
                        defer allocator.free(entry.key_ptr.*);
                        // Push value to stack
                        if (current_zig.minor == 14) {
                            stack.append(entry.value_ptr.*) catch {};
                        } else {
                            stack.append(allocator, entry.value_ptr.*) catch {};
                        }
                    }
                },

                else => {}, // nil, bool, int, uint, float, timestamp - no memory to free
            }
        }
    }

    /// get an i64 value from payload
    /// Tries to get i64 value, converting uint if it fits within i64 range.
    /// This is a lenient conversion method.
    pub fn getInt(self: Payload) !i64 {
        return switch (self) {
            .int => |val| val,
            .uint => |val| {
                if (val <= std.math.maxInt(i64)) {
                    return @intCast(val);
                }
                // Value exceeds i64 range
                return MsgPackError.InvalidType;
            },
            else => return MsgPackError.InvalidType,
        };
    }

    /// get an u64 value from payload
    /// Tries to get u64 value, converting positive int if possible.
    /// This is a lenient conversion method.
    pub fn getUint(self: Payload) !u64 {
        return switch (self) {
            .int => |val| {
                if (val >= 0) {
                    return @intCast(val);
                }
                // Negative values cannot be converted to u64
                return MsgPackError.InvalidType;
            },
            .uint => |val| val,
            else => return MsgPackError.InvalidType,
        };
    }

    /// Get i64 value without type conversion (strict mode).
    /// Returns error if payload is not exactly an int type.
    pub fn asInt(self: Payload) !i64 {
        return switch (self) {
            .int => |val| val,
            else => MsgPackError.InvalidType,
        };
    }

    /// Get u64 value without type conversion (strict mode).
    /// Returns error if payload is not exactly a uint type.
    pub fn asUint(self: Payload) !u64 {
        return switch (self) {
            .uint => |val| val,
            else => MsgPackError.InvalidType,
        };
    }

    /// Get f64 value without type conversion.
    pub fn asFloat(self: Payload) !f64 {
        return switch (self) {
            .float => |val| val,
            else => MsgPackError.InvalidType,
        };
    }

    /// Get bool value.
    pub fn asBool(self: Payload) !bool {
        return switch (self) {
            .bool => |val| val,
            else => MsgPackError.InvalidType,
        };
    }

    /// Get string slice. The string data is owned by the Payload.
    pub fn asStr(self: Payload) ![]const u8 {
        return switch (self) {
            .str => |s| s.value(),
            else => MsgPackError.InvalidType,
        };
    }

    /// Get binary data slice. The data is owned by the Payload.
    pub fn asBin(self: Payload) ![]u8 {
        return switch (self) {
            .bin => |b| b.value(),
            else => MsgPackError.InvalidType,
        };
    }

    /// Check if payload is nil.
    pub inline fn isNil(self: Payload) bool {
        return self == .nil;
    }

    /// Check if payload is a number (int, uint, or float).
    pub inline fn isNumber(self: Payload) bool {
        return switch (self) {
            .int, .uint, .float => true,
            else => false,
        };
    }

    /// Check if payload is an integer (int or uint).
    pub inline fn isInteger(self: Payload) bool {
        return switch (self) {
            .int, .uint => true,
            else => false,
        };
    }
};

/// markers
const Markers = enum(u8) {
    POSITIVE_FIXINT = 0x00,
    FIXMAP = 0x80,
    FIXARRAY = 0x90,
    FIXSTR = 0xa0,
    NIL = 0xc0,
    FALSE = 0xc2,
    TRUE = 0xc3,
    BIN8 = 0xc4,
    BIN16 = 0xc5,
    BIN32 = 0xc6,
    EXT8 = 0xc7,
    EXT16 = 0xc8,
    EXT32 = 0xc9,
    FLOAT32 = 0xca,
    FLOAT64 = 0xcb,
    UINT8 = 0xcc,
    UINT16 = 0xcd,
    UINT32 = 0xce,
    UINT64 = 0xcf,
    INT8 = 0xd0,
    INT16 = 0xd1,
    INT32 = 0xd2,
    INT64 = 0xd3,
    FIXEXT1 = 0xd4,
    FIXEXT2 = 0xd5,
    FIXEXT4 = 0xd6,
    FIXEXT8 = 0xd7,
    FIXEXT16 = 0xd8,
    STR8 = 0xd9,
    STR16 = 0xda,
    STR32 = 0xdb,
    ARRAY16 = 0xdc,
    ARRAY32 = 0xdd,
    MAP16 = 0xde,
    MAP32 = 0xdf,
    NEGATIVE_FIXINT = 0xe0,
};

/// A collection of errors that may occur when reading the payload
pub const MsgPackError = error{
    StrDataLengthTooLong,
    BinDataLengthTooLong,
    ArrayLengthTooLong,
    TupleLengthTooLong,
    MapLengthTooLong,
    InputValueTooLarge,
    FixedValueWriting,
    TypeMarkerReading,
    TypeMarkerWriting,
    DataReading,
    DataWriting,
    ExtTypeReading,
    ExtTypeWriting,
    ExtTypeLength,
    InvalidType,
    LengthReading,
    LengthWriting,
    Internal,

    // New safety errors for iterative parser
    MaxDepthExceeded, // Nesting depth exceeded limit
    ArrayTooLarge, // Array has too many elements
    MapTooLarge, // Map has too many key-value pairs
    StringTooLong, // String exceeds length limit
    ExtDataTooLarge, // Extension data exceeds length limit
};

/// Create an instance of msgpack_pack with custom limits
pub fn PackWithLimits(
    comptime WriteContext: type,
    comptime ReadContext: type,
    comptime WriteError: type,
    comptime ReadError: type,
    comptime writeFn: fn (context: WriteContext, bytes: []const u8) WriteError!usize,
    comptime readFn: fn (context: ReadContext, arr: []u8) ReadError!usize,
    comptime limits: ParseLimits,
) type {
    return struct {
        write_context: WriteContext,
        read_context: ReadContext,

        const Self = @This();
        const parse_limits = limits;

        /// init
        pub fn init(writeContext: WriteContext, readContext: ReadContext) Self {
            return Self{
                .write_context = writeContext,
                .read_context = readContext,
            };
        }

        /// wrap for writeFn
        fn writeTo(self: Self, bytes: []const u8) !usize {
            return writeFn(self.write_context, bytes);
        }

        /// write one byte
        inline fn writeByte(self: Self, byte: u8) !void {
            const bytes = [_]u8{byte};
            const len = try self.writeTo(&bytes);
            if (len != 1) {
                return MsgPackError.LengthWriting;
            }
        }

        /// write data
        inline fn writeData(self: Self, data: []const u8) !void {
            const len = try self.writeTo(data);
            if (len != data.len) {
                return MsgPackError.LengthWriting;
            }
        }

        /// Generic integer write helper
        inline fn writeIntRaw(self: Self, comptime T: type, val: T) !void {
            var arr: [@sizeOf(T)]u8 = undefined;
            std.mem.writeInt(T, &arr, val, big_endian);
            try self.writeData(&arr);
        }

        /// Generic data write with length prefix
        inline fn writeDataWithLength(self: Self, comptime LenType: type, data: []const u8) !void {
            try self.writeIntRaw(LenType, @intCast(data.len));
            try self.writeData(data);
        }

        /// Generic integer value write (without marker)
        inline fn writeIntValue(self: Self, comptime T: type, val: T) !void {
            if (T == u8 or T == i8) {
                try self.writeByte(@bitCast(val));
            } else {
                try self.writeIntRaw(T, val);
            }
        }

        /// Generic integer write with marker
        inline fn writeIntWithMarker(self: Self, comptime T: type, marker: Markers, val: T) !void {
            try self.writeTypeMarker(marker);
            try self.writeIntValue(T, val);
        }

        /// write type marker
        inline fn writeTypeMarker(self: Self, comptime marker: Markers) !void {
            switch (marker) {
                .POSITIVE_FIXINT, .FIXMAP, .FIXARRAY, .FIXSTR, .NEGATIVE_FIXINT => {
                    const err_msg = comptimePrint("marker ({}) is wrong, the can not be write directly!", .{marker});
                    @compileError(err_msg);
                },
                else => {},
            }
            try self.writeByte(@intFromEnum(marker));
        }

        /// write nil
        fn writeNil(self: Self) !void {
            try self.writeTypeMarker(Markers.NIL);
        }

        /// write bool
        fn writeBool(self: Self, val: bool) !void {
            if (val) {
                try self.writeTypeMarker(Markers.TRUE);
            } else {
                try self.writeTypeMarker(Markers.FALSE);
            }
        }

        /// write positive fix int
        inline fn writePfixInt(self: Self, val: u8) !void {
            if (val <= MAX_POSITIVE_FIXINT) {
                try self.writeByte(val);
            } else {
                return MsgPackError.InputValueTooLarge;
            }
        }

        inline fn writeU8Value(self: Self, val: u8) !void {
            try self.writeIntValue(u8, val);
        }

        /// write u8 int
        fn writeU8(self: Self, val: u8) !void {
            try self.writeIntWithMarker(u8, .UINT8, val);
        }

        inline fn writeU16Value(self: Self, val: u16) !void {
            try self.writeIntValue(u16, val);
        }

        /// write u16 int
        fn writeU16(self: Self, val: u16) !void {
            try self.writeIntWithMarker(u16, .UINT16, val);
        }

        inline fn writeU32Value(self: Self, val: u32) !void {
            try self.writeIntValue(u32, val);
        }

        /// write u32 int
        fn writeU32(self: Self, val: u32) !void {
            try self.writeIntWithMarker(u32, .UINT32, val);
        }

        inline fn writeU64Value(self: Self, val: u64) !void {
            try self.writeIntValue(u64, val);
        }

        /// write u64 int
        fn writeU64(self: Self, val: u64) !void {
            try self.writeIntWithMarker(u64, .UINT64, val);
        }

        /// write negative fix int
        inline fn writeNfixInt(self: Self, val: i8) !void {
            if (val >= MIN_NEGATIVE_FIXINT and val <= -1) {
                try self.writeByte(@bitCast(val));
            } else {
                return MsgPackError.InputValueTooLarge;
            }
        }

        inline fn writeI8Value(self: Self, val: i8) !void {
            try self.writeIntValue(i8, val);
        }

        /// write i8 int
        fn writeI8(self: Self, val: i8) !void {
            try self.writeIntWithMarker(i8, .INT8, val);
        }

        inline fn writeI16Value(self: Self, val: i16) !void {
            try self.writeIntValue(i16, val);
        }

        /// write i16 int
        fn writeI16(self: Self, val: i16) !void {
            try self.writeIntWithMarker(i16, .INT16, val);
        }

        inline fn writeI32Value(self: Self, val: i32) !void {
            try self.writeIntValue(i32, val);
        }

        /// write i32 int
        fn writeI32(self: Self, val: i32) !void {
            try self.writeIntWithMarker(i32, .INT32, val);
        }

        inline fn writeI64Value(self: Self, val: i64) !void {
            try self.writeIntValue(i64, val);
        }

        /// write i64 int
        fn writeI64(self: Self, val: i64) !void {
            try self.writeIntWithMarker(i64, .INT64, val);
        }

        /// write uint
        fn writeUint(self: Self, val: u64) !void {
            if (val <= MAX_POSITIVE_FIXINT) {
                try self.writePfixInt(@intCast(val));
            } else if (val <= MAX_UINT8) {
                try self.writeU8(@intCast(val));
            } else if (val <= MAX_UINT16) {
                try self.writeU16(@intCast(val));
            } else if (val <= MAX_UINT32) {
                try self.writeU32(@intCast(val));
            } else {
                try self.writeU64(val);
            }
        }

        /// write int
        fn writeInt(self: Self, val: i64) !void {
            if (val >= 0) {
                try self.writeUint(@intCast(val));
            } else if (val >= MIN_NEGATIVE_FIXINT) {
                try self.writeNfixInt(@intCast(val));
            } else if (val >= MIN_INT8) {
                try self.writeI8(@intCast(val));
            } else if (val >= MIN_INT16) {
                try self.writeI16(@intCast(val));
            } else if (val >= MIN_INT32) {
                try self.writeI32(@intCast(val));
            } else {
                try self.writeI64(val);
            }
        }

        inline fn writeF32Value(self: Self, val: f32) !void {
            const int: u32 = @bitCast(val);
            var arr: [4]u8 = undefined;
            std.mem.writeInt(u32, &arr, int, big_endian);

            try self.writeData(&arr);
        }

        /// write f32
        fn writeF32(self: Self, val: f32) !void {
            try self.writeTypeMarker(.FLOAT32);
            try self.writeF32Value(val);
        }

        inline fn writeF64Value(self: Self, val: f64) !void {
            const int: u64 = @bitCast(val);
            var arr: [8]u8 = undefined;
            std.mem.writeInt(u64, &arr, int, big_endian);

            try self.writeData(&arr);
        }

        /// write f64
        fn writeF64(self: Self, val: f64) !void {
            try self.writeTypeMarker(.FLOAT64);
            try self.writeF64Value(val);
        }

        /// write float
        fn writeFloat(self: Self, val: f64) !void {
            const tmp_val = if (val < 0) 0 - val else val;
            const min_f32 = std.math.floatMin(f32);
            const max_f32 = std.math.floatMax(f32);

            if (tmp_val >= min_f32 and tmp_val <= max_f32) {
                try self.writeF32(@floatCast(val));
            } else {
                try self.writeF64(val);
            }
        }

        inline fn writeFixStrValue(self: Self, str: []const u8) !void {
            try self.writeData(str);
        }

        /// write fix str
        fn writeFixStr(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > MAX_FIXSTR_LEN) {
                return MsgPackError.StrDataLengthTooLong;
            }
            const header: u8 = @intFromEnum(Markers.FIXSTR) + @as(u8, @intCast(len));
            try self.writeByte(header);
            try self.writeFixStrValue(str);
        }

        inline fn writeStr8Value(self: Self, str: []const u8) !void {
            try self.writeDataWithLength(u8, str);
        }

        /// write str8
        fn writeStr8(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > MAX_UINT8) {
                return MsgPackError.StrDataLengthTooLong;
            }

            try self.writeTypeMarker(.STR8);
            try self.writeStr8Value(str);
        }

        inline fn writeStr16Value(self: Self, str: []const u8) !void {
            try self.writeDataWithLength(u16, str);
        }

        /// write str16
        fn writeStr16(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > MAX_UINT16) {
                return MsgPackError.StrDataLengthTooLong;
            }

            try self.writeTypeMarker(.STR16);

            try self.writeStr16Value(str);
        }

        inline fn writeStr32Value(self: Self, str: []const u8) !void {
            try self.writeDataWithLength(u32, str);
        }

        /// write str32
        fn writeStr32(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > MAX_UINT32) {
                return MsgPackError.StrDataLengthTooLong;
            }

            try self.writeTypeMarker(.STR32);
            try self.writeStr32Value(str);
        }

        /// write str
        fn writeStr(self: Self, str: Str) !void {
            const len = str.value().len;
            if (len <= MAX_FIXSTR_LEN) {
                try self.writeFixStr(str.value());
            } else if (len <= MAX_UINT8) {
                try self.writeStr8(str.value());
            } else if (len <= MAX_UINT16) {
                try self.writeStr16(str.value());
            } else {
                try self.writeStr32(str.value());
            }
        }

        /// write bin8
        fn writeBin8(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > MAX_UINT8) {
                return MsgPackError.BinDataLengthTooLong;
            }

            try self.writeTypeMarker(.BIN8);

            try self.writeStr8Value(bin);
        }

        /// write bin16
        fn writeBin16(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > MAX_UINT16) {
                return MsgPackError.BinDataLengthTooLong;
            }

            try self.writeTypeMarker(.BIN16);

            try self.writeStr16Value(bin);
        }

        /// write bin32
        fn writeBin32(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > MAX_UINT32) {
                return MsgPackError.BinDataLengthTooLong;
            }

            try self.writeTypeMarker(.BIN32);

            try self.writeStr32Value(bin);
        }

        /// write bin
        fn writeBin(self: Self, bin: Bin) !void {
            const len = bin.value().len;
            if (len <= MAX_UINT8) {
                try self.writeBin8(bin.value());
            } else if (len <= MAX_UINT16) {
                try self.writeBin16(bin.value());
            } else {
                try self.writeBin32(bin.value());
            }
        }

        inline fn writeExtValue(self: Self, ext: EXT) !void {
            try self.writeI8Value(ext.type);
            try self.writeData(ext.data);
        }

        fn writeFixExt1(self: Self, ext: EXT) !void {
            if (ext.data.len != FIXEXT1_LEN) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.FIXEXT1);

            try self.writeExtValue(ext);
        }

        fn writeFixExt2(self: Self, ext: EXT) !void {
            if (ext.data.len != FIXEXT2_LEN) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.FIXEXT2);
            try self.writeExtValue(ext);
        }

        fn writeFixExt4(self: Self, ext: EXT) !void {
            if (ext.data.len != FIXEXT4_LEN) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.FIXEXT4);
            try self.writeExtValue(ext);
        }

        fn writeFixExt8(self: Self, ext: EXT) !void {
            if (ext.data.len != FIXEXT8_LEN) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.FIXEXT8);
            try self.writeExtValue(ext);
        }

        fn writeFixExt16(self: Self, ext: EXT) !void {
            if (ext.data.len != FIXEXT16_LEN) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.FIXEXT16);
            try self.writeExtValue(ext);
        }

        fn writeExt8(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u8)) {
                return MsgPackError.ExtTypeLength;
            }

            try self.writeTypeMarker(.EXT8);
            try self.writeU8Value(@intCast(ext.data.len));
            try self.writeExtValue(ext);
        }

        fn writeExt16(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u16)) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.EXT16);
            try self.writeU16Value(@intCast(ext.data.len));
            try self.writeExtValue(ext);
        }

        fn writeExt32(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u32)) {
                return MsgPackError.ExtTypeLength;
            }
            try self.writeTypeMarker(.EXT32);
            try self.writeU32Value(@intCast(ext.data.len));
            try self.writeExtValue(ext);
        }

        fn writeExt(self: Self, ext: EXT) !void {
            const len = ext.data.len;
            if (len == FIXEXT1_LEN) {
                try self.writeFixExt1(ext);
            } else if (len == FIXEXT2_LEN) {
                try self.writeFixExt2(ext);
            } else if (len == FIXEXT4_LEN) {
                try self.writeFixExt4(ext);
            } else if (len == FIXEXT8_LEN) {
                try self.writeFixExt8(ext);
            } else if (len == FIXEXT16_LEN) {
                try self.writeFixExt16(ext);
            } else if (len <= std.math.maxInt(u8)) {
                try self.writeExt8(ext);
            } else if (len <= std.math.maxInt(u16)) {
                try self.writeExt16(ext);
            } else if (len <= std.math.maxInt(u32)) {
                try self.writeExt32(ext);
            } else {
                return MsgPackError.ExtTypeLength;
            }
        }

        /// write timestamp
        fn writeTimestamp(self: Self, timestamp: Timestamp) !void {
            // According to MessagePack spec, timestamp uses extension type -1

            // timestamp 32 format: seconds fit in 32-bit unsigned int and nanoseconds is 0
            if (timestamp.nanoseconds == 0 and timestamp.seconds >= 0 and timestamp.seconds <= MAX_UINT32) {
                var data: [TIMESTAMP32_DATA_LEN]u8 = undefined;
                std.mem.writeInt(u32, &data, @intCast(timestamp.seconds), big_endian);
                const ext = EXT{ .type = TIMESTAMP_EXT_TYPE, .data = &data };
                try self.writeExt(ext);
                return;
            }

            // timestamp 64 format: seconds fit in 34-bit and nanoseconds <= 999999999
            if (timestamp.seconds >= 0 and (timestamp.seconds >> TIMESTAMP64_SECONDS_BITS) == 0 and timestamp.nanoseconds <= MAX_NANOSECONDS) {
                const data64: u64 = (@as(u64, timestamp.nanoseconds) << TIMESTAMP64_SECONDS_BITS) | @as(u64, @intCast(timestamp.seconds));
                var data: [TIMESTAMP64_DATA_LEN]u8 = undefined;
                std.mem.writeInt(u64, &data, data64, big_endian);
                const ext = EXT{ .type = TIMESTAMP_EXT_TYPE, .data = &data };
                try self.writeExt(ext);
                return;
            }

            // timestamp 96 format: full range with signed 64-bit seconds and 32-bit nanoseconds
            if (timestamp.nanoseconds <= MAX_NANOSECONDS) {
                var data: [TIMESTAMP96_DATA_LEN]u8 = undefined;
                std.mem.writeInt(u32, data[0..4], timestamp.nanoseconds, big_endian);
                std.mem.writeInt(i64, data[4..12], timestamp.seconds, big_endian);
                const ext = EXT{ .type = TIMESTAMP_EXT_TYPE, .data = &data };
                try self.writeExt(ext);
                return;
            }

            return MsgPackError.InvalidType;
        }

        /// write payload
        pub fn write(self: Self, payload: Payload) !void {
            switch (payload) {
                .nil => {
                    try self.writeNil();
                },
                .bool => |val| {
                    try self.writeBool(val);
                },
                .int => |val| {
                    try self.writeInt(val);
                },
                .uint => |val| {
                    try self.writeUint(val);
                },
                .float => |val| {
                    try self.writeFloat(val);
                },
                .str => |val| {
                    try self.writeStr(val);
                },
                .bin => |val| {
                    try self.writeBin(val);
                },
                .arr => |arr| {
                    const len = arr.len;
                    if (len <= MAX_FIXARRAY_LEN) {
                        const header: u8 = @intFromEnum(Markers.FIXARRAY) + @as(u8, @intCast(len));
                        try self.writeU8Value(header);
                    } else if (len <= MAX_UINT16) {
                        try self.writeTypeMarker(.ARRAY16);
                        try self.writeU16Value(@as(u16, @intCast(len)));
                    } else if (len <= MAX_UINT32) {
                        try self.writeTypeMarker(.ARRAY32);
                        try self.writeU32Value(@as(u32, @intCast(len)));
                    } else {
                        return MsgPackError.ArrayLengthTooLong;
                    }
                    for (arr) |val| {
                        try self.write(val);
                    }
                },
                .map => |map| {
                    const len = map.count();
                    if (len <= MAX_FIXMAP_LEN) {
                        const header: u8 = @intFromEnum(Markers.FIXMAP) + @as(u8, @intCast(len));
                        try self.writeU8Value(header);
                    } else if (len <= MAX_UINT16) {
                        try self.writeTypeMarker(.MAP16);
                        try self.writeU16Value(@intCast(len));
                    } else if (len <= MAX_UINT32) {
                        try self.writeTypeMarker(.MAP32);
                        try self.writeU32Value(@intCast(len));
                    } else {
                        return MsgPackError.MapLengthTooLong;
                    }
                    var itera = map.iterator();
                    while (itera.next()) |entry| {
                        try self.writeStr(Str.init(entry.key_ptr.*));
                        try self.write(entry.value_ptr.*);
                    }
                },
                .ext => |ext| {
                    try self.writeExt(ext);
                },
                .timestamp => |timestamp| {
                    try self.writeTimestamp(timestamp);
                },
            }
        }

        fn readFrom(self: Self, bytes: []u8) !usize {
            return readFn(self.read_context, bytes);
        }

        inline fn readByte(self: Self) !u8 {
            var res = [1]u8{0};
            const len = try self.readFrom(&res);

            if (len != 1) {
                return MsgPackError.LengthReading;
            }

            return res[0];
        }

        inline fn readData(self: Self, allocator: Allocator, len: usize) ![]u8 {
            const data = try allocator.alloc(u8, len);
            errdefer allocator.free(data);
            const data_len = try self.readFrom(data);

            if (data_len != len) {
                return MsgPackError.LengthReading;
            }

            return data;
        }

        /// Generic integer read helper
        inline fn readIntRaw(self: Self, comptime T: type) !T {
            var buffer: [@sizeOf(T)]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != @sizeOf(T)) {
                return MsgPackError.LengthReading;
            }
            return std.mem.readInt(T, &buffer, big_endian);
        }

        /// Generic integer value read
        inline fn readTypedInt(self: Self, comptime T: type) !T {
            if (T == u8) {
                return self.readByte();
            } else if (T == i8) {
                const val = try self.readByte();
                return @bitCast(val);
            } else {
                return self.readIntRaw(T);
            }
        }

        fn readTypeMarkerU8(self: Self) !u8 {
            const val = try self.readByte();
            return val;
        }

        /// Precomputed lookup table for marker byte to Markers enum conversion
        /// This eliminates branch misprediction overhead from switch statements
        const MARKER_LOOKUP_TABLE: [256]Markers = blk: {
            var table: [256]Markers = undefined;
            var i: usize = 0;
            while (i < 256) : (i += 1) {
                const byte: u8 = @intCast(i);
                table[i] = switch (byte) {
                    0x00...0x7f => .POSITIVE_FIXINT,
                    0x80...0x8f => .FIXMAP,
                    0x90...0x9f => .FIXARRAY,
                    0xa0...0xbf => .FIXSTR,
                    0xc0 => .NIL,
                    0xc1 => .NIL, // Reserved byte, treat as NIL
                    0xc2 => .FALSE,
                    0xc3 => .TRUE,
                    0xc4 => .BIN8,
                    0xc5 => .BIN16,
                    0xc6 => .BIN32,
                    0xc7 => .EXT8,
                    0xc8 => .EXT16,
                    0xc9 => .EXT32,
                    0xca => .FLOAT32,
                    0xcb => .FLOAT64,
                    0xcc => .UINT8,
                    0xcd => .UINT16,
                    0xce => .UINT32,
                    0xcf => .UINT64,
                    0xd0 => .INT8,
                    0xd1 => .INT16,
                    0xd2 => .INT32,
                    0xd3 => .INT64,
                    0xd4 => .FIXEXT1,
                    0xd5 => .FIXEXT2,
                    0xd6 => .FIXEXT4,
                    0xd7 => .FIXEXT8,
                    0xd8 => .FIXEXT16,
                    0xd9 => .STR8,
                    0xda => .STR16,
                    0xdb => .STR32,
                    0xdc => .ARRAY16,
                    0xdd => .ARRAY32,
                    0xde => .MAP16,
                    0xdf => .MAP32,
                    0xe0...0xff => .NEGATIVE_FIXINT,
                };
            }
            break :blk table;
        };

        /// Fast marker type lookup using precomputed table (O(1) with no branches)
        inline fn markerU8To(_: Self, marker_u8: u8) Markers {
            return MARKER_LOOKUP_TABLE[marker_u8];
        }

        fn readTypeMarker(self: Self) !Markers {
            const val = try self.readTypeMarkerU8();
            return self.markerU8To(val);
        }

        inline fn readBoolValue(_: Self, marker: Markers) !bool {
            switch (marker) {
                .TRUE => return true,
                .FALSE => return false,
                else => return MsgPackError.TypeMarkerReading,
            }
        }

        fn readBool(self: Self) !bool {
            const marker = try self.readTypeMarker();
            return self.readBoolValue(marker);
        }

        inline fn readFixintValue(_: Self, marker_u8: u8) i8 {
            return @bitCast(marker_u8);
        }

        inline fn readI8Value(self: Self) !i8 {
            return self.readTypedInt(i8);
        }

        inline fn readV8Value(self: Self) !u8 {
            return self.readTypedInt(u8);
        }

        inline fn readI16Value(self: Self) !i16 {
            return self.readTypedInt(i16);
        }

        inline fn readU16Value(self: Self) !u16 {
            return self.readTypedInt(u16);
        }

        inline fn readI32Value(self: Self) !i32 {
            return self.readTypedInt(i32);
        }

        inline fn readU32Value(self: Self) !u32 {
            return self.readTypedInt(u32);
        }

        inline fn readI64Value(self: Self) !i64 {
            return self.readTypedInt(i64);
        }

        inline fn readU64Value(self: Self) !u64 {
            return self.readTypedInt(u64);
        }

        fn readIntValue(self: Self, marker_u8: u8) !i64 {
            const marker = self.markerU8To(marker_u8);
            // Optimized branch order: handle most common cases first
            // fixint and 8-bit integers are most common in typical data
            switch (marker) {
                .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val = self.readFixintValue(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.readI8Value();
                    return val;
                },
                .UINT8 => {
                    const val = try self.readV8Value();
                    return val;
                },
                .INT16 => {
                    const val = try self.readI16Value();
                    return val;
                },
                .UINT16 => {
                    const val = try self.readU16Value();
                    return val;
                },
                .INT32 => {
                    const val = try self.readI32Value();
                    return val;
                },
                .UINT32 => {
                    const val = try self.readU32Value();
                    return val;
                },
                .INT64 => {
                    return self.readI64Value();
                },
                .UINT64 => {
                    const val = try self.readU64Value();
                    if (val <= std.math.maxInt(i64)) {
                        return @intCast(val);
                    }
                    return MsgPackError.InvalidType;
                },
                else => return MsgPackError.TypeMarkerReading,
            }
        }

        fn readUintValue(self: Self, marker_u8: u8) !u64 {
            const marker = self.markerU8To(marker_u8);
            // Optimized branch order: handle most common cases first
            // fixint and 8-bit integers are most common in typical data
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.readV8Value();
                    return val;
                },
                .INT8 => {
                    const val = try self.readI8Value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsgPackError.InvalidType;
                },
                .UINT16 => {
                    const val = try self.readU16Value();
                    return val;
                },
                .INT16 => {
                    const val = try self.readI16Value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsgPackError.InvalidType;
                },
                .UINT32 => {
                    const val = try self.readU32Value();
                    return val;
                },
                .INT32 => {
                    const val = try self.readI32Value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsgPackError.InvalidType;
                },
                .UINT64 => {
                    return self.readU64Value();
                },
                .INT64 => {
                    const val = try self.readI64Value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsgPackError.InvalidType;
                },
                else => return MsgPackError.TypeMarkerReading,
            }
        }

        inline fn readF32Value(self: Self) !f32 {
            const val_int = try self.readIntRaw(u32);
            const val: f32 = @bitCast(val_int);
            return val;
        }

        inline fn readF64Value(self: Self) !f64 {
            const val_int = try self.readIntRaw(u64);
            const val: f64 = @bitCast(val_int);
            return val;
        }

        fn readFloatValue(self: Self, marker: Markers) !f64 {
            switch (marker) {
                .FLOAT32 => {
                    const val = try self.readF32Value();
                    return val;
                },
                .FLOAT64 => {
                    return self.readF64Value();
                },
                else => return MsgPackError.TypeMarkerReading,
            }
        }

        fn readFixStrValue(self: Self, allocator: Allocator, marker_u8: u8) ![]const u8 {
            const len: u8 = marker_u8 - @intFromEnum(Markers.FIXSTR);
            const str = try self.readData(allocator, len);

            return str;
        }

        fn readStr8Value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.readV8Value();
            const str = try self.readData(allocator, len);

            return str;
        }

        fn readStr16Value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.readU16Value();
            const str = try self.readData(allocator, len);

            return str;
        }

        fn readStr32Value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.readU32Value();
            const str = try self.readData(allocator, len);

            return str;
        }

        fn readStrValue(self: Self, marker_u8: u8, allocator: Allocator) ![]const u8 {
            const marker = self.markerU8To(marker_u8);

            switch (marker) {
                .FIXSTR => {
                    return self.readFixStrValue(allocator, marker_u8);
                },
                .STR8 => {
                    return self.readStr8Value(allocator);
                },
                .STR16 => {
                    return self.readStr16Value(allocator);
                },
                .STR32 => {
                    return self.readStr32Value(allocator);
                },
                else => return MsgPackError.TypeMarkerReading,
            }
        }

        inline fn validateBinLength(len: usize) !void {
            // Inline validation for hot path
            if (len > parse_limits.max_bin_length) {
                return MsgPackError.BinDataLengthTooLong;
            }
        }

        fn readBin8Value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.readV8Value();
            try validateBinLength(len);
            const bin = try self.readData(allocator, len);

            return bin;
        }

        fn readBin16Value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.readU16Value();
            try validateBinLength(len);
            const bin = try self.readData(allocator, len);

            return bin;
        }

        fn readBin32Value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.readU32Value();
            try validateBinLength(len);
            const bin = try self.readData(allocator, len);

            return bin;
        }

        fn readBinValue(self: Self, marker: Markers, allocator: Allocator) ![]u8 {
            switch (marker) {
                .BIN8 => {
                    return self.readBin8Value(allocator);
                },
                .BIN16 => {
                    return self.readBin16Value(allocator);
                },
                .BIN32 => {
                    return self.readBin32Value(allocator);
                },
                else => return MsgPackError.TypeMarkerReading,
            }
        }

        inline fn validateExtLength(len: usize) !void {
            // Inline validation for hot path
            if (len > parse_limits.max_ext_length) {
                return MsgPackError.ExtDataTooLarge;
            }
        }

        inline fn readExtData(self: Self, allocator: Allocator, len: usize) !EXT {
            try validateExtLength(len);
            const ext_type = try self.readI8Value();
            const data = try self.readData(allocator, len);
            return EXT{
                .type = ext_type,
                .data = data,
            };
        }

        /// Check if a marker can potentially be a timestamp
        inline fn isTimestampCandidate(marker: Markers) bool {
            return marker == .FIXEXT4 or marker == .FIXEXT8 or marker == .EXT8;
        }

        /// Read timestamp 32-bit format (seconds only, 0 nanoseconds)
        inline fn readTimestamp32(self: Self) !Timestamp {
            const seconds = try self.readU32Value();
            return Timestamp.new(@intCast(seconds), 0);
        }

        /// Read timestamp 64-bit format (34-bit seconds + 30-bit nanoseconds)
        inline fn readTimestamp64(self: Self) !Timestamp {
            const data64 = try self.readU64Value();
            const nanoseconds: u32 = @intCast(data64 >> TIMESTAMP64_SECONDS_BITS);
            const seconds: i64 = @intCast(data64 & TIMESTAMP64_SECONDS_MASK);
            return Timestamp.new(seconds, nanoseconds);
        }

        /// Read timestamp 96-bit format (32-bit nanoseconds + 64-bit seconds)
        inline fn readTimestamp96(self: Self) !Timestamp {
            const nanoseconds = try self.readU32Value();
            const seconds = try self.readI64Value();
            return Timestamp.new(seconds, nanoseconds);
        }

        /// Read non-timestamp EXT data
        inline fn readRegularExt(self: Self, ext_type: i8, len: usize, allocator: Allocator) !Payload {
            try validateExtLength(len);
            const ext_data = try allocator.alloc(u8, len);
            errdefer allocator.free(ext_data);
            _ = try self.readFrom(ext_data);
            return Payload{ .ext = EXT{ .type = ext_type, .data = ext_data } };
        }

        /// Get EXT data length from marker
        inline fn getExtLength(marker: Markers) usize {
            return switch (marker) {
                .FIXEXT1 => FIXEXT1_LEN,
                .FIXEXT2 => FIXEXT2_LEN,
                .FIXEXT4 => FIXEXT4_LEN,
                .FIXEXT8 => FIXEXT8_LEN,
                .FIXEXT16 => FIXEXT16_LEN,
                else => unreachable,
            };
        }

        /// Read and validate EXT8 length for timestamp detection
        fn readExt8Length(self: Self) !struct { len: usize, is_timestamp_candidate: bool } {
            const len = try self.readV8Value();
            // Only timestamp 96 format uses 12 bytes in EXT8
            if (len != TIMESTAMP96_DATA_LEN) {
                return .{ .len = len, .is_timestamp_candidate = false };
            }
            return .{ .len = len, .is_timestamp_candidate = true };
        }

        /// Read timestamp payload based on marker
        inline fn readTimestampPayload(self: Self, marker: Markers) !Payload {
            const required_len: usize = switch (marker) {
                .FIXEXT4 => FIXEXT4_LEN,
                .FIXEXT8 => FIXEXT8_LEN,
                .EXT8 => TIMESTAMP96_DATA_LEN,
                else => unreachable,
            };
            try validateExtLength(required_len);
            const timestamp: Timestamp = switch (marker) {
                .FIXEXT4 => try self.readTimestamp32(),
                .FIXEXT8 => try self.readTimestamp64(),
                .EXT8 => try self.readTimestamp96(),
                else => unreachable,
            };
            return Payload{ .timestamp = timestamp };
        }

        /// read ext value or timestamp if it's timestamp type (-1)
        fn readExtValueOrTimestamp(self: Self, marker: Markers, allocator: Allocator) !Payload {
            // Fast path: not a timestamp candidate
            if (!isTimestampCandidate(marker)) {
                const val = try self.readExtValue(marker, allocator);
                return Payload{ .ext = val };
            }

            // Handle EXT8 special case (need to read length first)
            if (marker == .EXT8) {
                const len_info = try self.readExt8Length();

                // If not timestamp length, read as regular EXT
                if (!len_info.is_timestamp_candidate) {
                    const ext_type = try self.readI8Value();
                    return try self.readRegularExt(ext_type, len_info.len, allocator);
                }
            }

            // Read extension type to determine if it's a timestamp
            const ext_type = try self.readI8Value();

            // Timestamp type: read timestamp data
            if (ext_type == TIMESTAMP_EXT_TYPE) {
                return try self.readTimestampPayload(marker);
            }

            // Regular EXT: read remaining data
            const actual_len = if (marker == .EXT8) TIMESTAMP96_DATA_LEN else getExtLength(marker);
            return try self.readRegularExt(ext_type, actual_len, allocator);
        }

        fn readExtValue(self: Self, marker: Markers, allocator: Allocator) !EXT {
            switch (marker) {
                .FIXEXT1 => {
                    return self.readExtData(allocator, FIXEXT1_LEN);
                },
                .FIXEXT2 => {
                    return self.readExtData(allocator, FIXEXT2_LEN);
                },
                .FIXEXT4 => {
                    return self.readExtData(allocator, FIXEXT4_LEN);
                },
                .FIXEXT8 => {
                    return self.readExtData(allocator, FIXEXT8_LEN);
                },
                .FIXEXT16 => {
                    return self.readExtData(allocator, FIXEXT16_LEN);
                },
                .EXT8 => {
                    const len = try self.readV8Value();
                    return self.readExtData(allocator, len);
                },
                .EXT16 => {
                    const len = try self.readU16Value();
                    return self.readExtData(allocator, len);
                },
                .EXT32 => {
                    const len = try self.readU32Value();
                    return self.readExtData(allocator, len);
                },
                else => {
                    return MsgPackError.InvalidType;
                },
            }
        }

        // ========== Iterative Parser State Machine ==========

        /// Parse state for iterative parsing
        const ParseState = struct {
            container_type: enum {
                array, // Parsing array elements
                map_key, // Expecting map key (must be string)
                map_value, // Expecting map value
            },
            data: union(enum) {
                array: ArrayState,
                map: MapState,
            },
        };

        const ArrayState = struct {
            items: []Payload,
            current_index: usize,
            total_length: usize,
        };

        const MapState = struct {
            map: Map,
            current_key: ?[]const u8,
            remaining_pairs: usize,
        };

        /// Clean up parse stack on error
        fn cleanupParseStack(stack: *std.ArrayList(ParseState), allocator: Allocator) void {
            // Pop and free all states from the stack
            while (stack.items.len > 0) {
                const state = stack.pop() orelse break;
                switch (state.data) {
                    .array => |arr_state| {
                        // Free already parsed elements
                        for (arr_state.items[0..arr_state.current_index]) |item| {
                            item.free(allocator);
                        }
                        // Free the array itself
                        allocator.free(arr_state.items);
                    },
                    .map => |map_state| {
                        // Free current_key if it exists (orphaned key waiting for value)
                        if (map_state.current_key) |key| {
                            allocator.free(key);
                        }
                        // Free the map and its contents
                        var map_copy = map_state.map;
                        defer map_copy.deinit();
                        var iter = map_copy.iterator();
                        while (iter.next()) |entry| {
                            allocator.free(entry.key_ptr.*);
                            entry.value_ptr.free(allocator);
                        }
                    },
                }
            }
        }

        /// Read array length based on marker
        inline fn readArrayLength(self: Self, marker: Markers, marker_u8: u8) !usize {
            return switch (marker) {
                .FIXARRAY => marker_u8 - FIXARRAY_BASE,
                .ARRAY16 => try self.readU16Value(),
                .ARRAY32 => try self.readU32Value(),
                else => MsgPackError.InvalidType,
            };
        }

        /// Read map length based on marker
        inline fn readMapLength(self: Self, marker: Markers, marker_u8: u8) !usize {
            return switch (marker) {
                .FIXMAP => marker_u8 - FIXMAP_BASE,
                .MAP16 => try self.readU16Value(),
                .MAP32 => try self.readU32Value(),
                else => MsgPackError.InvalidType,
            };
        }

        /// Helper to append to parse stack (handles Zig version differences)
        inline fn appendToStack(stack: *std.ArrayList(ParseState), allocator: Allocator, item: ParseState) !void {
            if (current_zig.minor == 14) {
                try stack.append(item);
            } else {
                try stack.append(allocator, item);
            }
        }

        // ========== End of State Machine Helpers ==========

        /// Fast path for simple types that don't require heap allocation or complex state management
        inline fn readSimpleTypeFast(self: Self, marker: Markers, marker_u8: u8) !?Payload {
            return switch (marker) {
                .NIL => Payload{ .nil = void{} },
                .TRUE => Payload{ .bool = true },
                .FALSE => Payload{ .bool = false },

                .POSITIVE_FIXINT => Payload{ .uint = marker_u8 },
                .NEGATIVE_FIXINT => Payload{ .int = @as(i8, @bitCast(marker_u8)) },

                .UINT8 => Payload{ .uint = try self.readV8Value() },
                .UINT16 => Payload{ .uint = try self.readU16Value() },
                .UINT32 => Payload{ .uint = try self.readU32Value() },
                .UINT64 => Payload{ .uint = try self.readU64Value() },

                .INT8 => Payload{ .int = try self.readI8Value() },
                .INT16 => Payload{ .int = try self.readI16Value() },
                .INT32 => Payload{ .int = try self.readI32Value() },
                .INT64 => Payload{ .int = try self.readI64Value() },

                .FLOAT32 => Payload{ .float = try self.readF32Value() },
                .FLOAT64 => Payload{ .float = try self.readF64Value() },

                // Note: FIXEXT4/FIXEXT8 could be timestamps, but we need to read ext_type first
                // Since we can't "unread" in the stream, we handle all EXT types in the complex path
                // to avoid consuming bytes that need to be re-processed.

                else => null, // Not a simple type, needs complex handling
            };
        }

        /// read a payload, please use payload.free to free the memory
        /// This is an iterative implementation that avoids stack overflow from deep nesting
        pub fn read(self: Self, allocator: Allocator) !Payload {
            // Fast path optimization: handle simple types without state machine overhead
            const first_marker_u8 = try self.readTypeMarkerU8();
            const first_marker = self.markerU8To(first_marker_u8);

            // Try fast path for simple types (no containers, no allocation needed)
            if (try self.readSimpleTypeFast(first_marker, first_marker_u8)) |simple_payload| {
                return simple_payload;
            }

            // Complex types: use full iterative parser
            return self.readComplex(allocator, first_marker, first_marker_u8);
        }

        /// Internal iterative parser for complex types (arrays, maps, strings, etc.)
        fn readComplex(self: Self, allocator: Allocator, first_marker: Markers, first_marker_u8: u8) !Payload {
            // Explicit stack for iterative parsing (on heap)
            var parse_stack = if (current_zig.minor == 14)
                std.ArrayList(ParseState).init(allocator)
            else
                std.ArrayList(ParseState){};
            defer if (current_zig.minor == 14) parse_stack.deinit() else parse_stack.deinit(allocator);

            // Root payload to return
            var root: ?Payload = null;

            // Start with the already-read first marker
            var marker_u8 = first_marker_u8;
            var marker = first_marker;

            // Main loop (replaces recursion)
            // Process first marker directly, then read subsequent markers in loop
            var is_first = true;
            while (true) {
                // Check depth limit
                if (parse_stack.items.len >= parse_limits.max_depth) {
                    cleanupParseStack(&parse_stack, allocator);
                    return MsgPackError.MaxDepthExceeded;
                }

                // Read next type marker (skip on first iteration)
                if (!is_first) {
                    marker_u8 = try self.readTypeMarkerU8();
                    marker = self.markerU8To(marker_u8);
                }
                is_first = false;

                // Current payload being constructed
                var current_payload: Payload = undefined;
                var needs_parent_fill = true;

                switch (marker) {
                    // Simple types: construct directly
                    .NIL => {
                        current_payload = Payload{ .nil = void{} };
                    },
                    .TRUE, .FALSE => {
                        const val = try self.readBoolValue(marker);
                        current_payload = Payload{ .bool = val };
                    },
                    .POSITIVE_FIXINT, .UINT8, .UINT16, .UINT32, .UINT64 => {
                        const val = try self.readUintValue(marker_u8);
                        current_payload = Payload{ .uint = val };
                    },
                    .NEGATIVE_FIXINT, .INT8, .INT16, .INT32, .INT64 => {
                        const val = try self.readIntValue(marker_u8);
                        current_payload = Payload{ .int = val };
                    },
                    .FLOAT32, .FLOAT64 => {
                        const val = try self.readFloatValue(marker);
                        current_payload = Payload{ .float = val };
                    },
                    .FIXSTR, .STR8, .STR16, .STR32 => {
                        const val = try self.readStrValue(marker_u8, allocator);

                        // Validate string length
                        if (val.len > parse_limits.max_string_length) {
                            allocator.free(val);
                            cleanupParseStack(&parse_stack, allocator);
                            return MsgPackError.StringTooLong;
                        }

                        current_payload = Payload{ .str = Str.init(val) };
                    },
                    .BIN8, .BIN16, .BIN32 => {
                        const val = try self.readBinValue(marker, allocator);

                        // Validate binary length
                        if (val.len > parse_limits.max_bin_length) {
                            allocator.free(val);
                            cleanupParseStack(&parse_stack, allocator);
                            return MsgPackError.BinDataLengthTooLong;
                        }

                        current_payload = Payload{ .bin = Bin.init(val) };
                    },

                    // Container types: push to stack and continue
                    .FIXARRAY, .ARRAY16, .ARRAY32 => {
                        const len = try self.readArrayLength(marker, marker_u8);

                        // Validate array length
                        if (len > parse_limits.max_array_length) {
                            cleanupParseStack(&parse_stack, allocator);
                            return MsgPackError.ArrayTooLarge;
                        }

                        // Special case: empty array
                        if (len == 0) {
                            const arr = try allocator.alloc(Payload, 0);
                            current_payload = Payload{ .arr = arr };
                        } else {
                            // Allocate array
                            const arr = try allocator.alloc(Payload, len);
                            errdefer allocator.free(arr);

                            // Push to stack
                            try appendToStack(&parse_stack, allocator, .{
                                .container_type = .array,
                                .data = .{ .array = .{
                                    .items = arr,
                                    .current_index = 0,
                                    .total_length = len,
                                } },
                            });

                            needs_parent_fill = false;
                            continue; // Continue to read first element
                        }
                    },

                    .FIXMAP, .MAP16, .MAP32 => {
                        const len = try self.readMapLength(marker, marker_u8);

                        // Validate map size
                        if (len > parse_limits.max_map_size) {
                            cleanupParseStack(&parse_stack, allocator);
                            return MsgPackError.MapTooLarge;
                        }

                        // Special case: empty map
                        if (len == 0) {
                            current_payload = Payload{ .map = Map.init(allocator) };
                        } else {
                            // Initialize map
                            var map = Map.init(allocator);
                            var map_owned = false;
                            errdefer if (!map_owned) map.deinit();

                            const capacity = std.math.cast(u32, len) orelse {
                                cleanupParseStack(&parse_stack, allocator);
                                return MsgPackError.MapTooLarge;
                            };
                            try map.ensureTotalCapacity(capacity);

                            // Push to stack
                            try appendToStack(&parse_stack, allocator, .{
                                .container_type = .map_key,
                                .data = .{ .map = .{
                                    .map = map,
                                    .current_key = null,
                                    .remaining_pairs = len,
                                } },
                            });
                            map_owned = true;

                            needs_parent_fill = false;
                            continue; // Continue to read first key
                        }
                    },

                    // Extension types
                    .FIXEXT1, .FIXEXT2, .FIXEXT4, .FIXEXT8, .FIXEXT16, .EXT8, .EXT16, .EXT32 => {
                        const ext_result = try self.readExtValueOrTimestamp(marker, allocator);
                        current_payload = ext_result;
                    },
                }

                // Fill parent container or set root
                if (needs_parent_fill) {
                    // Add errdefer to clean up current_payload if parent fill fails
                    errdefer current_payload.free(allocator);

                    if (parse_stack.items.len == 0) {
                        // No parent, this is the root
                        root = current_payload;
                        break;
                    }

                    // Fill parent and check if complete
                    while (true) {
                        const parent = &parse_stack.items[parse_stack.items.len - 1];
                        const finished = try fillParentContainer(parent, current_payload, allocator, &parse_stack);

                        if (!finished) {
                            // Parent needs more elements
                            break;
                        }

                        // Parent container is complete, pop it
                        const completed_state = parse_stack.pop() orelse return MsgPackError.Internal;
                        const completed_payload = containerToPayload(completed_state);

                        if (parse_stack.items.len == 0) {
                            // This was the root container
                            root = completed_payload;
                            break;
                        }

                        // Continue with completed container as new current
                        current_payload = completed_payload;
                    }

                    if (root != null) break;
                }
            }

            return root orelse MsgPackError.Internal;
        }

        /// Fill parent container with child element
        /// Returns true if parent container is complete
        /// This is a hot path function, optimized for common cases
        inline fn fillParentContainer(
            parent: *ParseState,
            child: Payload,
            allocator: Allocator,
            stack: *std.ArrayList(ParseState),
        ) !bool {
            switch (parent.container_type) {
                .array => {
                    // Fast path: array insertion is just pointer assignment
                    var arr_state = &parent.data.array;
                    arr_state.items[arr_state.current_index] = child;
                    arr_state.current_index += 1;
                    return arr_state.current_index >= arr_state.total_length;
                },

                .map_key => {
                    // Child must be a string (key)
                    if (child != .str) {
                        child.free(allocator); // Free the invalid child first
                        cleanupParseStack(stack, allocator);
                        return MsgPackError.InvalidType;
                    }
                    parent.data.map.current_key = child.str.value();
                    parent.container_type = .map_value;
                    return false; // Still need to read value
                },

                .map_value => {
                    var map_state = &parent.data.map;
                    const key = map_state.current_key orelse return MsgPackError.Internal;
                    try map_state.map.put(key, child);
                    map_state.current_key = null;
                    map_state.remaining_pairs -= 1;

                    if (map_state.remaining_pairs == 0) {
                        return true; // Map complete
                    }

                    parent.container_type = .map_key;
                    return false; // Continue reading next key
                },
            }
        }

        /// Convert completed ParseState to Payload
        inline fn containerToPayload(state: ParseState) Payload {
            return switch (state.data) {
                .array => |arr_state| Payload{ .arr = arr_state.items },
                .map => |map_state| Payload{ .map = map_state.map },
            };
        }
    };
}

/// Create an instance of msgpack_pack with default limits (backward compatible)
pub fn Pack(
    comptime WriteContext: type,
    comptime ReadContext: type,
    comptime WriteError: type,
    comptime ReadError: type,
    comptime writeFn: fn (context: WriteContext, bytes: []const u8) WriteError!usize,
    comptime readFn: fn (context: ReadContext, arr: []u8) ReadError!usize,
) type {
    return PackWithLimits(
        WriteContext,
        ReadContext,
        WriteError,
        ReadError,
        writeFn,
        readFn,
        DEFAULT_LIMITS,
    );
}

// Export compatibility layer for cross-version support
pub const compat = @import("compat.zig");
