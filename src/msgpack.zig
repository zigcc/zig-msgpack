//! MessagePack implementation with zig
//! https://msgpack.org/

const std = @import("std");
const builtin = @import("builtin");

const current_zig = builtin.zig_version;
const Allocator = std.mem.Allocator;
const comptimePrint = std.fmt.comptimePrint;
const native_endian = builtin.cpu.arch.endian();

const big_endian = switch (current_zig.minor) {
     11 => std.builtin.Endian.Big,
     12, 13, 14, 15, 16 => std.builtin.Endian.big,
     else => @compileError("not support current version zig"),
};
const little_endian = switch (current_zig.minor) {
     11 => std.builtin.Endian.Little,
     12, 13, 14, 15, 16 => std.builtin.Endian.little,
     else => @compileError("not support current version zig"),
};

/// the Str Type
pub const Str = struct {
    str: []const u8,

    /// get Str values
    pub fn value(self: Str) []const u8 {
        return self.str;
    }
};

/// this is for encode str in struct
pub fn wrapStr(str: []const u8) Str {
    return Str{ .str = str };
}

/// the Bin Type
pub const Bin = struct {
    bin: []u8,

    /// get bin values
    pub fn value(self: Bin) []u8 {
        return self.bin;
    }
};

/// this is wrapping for bin
pub fn wrapBin(bin: []u8) Bin {
    return Bin{ .bin = bin };
}

/// the EXT Type
pub const EXT = struct {
    type: i8,
    data: []u8,
};

/// t is type, data is data
pub fn wrapEXT(t: i8, data: []u8) EXT {
    return EXT{
        .type = t,
        .data = data,
    };
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
    pub fn new(seconds: i64, nanoseconds: u32) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanoseconds = nanoseconds,
        };
    }

    /// Create timestamp from seconds only (nanoseconds = 0)
    pub fn fromSeconds(seconds: i64) Timestamp {
        return Timestamp{
            .seconds = seconds,
            .nanoseconds = 0,
        };
    }

    /// Get total seconds as f64 (including fractional nanoseconds)
    pub fn toFloat(self: Timestamp) f64 {
        return @as(f64, @floatFromInt(self.seconds)) + @as(f64, @floatFromInt(self.nanoseconds)) / 1_000_000_000.0;
    }
};

/// the map of payload
pub const Map = std.StringHashMap(Payload);

