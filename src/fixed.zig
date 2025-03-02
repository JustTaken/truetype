const std = @import("std");
pub const FFloat = struct {
    handle: f32,

    pub fn new(int: i16, neg: bool, float: u16) FFloat {
        var self: FFloat = undefined;

        self.handle = @floatFromInt(int);
        self.handle += @floatFromInt(float);

        if (neg and self.handle > 0) self.handle *= -1;

        return self;
    }

    pub fn fromFloat(f: f32) FFloat {
        return .{
            .handle = f,
        };
    }

    pub fn toInt(self: FFloat) i16 {
        return @intFromFloat(@round(self.handle));
    }

    pub fn sum(self: FFloat, other: FFloat) FFloat {
        return .{
            .handle = self.handle + other.handle,
        };
    }

    pub fn sub(self: FFloat, other: FFloat) FFloat {
        return .{
            .handle = self.handle - other.handle,
        };
    }

    pub fn multRound(self: FFloat, other: FFloat) u32 {
        const first: u32 = @intFromFloat(@round(self.handle));
        const second: u32 = @intFromFloat(@round(other.handle));

        return first * second;
    }

    pub fn mul(self: FFloat, other: FFloat) FFloat {
        return .{
            .handle = self.handle * other.handle,
        };
    }

    pub fn div(self: FFloat, other: FFloat) FFloat {
        return .{
            .handle = self.handle / other.handle,
        };
    }

    pub fn gti(self: FFloat, other: FFloat) bool {
        return self.handle > other.handle;
    }

    pub fn gt(self: FFloat, other: FFloat) bool {
        return self.handle > other.handle;
    }

    pub fn lt(self: FFloat, other: FFloat) bool {
        return self.handle < other.handle;
    }

    pub fn eq(self: FFloat, other: FFloat) bool {
        return std.math.approxEqRel(f32, self.handle, other.handle, 0.0001);
    }

    pub fn format(self: FFloat, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        try writer.print("[{}]", .{self.handle});
    }
};

