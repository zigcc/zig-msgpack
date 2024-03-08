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
    12 => std.builtin.Endian.big,
    else => @compileError("not support current version zig"),
};
const little_endian = switch (current_zig.minor) {
    11 => std.builtin.Endian.Little,
    12 => std.builtin.Endian.little,
    else => @compileError("not support current version zig"),
};

pub const Str = struct {
    str: []const u8,
    pub fn value(self: Str) []const u8 {
        return self.str;
    }
};

/// this is for encode str in struct
pub fn wrapStr(str: []const u8) Str {
    return Str{ .str = str };
}

pub const Bin = struct {
    bin: []u8,
    pub fn value(self: Bin) []u8 {
        return self.bin;
    }
};

/// this is wrapping for bin
pub fn wrapBin(bin: []u8) Bin {
    return Bin{ .bin = bin };
}

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

pub const Payload = union(enum) {
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

    pub fn free(self: *Payload, allocator: Allocator) void {
        switch (self.*) {
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
                        // @compileLog(@TypeOf(entry.key_ptr.*));
                        defer allocator.free(entry.key_ptr.*);
                        entry.value_ptr.free(allocator);
                    } else {
                        break;
                    }
                }
            },
            .arr => {
                var arr = self.arr;
                defer allocator.free(arr);
                for (0..arr.len) |i| {
                    arr[i].free(allocator);
                }
            },
            else => {},
        }
    }
};

pub const Map = std.StringHashMap(Payload);

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

/// error set
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

