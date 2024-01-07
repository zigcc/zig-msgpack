const std = @import("std");
const Allocator = std.mem.Allocator;
const expect = std.testing.expect;

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

test "bool serialize and unserialize" {
    const test_allocator = std.testing.allocator;

    const true_arr = try boolean.serialize(test_allocator, true);
    defer test_allocator.free(true_arr);

    try expect(true_arr.len == 1);
    try expect(true_arr[0] == 0xc3);
    try expect((try boolean.unserialize(true_arr)) == true);

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

            const value: u8 = 0 - val;
            var arr = try allocator.alloc(u8, 1);
            arr[0] = header | value;
            return arr;
        }

        fn unserialize(arr: []const u8) !i8 {
            if (arr.len > 1) {
                return IntegerParseFail.NFixIntOutOfBound;
            }
            const value = arr[0] - header;

            return 0 - value;
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
            var arr = try allocator.alloc(u32, 5);
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

            const val = std.mem.readInt(u64, arr[0..9], .big);
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

            const val: i8 = @intCast(arr[1]);
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

            std.mem.writeInt(u32, arr[1..], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !i32 {
            if (arr.len != 5) {
                return IntegerParseFail.I32IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.I32IntTypeError;
            }

            const v = std.mem.readInt(u32, arr[1..], .big);
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

            std.mem.writeInt(u64, arr[1..], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !i64 {
            if (arr.len != 9) {
                return IntegerParseFail.I64IntLenOut;
            }

            if (arr[0] != header) {
                return IntegerParseFail.I64IntTypeError;
            }

            const v = std.mem.readInt(u64, arr[1..], .big);
            const val: i64 = @bitCast(v);

            return val;
        }
    };
};

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

            std.mem.writeInt(u32, arr[1..], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !f32 {
            if (arr.len != 5) {
                return FloatParseFail.F32LenOut;
            }

            if (arr[0] != header) {
                return FloatParseFail.F32TypeError;
            }

            const v = std.mem.readInt(u32, arr[1..], .big);
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

            std.mem.writeInt(u64, arr[1..], v, .big);
            return arr;
        }

        fn unserialize(arr: []const u8) !f64 {
            if (arr.len != 9) {
                return FloatParseFail.F64LenOut;
            }

            if (arr[0] != header) {
                return FloatParseFail.F64TypeError;
            }

            const v = std.mem.readInt(u64, arr[1..], .big);
            const val: f64 = @bitCast(v);

            return val;
        }
    };
};