pub const Fixed = packed struct {
    float: u16,
    int: u16,

    const MAX: u32 = std.math.maxInt(u16);

    pub fn new(int: i16, neg: bool, float: u16) Fixed {
        var i: u16 = if (int < 0) @intCast(-int) else @intCast(int);
        if (int < 0 or neg) i |= SIGN_BIT;

        return .{
            .int = i,
            .float = float,
        };
    }

    pub fn fromFloat(f: f32) Fixed {
        const int: i16 = @intFromFloat(f);
        const float = (f - @as(f32, @floatFromInt(int))) * @as(f32, @floatFromInt(MAX));

        return Fixed.new(int, int < 0 or float < 0, abs(@intFromFloat(float)));
    }

    pub fn toInt(self: Fixed) i16 {
        const s = self.sign();
        var int: i16 = @intCast(self.value());
        int *= s;

        // std.debug.print("sign to int: {}\n", .{int});

        if (self.float > MAX / 2) {
            int += s;
        }
        // std.debug.print("sign to int: {}\n", .{int});

        return int;
    }

    fn value(self: Fixed) u16 {
        return self.int & (~SIGN_BIT);
    }

    fn sign(self: Fixed) i16 {
        return if (self.int & SIGN_BIT != 0) -1 else 1;
    }

    pub fn sum(self: Fixed, other: Fixed) Fixed {
        const self_sign = self.sign();
        const other_sign = other.sign();

        var int: isize = @as(i32, @intCast(self.value())) * self_sign;

        int += @as(i32, @intCast(other.value())) * other_sign;
        int *= @intCast(MAX);
        int += @as(isize, @intCast(self.float)) * self_sign;
        int += @as(isize, @intCast(other.float)) * other_sign;

        const neg = int < 0;
        var float: u16 = @intCast(@mod(int, @as(i32, @intCast(MAX))));

        if (self_sign != other_sign and self.float < other.float and neg) {
            float = @intCast(MAX - float);
        }

        int = @divTrunc(int, @as(i32, @intCast(MAX)));

        return Fixed.new(@intCast(int), neg, float);
    }

    pub fn sub(self: Fixed, other: Fixed) Fixed {
        const self_sign = self.sign();
        const other_sign = other.sign();

        var int: isize = @as(i32, @intCast(self.value())) * self_sign;

        int -= @as(i32, @intCast(other.value())) * other_sign;
        int *= @intCast(MAX);
        int += @as(isize, @intCast(self.float)) * self_sign;
        int -= @as(isize, @intCast(other.float)) * other_sign;

        // std.debug.print("int: {}\n", .{int});

        const neg = int < 0;
        var float: u16 = @intCast(@mod(int, @as(i32, @intCast(MAX))));

        // std.debug.print("float: {}\n", .{float});
        if (self_sign == other_sign and other.float > self.float and neg) {
            float = @intCast(MAX - float);
        }

        int = @divTrunc(int, @as(i32, @intCast(MAX)));
        // std.debug.print("int: {}, float: {}\n", .{int, float});
        const i = Fixed.new(@intCast(int), neg, @intCast(float));
        // std.debug.print("i ----: {}\n", .{i});
        return i;
    }

    pub fn multRound(self: Fixed, other: Fixed) u32 {
        // std.debug.assert((self.sign() == 1 and other.sign() == 1) or );

        var int: u32 = @intCast(self.toInt());
        int *= @intCast(other.toInt());

        return int;
    }

    pub fn mul(self: Fixed, other: Fixed) Fixed {
        var self_int: usize = self.value();

        self_int *= MAX;
        self_int += self.float;

        var other_int: usize = @intCast(other.value());
        other_int *= MAX;
        other_int += other.float;

        var int = (self_int * other_int) / MAX;
        const float = int % MAX;
        // try writer.print("[{s}{}.{}]", .{if (self.sign() < 0) "-" else "", self.value(), });
        // std.debug.print("self: {}, other: {}, float: {}\n", .{self_int, other_int, float * 10000 / MAX});
        int /= MAX;

        return Fixed.new(@as(i16, @intCast(int)), self.sign() * other.sign() < 0, @intCast(float));
    }

    pub fn div(self: Fixed, other: Fixed) Fixed {
        var self_int: usize = self.value();
        self_int *= MAX;
        self_int += self.float;
        self_int *= MAX;

        var other_int: usize = other.value();
        other_int *= MAX;
        other_int += other.float;

        var int = self_int / other_int;
        const float = int % MAX;

        int = int / MAX;

        return Fixed.new(@as(i16, @intCast(int)) ,self.sign() * other.sign() < 0, @intCast(float));
    }

    pub fn gti(self: Fixed, other: Fixed) bool {
        return self.toInt() > other.toInt();
    }

    pub fn gt(self: Fixed, other: Fixed) bool {
        if (self.int == other.int) return self.float > other.float;
        return self.int > other.int;
    }

    pub fn lt(self: Fixed, other: Fixed) bool {
        if (self.int == other.int) return self.float < other.float;
        return self.int < other.int;
    }

    pub fn eq(self: Fixed, other: Fixed) bool {
        return self.int == other.int and self.float == other.float;
    }

    pub fn format(self: Fixed, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const float: u32 = self.float;
        try writer.print("[{s}{}.{d:0>4}]", .{if (self.sign() < 0) "-" else "", self.value(), float * 10000 / MAX});
    }
};

fn abs(n: i32) u16 {
    return if (n < 0) @intCast(-n) else @intCast(n);
}

const SIGN_BIT: u16 = 0b1000000000000000;

test "sub no decimal" {
    const float = 0.0;
    const float2 = 224.00;
    // const first = Fixed.new(199, false, 0);
    const first = Fixed.fromFloat(float);
    const second = Fixed.fromFloat(float2);
    // const third = Fixed.new(600, false, 0);
    // const fourth = Fixed.fromFloat(float2);
    const result = first.sub(second);
    std.debug.print("result: {}\n", .{result});
    // std.debug.print("int: {}, result_float: {}\n", .{result.toInt(), result.float});

    // std.debug.print("{} -> {} + {}\n", .{result});
    // std.debug.print("{} -> {} * {}\n", .{second.mul(fourth), second, fourth});
    // std.debug.print("{} -> {} + {}\n", .{first.sum(fourth), first, fourth});
    // std.debug.print("{} -> {} + {}\n", .{first.sum(third), first, third});
    // std.debug.print("{} -> {} - {}\n", .{first.sub(third), first, third});
    // std.debug.print("{}\n", .{Fixed.fromFloat(5.55)});
}

test "sub with decimal" {
    const float = 0.0;
    const float2 = 4.1065;
    // const first = Fixed.new(199, false, 0);
    const first = Fixed.fromFloat(float);
    const second = Fixed.fromFloat(float2);
    const result = first.sub(second);
    std.debug.print("result: {}\n", .{result});
}

test "sum second neg" {
    const float = 0.0;
    const float2 = -4.1065;
    // const first = Fixed.new(199, false, 0);
    const first = Fixed.fromFloat(float);
    const second = Fixed.fromFloat(float2);
    const result = first.sum(second);
    std.debug.print("result: {}\n", .{result});
}

