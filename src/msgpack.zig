const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const native_endian = builtin.cpu.arch.endian();

pub const Str = struct {
    str: []const u8,
    pub fn value(self: Str) []const u8 {
        return self.str;
    }
};

// this is for encode str in struct
pub fn wrapStr(str: []const u8) Str {
    return Str{ .str = str };
}

pub const Bin = struct {
    bin: []u8,
    pub fn value(self: Bin) []u8 {
        return self.bin;
    }
};

pub fn wrapBin(bin: []u8) Bin {
    return Bin{ .bin = bin };
}

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

pub const MsGPackError = error{
    STR_DATA_LENGTH_TOO_LONG,
    BIN_DATA_LENGTH_TOO_LONG,
    ARRAY_LENGTH_TOO_LONG,
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

pub fn MsgPack(
    comptime Context: type,
    comptime ErrorSet: type,
    comptime writeFn: fn (context: *Context, bytes: []const u8) ErrorSet!usize,
    comptime readFn: fn (context: *Context, arr: []u8) ErrorSet!usize,
) type {
    return struct {
        context: *Context,

        const Self = @This();

        pub const Error = ErrorSet;

        pub fn init(context: Context) Self {
            return Self{
                .context = context,
            };
        }

        /// wrap for writeFn
        pub fn write_fn(self: Self, bytes: []const u8) ErrorSet!usize {
            return writeFn(self.context, bytes);
        }

        /// write one byte
        pub fn write_byte(self: Self, byte: u8) !void {
            const bytes = [_]u8{byte};
            const len = try self.write_fn(&bytes);
            if (len != 1) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        pub fn write_data(self: Self, data: []const u8) !void {
            const len = try self.write_fn(data);
            if (len != data.len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        /// write type marker
        pub fn write_type_marker(self: Self, comptime marker: Markers) !void {
            switch (marker) {
                .POSITIVE_FIXINT, .FIXMAP, .FIXARRAY, .FIXSTR, .NEGATIVE_FIXINT => {
                    @compileError("wrong marker was used");
                },
                else => {},
            }
            try self.write_byte(@intFromEnum(marker));
        }

        /// write nil
        pub fn write_nil(self: Self) !void {
            try self.write_type_marker(Markers.NIL);
        }

        /// write true
        fn write_true(self: Self) !void {
            try self.write_type_marker(Markers.TRUE);
        }

        /// write false
        fn write_false(self: Self) !void {
            try self.write_type_marker(Markers.FALSE);
        }

        /// write bool
        pub fn write_bool(self: Self, val: bool) !void {
            if (val) {
                try self.write_true();
            } else {
                try self.write_false();
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
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, val, .big);

            try self.write_data(&arr);
        }

        /// write u16 int
        fn write_u16(self: Self, val: u16) !void {
            try self.write_type_marker(.UINT16);
            try self.write_u16_value(val);
        }

        fn write_u32_value(self: Self, val: u32) !void {
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, val, .big);

            try self.write_data(&arr);
        }

        /// write u32 int
        fn write_u32(self: Self, val: u32) !void {
            try self.write_type_marker(.UINT32);
            try self.write_u32_value(val);
        }

        fn write_u64_value(self: Self, val: u64) !void {
            var arr: [8]u8 = std.mem.zeroes([8]u8);
            std.mem.writeInt(u64, &arr, val, .big);

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
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(i16, &arr, val, .big);

            try self.write_data(&arr);
        }

        /// write i16 int
        fn write_i16(self: Self, val: i16) !void {
            try self.write_type_marker(.INT16);
            try self.write_i16_value(val);
        }

        fn write_i32_value(self: Self, val: i32) !void {
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(i32, &arr, val, .big);

            try self.write_data(&arr);
        }

        /// write i32 int
        fn write_i32(self: Self, val: i32) !void {
            try self.write_type_marker(.INT32);
            try self.write_i32_value(val);
        }

        fn write_i64_value(self: Self, val: i64) !void {
            var arr: [8]u8 = std.mem.zeroes([8]u8);
            std.mem.writeInt(i64, &arr, val, .big);

            try self.write_data(&arr);
        }

        /// write i64 int
        fn write_i64(self: Self, val: i64) !void {
            try self.write_type_marker(.INT64);
            try self.write_i64_value(val);
        }

        /// write uint
        pub fn write_uint(self: Self, val: u64) !void {
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
        pub fn write_int(self: Self, val: i64) !void {
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
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, int, .big);

            try self.write_data(&arr);
        }

        /// write f32
        fn write_f32(self: Self, val: f32) !void {
            try self.write_type_marker(.FLOAT32);
            try self.write_f32_value(val);
        }

        fn write_f64_value(self: Self, val: f64) !void {
            const int: u64 = @bitCast(val);
            var arr: [8]u8 = std.mem.zeroes([8]u8);
            std.mem.writeInt(u64, &arr, int, .big);

            try self.write_data(&arr);
        }

        /// write f64
        fn write_f64(self: Self, val: f64) !void {
            try self.write_type_marker(.FLOAT64);
            try self.write_f64_value(val);
        }

        /// write float
        pub fn write_float(self: Self, val: f64) !void {
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
            const str_len: u8 = @intCast(len);
            var arr: [1]u8 = std.mem.zeroes([1]u8);
            std.mem.writeInt(u8, &arr, str_len, .big);

            try self.write_data(&arr);

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
            const str_len: u16 = @intCast(len);
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, str_len, .big);

            try self.write_data(&arr);

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
            const str_len: u32 = @intCast(len);
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, str_len, .big);

            try self.write_data(&arr);

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
        pub fn write_str(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len <= 0x1f) {
                try self.write_fix_str(str);
            } else if (len <= 0xff) {
                try self.write_str8(str);
            } else if (len <= 0xffff) {
                try self.write_str16(str);
            } else {
                try self.write_str32(str);
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
        pub fn write_bin(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len <= 0xff) {
                try self.write_bin8(bin);
            } else if (len <= 0xffff) {
                try self.write_bin16(bin);
            } else {
                try self.write_bin32(bin);
            }
        }

        /// write arr value
        fn write_arr_value(self: Self, comptime T: type, val: []const T) !void {
            const type_info = @typeInfo(T);
            switch (type_info) {
                .Null => {
                    for (val) |_| {
                        try self.write_nil();
                    }
                },
                .Bool => {
                    for (val) |value| {
                        try self.write_bool(value);
                    }
                },
                .Int => |int| {
                    // TODO: maybe this can be optimized?
                    const int_bits = int.bits;
                    const is_signed = if (int.signedness == .signed) true else false;
                    if (int_bits > 64) {
                        @compileError("not support bits larger than 64");
                    }

                    if (is_signed) {
                        for (val) |value| {
                            try self.write_int(@intCast(value));
                        }
                    } else {
                        for (val) |value| {
                            try self.write_uint(@intCast(value));
                        }
                    }
                },
                .Float => |float| {
                    const float_bits = float.bits;
                    if (float_bits > 64) {
                        @compileError("float larger than f64 is not supported!");
                    }
                    for (val) |value| {
                        try self.write_float(value);
                    }
                },
                .Pointer => |pointer| {
                    if (PO.to_slice(pointer)) |ele_type| {
                        try self.write_arr(ele_type, val);
                    } else {
                        @compileError("not support non-slice pointer!");
                    }
                },
                .Struct => {
                    for (val) |value| {
                        try self.write_map(T, value);
                    }
                },
                else => {
                    @compileError("type is not supported!");
                },
                // TODO: other type
                // arrary optional pointer
            }
        }

        /// write fix arr
        fn write_fix_arr(self: Self, comptime T: type, val: []const T) !void {
            const arr_len = val.len;
            const max_len = 0xf;

            if (arr_len > max_len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            // write marker
            const header: u8 = @intFromEnum(Markers.FIXARRAY) + @as(u8, @intCast(arr_len));
            try self.write_u8_value(header);

            // try to write arr value
            try self.write_arr_value(T, val);
        }

        /// write arr16
        fn write_arr16(self: Self, comptime T: type, val: []const T) !void {
            const arr_len = val.len;
            const max_len = 0xffff;

            if (arr_len > max_len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.ARRAY16);

            // try to write len
            try self.write_u16_value(@intCast(arr_len));

            // try to write arr value
            try self.write_arr_value(T, val);
        }

        /// write arr32
        fn write_arr32(self: Self, comptime T: type, val: []const T) !void {
            const arr_len = val.len;
            const max_len = 0xffff_ffff;

            if (arr_len > max_len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            // try to write marker
            try self.write_type_marker(.ARRAY32);

            // try to write len
            try self.write_u32_value(@intCast(arr_len));

            // try to write arr value
            try self.write_arr_value(T, val);
        }

        /// write arr
        pub fn write_arr(self: Self, comptime T: type, val: []const T) !void {
            const len = val.len;
            if (len <= 0xf) {
                try self.write_fix_arr(T, val);
            } else if (len <= 0xffff) {
                try self.write_arr16(T, val);
            } else {
                try self.write_arr32(T, val);
            }
        }

        /// write map value
        fn write_map_value(self: Self, comptime T: type, val: T, len: usize) !void {
            const type_info = @typeInfo(T);
            if (type_info != .Struct or type_info.Struct.is_tuple) {
                @compileError("now only support struct");
            }

            const fields_len = type_info.Struct.fields.len;
            if (fields_len > len) {
                return MsGPackError.MAP_LENGTH_TOO_LONG;
            }

            inline for (type_info.Struct.fields) |field| {
                const field_name = field.name;
                const field_type = field.type;
                const field_value = @field(val, field_name);
                const field_type_info = @typeInfo(field_type);

                // write key
                try self.write_str(field.name);

                // write value
                switch (field_type_info) {
                    .Null => {
                        try self.write_nil();
                    },
                    .Bool => {
                        try self.write_bool(field_value);
                    },
                    .Int => |int| {
                        // TODO: maybe this can be optimized ?
                        const int_bits = int.bits;
                        const is_signed = if (int.signedness == .signed) true else false;
                        if (int_bits > 64) {
                            @compileError("not support bits larger than 64");
                        }

                        if (is_signed) {
                            try self.write_int(@intCast(field_value));
                        } else {
                            try self.write_uint(@intCast(field_value));
                        }
                    },
                    .Float => |float| {
                        const float_bits = float.bits;
                        if (float_bits > 64) {
                            @compileError("float larger than f64 is not supported!");
                        }

                        try self.write_float(field_value);
                    },
                    .Pointer => |pointer| {
                        // NOTE: whether we support other pointer ?
                        if (PO.to_slice(pointer)) |ele_type| {
                            try self.write_arr(ele_type, field_value);
                        } else {
                            @compileError("not support non-slice pointer!");
                        }
                    },
                    .Struct => {
                        if (field_type == Str) {
                            try self.write_str(@as(Str, field_value).value());
                        } else if (field_type == Bin) {
                            try self.write_bin(@as(Bin, field_value).value());
                        } else {
                            try self.write_map(field_type, field_value);
                        }
                    },
                    else => {
                        @compileError("type is not supported!");
                    },
                    // TODO: other type
                }
            }
        }

        /// write fix map
        fn write_fixmap(self: Self, comptime T: type, val: T) !void {
            const type_info = @typeInfo(T);
            if (type_info != .Struct or type_info.Struct.is_tuple) {
                @compileError("now only support struct");
            }

            const max_len = 0xf;

            const fields_len = type_info.Struct.fields.len;
            if (fields_len > max_len) {
                return MsGPackError.MAP_LENGTH_TOO_LONG;
            }

            // write marker
            const header: u8 = @intFromEnum(Markers.FIXMAP) + @as(u8, @intCast(fields_len));
            try self.write_u8_value(header);

            // try to write map value
            try self.write_map_value(T, val, max_len);
        }

        /// write map16
        fn write_map16(self: Self, comptime T: type, val: T) !void {
            const type_info = @typeInfo(T);
            if (type_info != .Struct or type_info.Struct.is_tuple) {
                @compileError("now only support struct");
            }

            const max_len = 0xffff;

            const fields_len = type_info.Struct.fields.len;
            if (fields_len > max_len) {
                return MsGPackError.MAP_LENGTH_TOO_LONG;
            }

            // try to write marker
            try self.write_type_marker(.MAP16);

            // try to write len
            try self.write_u16_value(@intCast(fields_len));

            // try to write map value
            try self.write_map_value(T, val, max_len);
        }

        /// write map32
        fn write_map32(self: Self, comptime T: type, val: T) !void {
            const type_info = @typeInfo(T);
            if (type_info != .Struct or type_info.Struct.is_tuple) {
                @compileError("now only support struct");
            }

            const max_len = 0xffff_ffff;

            const fields_len = type_info.Struct.fields.len;
            if (fields_len > max_len) {
                return MsGPackError.MAP_LENGTH_TOO_LONG;
            }

            // try to write marker
            try self.write_type_marker(.MAP32);

            // try to write len
            try self.write_u32_value(@intCast(fields_len));

            // try to write map value
            try self.write_map_value(T, val, max_len);
        }

        /// write map
        pub fn write_map(self: Self, comptime T: type, val: T) !void {
            const type_info = @typeInfo(T);
            if (type_info != .Struct or type_info.Struct.is_tuple) {
                @compileError("now only support struct");
            }

            const fields_len = type_info.Struct.fields.len;

            if (fields_len <= 0xf) {
                try self.write_fixmap(T, val);
            } else if (fields_len <= 0xffff) {
                try self.write_map16(T, val);
            } else if (fields_len <= 0xffff_ffff) {
                try self.write_map32(T, val);
            } else {
                @compileError("too many keys for map");
            }
        }

        fn write_ext_value(self: Self, ext: EXT) !void {
            try self.write_u8_value(ext.type);
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

        pub fn write_ext(self: Self, ext: EXT) !void {
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

        /// write
        pub fn write(self: Self, val: anytype) !void {
            const val_type = @TypeOf(val);
            const val_type_info = @typeInfo(val_type);
            switch (val_type_info) {
                .Null => {
                    try self.write_nil();
                },
                .Bool => {
                    try self.write_bool(val);
                },
                .Int => {
                    if (val >= 0) {
                        try self.write_uint(val);
                    } else {
                        try self.write_int(val);
                    }
                },
                .Float => {
                    try self.write_float(val);
                },
                .Array => |array| {
                    const ele_type = array.child;
                    try self.write_arr(ele_type, &val);
                },
                .Pointer => |pointer| {
                    if (PO.to_slice(pointer)) |ele_type| {
                        try self.write_arr(ele_type, val);
                    } else {
                        @compileError("not support non-slice pointer!");
                    }
                },
                .Struct => {
                    try self.write_map(val_type, val);
                },
                else => {
                    @compileError("type is not supported!");
                },
            }
        }

        // TODO: add timestamp

        // read

        /// wrap for readFn
        pub fn read_fn(self: Self, bytes: []u8) ErrorSet!usize {
            return readFn(self.context, bytes);
        }

        /// read one byte
        pub fn read_byte(self: Self) !u8 {
            var res = [1]u8{0};
            const len = try readFn(self.context, &res);

            if (len != 1) {
                return MsGPackError.LENGTH_READING;
            }

            return res[0];
        }

        fn read_data(self: Self, allocator: Allocator, len: usize) ![]u8 {
            const data = try allocator.alloc(u8, len);
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
        pub fn marker_u8_to(_: Self, marker_u8: u8) !Markers {
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
            return try self.marker_u8_to(val);
        }

        /// read nil
        pub fn read_nil(self: Self) !void {
            const marker = try self.read_type_marker();
            if (marker != .NIL) {
                return MsGPackError.TYPE_MARKER_READING;
            }
        }

        /// read bool
        pub fn read_bool(self: Self) !bool {
            const marker = try self.read_type_marker();
            switch (marker) {
                .TRUE => return true,
                .FALSE => return false,
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        /// read positive and negative fixint
        fn read_fixint_value(_: Self, marker_u8: u8) i8 {
            return @bitCast(marker_u8);
        }

        fn read_i8_value(self: Self) !i8 {
            const val = try self.read_byte();
            return @bitCast(val);
        }

        fn read_u8_value(self: Self) !u8 {
            return self.read_byte();
        }

        fn read_i16_value(self: Self) !i16 {
            var buffer: [2]u8 = std.mem.zeroes([2]u8);
            const len = try self.read_fn(&buffer);
            if (len != 2) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i16, &buffer, .big);
            return val;
        }

        fn read_u16_value(self: Self) !u16 {
            var buffer: [2]u8 = std.mem.zeroes([2]u8);
            const len = try self.read_fn(&buffer);
            if (len != 2) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u16, &buffer, .big);
            return val;
        }

        fn read_i32_value(self: Self) !i32 {
            var buffer: [4]u8 = std.mem.zeroes([4]u8);
            const len = try self.read_fn(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i32, &buffer, .big);
            return val;
        }

        fn read_u32_value(self: Self) !u32 {
            var buffer: [4]u8 = std.mem.zeroes([4]u8);
            const len = try self.read_fn(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u32, &buffer, .big);
            return val;
        }

        fn read_i64_value(self: Self) !i64 {
            var buffer: [8]u8 = std.mem.zeroes([8]u8);
            const len = try self.read_fn(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(i64, &buffer, .big);
            return val;
        }

        fn read_u64_value(self: Self) !u64 {
            var buffer: [8]u8 = std.mem.zeroes([8]u8);
            const len = try self.read_fn(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val = std.mem.readInt(u64, &buffer, .big);
            return val;
        }

        /// read i8
        fn read_i8(self: Self) !i8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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
        fn read_i16(self: Self) !i16 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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
        fn read_i32(self: Self) !i32 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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
        fn read_i64(self: Self) !i64 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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

        /// read u8
        fn read_u8(self: Self) !u8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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

        /// read u16
        fn read_u16(self: Self) !u16 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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

        /// read u32
        fn read_u32(self: Self) !u32 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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
        fn read_u64(self: Self) !u64 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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

        /// read int
        pub fn read_int(self: Self) !i64 {
            return self.read_i64();
        }

        /// read uint
        pub fn read_uint(self: Self) !u64 {
            return self.read_u64();
        }

        fn read_f32_value(self: Self) !f32 {
            var buffer: [4]u8 = std.mem.zeroes([4]u8);
            const len = try self.read_fn(&buffer);
            if (len != 4) {
                return MsGPackError.LENGTH_READING;
            }
            const val_int = std.mem.readInt(u32, &buffer, .big);
            const val: f32 = @bitCast(val_int);
            return val;
        }

        fn read_f64_value(self: Self) !f64 {
            var buffer: [8]u8 = std.mem.zeroes([8]u8);
            const len = try self.read_fn(&buffer);
            if (len != 8) {
                return MsGPackError.LENGTH_READING;
            }
            const val_int = std.mem.readInt(u64, &buffer, .big);
            const val: f64 = @bitCast(val_int);
            return val;
        }

        /// read f32
        fn read_f32(self: Self) !f32 {
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
        pub fn read_float(self: Self) !f64 {
            return self.read_f64();
        }

        fn read_fix_str_value(self: Self, allocator: Allocator, marker_u8: u8) ![]const u8 {
            const len: u8 = marker_u8 - @intFromEnum(Markers.FIXSTR);
            const str = try self.read_data(allocator, len);

            return str;
        }

        fn read_str8_value(self: Self, allocator: Allocator) ![]const u8 {
            var arr: [1]u8 = std.mem.zeroes([1]u8);
            const str_len_len = try self.read_fn(&arr);

            if (str_len_len != arr.len) {
                return MsGPackError.LENGTH_READING;
            }

            const len = std.mem.readInt(u8, &arr, .big);
            const str = try self.read_data(allocator, len);

            return str;
        }

        fn read_str16_value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.read_u16_value();
            const str = try self.read_data(allocator, len);

            return str;
        }

        fn read_str32_value(self: Self, allocator: Allocator) ![]const u8 {
            const len = try self.read_u32_value();
            const str = try self.read_data(allocator, len);

            return str;
        }

        /// read str
        pub fn read_str(self: Self, allocator: Allocator) ![]const u8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);

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

        fn read_bin8_value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.read_u8_value();
            const bin = try self.read_data(allocator, len);

            return bin;
        }

        fn read_bin16_value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.read_u16_value();
            const bin = try self.read_data(allocator, len);

            return bin;
        }

        fn read_bin32_value(self: Self, allocator: Allocator) ![]u8 {
            const len = try self.read_u32_value();
            const bin = try self.read_data(allocator, len);

            return bin;
        }

        /// read bin
        pub fn read_bin(self: Self, allocator: Allocator) ![]u8 {
            const marker = try self.read_type_marker();

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

        /// read arr
        pub fn read_arr(self: Self, allocator: Allocator, comptime T: type) ![]T {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
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
            for (0..arr.len) |i| {
                const type_info = @typeInfo(T);
                switch (type_info) {
                    .Bool => {
                        arr[i] = try self.read_bool();
                    },

                    .Int => |int| {
                        const int_bits = int.bits;
                        const is_signed = if (int.signedness == .signed) true else false;

                        if (int_bits > 64) {
                            @compileError("not support bits larger than 64");
                        }
                        if (is_signed) {
                            const val = try self.read_int();
                            arr[i] = @intCast(val);
                        } else {
                            const val = try self.read_uint();
                            arr[i] = @intCast(val);
                        }
                    },
                    .Float => |float| {
                        const float_bits = float.bits;
                        if (float_bits > 64) {
                            @compileError("float larger than f64 is not supported!");
                        }

                        const val = try self.read_float();
                        arr[i] = @floatCast(val);
                    },
                    .Struct => {
                        arr[i] = try self.read_map(T);
                    },

                    else => {
                        @compileError("not support other type");
                    },
                }
            }
            return arr;
        }

        /// read map
        pub fn read_map(self: Self, comptime T: type, allocator: Allocator) !T {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            var len: usize = 0;
            const type_info = @typeInfo(T);
            if (type_info != .Struct) {
                @compileError("read map not support other type");
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
            if (map_len != struct_info.fields.len) {
                return MsGPackError.LENGTH_READING;
            }

            var res: T = undefined;

            for (0..map_len) |_| {
                const key = try self.read_str(allocator);
                defer allocator.free(key);
                inline for (struct_info.fields) |field| {
                    const field_name = field.name;
                    if (field_name.len == key.len and std.mem.eql(u8, field_name, key)) {
                        const field_type = field.type;
                        const field_type_info = @typeInfo(field_type);
                        switch (field_type_info) {
                            .Bool => {
                                const val = try self.read_bool();
                                @field(res, field_name) = val;
                            },
                            .Int => |int| {
                                const int_bits = int.bits;
                                const is_signed = if (int.signedness == .signed) true else false;

                                if (int_bits > 64) {
                                    @compileError("not support bits larger than 64");
                                }
                                if (is_signed) {
                                    const val = try self.read_int();
                                    @field(res, field_name) = @intCast(val);
                                } else {
                                    const val = try self.read_uint();
                                    @field(res, field_name) = @intCast(val);
                                }
                            },
                            .Float => |float| {
                                const float_bits = float.bits;
                                if (float_bits > 64) {
                                    @compileError("float larger than f64 is not supported!");
                                }

                                const val = try self.read_float();
                                @field(res, field_name) = @floatCast(val);
                            },
                            .Pointer => |pointer| {
                                // NOTE: whether we support other pointer ?
                                if (pointer.size == .Slice) {
                                    const ele_type = pointer.child;
                                    const arr = try self.read_arr(allocator, ele_type);
                                    @field(res, field_name) = arr;
                                } else {
                                    @compileError("not support non-slice pointer!");
                                }
                            },
                            .Struct => |ss| {
                                if (ss.is_tuple) {
                                    @compileError("not support tuple");
                                }
                                if (field_type == Str) {
                                    const str = try self.read_str(allocator);
                                    @field(res, field_name) = wrapStr(str);
                                } else if (field_type == Bin) {
                                    const bin = try self.read_bin(allocator);
                                    @field(res, field_name) = wrapBin(bin);
                                } else {
                                    const val = try self.read_map(field_type, allocator);
                                    @field(res, field_name) = val;
                                }
                            },
                            else => {
                                @compileError("type is not supported!");
                            },
                        }
                    }
                }
            }

            return res;
        }

        fn read_ext_value(self: Self, allocator: Allocator, len: usize) !EXT {
            const ext_type = try self.read_u8_value();
            const data = try self.read_data(allocator, len);
            return EXT{
                .type = ext_type,
                .data = data,
            };
        }

        pub fn read_ext(self: Self, allocator: Allocator) !EXT {
            const marker = try self.read_type_marker();
            switch (marker) {
                .FIXEXT1 => {
                    return self.read_ext_value(allocator, 1);
                },
                .FIXEXT2 => {
                    return self.read_ext_value(allocator, 2);
                },
                .FIXEXT4 => {
                    return self.read_ext_value(allocator, 4);
                },
                .FIXEXT8 => {
                    return self.read_ext_value(allocator, 8);
                },
                .FIXEXT16 => {
                    return self.read_ext_value(allocator, 16);
                },
                .EXT8 => {
                    const len = try self.read_u8_value();
                    return self.read_ext_value(allocator, len);
                },
                .EXT16 => {
                    const len = try self.read_u16_value();
                    return self.read_ext_value(allocator, len);
                },
                .EXT32 => {
                    const len = try self.read_u32_value();
                    return self.read_ext_value(allocator, len);
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }
        }

        // TODO: add read_ext and read_timestamp

        inline fn read_type_help(comptime T: type) type {
            const type_info = @typeInfo(T);
            switch (type_info) {
                .Array => |array| {
                    const child = array.child;
                    return []child;
                },
                else => {
                    return T;
                },
            }
        }

        /// read
        pub fn read(self: Self, comptime T: type, allocator: Allocator) !read_type_help(T) {
            const type_info = @typeInfo(T);
            switch (type_info) {
                .Bool => {
                    return self.read_bool();
                },
                .Int => |int| {
                    if (int.signedness) {
                        return self.read_int();
                    } else {
                        return self.read_uint();
                    }
                },
                .Float => {
                    return self.read_float();
                },
                .Array => |array| {
                    const ele_type = array.child;
                    return self.read_arr(allocator, ele_type);
                },
                .Pointer => |pointer| {
                    if (PO.to_slice(pointer)) |ele_type| {
                        return self.read_arr(allocator, ele_type);
                    } else {
                        @compileError("not support non-slice pointer!");
                    }
                },
                .Struct => {
                    return self.read_map(T, allocator);
                },
                else => {
                    @compileError("type is not supported!");
                },
            }
        }
    };
}

pub const Buffer = struct {
    arr: []u8,
    write_index: usize = 0,
    read_index: usize = 0,

    pub const ErrorSet = error{
        WRITE_LEFT_LENGTH,
        READ_LEFT_LENGTH,
    };

    pub fn write(self: *Buffer, bytes: []const u8) ErrorSet!usize {
        const index = self.write_index;
        const arr_len = self.arr.len;
        const left_len = arr_len - index;
        const bytes_len = bytes.len;

        if (left_len < bytes_len) {
            return ErrorSet.WRITE_LEFT_LENGTH;
        }

        @memcpy(self.arr[index .. index + bytes_len], bytes);
        self.write_index += bytes_len;
        return bytes_len;
    }

    pub fn set_write_index(self: *Buffer, index: usize) void {
        self.write_index = index;
    }

    pub fn get_write_index(self: *Buffer) usize {
        return self.write_index;
    }

    pub fn read(self: *Buffer, bytes: []u8) ErrorSet!usize {
        const index = self.read_index;
        const arr_len = self.arr.len;
        const left_len = arr_len - index;
        const bytes_len = bytes.len;

        if (left_len < bytes_len) {
            return ErrorSet.READ_LEFT_LENGTH;
        }

        @memcpy(bytes, self.arr[index .. index + bytes_len]);
        self.read_index += bytes_len;
        return bytes_len;
    }

    pub fn set_read_index(self: *Buffer, index: usize) void {
        self.read_index = index;
    }

    pub fn get_read_index(self: *Buffer) usize {
        return self.read_index;
    }
};

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

const EXT = struct {
    type: u8,
    data: []u8,
};
