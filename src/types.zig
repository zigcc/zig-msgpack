const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
const expect = std.testing.expect;
const native_endian = builtin.cpu.arch.endian();

const nil = struct {
    const header = 0xc0;

    fn serialize(allocator: Allocator) ![]const u8 {
        var arr = try allocator.alloc(u8, 1);
        arr[0] = header;
        return arr;
    }
};

test "nil serialize" {
    const test_allocator = std.testing.allocator;

    const arr = try nil.serialize(test_allocator);
    defer test_allocator.free(arr);

    try expect(arr.len == 1);
    try expect(arr[0] == 0xc0);
}

const boolean = struct {
    const header = 0xc2;

    const BoolParseFail = error{
        ArrLenOut,
        ValError,
    };

    fn serialize(allocator: Allocator, val: bool) ![]const u8 {
        var arr = try allocator.alloc(u8, 1);
        arr[0] = header;
        if (val) {
            arr[0] += 1;
        }
        return arr;
    }

    fn unserialize(arr: []const u8) !bool {
        if (arr.len > 1) {
            return BoolParseFail.ArrLenOut;
        }
        const v = arr[0] - header;
        if (v == 0) {
            return false;
        } else if (v == 1) {
            return true;
        }
        return BoolParseFail.ValError;
    }
};

test "bool true serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const true_arr = try boolean.serialize(test_allocator, true);
    defer test_allocator.free(true_arr);

    try expect(true_arr.len == 1);
    try expect(true_arr[0] == 0xc3);
    try expect((try boolean.unserialize(true_arr)) == true);
}

test "bool false serialize and unserialize" {
    const test_allocator = std.testing.allocator;
    const false_arr = try boolean.serialize(test_allocator, false);
    defer test_allocator.free(false_arr);

    try expect(false_arr.len == 1);
    try expect(false_arr[0] == 0xc2);
    try expect((try boolean.unserialize(false_arr)) == false);
}

