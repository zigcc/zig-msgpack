const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const native_endian = builtin.cpu.arch.endian();

const Markers = enum(u8) {
    POSITIVE_FIXINT = 0x00,
    FIXMAP = 0x80,
    FixArray = 0x90,
    FIXSTR = 0xa0,
    NIL = 0xc0,
    FALSE = 0xc2,
    TRUE = 0xc3,
    BIN8 = 0xc4,
    Bin16 = 0xc5,
    Bin32 = 0xc6,
    EXT8 = 0xc7,
    EXT16 = 0xc8,
    EXT32 = 0xc9,
    FLOAT32 = 0xca,
    FLOAT64 = 0xcb,
    DOUBLE = 0xcb,
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

const MsGPackError = error{
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
    INVALID_TYPE,
    LENGTH_READING,
    LENGTH_WRITING,
    INTERNAL,
};

pub fn MsgPack(
    comptime Context: type,
    comptime ErrorSet: type,
    comptime writeFn: fn (context: Context, bytes: []const u8) ErrorSet!usize,
    comptime readFn: fn (context: Context, bytes: []u8) ErrorSet!usize,
) type {
    return struct {
        context: Context,

        const Self = @This();

        pub const Error = ErrorSet;

        pub fn init(context: Context) Self {
            return Self{
                .context = context,
            };
        }

        // wrap for writeFn
        fn write_fn(self: Self, bytes: []const u8) ErrorSet!usize {
            return writeFn(self.context, bytes);
        }

        // write one byte
        fn write_byte(self: Self, byte: u8) !void {
            const bytes = [_]u8{byte};
            const len = try self.write_fn(&bytes);
            if (len != 1) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write type marker
        fn write_type_marker(self: Self, comptime marker: Markers) !void {
            switch (marker) {
                .POSITIVE_FIXINT, .FIXMAP, .FixArray, .FIXSTR, .NEGATIVE_FIXINT => {
                    @compileError("wrong marker was used");
                },
                else => {},
            }
            try self.write_byte(@intFromEnum(marker));
        }

        // write nil
        pub fn write_nil(self: Self) !void {
            try self.write_type_marker(Markers.NIL);
        }

        // write true
        fn write_true(self: Self) !void {
            try self.write_type_marker(Markers.TRUE);
        }

        // write false
        fn write_false(self: Self) !void {
            try self.write_type_marker(Markers.FALSE);
        }

        // write bool
        pub fn write_bool(self: Self, val: bool) !void {
            if (val) {
                try self.write_true();
            } else {
                try self.write_false();
            }
        }

        // write positive fix int
        fn write_pfix_int(self: Self, val: u8) !void {
            if (val <= 0x7f) {
                try self.write_byte(val);
            }
            return MsGPackError.INPUT_VALUE_TOO_LARGE;
        }

        // write u8 int
        fn write_u8(self: Self, val: u8) !void {
            try self.write_type_marker(.UINT8);
            try self.write_byte(val);
        }

        // write u16 int
        fn write_u16(self: Self, val: u16) !void {
            try self.write_type_marker(.UINT16);
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, val, .big);

            const len = try self.write_fn(&arr);
            if (len != 2) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write u32 int
        fn write_u32(self: Self, val: u32) !void {
            try self.write_type_marker(.UINT32);
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, val, .big);

            const len = try self.write_fn(&arr);
            if (len != 4) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write u64 int
        fn write_u64(self: Self, val: u64) !void {
            try self.write_type_marker(.UINT64);
            var arr: [8]u8 = std.mem.zeroes([8]u8);
            std.mem.writeInt(u64, &arr, val, .big);

            const len = try self.write_fn(&arr);
            if (len != 8) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write negative fix int
        fn write_nfix_int(self: Self, val: i8) !void {
            if (val >= -32 and val <= -1) {
                try self.write_byte(@bitCast(val));
            }
            return MsGPackError.INPUT_VALUE_TOO_LARGE;
        }

        // write i8 int
        fn write_i8(self: Self, val: i8) !void {
            try self.write_type_marker(.INT8);
            try self.write_byte(@bitCast(val));
        }

        // write i16 int
        fn write_i16(self: Self, val: i16) !void {
            try self.write_type_marker(.INT16);
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(i16, &arr, val, .big);

            const len = try self.write_fn(&arr);
            if (len != 2) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write i32 int
        fn write_i32(self: Self, val: i32) !void {
            try self.write_type_marker(.INT32);
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(i32, &arr, val, .big);

            const len = try self.write_fn(&arr);
            if (len != 4) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write i64 int
        fn write_i64(self: Self, val: i64) !void {
            try self.write_type_marker(.INT64);
            var arr: [8]u8 = std.mem.zeroes([8]u8);
            std.mem.writeInt(i64, &arr, val, .big);

            const len = try self.write_fn(&arr);
            if (len != 8) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write uint
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

        // write int
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

        // write f32
        pub fn write_f32(self: Self, val: f32) !void {
            try self.write_type_marker(.FLOAT32);
            const int: u32 = @bitCast(val);
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, int, .big);
            const len = try self.write_fn(&arr);
            if (len != 4) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write f64
        pub fn write_f64(self: Self, val: f64) !void {
            try self.write_type_marker(.FLOAT64);
            const int: u64 = @bitCast(val);
            var arr: [8]u8 = std.mem.zeroes([8]u8);
            std.mem.writeInt(u64, &arr, int, .big);
            const len = try self.write_fn(&arr);
            if (len != 8) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write fix str
        fn write_fix_str(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0x1f) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }
            const header: u8 = @intFromEnum(Markers.FIXSTR) + len;
            try self.write_byte(header);

            const write_len = try self.write_fn(str);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        // write str8
        fn write_str8(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.STR8);

            const str_len: u8 = @intCast(len);
            var arr: [1]u8 = std.mem.zeroes([1]u8);
            std.mem.writeInt(u8, &arr, str_len, .big);

            const write_len_len = try self.write_fn(&arr);
            if (write_len_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            const write_len = try self.write_fn(str);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        fn write_str16(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xffff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.STR16);

            const str_len: u16 = @intCast(len);
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, str_len, .big);

            const write_len_len = try self.write_fn(&arr);
            if (write_len_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            const write_len = try self.write_fn(str);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        fn write_str32(self: Self, str: []const u8) !void {
            const len = str.len;
            if (len > 0xffff_ffff) {
                return MsGPackError.STR_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.STR32);

            const str_len: u32 = @intCast(len);
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, str_len, .big);

            const write_len_len = try self.write_fn(&arr);
            if (write_len_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            const write_len = try self.write_fn(str);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

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

        fn write_bin8(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.BIN8);

            const bin_len: u8 = @intCast(len);
            var arr: [1]u8 = std.mem.zeroes([1]u8);
            std.mem.writeInt(u8, &arr, bin_len, .big);

            const write_len_len = try self.write_fn(&arr);
            if (write_len_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            const write_len = try self.write_fn(bin);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        fn write_bin16(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xffff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.Bin16);

            const bin_len: u16 = @intCast(len);
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, bin_len, .big);

            const write_len_len = try self.write_fn(&arr);
            if (write_len_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            const write_len = try self.write_fn(bin);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

        fn write_bin32(self: Self, bin: []const u8) !void {
            const len = bin.len;
            if (len > 0xffff_ffff) {
                return MsGPackError.BIN_DATA_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.Bin32);

            const bin_len: u32 = @intCast(len);
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, bin_len, .big);

            const write_len_len = try self.write_fn(&arr);
            if (write_len_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            const write_len = try self.write_fn(bin);
            if (write_len != len) {
                return MsGPackError.LENGTH_WRITING;
            }
        }

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

        fn write_arr_value(self: Self, T: type, val: []T) !void {
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

                    if (float_bits <= 32) {
                        for (val) |value| {
                            try self.write_f32(value);
                        }
                    } else if (float_bits <= 64) {
                        for (val) |value| {
                            try self.write_f64(value);
                        }
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

        fn write_fix_arr(self: Self, T: type, val: []T) !void {
            const arr_len = val.len;
            const max_len = 0xf;

            if (arr_len > max_len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            // write marker
            const header: u8 = @intFromEnum(Markers.FixArray) + @as(u8, @intCast(arr_len));
            try self.write_byte(header);

            // try to write arr value
            try self.write_arr_value(T, val);
        }

        fn write_arr16(self: Self, T: type, val: []T) !void {
            const arr_len = val.len;
            const max_len = 0xffff;

            if (arr_len > max_len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            try self.write_type_marker(.ARRAY16);

            // try to write len
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, @intCast(arr_len), .big);

            const write_len = try self.write_fn(&arr);
            if (write_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            // try to write arr value
            try self.write_arr_value(T, val);
        }

        fn write_arr32(self: Self, T: type, val: []T) !void {
            const arr_len = val.len;
            const max_len = 0xffff_ffff;

            if (arr_len > max_len) {
                return MsGPackError.ARRAY_LENGTH_TOO_LONG;
            }

            // try to write marker
            try self.write_type_marker(.ARRAY32);

            // try to write len
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, @intCast(arr_len), .big);

            const write_len = try self.write_fn(&arr);
            if (write_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            // try to write arr value
            try self.write_arr_value(T, val);
        }

        pub fn write_arr(self: Self, T: type, val: []T) !void {
            const len = val.len;
            if (len <= 0xf) {
                try self.write_fix_arr(T, val);
            } else if (len <= 0xffff) {
                try self.write_arr16(T, val);
            } else {
                try self.write_arr32(T, val);
            }
        }

        fn write_map_value(self: Self, T: type, val: T, len: usize) !void {
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

                        if (float_bits <= 32) {
                            try self.write_f32(field_value);
                        } else if (float_bits <= 64) {
                            try self.write_f64(field_value);
                        }
                    },
                    .Struct => {
                        try self.write_map(field_type, field_value);
                    },
                    else => {
                        @compileError("type is not supported!");
                    },
                    // TODO: other type
                    // arrary optional pointer
                }
            }
        }

        fn write_fixmap(self: Self, T: type, val: T) !void {
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
            try self.write_byte(header);

            // try to write map value
            try self.write_map_value(T, val, max_len);
        }

        fn write_map16(self: Self, T: type, val: T) !void {
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
            const map_len = fields_len * 2;
            var arr: [2]u8 = std.mem.zeroes([2]u8);
            std.mem.writeInt(u16, &arr, @intCast(map_len), .big);

            const write_len = try self.write_fn(&arr);
            if (write_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            // try to write map value
            try self.write_map_value(T, val, max_len);
        }

        fn write_map32(self: Self, T: type, val: T) !void {
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
            const map_len = fields_len * 2;
            var arr: [4]u8 = std.mem.zeroes([4]u8);
            std.mem.writeInt(u32, &arr, @intCast(map_len), .big);

            const write_len = try self.write_fn(&arr);
            if (write_len != arr.len) {
                return MsGPackError.LENGTH_WRITING;
            }

            // try to write map value
            try self.write_map_value(T, val, max_len);
        }

        pub fn write_map(self: Self, T: type, val: T) !void {
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

        // fn write_fix_ext1(self: Self, type: u8, val: []const u8) !void {}
        // fn write_fix_ext2(self: Self, type: u8, val: []const u8) !void {}
        // fn write_fix_ext4(self: Self, type: u8, val: []const u8) !void {}
        // fn write_fix_ext8(self: Self, type: u8, val: []const u8) !void {}
        // fn write_fix_ext16(self: Self, type: u8, val: []const u8) !void {}
        //
        // fn write_ext8(self: Self, type: u8, val: []const u8) !void {}
        // fn write_ext16(self: Self, type: u8, val: []const u8) !void {}
        // fn write_ext17(self: Self, type: u8, val: []const u8) !void {}
        //
        // pub fn write_ext(self: Self, type: u8, val: []const u8) !void {}

        // TODO: add timestamp

        // read

        fn read_fn(self: Self, bytes: []u8) ErrorSet!usize {
            return readFn(self.context, bytes);
        }

        fn read_byte(self: Self) !u8 {
            var res = [1]u8{0};
            try readFn(self.context, &res);
        }

        fn read_type_marker_u8(self: Self) !u8 {
            const val = try self.read_byte();
            return val;
        }

        fn marker_u8_to(_: Self, marker_u8: u8) !Markers {
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

        fn read_type_marker(self: Self) !Markers {
            const val = try self.read_type_marker_u8();
            return try self.marker_u8_to(val);
        }

        pub fn read_nil(self: Self) !void {
            const marker = try self.read_type_marker();
            if (marker != .NIL) {
                return MsGPackError.TYPE_MARKER_READING;
            }
        }

        pub fn read_bool(self: Self) !bool {
            const marker = try self.read_type_marker();
            switch (marker) {
                .TRUE => return true,
                .FALSE => return false,
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_i8(self: Self) !i8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    return @bitCast(marker_u8);
                },
                .INT8 => {
                    const val = try self.read_byte();
                    return @bitCast(val);
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    if (val <= 127) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_i16(self: Self) !i16 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .INT8, .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val: i8 = @bitCast(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    return @as(i8, @bitCast(val));
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i16, &buffer, .big);
                    return val;
                },
                .UINT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u16, &buffer, .big);
                    if (val <= 32767) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_i32(self: Self) !i32 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .INT8, .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val: i8 = @bitCast(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    return @as(i8, @bitCast(val));
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i16, &buffer, .big);
                    return val;
                },
                .UINT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u16, &buffer, .big);
                    return val;
                },
                .Int32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i32, &buffer, .big);
                    return val;
                },
                .UINT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u32, &buffer, .big);
                    if (val <= 2147483647) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_i64(self: Self) !i64 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .INT8, .NEGATIVE_FIXINT, .POSITIVE_FIXINT => {
                    const val: i8 = @bitCast(marker_u8);
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    return @as(i8, @bitCast(val));
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i16, &buffer, .big);
                    return val;
                },
                .UINT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u16, &buffer, .big);
                    return val;
                },
                .Int32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i32, &buffer, .big);
                    return val;
                },
                .UINT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u32, &buffer, .big);
                    return val;
                },
                .Int64 => {
                    var buffer: [8]u8 = std.mem.zeroes([8]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 8) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i64, &buffer, .big);
                    return val;
                },
                .UINT64 => {
                    var buffer: [8]u8 = std.mem.zeroes([8]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 8) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u64, &buffer, .big);
                    if (val <= 9223372036854775807) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_u8(self: Self) !u8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    const ival: i8 = @bitCast(val);
                    if (ival >= 0) {
                        return @intCast(ival);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_u16(self: Self) !u16 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    const ival: i8 = @bitCast(val);
                    if (ival >= 0) {
                        return @intCast(ival);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u16, &buffer, .big);
                    return val;
                },
                .INT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i16, &buffer, .big);
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_u32(self: Self) !u32 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    const ival: i8 = @bitCast(val);
                    if (ival >= 0) {
                        return @intCast(ival);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u16, &buffer, .big);
                    return val;
                },
                .INT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i16, &buffer, .big);
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u32, &buffer, .big);
                    return val;
                },
                .INT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i32, &buffer, .big);
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_u64(self: Self) !u64 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            switch (marker) {
                .POSITIVE_FIXINT => {
                    return marker_u8;
                },
                .UINT8 => {
                    const val = try self.read_byte();
                    return val;
                },
                .INT8 => {
                    const val = try self.read_byte();
                    const ival: i8 = @bitCast(val);
                    if (ival >= 0) {
                        return @intCast(ival);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u16, &buffer, .big);
                    return val;
                },
                .INT16 => {
                    var buffer: [2]u8 = std.mem.zeroes([2]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 2) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i16, &buffer, .big);
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u32, &buffer, .big);
                    return val;
                },
                .INT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(i32, &buffer, .big);
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                .UINT64 => {
                    var buffer: [8]u8 = std.mem.zeroes([8]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 8) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u64, &buffer, .big);
                    return val;
                },
                .INT64 => {
                    var buffer: [8]u8 = std.mem.zeroes([8]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 8) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val = std.mem.readInt(u64, &buffer, .big);
                    if (val >= 0) {
                        return @intCast(val);
                    }
                    return MsGPackError.INVALID_TYPE;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_f32(self: Self) !f32 {
            const marker = try self.read_type_marker();
            switch (marker) {
                .FLOAT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val_int = std.mem.readInt(u32, &buffer, .big);
                    const val: f32 = @bitCast(val_int);
                    return val;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }
        pub fn read_f64(self: Self) !f64 {
            const marker = try self.read_type_marker();
            switch (marker) {
                .FLOAT32 => {
                    var buffer: [4]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 4) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val_int = std.mem.readInt(u32, &buffer, .big);
                    const val: f32 = @bitCast(val_int);
                    return val;
                },
                .FLOAT64 => {
                    var buffer: [8]u8 = std.mem.zeroes([4]u8);
                    const len = try self.read_fn(&buffer);
                    if (len != 8) {
                        return MsGPackError.LENGTH_READING;
                    }
                    const val_int = std.mem.readInt(u64, &buffer, .big);
                    const val: f64 = @bitCast(val_int);
                    return val;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_str(self: Self, allocator: Allocator) ![]const u8 {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);

            switch (marker) {
                .FIXSTR => {
                    const len: u8 = marker_u8 - @intFromEnum(Markers.FIXSTR);

                    const str = try allocator.alloc(u8, len);
                    const str_len = try self.read_fn(str);

                    if (str_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return str;
                },
                .STR8 => {
                    var arr: [1]u8 = std.mem.zeroes([1]u8);
                    const str_len_len = try self.read_fn(&arr);

                    if (str_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    const len = std.mem.readInt(u8, &arr, .big);

                    const str = try allocator.alloc(u8, len);
                    const str_len = try self.read_fn(str);

                    if (str_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return str;
                },
                .STR16 => {
                    var arr: [2]u8 = std.mem.zeroes([2]u8);
                    const str_len_len = try self.read_fn(&arr);

                    if (str_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    const len = std.mem.readInt(u16, &arr, .big);

                    const str = try allocator.alloc(u8, len);
                    const str_len = try self.read_fn(str);

                    if (str_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return str;
                },
                .STR32 => {
                    var arr: [4]u8 = std.mem.zeroes([4]u8);
                    const str_len_len = try self.read_fn(&arr);

                    if (str_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    const len = std.mem.readInt(u32, &arr, .big);

                    const str = try allocator.alloc(u8, len);
                    const str_len = try self.read_fn(str);

                    if (str_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return str;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_bin(self: Self, allocator: Allocator) ![]const u8 {
            const marker = try self.read_type_marker();

            switch (marker) {
                .BIN8 => {
                    var arr: [1]u8 = std.mem.zeroes([1]u8);
                    const bin_len_len = try self.read_fn(&arr);

                    if (bin_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    const len = std.mem.readInt(u8, &arr, .big);

                    const bin = try allocator.alloc(u8, len);
                    const bin_len = try self.read_fn(bin);

                    if (bin_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return bin;
                },
                .BIN16 => {
                    var arr: [2]u8 = std.mem.zeroes([2]u8);
                    const bin_len_len = try self.read_fn(&arr);

                    if (bin_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    const len = std.mem.readInt(u16, &arr, .big);

                    const bin = try allocator.alloc(u8, len);
                    const bin_len = try self.read_fn(bin);

                    if (bin_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return bin;
                },
                .BIN32 => {
                    var arr: [4]u8 = std.mem.zeroes([4]u8);
                    const bin_len_len = try self.read_fn(&arr);

                    if (bin_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    const len = std.mem.readInt(u32, &arr, .big);

                    const bin = try allocator.alloc(u8, len);
                    const bin_len = try self.read_fn(bin);

                    if (bin_len != len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    return bin;
                },
                else => return MsGPackError.TYPE_MARKER_READING,
            }
        }

        pub fn read_arr(self: Self, allocator: Allocator, T: type) ![]T {
            const marker_u8 = try self.read_type_marker_u8();
            const marker = try self.marker_u8_to(marker_u8);
            var len: usize = 0;
            switch (marker) {
                .FIXMAP => {
                    len = marker_u8 - 0x90;
                },
                .MAP16 => {
                    var arr: [2]u8 = std.mem.zeroes([2]u8);
                    const map_len_len = try self.read_fn(&arr);

                    if (map_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    len = std.mem.readInt(u16, &arr, .big);
                },
                .MAP32 => {
                    var arr: [4]u8 = std.mem.zeroes([4]u8);
                    const map_len_len = try self.read_fn(&arr);

                    if (map_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    len = std.mem.readInt(u32, &arr, .big);
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
                            const val = try self.read_i64();
                            arr[i] = @intCast(val);
                        } else {
                            const val = try self.read_u64();
                            arr[i] = @intCast(val);
                        }
                    },
                    .Float => |float| {
                        const float_bits = float.bits;
                        if (float_bits > 64) {
                            @compileError("float larger than f64 is not supported!");
                        }

                        const val = try self.read_f64();
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
        }

        pub fn read_map(self: Self, T: type) !T {
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
                    len = marker_u8 - 0x80;
                },
                .MAP16 => {
                    var arr: [2]u8 = std.mem.zeroes([2]u8);
                    const map_len_len = try self.read_fn(&arr);

                    if (map_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    len = std.mem.readInt(u16, &arr, .big);
                },
                .MAP32 => {
                    var arr: [4]u8 = std.mem.zeroes([4]u8);
                    const map_len_len = try self.read_fn(&arr);

                    if (map_len_len != arr.len) {
                        return MsGPackError.LENGTH_READING;
                    }

                    len = std.mem.readInt(u32, &arr, .big);
                },
                else => {
                    return MsGPackError.INVALID_TYPE;
                },
            }

            const map_len = len / 2;
            if (map_len != struct_info.fields.len) {
                return MsGPackError.LENGTH_READING;
            }
            var res: T = undefined;
            for (struct_info.fields) |field| {
                const field_type = field.type;
                const field_type_info = @typeInfo(field_type);
                const field_name = field.name;
                switch (field_type_info) {
                    .Null => {
                        @field(res, field_name) = null;
                    },
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
                            const val = try self.read_i64();
                            @field(res, field_name) = @intCast(val);
                        } else {
                            const val = try self.read_u64();
                            @field(res, field_name) = @intCast(val);
                        }
                    },
                    .Float => |float| {
                        const float_bits = float.bits;
                        if (float_bits > 64) {
                            @compileError("float larger than f64 is not supported!");
                        }

                        const val = try self.read_f64();
                        @field(res, field_name) = @floatCast(val);
                    },
                    .Struct => |ss| {
                        if (ss.is_tuple) {
                            @compileError("not support tuple");
                        }
                        const val = try self.read_map(field_type);
                        @field(res, field_name) = val;
                    },
                    else => {
                        @compileError("type is not supported!");
                    },
                }
            }

            return res;
        }

        // TODO: add read_ext and read_timestamp
    };
}