/// main function
pub fn Pack(
    comptime WriteContext: type,
    comptime ReadContext: type,
    comptime WriteError: type,
    comptime ReadError: type,
    comptime writeFn: fn (context: WriteContext, bytes: []const u8) WriteError!usize,
    comptime readFn: fn (context: ReadContext, arr: []u8) ReadError!usize,
) type {
    return struct {
        writeContext: WriteContext,
        readContext: ReadContext,

        const Self = @This();

        /// init
        pub fn init(writeContext: WriteContext, readContext: ReadContext) Self {
            return Self{
                .writeContext = writeContext,
                .readContext = readContext,
            };
        }

        /// wrap for writeFn
        fn write_fn(self: Self, bytes: []const u8) !usize {
            return writeFn(self.writeContext, bytes);
        }

        /// write one byte
        fn write_byte(self: Self, byte: u8) !void {
            const bytes = [_]u8{byte};
            const len = try self.write_fn(&bytes);
            if (len != 1) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        /// write data
        fn write_data(self: Self, data: []const u8) !void {
            const len = try self.write_fn(data);
            if (len != data.len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        /// write type marker
        fn write_type_marker(self: Self, comptime marker: Markers) !void {
            switch (marker) {
                .POSITIVE_FIXINT, .FIXMAP, .FIXARRAY, .FIXSTR, .NEGATIVE_FIXINT => {
                    const err_msg = comptimePrint("marker ({}) is wrong, the can not be write directly!", .{marker});
                    @compileError(err_msg);
                },
                else => {},
            }
            try self.write_byte(@intFromEnum(marker));
        }

        /// write nil
        fn write_nil(self: Self) !void {
            try self.write_type_marker(Markers.NIL);
        }

        /// write bool
        fn write_bool(self: Self, val: bool) !void {
            if (val) {
                try self.write_type_marker(Markers.TRUE);
            } else {
                try self.write_type_marker(Markers.FALSE);
            }
        }

        /// write positive fix int
        fn write_pfix_int(self: Self, val: u8) !void {
            if (val <= 0x7f) {
                try self.write_byte(val);
            } else {
                return MsGPackError.INPUT_VALUE_TOO_LARGE;
            }
        }

        fn write_u8_value(self: Self, val: u8) !void {
            try self.write_byte(val);
        }

        /// write u8 int
        fn write_u8(self: Self, val: u8) !void {
            try self.write_type_marker(.UINT8);
            try self.write_u8_value(val);
        }

        fn write_u16_value(self: Self, val: u16) !void {
            var arr: [2]u8 = undefined;
            std.mem.writeInt(u16, &arr, val, big_endian);

            try self.write_data(&arr);
        }

        /// write u16 int
        fn write_u16(self: Self, val: u16) !void {
            try self.write_type_marker(.UINT16);
            try self.write_u16_value(val);
        }

        fn write_u32_value(self: Self, val: u32) !void {
            var arr: [4]u8 = undefined;
            std.mem.writeInt(u32, &arr, val, big_endian);

            try self.write_data(&arr);
        }

        /// write u32 int
        fn write_u32(self: Self, val: u32) !void {
            try self.write_type_marker(.UINT32);
            try self.write_u32_value(val);
        }

        fn write_u64_value(self: Self, val: u64) !void {
            var arr: [8]u8 = undefined;
            std.mem.writeInt(u64, &arr, val, big_endian);

            try self.write_data(&arr);
        }

        /// write u64 int
        fn write_u64(self: Self, val: u64) !void {
            try self.write_type_marker(.UINT64);
            try self.write_u64_value(val);
        }

        /// write negative fix int
        fn write_nfix_int(self: Self, val: i8) !void {
            if (val >= -32 and val <= -1) {
                try self.write_byte(@bitCast(val));
            } else {
                return MsGPackError.INPUT_VALUE_TOO_LARGE;
            }
        }

        fn write_i8_value(self: Self, val: i8) !void {
            try self.write_byte(@bitCast(val));
        }

        /// write i8 int
        fn write_i8(self: Self, val: i8) !void {
            try self.write_type_marker(.INT8);
            try self.write_i8_value(val);
        }

        fn write_i16_value(self: Self, val: i16) !void {
            var arr: [2]u8 = undefined;
            std.mem.writeInt(i16, &arr, val, big_endian);

            try self.write_data(&arr);
        }

        /// write i16 int
        fn write_i16(self: Self, val: i16) !void {
            try self.write_type_marker(.INT16);
            try self.write_i16_value(val);
        }

        fn write_i32_value(self: Self, val: i32) !void {
            var arr: [4]u8 = undefined;
            std.mem.writeInt(i32, &arr, val, big_endian);

            try self.write_data(&arr);
        }

        /// write i32 int
        fn write_i32(self: Self, val: i32) !void {
            try self.write_type_marker(.INT32);
            try self.write_i32_value(val);
        }

        fn write_i64_value(self: Self, val: i64) !void {
            var arr: [8]u8 = undefined;
            std.mem.writeInt(i64, &arr, val, big_endian);

            try self.write_data(&arr);
        }

        /// write i64 int
        fn write_i64(self: Self, val: i64) !void {
            try self.write_type_marker(.INT64);
            try self.write_i64_value(val);
        }

        /// write uint
        fn write_uint(self: Self, val: u64) !void {
            if (val <= 0x7f) {
                try self.write_pfix_int(@intCast(val));
            } else if (val <= 0xff) {
                try self.write_u8(@intCast(val));
            } else if (val <= 0xffff) {
                try self.write_u16(@intCast(val));
            } else if (val <= 0xffffffff) {
                try self.write_u32(@intCast(val));
            } else {
                try self.write_u64(val);
            }
        }

        /// write int
        fn write_int(self: Self, val: i64) !void {
            if (val >= 0) {
                try self.write_uint(@intCast(val));
            } else if (val >= -32) {
                try self.write_nfix_int(@intCast(val));
            } else if (val >= -128) {
                try self.write_i8(@intCast(val));
            } else if (val >= -32768) {
                try self.write_i16(@intCast(val));
            } else if (val >= -2147483648) {
                try self.write_i32(@intCast(val));
            } else {
                try self.write_i64(val);
            }
        }

        fn write_f32_value(self: Self, val: f32) !void {
            const int: u32 = @bitCast(val);
            var arr: [4]u8 = undefined;
            std.mem.writeInt(u32, &arr, int, big_endian);

            try self.write_data(&arr);
        }

        /// write f32
        fn write_f32(self: Self, val: f32) !void {
            try self.write_type_marker(.FLOAT32);
            try self.write_f32_value(val);
        }

        fn write_f64_value(self: Self, val: f64) !void {
            const int: u64 = @bitCast(val);
            var arr: [8]u8 = undefined;
            std.mem.writeInt(u64, &arr, int, big_endian);

            try self.write_data(&arr);
        }

        /// write f64
        fn write_f64(self: Self, val: f64) !void {
            try self.write_type_marker(.FLOAT64);
            try self.write_f64_value(val);
        }

        /// write float
        fn write_float(self: Self, val: f64) !void {
            const tmp_val = if (val < 0) 0 - val else val;
            const min_f32 = std.math.floatMin(f32);
            const max_f32 = std.math.floatMax(f32);

            if (tmp_val >= min_f32 and tmp_val <= max_f32) {
                try self.write_f32(@floatCast(val));
            } else {
                try self.write_f64(val);
            }
        }

        fn write_fix_str_value(self: Self, str: []const u8) !void {
            const len = str.len;
            const write_len = try self.write_fn(str);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        /// write fix str
        fn write_fix_str(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0x1f) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }
            const header: u8 = @intFromEnum(Markers.FIXSTR) + @as(u8, @intCast(len));
            try self.write_byte(header);
            try self.write_fix_str_value(str);
        }

        fn write_str8_value(self: Self, str: []const u8) !void {
            const len = str.len;
            try self.write_i8_value(@intCast(len));

            try self.write_data(str);
        }

        /// write str8
        fn write_str8(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.STR8);
            try self.write_str8_value(str);
        }

        fn write_str16_value(self: Self, str: []const u8) !void {
            const len = str.len;
            try self.write_u16_value(@intCast(len));

            try self.write_data(str);
        }

        /// write str16
        fn write_str16(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xffff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.STR16);

            try self.write_str16_value(str);
        }

        fn write_str32_value(self: Self, str: []const u8) !void {
            const len = str.len;
            try self.write_u32_value(@intCast(len));

            try self.write_data(str);
        }

        /// write str32
        fn write_str32(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xffff_ffff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.STR32);
            try self.write_str32_value(str);
        }

        /// write str
        fn write_str(self: Self, str: Str) !void {
            const len = str.value().len;
            if (len <= 0x1f) {
                try self.write_fix_str(str.value());
            } else if (len <= 0xff) {
                try self.write_str8(str.value());
            } else if (len <= 0xffff) {
                try self.write_str16(str.value());
            } else {
                try self.write_str32(str.value());
            }
        }

        /// write bin8
        fn write_bin8(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.BIN8);

            try self.write_str8_value(bin);
        }

        /// write bin16
        fn write_bin16(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xffff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.BIN16);

            try self.write_str16_value(bin);
        }

        /// write bin32
        fn write_bin32(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xffff_ffff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.BIN32);

            try self.write_str32_value(bin);
        }

        /// write bin
        fn write_bin(self: Self, bin: Bin) !void {
            const len = bin.value().len;
            if (len <= 0xff) {
                try self.write_bin8(bin.value());
            } else if (len <= 0xffff) {
                try self.write_bin16(bin.value());
            } else {
                try self.write_bin32(bin.value());
            }
        }

        fn write_ext_value(self: Self, ext: EXT) !void {
            try self.write_i8_value(ext.type);
            try self.write_data(ext.data);
        }

        fn write_fix_ext1(self: Self, ext: EXT) !void {
            if (ext.data.len != 1) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.FIXEXT1);

            try self.write_ext_value(ext);
        }

        fn write_fix_ext2(self: Self, ext: EXT) !void {
            if (ext.data.len != 2) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.FIXEXT2);
            try self.write_ext_value(ext);
        }

        fn write_fix_ext4(self: Self, ext: EXT) !void {
            if (ext.data.len != 4) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.FIXEXT4);
            try self.write_ext_value(ext);
        }

        fn write_fix_ext8(self: Self, ext: EXT) !void {
            if (ext.data.len != 8) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.FIXEXT8);
            try self.write_ext_value(ext);
        }

        fn write_fix_ext16(self: Self, ext: EXT) !void {
            if (ext.data.len != 16) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.FIXEXT16);
            try self.write_ext_value(ext);
        }

        fn write_ext8(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u8)) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }

            try self.write_type_marker(.EXT8);
            try self.write_u8_value(@intCast(ext.data.len));
            try self.write_ext_value(ext);
        }

        fn write_ext16(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u16)) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.EXT16);
            try self.write_u16_value(@intCast(ext.data.len));
            try self.write_ext_value(ext);
        }

        fn write_ext32(self: Self, ext: EXT) !void {
            if (ext.data.len > std.math.maxInt(u32)) {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
            try self.write_type_marker(.EXT32);
            try self.write_u32_value(@intCast(ext.data.len));
            try self.write_ext_value(ext);
        }

        /// write EXT
        fn write_ext(self: Self, ext: EXT) !void {
            const len = ext.data.len;
            if (len == 1) {
                try self.write_fix_ext1(ext);
            } else if (len == 2) {
                try self.write_fix_ext2(ext);
            } else if (len == 4) {
                try self.write_fix_ext4(ext);
            } else if (len == 8) {
                try self.write_fix_ext8(ext);
            } else if (len == 16) {
                try self.write_fix_ext16(ext);
            } else if (len <= std.math.maxInt(u8)) {
                try self.write_ext8(ext);
            } else if (len <= std.math.maxInt(u16)) {
                try self.write_ext16(ext);
            } else if (len <= std.math.maxInt(u32)) {
                try self.write_ext32(ext);
            } else {
                return MsGPackError.EXT_TYPE_LENGTH;
            }
        }

        pub fn write(self: Self, payload: Payload) !void {
            switch (payload) {
                .nil => {
                    try self.write_nil();
                },
                .bool => |val| {
                    try self.write_bool(val);
                },
                .int => |val| {
                    try self.write_int(val);
                },
                .uint => |val| {
                    try self.write_uint(val);
                },
                .float => |val| {
                    try self.write_float(val);
                },
                .str => |val| {
                    try self.write_str(val);
                },
                .bin => |val| {
                    try self.write_bin(val);
                },
                .arr => |arr| {
                    const len = arr.len;
                    if (len <= 0xf) {
                        const header: u8 = @intFromEnum(Markers.FIXARRAY) + @as(u8, @intCast(len));
                        try self.write_u8_value(header);
                    } else if (len <= 0xffff) {
                        try self.write_type_marker(.ARRAY16);
                    } else if (len <= 0xffff_ffff) {
                        try self.write_type_marker(.ARRAY32);
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
                        try self.write_u8_value(header);
                    } else if (len <= 0xffff) {
                        try self.write_type_marker(.MAP16);
                    } else if (len <= 0xffff_ffff) {
                        try self.write_type_marker(.MAP32);
                    } else {
                        return MsGPackError.MAP_LENGTH_TOO_LONG;
                    }
                    var itera = map.iterator();
                    while (itera.next()) |entry| {
                        try self.write_str(wrapStr(entry.key_ptr.*));
                        try self.write(entry.value_ptr.*);
                    }
                },
                .ext => |ext| {
                    try self.write_ext(ext);
                },
            }
        }

        // TODO: add timestamp

        //// read

        fn read_fn(self: Self, bytes: []u8) !usize {
            return readFn(self.readContext, bytes);
        }

        /// read one byte
        pub fn read_byte(self: Self) !u8 {
            var res = [1]u8{0};
            const len = try self.read_fn(&res);

            if (len != 1) {
                return MsGPackError.LENGTH_READING;
            }

            return res[0];
        }

        /// read data
        pub fn read_data(self: Self, allocator: Allocator, len: usize) ![]u8 {
            const data = try allocator.alloc(u8, len);
            errdefer allocator.free(data);
            const data_len = try self.read_fn(data);

            if (data_len != len) {
                return MsGPackError.LENGTH_READING;
            }

            return data;
        }

        /// read type marker u8
        pub fn read_type_marker_u8(self: Self) !u8 {
            const val = try self.read_byte();
            return val;
        }

        /// convert marker u8 to marker
        pub fn marker_u8_to(_: Self, marker_u8: u8) Markers {
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

        /// read type marker
        pub fn read_type_marker(self: Self) !Markers {
            const val = try self.read_type_marker_u8();
            return self.marker_u8_to(val);
        }

        /// read nil
        pub fn read_nil(self: Self) !void {
            const marker = try self.read_type_marker();
            if (marker != .NIL) {
                return MsGPackError.TYPE_MARKER_READING;
            }
        }

        pub fn read_bool_value(_: Self, marker: Markers) !bool {
            switch (marker) {
                .TRUE => return true,
                .FALSE => return false,
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read bool
        pub fn read_bool(self: Self) !bool {
            const marker = try self.read_type_marker();
            return self.read_bool_value(marker);
        }

        /// read positive and negative fixint
        pub fn read_fixint_value(_: Self, marker_u8: u8) i8 {
            return @bitCast(marker_u8);
        }

        pub fn read_i8_value(self: Self) !i8 {
            const val = try self.read_byte();
            return @bitCast(val);
        }

        pub fn read_u8_value(self: Self) !u8 {
            return self.read_byte();
        }

        pub fn read_i16_value(self: Self) !i16 {
            var buffer: [2]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 2) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i16, &buffer, big_endian);
            return val;
        }

        pub fn read_u16_value(self: Self) !u16 {
            var buffer: [2]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 2) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u16, &buffer, big_endian);
            return val;
        }

        pub fn read_i32_value(self: Self) !i32 {
            var buffer: [4]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i32, &buffer, big_endian);
            return val;
        }

        pub fn read_u32_value(self: Self) !u32 {
            var buffer: [4]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u32, &buffer, big_endian);
            return val;
        }

        pub fn read_i64_value(self: Self) !i64 {
            var buffer: [8]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i64, &buffer, big_endian);
            return val;
        }

        pub fn read_u64_value(self: Self) !u64 {
            var buffer: [8]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u64, &buffer, big_endian);
            return val;
        }

        /// read i8
        pub fn read_i8(self: Self) !i8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    return self.read_fixint_value(marker_u8);
                },
                .INT8 => {
                    return self.read_i8_value();
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    if (val <= 127) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read i16
        pub fn read_i16(self: Self) !i16 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val = self.read_fixint_value(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    return val;
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    return val;
                },
                .INT16 => {
                    return self.read_i16_value();
                },
                .UINT16 => {
                    const val = try self.read_u16_value();
                    if (val <= 32767) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read i32
        pub fn read_i32(self: Self) !i32 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val = self.read_fixint_value(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    return val;
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    return val;
                },
                .INT16 => {
                    const val = try self.read_i16_value();
                    return val;
                },
                .UINT16 => {
                    const val = try self.read_u16_value();
                    return val;
                },
                .Int32 => {
                    const val = try self.read_i32_value();
                    return val;
                },
                .UINT32 => {
                    const val = try self.read_u32_value();
                    if (val <= 2147483647) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read i64
        pub fn read_i64(self: Self) !i64 {
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_int_value(marker_u8);
        }

        // read u8
        pub fn read_u8(self: Self) !u8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    return self.read_u8_value();
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        // read u16
        pub fn read_u16(self: Self) !u16 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT16 => {
                    return self.read_u16_value();
                },
                .INT16 => {
                    const val = try self.read_i16_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        // read u32
        pub fn read_u32(self: Self) !u32 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT16 => {
                    const val = try self.read_u16_value();
                    return val;
                },
                .INT16 => {
                    const val = try self.read_i16_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT32 => {
                    return self.read_u32_value();
                },
                .INT32 => {
                    const val = try self.read_i32_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read u64
        pub fn read_u64(self: Self) !u64 {
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_uint_value(marker_u8);
        }

        pub fn read_int_value(self: Self, marker_u8: u8) !i64 {
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val = self.read_fixint_value(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    return val;
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    return val;
                },
                .INT16 => {
                    const val = try self.read_i16_value();
                    return val;
                },
                .UINT16 => {
                    const val = try self.read_u16_value();
                    return val;
                },
                .INT32 => {
                    const val = try self.read_i32_value();
                    return val;
                },
                .UINT32 => {
                    const val = try self.read_u32_value();
                    return val;
                },
                .INT64 => {
                    return self.read_i64_value();
                },
                .UINT64 => {
                    const val = try self.read_u64_value();
                    if (val <= std.math.maxInt(i64)) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read int
        pub const read_int = read_i64;

        pub fn read_uint_value(self: Self, marker_u8: u8) !u64 {
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_u8_value();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_i8_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT16 => {
                    const val = try self.read_u16_value();
                    return val;
                },
                .INT16 => {
                    const val = try self.read_i16_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT32 => {
                    const val = try self.read_u32_value();
                    return val;
                },
                .INT32 => {
                    const val = try self.read_i32_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT64 => {
                    return self.read_u64_value();
                },
                .INT64 => {
                    const val = try self.read_i64_value();
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read uint
        pub const read_uint = read_u64;

        pub fn read_f32_value(self: Self) !f32 {
            var buffer: [4]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val_int = std.mem.readInt(u32, &buffer, big_endian);
            const val: f32 = @bitCast(val_int);
            return val;
        }

        pub fn read_f64_value(self: Self) !f64 {
            var buffer: [8]u8 = undefined;
            const len = try self.read_fn(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val_int = std.mem.readInt(u64, &buffer, big_endian);
            const val: f64 = @bitCast(val_int);
            return val;
        }

        // read f32
        pub fn read_f32(self: Self) !f32 {
            const marker = try self.read_type_marker();
            switch (marker) {
                .FLOAT32 => {
                    return self.read_f32_value();
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read f64
        fn read_f64(self: Self) !f64 {
            const marker = try self.read_type_marker();
            return self.read_float_value(marker);
        }

        pub fn read_float_value(self: Self, marker: Markers) !f64 {
            switch (marker) {
                .FLOAT32 => {
                    const val = try self.read_f32_value();
                    return val;
                },
                .FLOAT64 => {
                    return self.read_f64_value();
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read float
        pub const read_float = read_f64;

        pub fn read_fix_str_value(self: Self, allocator: Allocator, marker_u8: u8) ![]const u8 {
            const len: u8 = marker_u8 - @intFromEnum(Markers.FIXSTR);
            const str = try self.read_data(allocator, len);

            return str;
        }

        pub fn read_str8_value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.read_u8_value();
            const str = try self.read_data(allocator, len);

            return str;
        }

        pub fn read_str16_value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.read_u16_value();
            const str = try self.read_data(allocator, len);

            return str;
        }

        pub fn read_str32_value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.read_u32_value();
            const str = try self.read_data(allocator, len);

            return str;
        }

        pub fn read_str_value(self: Self, marker_u8: u8, allocator: Allocator) ![]const u8 {
            const marker = self.marker_u8_to(marker_u8);

            switch (marker) {
                .FIXSTR => {
                    return self.read_fix_str_value(allocator, marker_u8);
                },
                .STR8 => {
                    return self.read_str8_value(allocator);
                },
                .STR16 => {
                    return self.read_str16_value(allocator);
                },
                .STR32 => {
                    return self.read_str32_value(allocator);
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read str
        pub fn read_str(self: Self, allocator: Allocator) !Str {
            const marker_u8 = try self.read_type_marker_u8();
            const str = try self.read_str_value(marker_u8, allocator);
            return Str{
                .str = str,
            };
        }

        pub fn read_bin8_value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.read_u8_value();
            const bin = try self.read_data(allocator, len);

            return bin;
        }

        pub fn read_bin16_value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.read_u16_value();
            const bin = try self.read_data(allocator, len);

            return bin;
        }

        pub fn read_bin32_value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.read_u32_value();
            const bin = try self.read_data(allocator, len);

            return bin;
        }

        pub fn read_bin_value(self: Self, marker: Markers, allocator: Allocator) ![]u8 {
            switch (marker) {
                .BIN8 => {
                    return self.read_bin8_value(allocator);
                },
                .BIN16 => {
                    return self.read_bin16_value(allocator);
                },
                .BIN32 => {
                    return self.read_bin32_value(allocator);
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read bin
        pub fn read_bin(self: Self, allocator: Allocator) !Bin {
            const marker = try self.read_type_marker();
            const bin = try self.read_bin_value(marker, allocator);
            return Bin{
                .bin = bin,
            };
        }

        pub fn read_slice_value(self: Self, marker_u8: u8, allocator: Allocator, comptime T: type) ![]T {
            const marker = self.marker_u8_to(marker_u8);
            var len: usize = 0;
            switch (marker) {
                .FIXARRAY => {
                    len = marker_u8 - 0x90;
                },
                .ARRAY16 => {
                    len = try self.read_u16_value();
                },
                .ARRAY32 => {
                    len = try self.read_u32_value();
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }

            const arr = try allocator.alloc(T, len);
            errdefer allocator.free(arr);
            for (0..len) |i| {
                arr[i] = try self.read(T, allocator);
            }
            return arr;
        }

        pub fn read_array_value(self: Self, marker_u8: u8, allocator: Allocator, comptime T: type) !T {
            const type_info = @typeInfo(T);
            if (type_info != .Array) {
                const err_msg = comptimePrint("type T ({}) must be array", .{T});
                @compileError(err_msg);
            }
            const array_info = type_info.Array;

            const marker = self.marker_u8_to(marker_u8);
            var len: usize = 0;
            switch (marker) {
                .FIXARRAY => {
                    len = marker_u8 - 0x90;
                },
                .ARRAY16 => {
                    len = try self.read_u16_value();
                },
                .ARRAY32 => {
                    len = try self.read_u32_value();
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }

            // check the len whether is valid
            if (len != array_info.len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }
            var res: T = undefined;
            for (0..len) |index| {
                res[index] = try self.read(array_info.child, allocator);
            }
            return res;
        }

        pub fn read_array_value_no_alloc(self: Self, marker_u8: u8, comptime T: type) !T {
            const type_info = @typeInfo(T);
            if (type_info != .Array) {
                const err_msg = comptimePrint("type T ({}) must be array", .{T});
                @compileError(err_msg);
            }
            const array_info = type_info.Array;

            const marker = self.marker_u8_to(marker_u8);
            var len: usize = 0;
            switch (marker) {
                .FIXARRAY => {
                    len = marker_u8 - 0x90;
                },
                .ARRAY16 => {
                    len = try self.read_u16_value();
                },
                .ARRAY32 => {
                    len = try self.read_u32_value();
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }

            // check the len whether is valid
            if (len != array_info.len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            var res: T = undefined;
            for (0..len) |index| {
                res[index] = try self.readNoAlloc(array_info.child);
            }
            return res;
        }

        /// read Slice
        pub fn read_slice(self: Self, allocator: Allocator, comptime T: type) ![]T {
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_slice_value(marker_u8, allocator, T);
        }

        pub fn read_array(self: Self, allocator: Allocator, comptime T: type) !T {
            const type_info = @typeInfo(T);
            if (type_info != .Array) {
                const err_msg = comptimePrint("type T ({}) must be array", .{T});
                @compileError(err_msg);
            }
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_array_value(marker_u8, allocator, T);
        }

        /// read array
        pub fn read_array_no_alloc(self: Self, comptime T: type) !T {
            const type_info = @typeInfo(T);
            if (type_info != .Array) {
                const err_msg = comptimePrint("type T ({}) must be array", .{T});
                @compileError(err_msg);
            }
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_array_value_no_alloc(marker_u8, T);
        }

        pub fn read_tuple_value(self: Self, marker_u8: u8, comptime T: type, allocator: Allocator) !T {
            const tuple_info = @typeInfo(T).Struct;
            const marker = self.marker_u8_to(marker_u8);

            var len: usize = 0;
            switch (marker) {
                .FIXARRAY => {
                    len = marker_u8 - 0x90;
                },
                .ARRAY16 => {
                    len = try self.read_u16_value();
                },
                .ARRAY32 => {
                    len = try self.read_u32_value();
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }
            if (len != tuple_info.fields.len) {
                return MsGPackError.TUPLE_LENGTH_TOO_LONG;
            }
            var res: T = undefined;
            inline for (tuple_info.fields) |field| {
                const field_type = field.type;
                const field_name = field.name;
                @field(res, field_name) = try self.read(field_type, allocator);
            }
            return res;
        }

        /// read tuple
        pub fn read_tuple(self: Self, comptime T: type, allocator: Allocator) !T {
            const type_info = @typeInfo(T);
            if (type_info != .Struct or !type_info.Struct.is_tuple) {
                const err_msg = comptimePrint("type T ({}) must be tuple", .{T});
                @compileError(err_msg);
            }

            const marker_u8 = try self.read_type_marker_u8();
            return self.read_tuple_value(marker_u8, T, allocator);
        }

        pub fn read_tuple_value_no_alloc(self: Self, marker_u8: u8, comptime T: type) !T {
            if (comptime typeIfNeedAlloc(T)) {
                const err_msg = comptimePrint("type T ({}) must be non-alloc", .{T});
                @compileError(err_msg);
            }
            const tuple_info = @typeInfo(T).Struct;
            const marker = self.marker_u8_to(marker_u8);

            var len: usize = 0;
            switch (marker) {
                .FIXARRAY => {
                    len = marker_u8 - 0x90;
                },
                .ARRAY16 => {
                    len = try self.read_u16_value();
                },
                .ARRAY32 => {
                    len = try self.read_u32_value();
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }
            if (len != tuple_info.fields.len) {
                return MsGPackError.TUPLE_LENGTH_TOO_LONG;
            }
            var res: T = undefined;
            inline for (tuple_info.fields) |field| {
                const field_type = field.type;
                const field_name = field.name;
                @field(res, field_name) = try self.readNoAlloc(field_type);
            }
            return res;
        }

        pub fn read_tuple_no_alloc(self: Self, comptime T: type) !T {
            if (comptime typeIfNeedAlloc(T)) {
                const err_msg = comptimePrint("type T ({}) must be non-alloc", .{T});
                @compileError(err_msg);
            }
            const type_info = @typeInfo(T);
            if (type_info != .Struct or !type_info.Struct.is_tuple) {
                const err_msg = comptimePrint("type T ({}) must be tuple", .{T});
                @compileError(err_msg);
            }

            const marker_u8 = try self.read_type_marker_u8();
            return self.read_tuple_value_no_alloc(marker_u8, T);
        }

        pub fn read_enum_value(self: Self, marker_u8: u8, comptime T: type) !T {
            const type_info = @typeInfo(T);
            if (type_info != .Enum) {
                const err_msg = comptimePrint("type T ({}) must be enum type!", .{T});
                @compileError(err_msg);
            }

            const val = try self.read_uint_value(marker_u8);
            return @enumFromInt(val);
        }

        /// read enum
        pub fn read_enum(self: Self, comptime T: type) !T {
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_enum_value(marker_u8, T);
        }

        pub fn read_map_value(self: Self, marker_u8: u8, comptime T: type, allocator: Allocator) !T {
            if (T == EXT) {
                @compileError("please use read_ext for EXT");
            }
            if (T == Str) {
                @compileError("please use read_str for Str");
            }
            if (T == Bin) {
                @compileError("please use read_bin for Bin");
            }

            const marker = self.marker_u8_to(marker_u8);
            var len: usize = 0;

            const type_info = @typeInfo(T);
            if (type_info != .Struct or type_info.Struct.is_tuple) {
                const err = std.fmt.comptimePrint("type T ({}) must be struct!", .{T});
                @compileError(err);
            }

            const struct_info = type_info.Struct;

            switch (marker) {
                .FIXMAP => {
                    len = marker_u8 - @intFromEnum(Markers.FIXMAP);
                },
                .MAP16 => {
                    len = try self.read_u16_value();
                },
                .MAP32 => {
                    len = try self.read_u32_value();
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }

            const map_len = len;

            const field_len = blk: {
                var tmp_len = struct_info.fields.len;
                inline for (struct_info.fields) |field| {
                    if (field.default_value != null) {
                        tmp_len -= 1;
                    }
                }

                break :blk tmp_len;
            };
            if (map_len != field_len and map_len != struct_info.fields.len) {
                std.log.err("map_len is {}, field_len is {}", .{ map_len, field_len });
                return MsGPackError.LENGTH_READING;
            }

            var res: T = undefined;

            // first we need to assign default to struct
            inline for (struct_info.fields) |field| {
                const field_name = field.name;
                const field_type = field.type;
                // assign default value
                if (field.default_value) |default_ptr| {
                    const new_default_ptr: *align(field.alignment) const anyopaque = @alignCast(default_ptr);
                    const ptr: *const field_type = @ptrCast(new_default_ptr);
                    @field(res, field_name) = ptr.*;
                }
            }

            for (0..map_len) |_| {
                const key = try self.read_str(allocator);
                defer allocator.free(key.str);
                inline for (struct_info.fields) |field| {
                    const field_name = field.name;
                    const field_type = field.type;
                    if (field_name.len == key.str.len and std.mem.eql(u8, field_name, key.value())) {
                        @field(res, field_name) = try self.read(field_type, allocator);
                    }
                }
            }

            return res;
        }

        /// read map
        pub fn read_map(self: Self, comptime T: type, allocator: Allocator) !T {
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_map_value(marker_u8, T, allocator);
        }

        pub fn read_ext_data(self: Self, allocator: Allocator, len: usize) !EXT {
            const ext_type = try self.read_i8_value();
            const data = try self.read_data(allocator, len);
            return EXT{
                .type = ext_type,
                .data = data,
            };
        }

        pub fn read_ext_value(self: Self, marker: Markers, allocator: Allocator) !EXT {
            switch (marker) {
                .FIXEXT1 => {
                    return self.read_ext_data(allocator, 1);
                },
                .FIXEXT2 => {
                    return self.read_ext_data(allocator, 2);
                },
                .FIXEXT4 => {
                    return self.read_ext_data(allocator, 4);
                },
                .FIXEXT8 => {
                    return self.read_ext_data(allocator, 8);
                },
                .FIXEXT16 => {
                    return self.read_ext_data(allocator, 16);
                },
                .EXT8 => {
                    const len = try self.read_u8_value();
                    return self.read_ext_data(allocator, len);
                },
                .EXT16 => {
                    const len = try self.read_u16_value();
                    return self.read_ext_data(allocator, len);
                },
                .EXT32 => {
                    const len = try self.read_u32_value();
                    return self.read_ext_data(allocator, len);
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }
        }

        pub fn read_ext(self: Self, allocator: Allocator) !EXT {
            const marker = try self.read_type_marker();
            return self.read_ext_value(marker, allocator);
        }

        // TODO: add read_ext and read_timestamp

        pub fn read_value(self: Self, marker_u8: u8, comptime T: type, allocator: Allocator) !read_type_help(T) {
            const marker = self.marker_u8_to(marker_u8);
            const type_info = @typeInfo(T);
            if (comptime !typeIfNeedAlloc(T)) {
                const err_msg = comptimePrint("type T ({}) must be non-alloc", .{T});
                @compileError(err_msg);
            }

            switch (type_info) {
                .Union => {
                    if (T == Payload) {
                        return try self.read_payload_value(marker_u8, allocator);
                    } else {
                        const err_msg = comptimePrint("type T ({}) is not supported, union only support Payload!", .{T});
                        @compileError(err_msg);
                    }
                },
                .Array => {
                    return self.read_array_value(marker_u8, allocator, T);
                },
                .Pointer => |pointer| {
                    if (PO.to_slice(pointer)) |ele_type| {
                        return self.read_slice_value(marker_u8, allocator, ele_type);
                    } else {
                        const err_msg = comptimePrint("type T ({}) must be non-slice pointer", .{T});
                        @compileError(err_msg);
                    }
                },
                .Struct => |ss| {
                    if (ss.is_tuple) {
                        return self.read_tuple_value(marker_u8, T, allocator);
                    } else if (T == EXT) {
                        return self.read_ext_value(marker, allocator);
                    } else if (T == Bin) {
                        const bin = try self.read_bin_value(marker, allocator);
                        return Bin{ .bin = bin };
                    } else if (T == Str) {
                        const str = try self.read_str_value(marker_u8, allocator);
                        return Str{ .str = str };
                    } else {
                        return self.read_map_value(marker_u8, T, allocator);
                    }
                },
                else => {
                    const err_msg = comptimePrint("type T ({}) is not supported!", .{T});
                    @compileError(err_msg);
                },
            }
        }

        /// read
        pub fn read(self: Self, comptime T: type, allocator: Allocator) !read_type_help(T) {
            if (comptime !typeIfNeedAlloc(T)) {
                return self.readNoAlloc(T);
            }
            const type_info = @typeInfo(T);
            const marker_u8 = try self.read_type_marker_u8();
            if (type_info == .Optional) {
                const marker = self.marker_u8_to(marker_u8);
                if (marker == .NIL) {
                    return null;
                }
                return try self.read_value(marker_u8, type_info.Optional.child, allocator);
            } else {
                return try self.read_value(marker_u8, T, allocator);
            }
        }

        pub fn read_value_no_alloc(self: Self, marker_u8: u8, comptime T: type) !read_type_help_no_alloc(T) {
            const marker = self.marker_u8_to(marker_u8);
            const type_info = @typeInfo(T);

            switch (type_info) {
                .Void => {
                    return;
                },
                .Bool => {
                    return self.read_bool_value(marker);
                },
                .Int => |int| {
                    if (int.bits > 64) {
                        const err_msg = comptimePrint("type T ({}) is too larger, the max value is 64 bits!", .{T});
                        @compileError(err_msg);
                    }
                    const is_signed = int.signedness == .signed;

                    if (is_signed) {
                        const val = try self.read_int_value(marker_u8);
                        return @intCast(val);
                    } else {
                        const val = try self.read_uint_value(marker_u8);
                        return @intCast(val);
                    }
                },
                .Float => {
                    const val = try self.read_float_value(marker);
                    return @floatCast(val);
                },
                .Enum => {
                    return self.read_enum_value(marker_u8, T);
                },
                .Array => {
                    return self.read_array_value_no_alloc(marker_u8, T);
                },
                .Struct => |s| {
                    if (s.is_tuple) {
                        return self.read_tuple_value_no_alloc(marker_u8, T);
                    } else {
                        const err_msg = comptimePrint("type T({}) must be tuple with non-alloc", .{T});
                        @compileError(err_msg);
                    }
                },
                else => {
                    const err_msg = comptimePrint("type T ({}) is not supported", .{T});
                    @compileError(err_msg);
                },
            }
        }

        // generic read func without allocator
        pub fn readNoAlloc(self: Self, comptime T: type) !read_type_help_no_alloc(T) {
            if (comptime typeIfNeedAlloc(T)) {
                const err_msg = comptimePrint("Type T({}) must be of no memory allocated!", .{T});
                @compileError(err_msg);
            }
            const type_info = @typeInfo(T);
            const marker_u8 = try self.read_type_marker_u8();
            if (type_info == .Optional) {
                const marker = self.marker_u8_to(marker_u8);
                if (marker == .NIL) {
                    return null;
                }
                return try self.read_value_no_alloc(marker_u8, type_info.Optional.child);
            } else {
                return try self.read_value_no_alloc(marker_u8, T);
            }
        }

        pub fn read_payload_value(self: Self, marker_u8: u8, allocator: Allocator) !Payload {
            var res: Payload = undefined;
            const marker = self.marker_u8_to(marker_u8);
            switch (marker) {
                // read nil
                .NIL => {
                    res = Payload{
                        .nil = void{},
                    };
                },
                // read bool
                .TRUE, .FALSE => {
                    const val = try self.read_bool_value(marker);
                    res = Payload{
                        .bool = val,
                    };
                },
                // read uint
                .POSITIVE_FIXINT, .UINT8, .UINT16, .UINT32, .UINT64 => {
                    const val = try self.read_uint_value(marker_u8);
                    res = Payload{
                        .uint = val,
                    };
                },
                // read int
                .NEGATIVE_FIXINT, .INT8, .INT16, .INT32, .INT64 => {
                    const val = try self.read_int_value(marker_u8);
                    res = Payload{
                        .int = val,
                    };
                },
                // read float
                .FLOAT32, .FLOAT64 => {
                    const val = try self.read_float_value(marker);
                    res = Payload{
                        .float = val,
                    };
                },
                // read str
                .FIXSTR, .STR8, .STR16, .STR32 => {
                    const val = try self.read_str_value(marker_u8, allocator);
                    errdefer allocator.free(val);
                    res = Payload{
                        .str = wrapStr(val),
                    };
                },
                // read bin
                .BIN8, .BIN16, .BIN32 => {
                    const val = try self.read_bin_value(marker, allocator);
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
                            len = try self.read_u16_value();
                        },
                        .ARRAY32 => {
                            len = try self.read_u32_value();
                        },
                        else => {
                            return MsGPackError.INVALID_TYPE;
                        },
                    }

                    const arr = try allocator.alloc(Payload, len);
                    errdefer allocator.free(arr);

                    for (0..len) |i| {
                        const i_marker_u8 = try self.read_type_marker_u8();
                        arr[i] = try self.read_payload_value(i_marker_u8, allocator);
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
                            len = try self.read_u16_value();
                        },
                        .MAP32 => {
                            len = try self.read_u32_value();
                        },
                        else => {
                            return MsGPackError.INVALID_TYPE;
                        },
                    }

                    var map = Map.init(allocator);
                    for (0..len) |_| {
                        const key = try self.read_str(allocator);
                        const i_marker_u8 = try self.read_type_marker_u8();
                        const val = try self.read_payload_value(i_marker_u8, allocator);
                        try map.put(key.value(), val);
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
                    const val = try self.read_ext_value(marker, allocator);
                    res = Payload{
                        .ext = val,
                    };
                },
            }
            return res;
        }

        /// This function will return a payload,
        /// which is very convenient for reading the type of unknown structure.
        /// However, it should be noted that
        /// the map is completed using stringhashmap and requires manual deinit.
        pub fn read_payload(self: Self, allocator: Allocator) !Payload {
            const marker_u8 = try self.read_type_marker_u8();
            return self.read_payload_value(marker_u8, allocator);
        }

        /// get the Map read handle
        pub fn getArrayReader(self: Self) !ArrayReader {
            const marker_u8 = try self.read_type_marker_u8();
            return ArrayReader.init(self, marker_u8);
        }

        /// this for dynamic array
        pub const ArrayReader = struct {
            len: u32,
            pack: Self,

            pub const ArrayReaderErrorSet = error{
                MARKERINVALID,
            };

            pub fn subArrayReader(self: ArrayReader) !ArrayReader {
                return self.pack.getArrayReader();
            }

            pub fn subMapReader(self: MapReader) !MapReader {
                return self.pack.getMapReader();
            }

            fn init(pack: Self, marker_u8: u8) !ArrayReader {
                var len: u32 = 0;
                const marker = pack.marker_u8_to(marker_u8);

                switch (marker) {
                    .FIXARRAY => {
                        len = marker_u8 - 0x90;
                    },
                    .ARRAY16 => {
                        len = try pack.read_u16_value();
                    },
                    .ARRAY32 => {
                        len = try pack.read_u32_value();
                    },
                    else => {
                        return ArrayReaderErrorSet.MARKERINVALID;
                    },
                }
                return ArrayReader{
                    .len = len,
                    .pack = pack,
                };
            }

            /// read element
            pub fn read_element(self: ArrayReader, comptime T: type, allocator: Allocator) !read_type_help(T) {
                return self.pack.read(T, allocator);
            }

            /// read elemtn no alloc
            pub fn read_element_no_alloc(self: ArrayReader, comptime T: type) !read_type_help_no_alloc(T) {
                return self.pack.readNoAlloc(T);
            }
        };

        /// get the Map read handle
        pub fn getMapReader(self: Self) !MapReader {
            const marker_u8 = try self.read_type_marker_u8();
            return MapReader.init(self, marker_u8);
        }

        /// this for dynamic map
        pub const MapReader = struct {
            len: u32,
            pack: Self,

            pub const MapErrorSet = error{
                MARKERINVALID,
            };

            pub fn subMapReader(self: MapReader) !MapReader {
                return self.pack.getMapReader();
            }

            pub fn subArrayReader(self: MapReader) !ArrayReader {
                return self.pack.getArrayReader();
            }

            fn init(pack: Self, marker_u8: u8) !MapReader {
                var len: u32 = 0;
                const marker = pack.marker_u8_to(marker_u8);

                switch (marker) {
                    .FIXMAP => {
                        len = marker_u8 - @intFromEnum(Markers.FIXMAP);
                    },
                    .MAP16 => {
                        len = try pack.read_u16_value();
                    },
                    .MAP32 => {
                        len = try pack.read_u32_value();
                    },
                    else => {
                        return MapErrorSet.MARKERINVALID;
                    },
                }

                return MapReader{
                    .len = len,
                    .pack = pack,
                };
            }

            /// get the key
            pub fn read_key(self: MapReader, allocator: Allocator) !Str {
                return self.pack.read_str(allocator);
            }

            /// read value
            pub fn read(self: MapReader, comptime T: type, allocator: Allocator) !read_type_help(T) {
                return self.pack.read(T, allocator);
            }

            /// read elemet no alloc
            pub fn read_no_alloc(self: MapReader, comptime T: type) !read_type_help_no_alloc(T) {
                return self.pack.readNoAlloc(T);
            }
        };

        // skip
        pub fn skip(self: Self) !void {
            // get marker u8
            const marker_u8 = try self.read_type_marker_u8();
            // convert to markers
            const marker = self.marker_u8_to(marker_u8);
            // declare len
            var len: usize = 0;
            // use switch to match
            switch (marker) {
                .NIL, .FALSE, .TRUE, .POSITIVE_FIXINT, .NEGATIVE_FIXINT => {},
                .EXT32 => {
                    // read len
                    len = try self.read_u32_value();
                    // read data
                    _ = try self.read_u8_value();
                },
                .EXT16 => {
                    // read len
                    len = try self.read_u16_value();
                    // read type
                    _ = try self.read_u8_value();
                },
                .EXT8 => {
                    // read len
                    len = try self.read_u8_value();
                    // read type
                    _ = try self.read_u8_value();
                },
                .FIXEXT16 => {
                    len = 16;
                    // read type
                    _ = try self.read_u8_value();
                },
                .FIXEXT8 => {
                    len = 8;
                    // read type
                    _ = try self.read_u8_value();
                },
                .FIXEXT4 => {
                    len = 4;
                    // read type
                    _ = try self.read_u8_value();
                },
                .FIXEXT2 => {
                    len = 2;
                    // read type
                    _ = try self.read_u8_value();
                },
                .FIXEXT1 => {
                    len = 1;
                    // read type
                    _ = try self.read_u8_value();
                },
                .FIXMAP, .MAP16, .MAP32 => |val| {
                    if (val == .FIXMAP) {
                        len = marker_u8 - @intFromEnum(Markers.FIXMAP);
                    } else if (val == .MAP16) {
                        len = try self.read_u16_value();
                    } else {
                        len = try self.read_u32_value();
                    }
                    for (0..len * 2) |_| {
                        try self.skip();
                    }
                    return;
                },
                .STR32, .BIN32 => {
                    len = try self.read_u32_value();
                },
                .STR16, .BIN16 => {
                    len = try self.read_u16_value();
                },
                .STR8, .BIN8 => {
                    len = try self.read_u8_value();
                },
                .FIXARRAY, .ARRAY16, .ARRAY32 => |val| {
                    if (val == .FIXARRAY) {
                        len = marker_u8 - @intFromEnum(Markers.FIXARRAY);
                    } else if (val == .ARRAY16) {
                        len = try self.read_u16_value();
                    } else {
                        len = try self.read_u32_value();
                    }
                    for (0..len) |_| {
                        try self.skip();
                    }
                    return;
                },
                .FIXSTR => {
                    len = marker_u8 - @intFromEnum(Markers.FIXSTR);
                },
                .UINT64, .INT64, .FLOAT64 => {
                    _ = try self.read_u64_value();
                },
                .INT32, .UINT32, .FLOAT32 => {
                    _ = try self.read_u32_value();
                },
                .UINT16, .INT16 => {
                    _ = try self.read_u16_value();
                },
                .UINT8, .INT8 => {
                    _ = try self.read_u8_value();
                },
            }
            for (0..len) |_| {
                _ = try self.read_byte();
            }
        }
    };
}

const PO = struct {
    fn to_slice(comptime pointer: std.builtin.Type.Pointer) ?type {
        if (pointer.size == .Slice) {
            return pointer.child;
        } else if (pointer.size == .One) {
            const child_type = pointer.child;
            const child_type_info = @typeInfo(child_type);
            if (child_type_info == .Array) {
                return child_type_info.Array.child;
            }
            return null;
        }
        return null;
    }
};

pub fn typeIfNeedAlloc(comptime T: type) bool {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Void => {
            return false;
        },
        .Optional => |optional| {
            return typeIfNeedAlloc(optional.child);
        },
        .Null => {
            return false;
        },
        .Bool => {
            return false;
        },
        .Int => {
            return false;
        },
        .Float => {
            return false;
        },
        .Enum => {
            return false;
        },
        .Array => |array| {
            return typeIfNeedAlloc(array.child);
        },
        .Union => |u| {
            // when we meet Payload, directly return true
            if (T == Payload) {
                return true;
            }
            inline for (u.fields) |field| {
                if (typeIfNeedAlloc(field.type)) {
                    return true;
                }
            }
            return false;
        },
        .Struct => |s| {
            if (s.is_tuple) {
                inline for (s.fields) |field| {
                    if (typeIfNeedAlloc(field.type)) {
                        return true;
                    }
                }
                return false;
            } else {
                return true;
            }
        },
        .Pointer => {
            return true;
        },
        else => {
            const err_msg = comptimePrint("this type ({}) is not supported!", .{T});
            @compileError(err_msg);
        },
    }
    return true;
}

pub inline fn read_type_help(comptime T: type) type {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Pointer => |pointer| {
            if (PO.to_slice(pointer)) |ele_type| {
                return []ele_type;
            } else {
                const err_msg = comptimePrint("type T ({}) must be silce for pointer", .{});
                @compileError(err_msg);
            }
        },
        .Optional => |optional| {
            const child_type = optional.child;
            return ?read_type_help(child_type);
        },
        else => {
            return T;
        },
    }
}

pub inline fn read_type_help_no_alloc(comptime T: type) type {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Pointer => {
            const err_msg = comptimePrint("type T ({}) must be silce for pointer", .{});
            @compileError(err_msg);
        },
        .Optional => |optional| {
            const child_type = optional.child;
            return ?read_type_help(child_type);
        },
        else => {
            return T;
        },
    }
}
