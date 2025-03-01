const std = @import("std");
pub const Fixed = packed struct {
    float: u16,
    int: i16,

    const MAX: u32 = std.math.maxInt(u16);

    pub fn new(int: i16, float: u16) Fixed {
        return .{
            .int = int,
            .float = float,
        };
    }

    pub fn fromFloat(f: f32) Fixed {
        const int: i16 = @intFromFloat(f);
        const float = (f - @as(f32, @floatFromInt(int))) * @as(f32, @floatFromInt(MAX));

        return Fixed.new(int, @intFromFloat(float));
    }

    pub fn to_int(self: Fixed) i16 {
        var int = self.int;

        if (self.float > MAX / 2) {
            int += 1;
        }

        return int;
    }

    pub fn sum(self: Fixed, other: Fixed) Fixed {
        var int = self.int + other.int;
        var float: u32 = self.float;
        float += other.float;

        if (float > MAX) {
            float -= MAX;
            int += 1;
        }

        return Fixed.new(int, @intCast(float));
    }

    pub fn sub(self: Fixed, other: Fixed) Fixed {
        var int = self.int - other.int;
        var float: i32 = @intCast(self.float);
        float -= @intCast(other.float);

        if (float < 0) {
            float = @as(i32, @intCast(MAX)) + float;
            int -= 1;
        }

        return Fixed.new(int, @intCast(float));
    }

    pub fn multInt(self: Fixed, other: Fixed) u32 {
        var int: u32 = @intCast(self.int);
        int *= @intCast(other.int);

        var float: u32 = @intCast(self.float);
        float *= @intCast(other.float);

        if (float > MAX) {
            int += @intCast(float / MAX);
        }

        return int;
    }

    pub fn mul(self: Fixed, other: Fixed) Fixed {
        var int = self.int * other.int;
        var float: u32 = @intCast(self.float);
        float *= @intCast(other.float);

        if (float > MAX) {
            int += @intCast(float / MAX);
            float %= MAX;
        }

        return Fixed.new(int, @intCast(float));
    }

    pub fn div(self: Fixed, other: Fixed) Fixed {
        const self_sign = sign(self.int);
        const other_sign = sign(other.int);

        var self_int: usize = @intCast(self.int * self_sign);
        self_int *= MAX;
        self_int += self.float;
        self_int *= MAX; // increase precision

        var other_int: usize = @intCast(other.int * other_sign);
        other_int *= MAX;
        other_int += other.float;

        var int = self_int / other_int;
        const float = int % MAX;
        // std.debug.print("int: {}, float: {}, self_int: {}, other_int: {}\n", .{int, float, self_int, other_int});

        int = int / MAX;

        return Fixed.new(@as(i16, @intCast(int)) * self_sign * other_sign, @intCast(float));
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
};

fn abs(n: i32) u32 {
    return if (n < 0) @intCast(-n) else @intCast(n);
}

fn sign(n: i16) i16 {
    return if (n < 0) -1 else 1;
}

test "fixed" {
    const first = Fixed.new(30, 0);
    const sub = first.div(Fixed.new(20, 0));

    std.debug.print("{}\n", .{sub});
    std.debug.print("{}\n", .{Fixed.fromFloat(5.55)});
}
