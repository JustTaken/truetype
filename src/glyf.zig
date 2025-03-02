const std = @import("std");

const ByteReader = @import("reader.zig").ByteReader;
const TableDirectory = @import("table.zig").TableDirectory;

const Loca = @import("loca.zig").Loca;
const Cmap = @import("cmap.zig").Cmap;
const MaxP = @import("maxp.zig").MaxP;

const Fixed = @import("fixed.zig").Fixed;
// const Fixed = @import("fixed.zig").FFloat;
const ZERO = Fixed.new(0, false, 0);

const DIV: u16 = 1;
const MAX_RAD: u32 = 3;
const INTERPOLATIONS: u32 = 15;
const FILL_BYTE: u8 = 255;

const GlyphKind = enum(i16) {
    Simple,
    Compound,
    None,

    fn new(int: i16) GlyphKind {
        if (int < 0) return .Compound;
        if (int == 0) return .None;
        return .Simple;
    }
};

const GlyphDescription = packed struct {
    number_of_contours: i16,
    x_min: i16,
    y_min: i16,
    x_max: i16,
    y_max: i16,
};

const SimpleGlyph = struct {
    bitmap: []u8,
    width: Fixed,
    height: Fixed,

    const Point = struct {
        x: Fixed,
        y: Fixed,

        fn scale(self: *Point, n: usize) void {
            const i_n = Fixed.new(@intCast(n), false, 0);

            self.x = self.x.div(i_n);
            self.y = self.y.div(i_n);
        }

        fn addCoords(self: *Point, x: i16, y: i16) void {
            self.x = self.x.sum(Fixed.new(x, false, 0));
            self.y = self.y.sum(Fixed.new(y, false, 0));
        }

        fn sum(self: *Point, other: Point) void {
            self.x = self.x.sum(other.x);
            self.y = self.y.sum(other.y);
        }

        pub fn format(self: Point, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;

            try writer.print("{}, {}", .{self.x, self.y});
        }
    };

    const Orientation = enum {
        Clockwise,
        CounterClockwise,
    };

    const Bezier = struct {
        fn contourOutline(
            raw_points: []Point,
            on_curve: []bool,
            interpolations: u32,
            allocator: std.mem.Allocator,
        ) error{OutOfMemory}![]Point {
            var line_points = try std.ArrayList(Point).initCapacity(allocator, 20);
            var points = try std.ArrayList(Point).initCapacity(allocator, raw_points.len);

            var i: usize = 0;
            var total_count: usize = 0;
            while (total_count < raw_points.len) {
                while (!on_curve[i]) : (i = (i + 1) % raw_points.len) {}

                line_points.clearRetainingCapacity();

                try line_points.append(raw_points[i]);

                i = (i + 1) % raw_points.len;

                while (!on_curve[i]) {
                    try line_points.append(raw_points[i]);
                    i = (i + 1) % raw_points.len;
                }

                try line_points.append(raw_points[i]);

                try interpolate(&points, line_points.items, interpolations);

                total_count += line_points.items.len - 1;
            }

            return points.items;
        }

        fn interpolate(points: *std.ArrayList(Point), raw_points: []Point, interpolations: u32) error{OutOfMemory}!void {
            if (raw_points.len == 2) {
                try points.append(raw_points[0]);

                return;
            }

            const delta: f32 = 1.0 / @as(f32, @floatFromInt(interpolations));
            const n = raw_points.len - 1;

            var t: f32 = 0.0;
            for (0..interpolations) |_| {
                defer t += delta;

                var point = Point{ .x = Fixed.new(0, false, 0), .y = Fixed.new(0, false, 0) };

                for (0..raw_points.len) |i| {
                    point.sum(calculateSum(t, @intCast(n - i), @intCast(i), binomial(n, i), raw_points[i]));
                }

                try points.append(point);
            }
        }

        fn calculateSum(t: f32, t_neg_exp: u32, t_exp: u32, cof: f32, point: Point) Point {
            const t_exp_neg_result = std.math.pow(f32, (1 - t), @floatFromInt(t_neg_exp));
            const t_exp_result = std.math.pow(f32, t, @floatFromInt(t_exp));

            const mult = Fixed.fromFloat(t_exp_neg_result * t_exp_result * cof);

            const x = point.x.mul(mult);
            const y = point.y.mul(mult);

            return .{
                .x = x,
                .y = y,
            };
        }

        fn findXIntersections(curve: []Point, height: i16, allocator: std.mem.Allocator) error{OutOfMemory}![]Fixed {
            var intersections = try std.ArrayList(Fixed).initCapacity(allocator, 10);
            const f_height = Fixed.new(height, false, 0);

            var i: usize = 0;
            while (i < curve.len) : (i += 1) {
                const prev = curve[i];
                const next = curve[(i + 1) % curve.len];
                var current = next;

                while (current.y.eq(f_height)) {
                    i += 1;
                    current = curve[(i + 1) % curve.len];
                }


                if (!current.y.gt(f_height) and !prev.y.gt(f_height)) continue;
                if (!current.y.lt(f_height) and !prev.y.lt(f_height)) continue;

                const coef = next.x.sub(prev.x).div(next.y.sub(prev.y));
                const x = prev.x.sum(coef.mul(f_height.sub(prev.y)));

                try intersections.append(x);
            }

            return intersections.items;
        }

        fn contourOrientation(outline: []Point) Orientation {
            var sum: i32 = 0;
            for (0..outline.len) |i| {
                const current = outline[i];
                const next = outline[(i + 1) % outline.len];
                const y: i32 = @divFloor((next.y.toInt() + current.y.toInt()), 2);
                const xdif: i32 = next.x.toInt() - current.x.toInt();

                sum += y * xdif;
            }

            return if (sum > 0) .Clockwise else .CounterClockwise;
        }
    };

    const Flag = packed struct {
        on_curve: bool,
        x_short_vector: bool,
        y_short_vector: bool,
        repeat: bool,
        x_is_same: bool,
        y_is_same: bool,
        reserved0: bool,
        reserved1: bool,
    };

    fn coordinateFromFlag(reader: *ByteReader, short: bool, same: bool) Fixed {
        return switch (short) {
            true => switch (same) {
                true => Fixed.new(@intCast(reader.readValue(u8)), false, 0),
                false => Fixed.new(@as(i16, @intCast(reader.readValue(u8))), true, 0),
            },
            false => switch (same) {
                true => Fixed.new(0, false, 0),
                false => Fixed.new(reader.readValue(i16), false, 0),
            },
        };
    }

    pub fn new(
        description: GlyphDescription,
        reader: *ByteReader,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!SimpleGlyph {
        var self: SimpleGlyph = undefined;

        self.width = Fixed.new(description.x_max - description.x_min + 1, false, 0);
        self.height = Fixed.new(description.y_max - description.y_min + 1, false, 0);
        self.bitmap = try allocator.alloc(u8, @intCast(self.width.multRound(self.height)));

        @memset(self.bitmap, 0);

        const number_of_contours: u16 = @intCast(description.number_of_contours);
        const end_pts_of_contours = try reader.readSlice(u16, number_of_contours);

        const instructionLength = reader.readValue(u16);
        const instructions = try reader.readSlice(u8, instructionLength);
        _ = instructions;

        const point_count = end_pts_of_contours[number_of_contours - 1] + 1;

        const coodinate_points = try allocator.alloc(Point, point_count);
        const on_curve = try allocator.alloc(bool, point_count);

        const flags = try allocator.alloc(Flag, point_count);
        defer allocator.free(flags);

        var count = point_count;
        while (count > 0) {
            const flag: Flag = @bitCast(reader.readValue(u8));

            flags[point_count - count] = flag;
            std.debug.assert(!flag.reserved0 and !flag.reserved1);

            if (flag.repeat) {
                var repeat_count = reader.readValue(u8);
                count -= repeat_count;

                while (repeat_count > 0) {
                    repeat_count -= 1;
                    flags[point_count - count - repeat_count] = flag;
                }
            }

            count -= 1;
        }

        var accX = Fixed.new(0, false, 0);
        for (flags, 0..) |flag, i| {
            accX = accX.sum(coordinateFromFlag(reader, flag.x_short_vector, flag.x_is_same));
            coodinate_points[i].x = accX;

            on_curve[i] = flag.on_curve;
        }

        var accY = Fixed.new(0, false, 0);
        for (flags, 0..) |flag, i| {
            accY = accY.sum(coordinateFromFlag(reader, flag.y_short_vector, flag.y_is_same));
            coodinate_points[i].y = accY;
        }

        const contours = try allocator.alloc([]Point, number_of_contours);
        const orientations = try allocator.alloc(Orientation, number_of_contours);

        count = 0;
        for (0..number_of_contours) |i| {
            const end = end_pts_of_contours[i] + 1;

            defer count = end;

            contours[i] = try Bezier.contourOutline(
                coodinate_points[count..end],
                on_curve[count..end],
                INTERPOLATIONS,
                allocator,
            );

            for (contours[i]) |*point| {
                point.addCoords(-description.x_min, -description.y_min);
                point.scale(DIV);
            }

            orientations[i] = Bezier.contourOrientation(contours[i]);

            for (0..contours[i].len) |k| {
                self.writeLine(contours[i][k], contours[i][(k + 1) % contours[i].len], FILL_BYTE);
            }
        }

        var fixedAllocator = std.heap.FixedBufferAllocator.init(try allocator.alloc(u8, 1024));
        const curveAllocator = fixedAllocator.allocator();

        var line_xs = try std.ArrayList(Fixed).initCapacity(allocator, 30);
        for (0..@intCast(self.height.toInt())) |y| {
            defer line_xs.clearRetainingCapacity();

            for (0..number_of_contours) |i| {
                defer fixedAllocator.reset();

                const contour = contours[i];

                const xs = try Bezier.findXIntersections(contour, @intCast(y), curveAllocator);
                std.debug.assert(xs.len % 2 == 0);

                try line_xs.appendSlice(xs);
            }

            if (line_xs.items.len == 0) continue;
            std.mem.sort(Fixed, line_xs.items, .{}, less);

            const height = y * @as(u32, @intCast(self.width.toInt()));
            for (0..line_xs.items.len / 2) |x| {
                const index = x * 2;

                const x1: u32 = @intCast(line_xs.items[index].toInt());
                const x2: u32 = @intCast(line_xs.items[index + 1].toInt());

                @memset(self.bitmap[height + x1..height + x2 + 1], FILL_BYTE);
            }
        }

        return self;
    }

    fn writeLine(self: *SimpleGlyph, first: Point, second: Point, alpha: u8) void {
        const Independent = enum { X, Y };

        const dx = second.x.sub(first.x);
        const dy = second.y.sub(first.y);

        if (dx.eq(ZERO) and dy.eq(ZERO)) return;

        const dx_int = dx.toInt();
        const dy_int = dy.toInt();

        const ind: Independent = if (abs(dx_int) > abs(dy_int)) .X else .Y;
        const coef = if (ind == .X) dy.div(dx) else dx.div(dy);

        const d_max = if (ind == .X) dx_int else dy_int;

        for (0..abs(d_max) + 1) |i| {
            const ii = Fixed.new(@as(i16, @intCast(i)), (d_max < 0), 0);
            const deltaX = if (ind == .X) ii else coef.mul(ii);
            const deltaY = if (ind == .Y) ii else coef.mul(ii);

            self.addAndWrite(first.x, first.y, deltaX, deltaY, alpha);
        }
    }

    fn addAndWrite(self: *SimpleGlyph, x: Fixed, y: Fixed, deltaX: Fixed, deltaY: Fixed, b: u8) void {
        const r_x = x.sum(deltaX);
        const r_y = y.sum(deltaY);

        if (r_x.lt(ZERO) or r_y.lt(ZERO) or !self.height.gti(r_y) or !self.width.gti(r_x)) return;

        const width: u32 = @intCast(r_x.toInt());
        const height = r_y.multRound(self.width);

        self.bitmap[height + width] = b;
    }
};

pub const Glyf = struct {
    table: TableDirectory,
    loca: Loca,
    cmap: Cmap,
    maxp: MaxP,
    bytes: []u8,

    pub fn new(
        table: TableDirectory,
        cmap: Cmap,
        loca: Loca,
        maxp: MaxP,
        bytes: []u8,
    ) Glyf {
        return .{
            .table = table,
            .loca = loca,
            .cmap = cmap,
            .maxp = maxp,
            .bytes = bytes[table.offset..],
        };
    }

    pub fn get(self: *Glyf, char: u16, allocator: std.mem.Allocator) error{OutOfMemory}!SimpleGlyph {
        const index = self.cmap.get_index(char) orelse 0;

        std.debug.assert(index <= self.maxp.num_glyphs);

        const offset: u32 = self.loca.readF(&self.loca, index);

        var glyph_reader = ByteReader.new(self.bytes[offset..]);
        const glyph_description = glyph_reader.readType(GlyphDescription);

        switch (GlyphKind.new(glyph_description.number_of_contours)) {
            .Simple => return try SimpleGlyph.new(glyph_description, &glyph_reader, allocator),
            .Compound => unreachable,
            .None => unreachable,
        }
    }
};

fn binomial(numerator: usize, denumerator: usize) f32 {
    const n = fac(numerator);
    const d = fac(denumerator);
    const dif = fac(numerator - denumerator);

    return @as(f32, @floatFromInt(n)) / @as(f32, @floatFromInt(d * dif));
}

fn fac(number: usize) usize {
    if (number <= 1) return 1;
    return fac(number - 1) * number;
}

fn max(first: isize, second: isize) isize {
    return if (abs(first) > abs(second)) first else second;
}

fn abs(number: isize) usize {
    return if (number < 0) @intCast(-number) else @intCast(number);
}

fn sign(number: isize) isize {
    return if (number < 0) -1 else 1;
}

fn less(_: @TypeOf(.{}), first: Fixed, second: Fixed) bool {
    return first.lt(second);
}
