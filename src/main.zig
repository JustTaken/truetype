const std = @import("std");

const TableTag = enum  {
    @"GDEF",
    @"GPOS",
    @"GSUB",
    @"OS/2",
    @"PfEd",
    @"cmap",
    @"cvt ",
    @"fpgm",
    @"gasp",
    @"glyf",
    @"head",
    @"hhea",
    @"hmtx",
    @"loca",
    @"maxp",
    @"name",
    @"post",
    @"prep",

    fn from_bytes(bytes: [4]u8) ?TableTag {
        inline for (@typeInfo(TableTag).Enum.fields) |field| {
            if (std.mem.eql(u8, field.name, &bytes)) {
                return @enumFromInt(field.value);
            }
        }

        return null;
    }
};

const OffsetTable = extern struct {
    scaler_type: u32,
    num_tables: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
};

const TableDirectory = extern struct {
    tag: [4]u8,
    checkSum: u32,
    offset: u32,
    length: u32,
};

const ByteReader = struct {
    bytes: []u8,
    index: u32,

    fn new(bytes: []u8) ByteReader {
        return .{
            .bytes = bytes,
            .index = 0,
        };
    }

    fn readSlice(self: *ByteReader, T: type, count: u32) []T {
        defer self.index += @sizeOf(T) * count;

        const values = std.mem.bytesAsSlice(T, self.bytes[self.index..self.index + @sizeOf(T) * count]);

        for (values) |*value| {
            value.* = std.mem.bigToNative(T, value.*);
        }

        return @alignCast(values);
    }

    fn readValue(self: *ByteReader, T: type) T {
        defer self.index += @sizeOf(T);
        return std.mem.bigToNative(T, std.mem.bytesToValue(T, self.bytes[self.index..]));
    }

    fn readType(self: *ByteReader, T: type) T {
        defer self.index += @sizeOf(T);
        var value = std.mem.bytesToValue(T, self.bytes[self.index..self.index + @sizeOf(T)]);
        std.mem.byteSwapAllFields(T, &value);

        return value;
    }

    fn readTypeSlice(self: *ByteReader, T: type, count: u32) []T {
        defer self.index += @sizeOf(T) * count;
        const values = std.mem.bytesAsSlice(T, self.bytes[self.index..self.index + @sizeOf(T) * count]);

        for (values) |*value| {
            std.mem.byteSwapAllFields(T, @alignCast(value));
        }

        return @alignCast(values);
    }
};

const Cmap = struct {
    index: Index,
    subtables: []SubTable,

    const Index = extern struct {
        version: u16,
        num_sub_tables: u16,
    };

    const SubTable = extern struct {
        id: u16,
        specific_id: u16,
        offset: u32,

        const Format4 = struct {
            format: u16,
            length: u16,
            language: u16,
            seg_count_x2: u16,
            search_range: u16,
            entry_selector: u16,
            range_shift: u16,
            end_code: []u16,
            reserved_pad: u16,
            start_code: []u16,
            id_delta: []u16,
            id_range_offset: []u16,
            glyph_index_array: []u16,

            fn new(reader: *ByteReader) Format4 {
                var self: Format4 = undefined;

                self.length = reader.readValue(u16);
                self.language = reader.readValue(u16);
                self.seg_count_x2 = reader.readValue(u16);
                self.search_range = reader.readValue(u16);
                self.entry_selector = reader.readValue(u16);
                self.range_shift = reader.readValue(u16);
                self.end_code = reader.readSlice(u16, self.seg_count_x2 / 2);
                self.reserved_pad = reader.readValue(u16);
                self.start_code = reader.readSlice(u16, self.seg_count_x2 / 2);
                self.id_delta = reader.readSlice(u16, self.seg_count_x2 / 2);
                self.id_range_offset = reader.readSlice(u16, self.seg_count_x2 / 2);

                const bytes: [*]u8 = reader.bytes[reader.index..].ptr;
                const u16_array: [*]u16 = @ptrCast(@alignCast((bytes)));

                self.glyph_index_array = u16_array[0..(reader.bytes.len - reader.index) / 2];

                return self;
            }

            fn get(self: Format4, char: u16) ?u16 {
                for (0..self.seg_count_x2 / 2) |i| {
                    if (!(self.start_code[i] <= char and self.end_code[i] >= char)) continue;

                    std.debug.assert(self.id_range_offset[i] == 0);

                    const delta: i16 = @bitCast(self.id_delta[i]);
                    const c: i16 = @intCast(char);
                    const index: u16 = @bitCast(delta + c);

                    std.debug.print("char: {c}, index: {}, delta: {}, start: {}, end: {}\n", .{@as(u8, @intCast(char)), index, delta, self.start_code[i], self.end_code[i]});

                    return index;
                }

                return null;
            }
        };

        const Format = union(Kind) {
            Format4: Format4,
            Format12: void,

            const Kind = enum(u16) {
                Format4 = 4,
                Format12 = 12,
            };

            fn new(bytes: []u8) ?Format {
                var reader = ByteReader.new(bytes);

                const format = std.meta.intToEnum(Kind, reader.readValue(u16)) catch return null;

                return switch (format) {
                    .Format4 => .{ .Format4 = Format4.new(&reader) },
                    .Format12 => null,
                };
            }

            fn get(self: Format, char: u16) ?u16 {
                return switch (self) {
                    .Format4 => |f| f.get(char),
                    .Format12 => char,
                };
            }
        };

        const UnicodePlatform: u32 = 0;
        const WindowsPlatform: u32 = 3;

        fn is_unicode(self: SubTable) bool {
            switch (self.id) {
                UnicodePlatform => return true,
                WindowsPlatform => return self.specific_id == 1 or self.specific_id == 10,
                else => return false,
            }
        }

        fn get_format(self: SubTable, bytes: []u8) ?Format {
            if (!self.is_unicode()) return null;

            return Format.new(bytes[self.offset..]);
        }
    };

    fn new(bytes: []u8) Cmap {
        var self: Cmap = undefined;
        var reader = ByteReader.new(bytes);

        self.index = reader.readType(Index);
        self.subtables = reader.readTypeSlice(SubTable, self.index.num_sub_tables);

        return self;
    }
};

pub fn main() !void {
    const bytes = try std.heap.page_allocator.alloc(u8, 1024 * 1024 * 10);
    var fixedAllocator = std.heap.FixedBufferAllocator.init(bytes);
    const allocator = fixedAllocator.allocator();

    const content = try std.fs.cwd().readFileAlloc(allocator, "assets/font.ttf", bytes.len - 1);
    var reader = ByteReader.new(content);

    const offset_table = reader.readType(OffsetTable);
    const tables = reader.readTypeSlice(TableDirectory, offset_table.num_tables);

    for (tables) |table| {
        const tag = TableTag.from_bytes(table.tag) orelse continue;

        switch (tag) {
            .@"cmap" => {
                const cmap = Cmap.new(content[table.offset..]);

                for (cmap.subtables) |sub_table| {
                    if (sub_table.get_format(content[table.offset..])) |format| {
                        _ = format.get('a') orelse continue;
                        _ = format.get('b') orelse continue;
                        _ = format.get('c') orelse continue;
                    }
                }
            },
            else => {}
        }
    }
}

