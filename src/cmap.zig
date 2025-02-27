const std = @import("std");

const ByteReader = @import("reader.zig").ByteReader;
const TableDirectory = @import("table.zig").TableDirectory;

const Format4 = struct {
    format: u16,
    length: u16,
    language: u16,
    seg_count_x2: u16,
    search_range: u16,
    entry_selector: u16,
    range_shift: u16,
    end_code: []align(1) u16,
    reserved_pad: u16,
    start_code: []align(1) u16,
    id_delta: []align(1) u16,
    id_range_offset: []align(1) u16,
    glyph_index_array: []u8,

    fn new(reader: *ByteReader) error{OutOfMemory}!Format4 {
        var self: Format4 = undefined;

        self.length = reader.readValue(u16);
        self.language = reader.readValue(u16);
        self.seg_count_x2 = reader.readValue(u16);
        self.search_range = reader.readValue(u16);
        self.entry_selector = reader.readValue(u16);
        self.range_shift = reader.readValue(u16);
        self.end_code = try reader.readSlice(u16, self.seg_count_x2 / 2);
        self.reserved_pad = reader.readValue(u16);
        self.start_code = try reader.readSlice(u16, self.seg_count_x2 / 2);
        self.id_delta = try reader.readSlice(u16, self.seg_count_x2 / 2);
        self.id_range_offset = try reader.readSlice(u16, self.seg_count_x2 / 2);

        self.glyph_index_array = reader.bytes[reader.index..];

        return self;
    }

    fn get(self: Format4, char: u16) ?u16 {
        for (0..self.seg_count_x2 / 2) |i| {
            if (!(self.start_code[i] <= char and self.end_code[i] >= char)) continue;

            switch (self.id_range_offset[i]) {
                0 => return self.id_delta[i] +% char,
                else => |range_offset| {
                    var reader = ByteReader.new(self.glyph_index_array);
                    const index_offset = i + range_offset / 2 + (char - self.start_code[i]);

                    return reader.readValueFromOffset(u16, @intCast(index_offset - self.id_range_offset.len));
                },
            }
        }

        return null;
    }
};

const Format12 = struct {
    reserved: u16,
    length: u32,
    language: u32,
    groups: []align(1) Group,

    const Group = struct {
        start_char_code: u32,
        end_char_code: u32,
        start_glyph_code: u32,
    };

    fn new(reader: *ByteReader) error{OutOfMemory}!Format12 {
        var self: Format12 = undefined;

        self.reserved = reader.readValue(u16);
        self.length = reader.readValue(u32);
        self.language = reader.readValue(u32);

        const group_count = reader.readValue(u32);

        self.groups = try reader.readTypeSlice(Group, group_count);

        return self;
    }

    fn get(self: Format12, char: u16) ?u16 {
        for (self.groups) |group| {
            if (group.start_char_code <= char and group.end_char_code >= char) {
                const index: u16 = @intCast(group.start_glyph_code + (char - group.start_char_code));

                return index;
            }
        }

        return null;
    }
};

const Format = union(Kind) {
    Format4: Format4,
    Format12: Format12,

    const Kind = enum(u16) {
        Format4 = 4,
        Format12 = 12,
    };

    pub fn new(bytes: []u8) ?Format {
        var reader = ByteReader.new(bytes);

        const format = std.meta.intToEnum(Kind, reader.readValue(u16)) catch return null;

        return switch (format) {
            .Format4 => .{ .Format4 = Format4.new(&reader) catch return null },
            .Format12 => .{ .Format12 = Format12.new(&reader) catch return null },
        };
    }

    pub fn get(self: Format, char: u16) ?u16 {
        return switch (self) {
            .Format4 => |f| f.get(char),
            .Format12 => |f| f.get(char),
        };
    }
};

pub const Cmap = struct {
    index: Index,
    subtables: []align(1) SubTable,
    format: Format,

    const Index = packed struct {
        version: u16,
        num_sub_tables: u16,
    };

    const SubTable = packed struct {
        id: u16,
        specific_id: u16,
        offset: u32,

        const UnicodePlatform: u32 = 0;
        const WindowsPlatform: u32 = 3;

        pub fn is_unicode(self: SubTable) bool {
            switch (self.id) {
                UnicodePlatform => return true,
                WindowsPlatform => return self.specific_id == 1 or self.specific_id == 10,

                else => return false,
            }
        }

        pub fn get_format(self: SubTable, bytes: []u8) ?Format {
            if (!self.is_unicode()) return null;

            return Format.new(bytes[self.offset..]);
        }
    };

    pub fn new(table: TableDirectory, bytes: []u8) error{Format, OutOfMemory}!Cmap {
        var self: Cmap = undefined;
        var reader = ByteReader.new(bytes[table.offset..]);

        self.index = reader.readType(Index);
        self.subtables = try reader.readTypeSlice(SubTable, self.index.num_sub_tables);

        var format: ?Format = null;

        for (self.subtables) |subtable| {
            if (subtable.get_format(bytes[table.offset..])) |f| {
                format = f;
                break;
            }
        }

        self.format = format orelse return error.Format;

        return self;
    }

    pub fn get_index(self: Cmap, char: u16) ?u16 {
        return self.format.get(char);
    }
};

