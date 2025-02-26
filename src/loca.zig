const std = @import("std");

const TableDirectory = @import("table.zig").TableDirectory;
const ByteReader = @import("reader.zig").ByteReader;
const Head = @import("head.zig").Head;
const MaxP = @import("maxp.zig").MaxP;

pub const Loca = struct {
    reader: ByteReader,
    readF: *const fn (*const Loca, u32) u32,

    const Version = enum(i16) {
        Short = 0,
        Long = 1,
    };

    pub fn read_short(self: *const Loca, offset: u32) u32 {
        return @intCast(self.reader.readValueFromOffset(u16, offset) * 2);
    }

    pub fn read_long(self: *const Loca, offset: u32) u32 {
        return self.reader.readValueFromOffset(u32, offset);
    }

    pub fn new(table: TableDirectory, head: Head, bytes: []u8) error{VersionNotHandled, OutOfMemory}!Loca {
        var self: Loca = undefined;
        self.reader = ByteReader.new(bytes[table.offset..], null);

        const format = std.meta.intToEnum(Version, head.index_to_loc_format) catch return error.VersionNotHandled;

        switch (format) {
            .Short => self.readF = read_short,
            .Long => self.readF = read_long,
        }

        return self;
    }
};