const int = struct {
    const IntegerParseFail = error{
        PFixIntArrLenOut,
        NFixIntArrLenOut,

        PFixIntOutOfBound,

        U8IntLenOut,
        U16IntLenOut,
        U32IntLenOut,
        U64IntLenOut,

        U8IntTypeError,
        U16IntTypeError,
        U32IntTypeError,
        U64IntTypeError,

        I8IntLenOut,
        I16IntLenOut,
        I32IntLenOut,
        I64IntLenOut,

        I8IntTypeError,
        I16IntTypeError,
        I32IntTypeError,
        I64IntTypeError,
    };

    const positive_fix_int = struct {
        const header = 0x0;

        fn serialize(allocator: Allocator, val: u8) ![]const u8 {
            if (val >= 128) {
                return IntegerParseFail.PFixIntOutOfBound;
            }
            var arr = try allocator.alloc(u8, 1);
            arr[0] = val;
            return arr;
        }

        fn unserialize(arr: []const u8) !u8 {
            if (arr.len > 1) {
                return IntegerParseFail.PFixIntArrLenOut;
            }
            const value = arr[0];
            if (value >= 128) {
                return IntegerParseFail.PFixIntOutOfBound;
            }
            return value;
        }
    };

    const negative_fix_int = struct {
        const header = 0xe0;

        fn serialize(allocator: Allocator, val: i8) ![]const u8 {
            if (val > 0 or val <= -32) {
                return IntegerParseFail.NFixIntArrLenOut;
            }

            const value: u8 = @intCast(0 - val);
            var arr = try allocator.alloc(u8, 1);
            arr[0] = header + value;
            return arr;
        }

        fn unserialize(arr: []const u8) !i8 {
            if (arr.len > 1) {
                return IntegerParseFail.NFixIntArrLenOut;
            }
            const value: i8 = @intCast(arr[0] - header);
            const val: i8 = 0 - value;
            if (val > 0 or val <= -32) {
                return IntegerParseFail.NFixIntArrLenOut;
            }

            return val;
        }
    };

    const unsigned_8_int = struct {
        const header = 0xcc;

        fn serialize(allocator: Allocator, val: u8) ![]const u8 {
            var arr = try allocator.alloc(u8, 2);
            arr[0] = header;
            arr[1] = val;
            return arr;
        }

        fn unserialize(arr: []const u8) !u8 {
            if (arr.len != 2) {
                return IntegerParseFail.U8IntLenOut;
            }
            if (arr[0] != header) {
                return IntegerParseFail.U8IntTypeError;
            }

            return arr[1];
        }
    };

    const unsigned_16_int = struct {
        const header = 0xcd;

        fn serialize(allocator: Allocator, val: u16) ![]const u8 {
            var arr = try allocator.alloc(u8, 3);
            arr[0] = header;
            std.mem.writeInt(u16, arr[1..3], val, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !u16 {
            if (arr.len != 3) {
                return IntegerParseFail.U16IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.U16IntTypeError;
            }

            const val = std.mem.readInt(u16, arr[1..3], .big);
            return val;
        }
    };

    const unsigned_32_int = struct {
        const header = 0xce;

        fn serialize(allocator: Allocator, val: u32) ![]const u8 {
            var arr = try allocator.alloc(u8, 5);
            arr[0] = header;
            std.mem.writeInt(u32, arr[1..5], val, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !u32 {
            if (arr.len != 5) {
                return IntegerParseFail.U32IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.U32IntTypeError;
            }

            const val = std.mem.readInt(u32, arr[1..5], .big);
            return val;
        }
    };

    const unsigned_64_int = struct {
        const header = 0xcf;

        fn serialize(allocator: Allocator, val: u64) ![]const u8 {
            var arr = try allocator.alloc(u8, 9);
            arr[0] = header;
            std.mem.writeInt(u64, arr[1..9], val, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !u64 {
            if (arr.len != 9) {
                return IntegerParseFail.U64IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.U64IntTypeError;
            }

            const val = std.mem.readInt(u64, arr[1..9], .big);
            return val;
        }
    };

    const signed_8_int = struct {
        const header = 0xd0;

        fn serialize(allocator: Allocator, val: i8) ![]const u8 {
            var arr = try allocator.alloc(u8, 2);
            arr[0] = header;
            const v: u8 = @bitCast(val);
            arr[1] = v;
            return arr;
        }

        fn unserialize(arr: []const u8) !i8 {
            if (arr.len != 2) {
                return IntegerParseFail.I8IntLenOut;
            }
            if (arr[0] != header) {
                return IntegerParseFail.I8IntTypeError;
            }

            const val: i8 = @bitCast(arr[1]);
            return val;
        }
    };

    const signed_16_int = struct {
        const header = 0xd1;

        fn serialize(allocator: Allocator, val: i16) ![]const u8 {
            var arr = try allocator.alloc(u8, 3);
            arr[0] = header;
            const v: u16 = @bitCast(val);

            std.mem.writeInt(u16, arr[1..3], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !i16 {
            if (arr.len != 3) {
                return IntegerParseFail.I16IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.I16IntTypeError;
            }

            const v = std.mem.readInt(u16, arr[1..3], .big);
            const val: i16 = @bitCast(v);

            return val;
        }
    };

    const signed_32_int = struct {
        const header = 0xd2;

        fn serialize(allocator: Allocator, val: i32) ![]const u8 {
            var arr = try allocator.alloc(u8, 5);
            arr[0] = header;
            const v: u32 = @bitCast(val);

            std.mem.writeInt(u32, arr[1..5], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !i32 {
            if (arr.len != 5) {
                return IntegerParseFail.I32IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.I32IntTypeError;
            }

            const v = std.mem.readInt(u32, arr[1..5], .big);
            const val: i32 = @bitCast(v);

            return val;
        }
    };

    const signed_64_int = struct {
        const header = 0xd3;

        fn serialize(allocator: Allocator, val: i64) ![]const u8 {
            var arr = try allocator.alloc(u8, 9);
            arr[0] = header;
            const v: u64 = @bitCast(val);

            std.mem.writeInt(u64, arr[1..9], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !i64 {
            if (arr.len != 9) {
                return IntegerParseFail.I64IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.I64IntTypeError;
            }

            const v = std.mem.readInt(u64, arr[1..9], .big);
            const val: i64 = @bitCast(v);

            return val;
        }
    };
};

// TODO: add integer test
test "positive fix integer" {
    const test_allocator = std.testing.allocator;

    const n: u8 = 8;
    const arr = try int.positive_fix_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 1);
    try expect(0x0 < arr[0] and arr[0] < 0x7f);
    try expect((try int.positive_fix_int.unserialize(arr)) == n);
}

test "negative fix integer" {
    const test_allocator = std.testing.allocator;

    const n: i8 = -10;
    const arr = try int.negative_fix_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 1);
    try expect(0xe0 < arr[0] and arr[0] < 0xff);
    try expect((try int.negative_fix_int.unserialize(arr)) == n);
}

test "unsigned 8 int" {
    const test_allocator = std.testing.allocator;

    const n: u8 = 42;
    const arr = try int.unsigned_8_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 2);
    try expect(arr[0] == 0xcc);
    try expect((try int.unsigned_8_int.unserialize(arr)) == n);
}

test "unsigned 16 int" {
    const test_allocator = std.testing.allocator;

    const n: u16 = 666;
    const arr = try int.unsigned_16_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 3);
    try expect(arr[0] == 0xcd);
    try expect((try int.unsigned_16_int.unserialize(arr)) == n);
}

test "unsigned 32 int" {
    const test_allocator = std.testing.allocator;

    const n: u32 = 65536;
    const arr = try int.unsigned_32_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 5);
    try expect(arr[0] == 0xce);
    try expect((try int.unsigned_32_int.unserialize(arr)) == n);
}

test "unsigned 64 int" {
    const test_allocator = std.testing.allocator;

    const n: u64 = 4294967296;
    const arr = try int.unsigned_64_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 9);
    try expect(arr[0] == 0xcf);
    try expect((try int.unsigned_64_int.unserialize(arr)) == n);
}

test "signed 8 int" {
    const test_allocator = std.testing.allocator;

    const n: i8 = -10;
    const arr = try int.signed_8_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 2);
    try expect(arr[0] == 0xd0);
    try expect((try int.signed_8_int.unserialize(arr)) == n);
}

test "signed 16 int" {
    const test_allocator = std.testing.allocator;

    const n: i16 = -666;
    const arr = try int.signed_16_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 3);
    try expect(arr[0] == 0xd1);
    try expect((try int.signed_16_int.unserialize(arr)) == n);
}

test "signed 32 int" {
    const test_allocator = std.testing.allocator;

    const n: i32 = -65536;
    const arr = try int.signed_32_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 5);
    try expect(arr[0] == 0xd2);
    try expect((try int.signed_32_int.unserialize(arr)) == n);
}

test "signed 64 int" {
    const test_allocator = std.testing.allocator;

    const n: i64 = -4294967296;
    const arr = try int.signed_64_int.serialize(test_allocator, n);
    defer test_allocator.free(arr);

    try expect(arr.len == 9);
    try expect(arr[0] == 0xd3);
    try expect((try int.signed_64_int.unserialize(arr)) == n);
}

const float = struct {
    const FloatParseFail = error{
        F32LenOut,
        F32TypeError,
        F64LenOut,
        F64TypeError,
    };

    const single_precision_float = struct {
        const header = 0xca;

        fn serialize(allocator: Allocator, val: f32) ![]const u8 {
            var arr = try allocator.alloc(u8, 5);
            arr[0] = header;
            const v: u32 = @bitCast(val);

            std.mem.writeInt(u32, arr[1..5], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !f32 {
            if (arr.len != 5) {
                return FloatParseFail.F32LenOut;
            }

            if (arr[0] != header) {
                return FloatParseFail.F32TypeError;
            }

            const v = std.mem.readInt(u32, arr[1..5], .big);
            const val: f32 = @bitCast(v);

            return val;
        }
    };

    const double_precision_float = struct {
        const header = 0xcb;

        fn serialize(allocator: Allocator, val: f64) ![]const u8 {
            var arr = try allocator.alloc(u8, 9);
            arr[0] = header;
            const v: u64 = @bitCast(val);

            std.mem.writeInt(u64, arr[1..9], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !f64 {
            if (arr.len != 9) {
                return FloatParseFail.F64LenOut;
            }

            if (arr[0] != header) {
                return FloatParseFail.F64TypeError;
            }

            const v = std.mem.readInt(u64, arr[1..9], .big);
            const val: f64 = @bitCast(v);

            return val;
        }
    };
};

test "float 32 serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const float_32: f32 = 3.14;
    const f32_arr = try float.single_precision_float.serialize(test_allocator, float_32);
    defer test_allocator.free(f32_arr);

    try expect(f32_arr.len == 5);
    try expect(f32_arr[0] == 0xca);
    try expect((try float.single_precision_float.unserialize(f32_arr)) == float_32);
}

test "float 64 serialize and unserialiaze" {
    const test_allocator = std.testing.allocator;

    const float_64: f64 = 3.141592653589793;
    const f64_arr = try float.double_precision_float.serialize(test_allocator, float_64);
    defer test_allocator.free(f64_arr);

    try expect(f64_arr.len == 9);
    try expect(f64_arr[0] == 0xcb);
    try expect((try float.double_precision_float.unserialize(f64_arr)) == float_64);
}

const string = struct {
    const StrParseFail = error{
        FStrLenOut,
        FStrLenLess,
        FStrTypeError,
        U8StrLenOut,
        U8StrLenLess,
        U8StrTypeError,
        U16StrLenOut,
        U16StrLenLess,
        U16StrTypeError,
        U32StrLenOut,
        U32StrLenLess,
        U32StrTypeError,
    };

    const fix_str = struct {
        const header = 0xa0;

        fn serialize(allocator: Allocator, val: []const u8) ![]const u8 {
            if (val.len > std.math.maxInt(u5)) {
                return StrParseFail.FStrLenOut;
            }
            var arr = try allocator.alloc(u8, val.len + 1);
            arr[0] = @intCast(header + val.len);

            @memcpy(arr[1..], val);

            return arr;
        }

        fn len(arr: []const u8) !u8 {
            if (arr.len == 0) {
                return StrParseFail.FStrLenLess;
            }
            const str_len = arr[0] - header;
            return str_len;
        }

        fn unserialize(allocator: Allocator, arr: []const u8) ![]const u8 {
            const str_len = try len(arr);
            const arr_len = arr.len;

            if (str_len >= header) {
                return StrParseFail.FStrTypeError;
            }
            if (str_len != arr_len - 1) {
                return StrParseFail.FStrLenOut;
            }

            const str = try allocator.alloc(u8, str_len);

            @memcpy(str, arr[1..]);

            return str;
        }
    };

    const u8_str = struct {
        const header = 0xd9;

        fn serialize(allocator: Allocator, val: []const u8) ![]const u8 {
            if (val.len <= std.math.maxInt(u5) or val.len > std.math.maxInt(u8)) {
                return StrParseFail.U8StrLenOut;
            }
            var arr = try allocator.alloc(u8, val.len + 2);
            arr[0] = header;
            arr[1] = @intCast(val.len);

            @memcpy(arr[2..], val);

            return arr;
        }

        fn len(arr: []const u8) !u8 {
            if (arr.len >= 2) {
                return arr[1];
            }
            return StrParseFail.U8StrLenLess;
        }

        fn unserialize(allocator: Allocator, arr: []const u8) ![]const u8 {
            const str_len = try len(arr);
            const arr_len = arr.len;

            if (arr[0] != header) {
                return StrParseFail.U8StrTypeError;
            }

            if (str_len != arr_len - 2) {
                return StrParseFail.U8StrLenOut;
            }

            const str = try allocator.alloc(u8, str_len);

            @memcpy(str, arr[2..]);

            return str;
        }
    };

    const u16_str = struct {
        const header = 0xda;

        fn serialize(allocator: Allocator, val: []const u8) ![]const u8 {
            if (val.len <= std.math.maxInt(u8) or val.len > std.math.maxInt(u16)) {
                return StrParseFail.U16StrLenOut;
            }
            var arr = try allocator.alloc(u8, val.len + 3);

            arr[0] = header;
            std.mem.writeInt(u16, arr[1..3], @intCast(val.len), .big);

            @memcpy(arr[3..], val);

            return arr;
        }

        fn len(arr: []const u8) !u16 {
            if (arr.len >= 3) {
                return std.mem.readInt(u16, arr[1..3], .big);
            }
            return StrParseFail.U16StrLenLess;
        }

        fn unserialize(allocator: Allocator, arr: []const u8) ![]const u8 {
            const str_len = try len(arr);
            const arr_len = arr.len;

            if (arr[0] != header) {
                return StrParseFail.U16StrTypeError;
            }

            if (str_len != arr_len - 3) {
                return StrParseFail.U16StrLenOut;
            }

            const str = try allocator.alloc(u8, str_len);

            @memcpy(str, arr[3..]);

            return str;
        }
    };

    const u32_str = struct {
        const header = 0xdb;

        fn serialize(allocator: Allocator, val: []const u8) ![]const u8 {
            if (val.len <= std.math.maxInt(u16) or val.len > std.math.maxInt(u32)) {
                return StrParseFail.U32StrLenOut;
            }
            var arr = try allocator.alloc(u8, val.len + 5);

            arr[0] = header;
            std.mem.writeInt(u32, arr[1..5], @intCast(val.len), .big);

            @memcpy(arr[5..], val);

            return arr;
        }

        fn len(arr: []const u8) !u32 {
            if (arr.len >= 5) {
                return std.mem.readInt(u32, arr[1..5], .big);
            }
            return StrParseFail.U32StrLenLess;
        }

        fn unserialize(allocator: Allocator, arr: []const u8) ![]const u8 {
            const str_len = try len(arr);
            const arr_len = arr.len;

            if (arr[0] != header) {
                return StrParseFail.U32StrTypeError;
            }

            if (str_len != arr_len - 5) {
                return StrParseFail.U32StrLenOut;
            }

            const str = try allocator.alloc(u8, str_len);

            @memcpy(str, arr[5..]);

            return str;
        }
    };
};

test "fix str serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const str = "Hello, world!";
    const fix_str = try string.fix_str.serialize(test_allocator, str);
    defer test_allocator.free(fix_str);

    try expect(try string.fix_str.len(fix_str) == str.len);
    try expect(fix_str[0] - try string.fix_str.len(fix_str) == 0xa0);
    const new_str = try string.fix_str.unserialize(test_allocator, fix_str);
    defer test_allocator.free(new_str);
    try expect(std.mem.eql(u8, new_str, str));
}

test "u8 str serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const str = "This is a string that is more than 32 bytes long.";
    const u8_str = try string.u8_str.serialize(test_allocator, str);
    defer test_allocator.free(u8_str);

    try expect(try string.u8_str.len(u8_str) == str.len);
    try expect(u8_str[0] == 0xd9);

    const new_str = try string.u8_str.unserialize(test_allocator, u8_str);
    defer test_allocator.free(new_str);
    try expect(std.mem.eql(u8, new_str, str));
}

test "u16 str serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const str = "When the zig test tool is building a test runner, only resolved test declarations are included in the build. Initially, only the given Zig source file's top-level declarations are resolved. Unless nested containers are referenced from a top-level test declaration, nested container tests will not be resolved.";
    const u16_str = try string.u16_str.serialize(test_allocator, str);
    defer test_allocator.free(u16_str);

    try expect(try string.u16_str.len(u16_str) == str.len);
    try expect(u16_str[0] == 0xda);

    const new_str = try string.u16_str.unserialize(test_allocator, u16_str);
    defer test_allocator.free(new_str);
    try expect(std.mem.eql(u8, new_str, str));
}

test "u32 str serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const default_str = "When the zig test tool is building a test runner, only resolved test declarations are included in the build. Initially, only the given Zig source file's top-level declarations are resolved. Unless nested containers are referenced from a top-level test declaration, nested container tests will not be resolved.";
    const strr = @as([309:0]u8, default_str.*) ** 255;
    const str = &strr;
    const u32_str = try string.u32_str.serialize(test_allocator, str);
    defer test_allocator.free(u32_str);

    try expect(try string.u32_str.len(u32_str) == str.len);
    try expect(u32_str[0] == 0xdb);

    const new_str = try string.u32_str.unserialize(test_allocator, u32_str);
    defer test_allocator.free(new_str);
    try expect(std.mem.eql(u8, new_str, str));
}