/// Entity to store msgpack
///
/// Note: The payload and its subvalues must have the same allocator
pub const Payload = union(enum) {
    /// the error for Payload
    pub const Errors = error{
        NotMap,
        NotArr,
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
            return Errors.NotArr;
        }
        return self.arr[index];
    }

    /// get array length
    pub fn getArrLen(self: Payload) !usize {
        if (self != .arr) {
            return Errors.NotArr;
        }
        return self.arr.len;
    }

    /// get map's element
    pub fn mapGet(self: Payload, key: []const u8) !?Payload {
        if (self != .map) {
            return Errors.NotMap;
        }
        return self.map.get(key);
    }

    /// set array element
    pub fn setArrElement(self: *Payload, index: usize, val: Payload) !void {
        if (self.* != .arr) {
            return Errors.NotArr;
        }
        self.arr[index] = val;
    }

    /// put a new element to map payload
    pub fn mapPut(self: *Payload, key: []const u8, val: Payload) !void {
        if (self.* != .map) {
            return Errors.NotMap;
        }
        // TODO: This maybe memory leak
        const old_key = self.map.getKey(key);
        if (old_key) |old_key_ptr| {
            // if the key is already in map, free the old key
            self.map.allocator.free(old_key_ptr);
        }
        const new_key = try self.map.allocator.alloc(u8, key.len);
        @memcpy(new_key, key);
        try self.map.put(new_key, val);
    }

    /// get a NIL payload
    pub fn nilToPayload() Payload {
        return Payload{
            .nil = void{},
        };
    }

    /// get a bool payload
    pub fn boolToPayload(val: bool) Payload {
        return Payload{
            .bool = val,
        };
    }

    /// get a int payload
    pub fn intToPayload(val: i64) Payload {
        return Payload{
            .int = val,
        };
    }

    /// get a uint payload
    pub fn uintToPayload(val: u64) Payload {
        return Payload{
            .uint = val,
        };
    }

    /// get a float payload
    pub fn floatToPayload(val: f64) Payload {
        return Payload{
            .float = val,
        };
    }

    /// get a str payload
    pub fn strToPayload(val: []const u8, allocator: Allocator) !Payload {
        // alloca memory
        const new_str = try allocator.alloc(u8, val.len);
        // copy the val
        @memcpy(new_str, val);
        return Payload{
            .str = wrapStr(new_str),
        };
    }

    /// get a bin payload
    pub fn binToPayload(val: []const u8, allocator: Allocator) !Payload {
        // alloca memory
        const new_bin = try allocator.alloc(u8, val.len);
        // copy the val
        @memcpy(new_bin, val);
        return Payload{
            .bin = wrapBin(new_bin),
        };
    }

    /// get an array payload
    pub fn arrPayload(len: usize, allocator: Allocator) !Payload {
        const arr = try allocator.alloc(Payload, len);
        for (0..len) |i| {
            arr[i] = Payload.nilToPayload();
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
        // alloca memory
        const new_data = try allocator.alloc(u8, data.len);
        // copy the val
        @memcpy(new_data, data);
        return Payload{
            .ext = wrapEXT(t, new_data),
        };
    }

    /// get a timestamp payload
    pub fn timestampToPayload(seconds: i64, nanoseconds: u32) Payload {
        return Payload{
            .timestamp = Timestamp.new(seconds, nanoseconds),
        };
    }

    /// get a timestamp payload from seconds only
    pub fn timestampFromSeconds(seconds: i64) Payload {
        return Payload{
            .timestamp = Timestamp.fromSeconds(seconds),
        };
    }

    /// free the all memeory for this payload and sub payloads
    /// the allocator is payload's allocator
    pub fn free(self: Payload, allocator: Allocator) void {
        switch (self) {
            .str => {
                const str = self.str;
                allocator.free(str.value());
            },
            .bin => {
                const bin = self.bin;
                allocator.free(bin.value());
            },
            .ext => {
                const ext = self.ext;
                allocator.free(ext.data);
            },
            .map => {
                var map = self.map;
                defer map.deinit();
                var itera = map.iterator();
                while (true) {
                    if (itera.next()) |entry| {
                        // free the key
                        defer allocator.free(entry.key_ptr.*);
                        entry.value_ptr.free(allocator);
                    } else {
                        break;
                    }
                }
            },
            .arr => {
                const arr = self.arr;
                defer allocator.free(arr);
                for (0..arr.len) |i| {
                    arr[i].free(allocator);
                }
            },
            else => {},
        }
    }

    /// get a i64 value from payload
    /// Note: if the payload is not a int or the value is too large, it will return MsGPackError.INVALID_TYPE
    pub fn getInt(self: Payload) !i64 {
        return switch (self) {
            .int => |val| val,
            .uint => |val| {
                if (val <= std.math.maxInt(i64)) {
                    return @intCast(val);
                }
                // TODO: we can not return this error
                return MsGPackError.INVALID_TYPE;
            },
            else => return MsGPackError.INVALID_TYPE,
        };
    }

    /// get a u64 value from payload
    /// Note: if the payload is not a uint or the value is negative, it will return MsGPackError.INVALID_TYPE
    pub fn getUint(self: Payload) !u64 {
        return switch (self) {
            .int => |val| {
                if (val >= 0) {
                    return @intCast(val);
                }
                // TODO: we can not return this error
                return MsGPackError.INVALID_TYPE;
            },
            .uint => |val| val,
            else => return MsGPackError.INVALID_TYPE,
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
pub const MsGPackError = error{
    STR_DATA_LENGTH_TOO_LONG,
    BIN_DATA_LENGTH_TOO_LONG,
    ARRAY_LENGTH_TOO_LONG,
    TUPLE_LENGTH_TOO_LONG,
    MAP_LENGTH_TOO_LONG,
    INPUT_VALUE_TOO_LARGE,
    FIXED_VALUE_WRITING,
    TYPE_MARKER_READING,
    TYPE_MARKER_WRITING,
    DATA_READING,
    DATA_WRITING,
    EXT_TYPE_READING,
    EXT_TYPE_WRITING,
    EXT_TYPE_LENGTH,
    INVALID_TYPE,
    LENGTH_READING,
    LENGTH_WRITING,
    INTERNAL,
};

/// Create an instance of msgpack_pack
pub fn Pack(
    comptime WriteContext: type,
    comptime ReadContext: type,
    comptime WriteError: type,
    comptime ReadError: type,
    comptime writeFn: fn (context: WriteContext, bytes: []const u8) WriteError!usize,
    comptime readFn: fn (context: ReadContext, arr: []u8) ReadError!usize,
) type {
    return struct {
        write_context: WriteContext,
        read_context: ReadContext,

        const Self = @This();

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
        fn writeByte(self: Self, byte: u8) !void {
            const bytes = [_]u8{byte};
            const len = try self.writeTo(&bytes);
            if (len != 1) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        /// write data
        fn writeData(self: Self, data: []const u8) !void {
            const len = try self.writeTo(data);
            if (len != data.len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        /// write type marker
        fn writeTypeMarker(self: Self, comptime marker: Markers) !void {
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
        fn writePfixInt(self: Self, val: u8) !void {
            if (val <= 0x7f) {
                try self.writeByte(val);
            } else {
                return MsGPackError.INPUT_VALUE_TOO_LARGE;
            }
        }

        fn writeU8Value(self: Self, val: u8) !void {
            try self.writeByte(val);
        }

        /// write u8 int
        fn writeU8(self: Self, val: u8) !void {
            try self.writeTypeMarker(.UINT8);
            try self.writeU8Value(val);
        }

        fn writeU16Value(self: Self, val: u16) !void {
            var arr: [2]u8 = undefined;
            std.mem.writeInt(u16, &arr, val, big_endian);

            try self.writeData(&arr);
        }

        /// write u16 int
        fn writeU16(self: Self, val: u16) !void {
            try self.writeTypeMarker(.UINT16);
            try self.writeU16Value(val);
        }

        fn writeU32Value(self: Self, val: u32) !void {
            var arr: [4]u8 = undefined;
            std.mem.writeInt(u32, &arr, val, big_endian);

            try self.writeData(&arr);
        }

        /// write u32 int
        fn writeU32(self: Self, val: u32) !void {
            try self.writeTypeMarker(.UINT32);
            try self.writeU32Value(val);
        }

        fn writeU64Value(self: Self, val: u64) !void {
            var arr: [8]u8 = undefined;
            std.mem.writeInt(u64, &arr, val, big_endian);

            try self.writeData(&arr);
        }

        /// write u64 int
        fn writeU64(self: Self, val: u64) !void {
            try self.writeTypeMarker(.UINT64);
            try self.writeU64Value(val);
        }

        /// write negative fix int
        fn writeNfixInt(self: Self, val: i8) !void {
            if (val >= -32 and val <= -1) {
                try self.writeByte(@bitCast(val));
            } else {
                return MsGPackError.INPUT_VALUE_TOO_LARGE;
            }
        }

        fn writeI8Value(self: Self, val: i8) !void {
            try self.writeByte(@bitCast(val));
        }

        /// write i8 int
        fn writeI8(self: Self, val: i8) !void {
            try self.writeTypeMarker(.INT8);
            try self.writeI8Value(val);
        }

        fn writeI16Value(self: Self, val: i16) !void {
            var arr: [2]u8 = undefined;
            std.mem.writeInt(i16, &arr, val, big_endian);

            try self.writeData(&arr);
        }

        /// write i16 int
        fn writeI16(self: Self, val: i16) !void {
            try self.writeTypeMarker(.INT16);
            try self.writeI16Value(val);
        }

        fn writeI32Value(self: Self, val: i32) !void {
            var arr: [4]u8 = undefined;
            std.mem.writeInt(i32, &arr, val, big_endian);

            try self.writeData(&arr);
        }

        /// write i32 int
        fn writeI32(self: Self, val: i32) !void {
            try self.writeTypeMarker(.INT32);
            try self.writeI32Value(val);
        }

        fn writeI64Value(self: Self, val: i64) !void {
            var arr: [8]u8 = undefined;
            std.mem.writeInt(i64, &arr, val, big_endian);

            try self.writeData(&arr);
        }

        /// write i64 int
        fn writeI64(self: Self, val: i64) !void {
            try self.writeTypeMarker(.INT64);
            try self.writeI64Value(val);
        }

        /// write uint
        fn writeUint(self: Self, val: u64) !void {
            if (val <= 0x7f) {
                try self.writePfixInt(@intCast(val));
            } else if (val <= 0xff) {
                try self.writeU8(@intCast(val));
            } else if (val <= 0xffff) {
                try self.writeU16(@intCast(val));
            } else if (val <= 0xffffffff) {
                try self.writeU32(@intCast(val));
            } else {
                try self.writeU64(val);
            }
        }

        /// write int
        fn writeInt(self: Self, val: i64) !void {
            if (val >= 0) {
                try self.writeUint(@intCast(val));
            } else if (val >= -32) {
                try self.writeNfixInt(@intCast(val));
            } else if (val >= -128) {
                try self.writeI8(@intCast(val));
            } else if (val >= -32768) {
                try self.writeI16(@intCast(val));
            } else if (val >= -2147483648) {
                try self.writeI32(@intCast(val));
            } else {
                try self.writeI64(val);
            }
        }

        fn writeF32Value(self: Self, val: f32) !void {
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

        fn writeF64Value(self: Self, val: f64) !void {
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

        fn writeFixStrValue(self: Self, str: []const u8) !void {
            try self.writeData(str);
        }

        /// write fix str
        fn writeFixStr(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0x1f) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }
            const header: u8 = @intFromEnum(Markers.FIXSTR) + @as(u8, @intCast(len));
            try self.writeByte(header);
            try self.writeFixStrValue(str);
        }

        fn writeStr8Value(self: Self, str: []const u8) !void {
            const len = str.len;
            try self.writeU8Value(@intCast(len));

            try self.writeData(str);
        }

        /// write str8
        fn writeStr8(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.writeTypeMarker(.STR8);
            try self.writeStr8Value(str);
        }

        fn writeStr16Value(self: Self, str: []const u8) !void {
            const len = str.len;
            try self.writeU16Value(@intCast(len));

            try self.writeData(str);
        }

        /// write str16
        fn writeStr16(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xffff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.writeTypeMarker(.STR16);

            try self.writeStr16Value(str);
        }

        fn writeStr32Value(self: Self, str: []const u8) !void {
            const len = str.len;
            try self.writeU32Value(@intCast(len));

            try self.writeData(str);
        }

        /// write str32
        fn writeStr32(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xffff_ffff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.writeTypeMarker(.STR32);
            try self.writeStr32Value(str);
        }

        /// write str
        fn writeStr(self: Self, str: Str) !void {
            const len = str.value().len;
            if (len <= 0x1f) {
                try self.writeFixStr(str.value());
            } else if (len <= 0xff) {
                try self.writeStr8(str.value());
            } else if (len <= 0xffff) {
                try self.writeStr16(str.value());
            } else {
                try self.writeStr32(str.value());
            }
        }

        /// write bin8
        fn writeBin8(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.writeTypeMarker(.BIN8);

            try self.writeStr8Value(bin);
        }

        /// write bin16
        fn writeBin16(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xffff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.writeTypeMarker(.BIN16);

            try self.writeStr16Value(bin);
        }

        /// write bin32
        fn writeBin32(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xffff_ffff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.writeTypeMarker(.BIN32);

            try self.writeStr32Value(bin);
        }

        /// write bin
        fn writeBin(self: Self, bin: Bin) !void {
            const len = bin.value().len;
            if (len <= 0xff) {
                try self.writeBin8(bin.value());
            } else if (len <= 0xffff) {
                try self.writeBin16(bin.value());
            } else {
                try self.writeBin32(bin.value());
            }
        }

        fn writeExtValue(self: Self, ext: EXT) !void {
            try self.writeI8Value(ext.type);
            try self.writeData(ext.data);
        }

        fn writeFixExt1(self: Self, ext: EXT) !void {
            if (ext.data.len != 1) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.FIXEXT1);

            try self.writeExtValue(ext);
        }

        fn writeFixExt2(self: Self, ext: EXT) !void {
            if (ext.data.len != 2) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.FIXEXT2);
            try self.writeExtValue(ext);
        }

        fn writeFixExt4(self: Self, ext: EXT) !void {
            if (ext.data.len != 4) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.FIXEXT4);
            try self.writeExtValue(ext);
        }

        fn writeFixExt8(self: Self, ext: EXT) !void {
            if (ext.data.len != 8) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.FIXEXT8);
            try self.writeExtValue(ext);
        }

        fn writeFixExt16(self: Self, ext: EXT) !void {
            if (ext.data.len != 16) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.FIXEXT16);
            try self.writeExtValue(ext);
        }

        fn writeExt8(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u8)) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }

            try self.writeTypeMarker(.EXT8);
            try self.writeU8Value(@intCast(ext.data.len));
            try self.writeExtValue(ext);
        }

        fn writeExt16(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u16)) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.EXT16);
            try self.writeU16Value(@intCast(ext.data.len));
            try self.writeExtValue(ext);
        }

        fn writeExt32(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u32)) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.writeTypeMarker(.EXT32);
            try self.writeU32Value(@intCast(ext.data.len));
            try self.writeExtValue(ext);
        }

        fn writeExt(self: Self, ext: EXT) !void {
            const len = ext.data.len;
            if (len == 1) {
                try self.writeFixExt1(ext);
            } else if (len == 2) {
                try self.writeFixExt2(ext);
            } else if (len == 4) {
                try self.writeFixExt4(ext);
            } else if (len == 8) {
                try self.writeFixExt8(ext);
            } else if (len == 16) {
                try self.writeFixExt16(ext);
            } else if (len <= std.math.maxInt(u8)) {
                try self.writeExt8(ext);
            } else if (len <= std.math.maxInt(u16)) {
                try self.writeExt16(ext);
            } else if (len <= std.math.maxInt(u32)) {
                try self.writeExt32(ext);
            } else {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
        }

        /// write timestamp
        fn writeTimestamp(self: Self, timestamp: Timestamp) !void {
            // According to MessagePack spec, timestamp uses extension type -1
            const TIMESTAMP_TYPE: i8 = -1;

            // timestamp 32 format: seconds fit in 32-bit unsigned int and nanoseconds is 0
            if (timestamp.nanoseconds == 0 and timestamp.seconds >= 0 and timestamp.seconds <= 0xffffffff) {
                var data: [4]u8 = undefined;
                std.mem.writeInt(u32, &data, @intCast(timestamp.seconds), big_endian);
                const ext = EXT{ .type = TIMESTAMP_TYPE, .data = &data };
                try self.writeExt(ext);
                return;
            }

            // timestamp 64 format: seconds fit in 34-bit and nanoseconds <= 999999999
            if (timestamp.seconds >= 0 and (timestamp.seconds >> 34) == 0 and timestamp.nanoseconds <= 999999999) {
                const data64: u64 = (@as(u64, timestamp.nanoseconds) << 34) | @as(u64, @intCast(timestamp.seconds));
                var data: [8]u8 = undefined;
                std.mem.writeInt(u64, &data, data64, big_endian);
                const ext = EXT{ .type = TIMESTAMP_TYPE, .data = &data };
                try self.writeExt(ext);
                return;
            }

            // timestamp 96 format: full range with signed 64-bit seconds and 32-bit nanoseconds
            if (timestamp.nanoseconds <= 999999999) {
                var data: [12]u8 = undefined;
                std.mem.writeInt(u32, data[0..4], timestamp.nanoseconds, big_endian);
                std.mem.writeInt(i64, data[4..12], timestamp.seconds, big_endian);
                const ext = EXT{ .type = TIMESTAMP_TYPE, .data = &data };
                try self.writeExt(ext);
                return;
            }

            return MsGPackError.INVALID_TYPE;
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
                    if (len <= 0xf) {
                        const header: u8 = @intFromEnum(Markers.FIXARRAY) + @as(u8, @intCast(len));
                        try self.writeU8Value(header);
                    } else if (len <= 0xffff) {
                        try self.writeTypeMarker(.ARRAY16);
                        try self.writeU16Value(@as(u16, @intCast(len)));
                    } else if (len <= 0xffff_ffff) {
                        try self.writeTypeMarker(.ARRAY32);
                        try self.writeU32Value(@as(u32, @intCast(len)));
                    } else {
                        return MsGPackError.MAP_LENGTH_TOO_LONG;
                    }
                    for (arr) |val| {
                        try self.write(val);
                    }
                },
                .map => |map| {
                    const len = map.count();
                    if (len <= 0xf) {
                        const header: u8 = @intFromEnum(Markers.FIXMAP) + @as(u8, @intCast(len));
                        try self.writeU8Value(header);
                    } else if (len <= 0xffff) {
                        try self.writeTypeMarker(.MAP16);
                        try self.writeU16Value(@intCast(len));
                    } else if (len <= 0xffff_ffff) {
                        try self.writeTypeMarker(.MAP32);
                        try self.writeU32Value(@intCast(len));
                    } else {
                        return MsGPackError.MAP_LENGTH_TOO_LONG;
                    }
                    var itera = map.iterator();
                    while (itera.next()) |entry| {
                        try self.writeStr(wrapStr(entry.key_ptr.*));
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

        // TODO: add timestamp

        fn readFrom(self: Self, bytes: []u8) !usize {
            return readFn(self.read_context, bytes);
        }

        fn readByte(self: Self) !u8 {
            var res = [1]u8{0};
            const len = try self.readFrom(&res);

            if (len != 1) {
                return MsGPackError.LENGTH_READING;
            }

            return res[0];
        }

        fn readData(self: Self, allocator: Allocator, len: usize) ![]u8 {
            const data = try allocator.alloc(u8, len);
            errdefer allocator.free(data);
            const data_len = try self.readFrom(data);

            if (data_len != len) {
                return MsGPackError.LENGTH_READING;
            }

            return data;
        }

        fn readTypeMarkerU8(self: Self) !u8 {
            const val = try self.readByte();
            return val;
        }

        fn markerU8To(_: Self, marker_u8: u8) Markers {
            var val = marker_u8;

            if (val <= 0x7f) {
                val = 0x00;
            } else if (0x80 <= val and val <= 0x8f) {
                val = 0x80;
            } else if (0x90 <= val and val <= 0x9f) {
                val = 0x90;
            } else if (0xa0 <= val and val <= 0xbf) {
                val = 0xa0;
            } else if (0xe0 <= val and val <= 0xff) {
                val = 0xe0;
            }

            return @enumFromInt(val);
        }

        fn readTypeMarker(self: Self) !Markers {
            const val = try self.readTypeMarkerU8();
            return self.markerU8To(val);
        }

        fn readBoolValue(_: Self, marker: Markers) !bool {
            switch (marker) {
                .TRUE => return true,
                .FALSE => return false,
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        fn readBool(self: Self) !bool {
            const marker = try self.readTypeMarker();
            return self.readBoolValue(marker);
        }

        fn readFixintValue(_: Self, marker_u8: u8) i8 {
            return @bitCast(marker_u8);
        }

        fn readI8Value(self: Self) !i8 {
            const val = try self.readByte();
            return @bitCast(val);
        }

        fn readV8Value(self: Self) !u8 {
            return self.readByte();
        }

        fn readI16Value(self: Self) !i16 {
            var buffer: [2]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 2) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i16, &buffer, big_endian);
            return val;
        }

        fn readU16Value(self: Self) !u16 {
            var buffer: [2]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 2) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u16, &buffer, big_endian);
            return val;
        }

        fn readI32Value(self: Self) !i32 {
            var buffer: [4]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i32, &buffer, big_endian);
            return val;
        }

        fn readU32Value(self: Self) !u32 {
            var buffer: [4]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u32, &buffer, big_endian);
            return val;
        }

        fn readI64Value(self: Self) !i64 {
            var buffer: [8]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i64, &buffer, big_endian);
            return val;
        }

        fn readU64Value(self: Self) !u64 {
            var buffer: [8]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u64, &buffer, big_endian);
            return val;
        }

        fn readIntValue(self: Self, marker_u8: u8) !i64 {
            const marker = self.markerU8To(marker_u8);
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
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        fn readUintValue(self: Self, marker_u8: u8) !u64 {
            const marker = self.markerU8To(marker_u8);
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
                    return MsGPackError.INVALID_TYPE;
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
                    return MsGPackError.INVALID_TYPE;
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
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT64 => {
                    return self.readU64Value();
                },
                .INT64 => {
                    const val = try self.readI64Value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        fn readF32Value(self: Self) !f32 {
            var buffer: [4]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val_int = std.mem.readInt(u32, &buffer, big_endian);
            const val: f32 = @bitCast(val_int);
            return val;
        }

        fn readF64Value(self: Self) !f64 {
            var buffer: [8]u8 = undefined;
            const len = try self.readFrom(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val_int = std.mem.readInt(u64, &buffer, big_endian);
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
                else => return MsGPackError.TYPE_MARKER_READING,
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
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        fn readBin8Value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.readV8Value();
            const bin = try self.readData(allocator, len);

            return bin;
        }

        fn readBin16Value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.readU16Value();
            const bin = try self.readData(allocator, len);

            return bin;
        }

        fn readBin32Value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.readU32Value();
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
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        fn readExtData(self: Self, allocator: Allocator, len: usize) !EXT {
            const ext_type = try self.readI8Value();
            const data = try self.readData(allocator, len);
            return EXT{
                .type = ext_type,
                .data = data,
            };
        }

        /// read ext value or timestamp if it's timestamp type (-1)
        fn readExtValueOrTimestamp(self: Self, marker: Markers, allocator: Allocator) !Payload {
            const TIMESTAMP_TYPE: i8 = -1;

            // First, check if this could be a timestamp format
            if (marker == .FIXEXT4 or marker == .FIXEXT8 or marker == .EXT8) {
                // Read and check length for EXT8
                var actual_len: usize = 0;
                if (marker == .EXT8) {
                    actual_len = try self.readV8Value();
                    if (actual_len != 12) {
                        // Not timestamp 96, read as regular EXT
                        const ext_type = try self.readI8Value();
                        const ext_data = try allocator.alloc(u8, actual_len);
                        _ = try self.readFrom(ext_data);
                        return Payload{ .ext = EXT{ .type = ext_type, .data = ext_data } };
                    }
                } else if (marker == .FIXEXT4) {
                    actual_len = 4;
                } else if (marker == .FIXEXT8) {
                    actual_len = 8;
                }

                // Read the type
                const ext_type = try self.readI8Value();

                if (ext_type == TIMESTAMP_TYPE) {
                    // This is a timestamp
                    if (marker == .FIXEXT4) {
                        // timestamp 32
                        const seconds = try self.readU32Value();
                        return Payload{ .timestamp = Timestamp.new(@intCast(seconds), 0) };
                    } else if (marker == .FIXEXT8) {
                        // timestamp 64
                        const data64 = try self.readU64Value();
                        const nanoseconds: u32 = @intCast(data64 >> 34);
                        const seconds: i64 = @intCast(data64 & 0x3ffffffff);
                        return Payload{ .timestamp = Timestamp.new(seconds, nanoseconds) };
                    } else if (marker == .EXT8) {
                        // timestamp 96
                        const nanoseconds = try self.readU32Value();
                        const seconds = try self.readI64Value();
                        return Payload{ .timestamp = Timestamp.new(seconds, nanoseconds) };
                    }
                } else {
                    // Not a timestamp, read as regular EXT
                    const ext_data = try allocator.alloc(u8, actual_len);
                    _ = try self.readFrom(ext_data);
                    return Payload{ .ext = EXT{ .type = ext_type, .data = ext_data } };
                }
            }

            // Regular EXT processing
            const val = try self.readExtValue(marker, allocator);
            return Payload{ .ext = val };
        }

        /// try to read timestamp from ext data, return error if not timestamp
        fn tryReadTimestamp(self: Self, marker: Markers, _: Allocator) !Timestamp {
            const TIMESTAMP_TYPE: i8 = -1;

            switch (marker) {
                .FIXEXT4 => {
                    // timestamp 32 format
                    const ext_type = try self.readI8Value();
                    if (ext_type != TIMESTAMP_TYPE) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const seconds = try self.readU32Value();
                    return Timestamp.new(@intCast(seconds), 0);
                },
                .FIXEXT8 => {
                    // timestamp 64 format
                    const ext_type = try self.readI8Value();
                    if (ext_type != TIMESTAMP_TYPE) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const data64 = try self.readU64Value();
                    const nanoseconds: u32 = @intCast(data64 >> 34);
                    const seconds: i64 = @intCast(data64 & 0x3ffffffff);
                    return Timestamp.new(seconds, nanoseconds);
                },
                .EXT8 => {
                    // timestamp 96 format (length should be 12)
                    const len = try self.readV8Value();
                    if (len != 12) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const ext_type = try self.readI8Value();
                    if (ext_type != TIMESTAMP_TYPE) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const nanoseconds = try self.readU32Value();
                    const seconds = try self.readI64Value();
                    return Timestamp.new(seconds, nanoseconds);
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }
        }

        /// read timestamp from ext data
        fn readTimestamp(self: Self, marker: Markers, _: Allocator) !Timestamp {
            const TIMESTAMP_TYPE: i8 = -1;

            switch (marker) {
                .FIXEXT4 => {
                    // timestamp 32 format
                    const ext_type = try self.readI8Value();
                    if (ext_type != TIMESTAMP_TYPE) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const seconds = try self.readU32Value();
                    return Timestamp.new(@intCast(seconds), 0);
                },
                .FIXEXT8 => {
                    // timestamp 64 format
                    const ext_type = try self.readI8Value();
                    if (ext_type != TIMESTAMP_TYPE) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const data64 = try self.readU64Value();
                    const nanoseconds: u32 = @intCast(data64 >> 34);
                    const seconds: i64 = @intCast(data64 & 0x3ffffffff);
                    return Timestamp.new(seconds, nanoseconds);
                },
                .EXT8 => {
                    // timestamp 96 format (length should be 12)
                    const len = try self.readV8Value();
                    if (len != 12) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const ext_type = try self.readI8Value();
                    if (ext_type != TIMESTAMP_TYPE) {
                        return MsGPackError.INVALID_TYPE;
                    }
                    const nanoseconds = try self.readU32Value();
                    const seconds = try self.readI64Value();
                    return Timestamp.new(seconds, nanoseconds);
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }
        }

        fn readExtValue(self: Self, marker: Markers, allocator: Allocator) !EXT {
            switch (marker) {
                .FIXEXT1 => {
                    return self.readExtData(allocator, 1);
                },
                .FIXEXT2 => {
                    return self.readExtData(allocator, 2);
                },
                .FIXEXT4 => {
                    return self.readExtData(allocator, 4);
                },
                .FIXEXT8 => {
                    return self.readExtData(allocator, 8);
                },
                .FIXEXT16 => {
                    return self.readExtData(allocator, 16);
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
                    return MsGPackError.INVALID_TYPE;
                },
            }
        }

        /// read a payload, please use payload.free to free the memory
        pub fn read(self: Self, allocator: Allocator) !Payload {
            var res: Payload = undefined;

            const marker_u8 = try self.readTypeMarkerU8();
            const marker = self.markerU8To(marker_u8);

            switch (marker) {
                // read nil
                .NIL => {
                    res = Payload{
                        .nil = void{},
                    };
                },
                // read bool
                .TRUE, .FALSE => {
                    const val = try self.readBoolValue(marker);
                    res = Payload{
                        .bool = val,
                    };
                },
                // read uint
                .POSITIVE_FIXINT, .UINT8, .UINT16, .UINT32, .UINT64 => {
                    const val = try self.readUintValue(marker_u8);
                    res = Payload{
                        .uint = val,
                    };
                },
                // read int
                .NEGATIVE_FIXINT, .INT8, .INT16, .INT32, .INT64 => {
                    const val = try self.readIntValue(marker_u8);
                    res = Payload{
                        .int = val,
                    };
                },
                // read float
                .FLOAT32, .FLOAT64 => {
                    const val = try self.readFloatValue(marker);
                    res = Payload{
                        .float = val,
                    };
                },
                // read str
                .FIXSTR, .STR8, .STR16, .STR32 => {
                    const val = try self.readStrValue(marker_u8, allocator);
                    errdefer allocator.free(val);
                    res = Payload{
                        .str = wrapStr(val),
                    };
                },
                // read bin
                .BIN8, .BIN16, .BIN32 => {
                    const val = try self.readBinValue(marker, allocator);
                    errdefer allocator.free(val);
                    res = Payload{
                        .bin = wrapBin(val),
                    };
                },
                // read array
                .FIXARRAY, .ARRAY16, .ARRAY32 => {
                    var len: usize = 0;
                    switch (marker) {
                        .FIXARRAY => {
                            len = marker_u8 - 0x90;
                        },
                        .ARRAY16 => {
                            len = try self.readU16Value();
                        },
                        .ARRAY32 => {
                            len = try self.readU32Value();
                        },
                        else => {
                            return MsGPackError.INVALID_TYPE;
                        },
                    }

                    const arr = try allocator.alloc(Payload, len);
                    errdefer allocator.free(arr);

                    for (0..len) |i| {
                        arr[i] = try self.read(allocator);
                    }
                    res = Payload{
                        .arr = arr,
                    };
                },
                // read map
                .FIXMAP, .MAP16, .MAP32 => {
                    var len: usize = 0;
                    switch (marker) {
                        .FIXMAP => {
                            len = marker_u8 - @intFromEnum(Markers.FIXMAP);
                        },
                        .MAP16 => {
                            len = try self.readU16Value();
                        },
                        .MAP32 => {
                            len = try self.readU32Value();
                        },
                        else => {
                            return MsGPackError.INVALID_TYPE;
                        },
                    }

                    var map = Map.init(allocator);
                    for (0..len) |_| {
                        const str = try self.readStrValue(
                            try self.readTypeMarkerU8(),
                            allocator,
                        );
                        const val = try self.read(allocator);
                        try map.put(str, val);
                    }
                    res = Payload{
                        .map = map,
                    };
                },
                // read ext
                .FIXEXT1,
                .FIXEXT2,
                .FIXEXT4,
                .FIXEXT8,
                .FIXEXT16,
                .EXT8,
                .EXT16,
                .EXT32,
                => {
                    const ext_result = try self.readExtValueOrTimestamp(marker, allocator);
                    res = ext_result;
                },
            }
            return res;
        }
    };
}
