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

    pub fn lti(self: FFloat, other: FFloat) bool {
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

    const MAX: u16 = std.math.maxInt(u16);

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

        const i = Fixed.new(int, int < 0 or float < 0, @intCast(abs(@intFromFloat(float))));
        // std.debug.print("from float: {}, -> {}\n", .{f, i});
        return i;
    }

    pub fn toInt(self: Fixed) i16 {
        const s = self.sign();
        var int: i16 = @intCast(self.value());
        int *= s;

        if (self.float > MAX / 2) {
            int += s;
        }

        return int;
    }

    pub fn value(self: Fixed) u16 {
        return self.int & (~SIGN_BIT);
    }

    pub fn sign(self: Fixed) i16 {
        return if (self.int & SIGN_BIT != 0) -1 else 1;
    }

    pub fn sum(self: Fixed, other: Fixed) Fixed {
        const self_sign = self.sign();
        const other_sign = other.sign();

        var int: i32 = @as(i32, @intCast(self.value())) * self_sign;

        int += @as(i32, @intCast(other.value())) * other_sign;
        int *= @intCast(MAX);
        int += @as(i32, @intCast(self.float)) * self_sign;
        int += @as(i32, @intCast(other.float)) * other_sign;

        const neg = int < 0;
        const i = abs(int);
        const float: u16 = @intCast(i % MAX);

        return Fixed.new(@intCast(i / MAX), neg, float);
    }

    pub fn sub(self: Fixed, other: Fixed) Fixed {
        const self_sign = self.sign();
        const other_sign = other.sign();

        var int: i32 = @as(i32, @intCast(self.value())) * self_sign;

        int -= @as(i32, @intCast(other.value())) * other_sign;
        int *= @intCast(MAX);
        int += @as(i32, @intCast(self.float)) * self_sign;
        int -= @as(i32, @intCast(other.float)) * other_sign;

        const neg = int < 0;
        const i = abs(int);
        const float: u16 = @intCast(i % MAX);

        // if (neg) {
        //     float = @intCast(MAX - float);
        // }

        // int = @divTrunc(int, @as(i32, @intCast(MAX)));
        return Fixed.new(@intCast(i / MAX), neg, float);
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
        return self.value() > other.value();
    }

    pub fn lti(self: Fixed, other: Fixed) bool {
        return self.toInt() < other.toInt();
    }

    pub fn lt(self: Fixed, other: Fixed) bool {
        if (self.int == other.int) return self.float < other.float;
        return self.value() < other.value();
    }

    pub fn eq(self: Fixed, other: Fixed) bool {
        return self.int == other.int and self.float == other.float;
    }

    pub fn format(self: Fixed, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const float: u32 = self.float;
        try writer.print("[{s}{}.{d:0>4}] ({})", .{if (self.sign() < 0) "-" else "", self.value(), float * 10000 / MAX, float});
    }
};

fn abs(n: i32) u32 {
    return if (n < 0) @intCast(-n) else @intCast(n);
}

const SIGN_BIT: u16 = 0b1000000000000000;

test "sub no decimal" {
    const first = Fixed.fromFloat(0.0);
    const second = Fixed.fromFloat(224.00);

    std.debug.print("result: {}\n", .{first.sub(second)});
}

test "sub neg" {
    const first = Fixed.new(0, true, 2907);
    const second = Fixed.new(2, true, 145);

    std.debug.print("result: {} ({} + {})\n", .{first.sum(second), first, second});
}

test "sub with decimal" {
    const first = Fixed.fromFloat(0.0);
    const second = Fixed.fromFloat(4.1065);

    std.debug.print("result: {}\n", .{first.sub(second)});
}

test "sum second neg" {
    const first = Fixed.fromFloat(0.0);
    const second = Fixed.fromFloat(-4.1065);

    std.debug.print("result: {}\n", .{first.sum(second)});
}

test "sub first neg" {
    const first = Fixed.fromFloat(-169.6318);
    const second = Fixed.fromFloat(-168.0);

    std.debug.print("result: {}\n", .{first.sub(second)});
}

test "sum first neg" {
    const first = Fixed.fromFloat(-105.0);
    const second = Fixed.fromFloat(0.0);

    std.debug.print("result: {}\n", .{first.sum(second)});
}

test "sum first neg and sec pos" {
    const first = Fixed.fromFloat(-105.0);
    const second = Fixed.fromFloat(0.20);

    std.debug.print("result: {}\n", .{first.sum(second)});
}

//([425.3656], [-169.6318]) from -> { ([517.0000], [-153.0000]), ([486.0000], [-161.0000]), ([446.0000], [-168.0000]), ([420.0000], [-168.0000]) }, width: [548.0000] height: [983.0000]
