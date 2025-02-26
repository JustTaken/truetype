const std = @import("std");
const builtin = @import("builtin");

pub const ByteReader = struct {
    bytes: []u8,
    index: u32,
    allocator: ?std.mem.Allocator,

    pub fn new(bytes: []u8, allocator: ?std.mem.Allocator) ByteReader {
        return .{
            .bytes = bytes,
            .index = 0,
            .allocator = allocator,
        };
    }

    pub fn readSlice(self: *ByteReader, T: type, count: u32) error{OutOfMemory}![]T {
        const allocator = self.allocator orelse return error.OutOfMemory;
        defer self.index += sizeof(T) * count;

        const values = std.mem.bytesAsSlice(T, self.bytes[self.index..self.index + sizeof(T) * count]);
        const res = try allocator.alloc(T, count);

        for (values, 0..) |value, i| {
            res[i]= std.mem.bigToNative(T, value);
        }

        return res;
    }

    pub fn readValue(self: *ByteReader, T: type) T {
        defer self.index += sizeof(T);
        return std.mem.bigToNative(T, std.mem.bytesToValue(T, self.bytes[self.index..]));
    }

    pub fn readValueFromOffset(self: *const ByteReader, T: type, offset: u32) T {
        const start = offset * sizeof(T);

        return std.mem.bigToNative(T, std.mem.bytesToValue(T, self.bytes[start..start + sizeof(T)]));
    }

    pub fn readTypeFromAbsoluteOffset(self: *const ByteReader, T: type, offset: u32) T {
        var value = std.mem.bytesToValue(T, self.bytes[offset..offset + sizeof(T)]);

        if (builtin.cpu.arch.endian() != .big) {
            std.mem.byteSwapAllFields(T, &value);
        }

        return value;
    }

    pub fn readTypeFromOffset(self: *const ByteReader, T: type, offset: u32) T {
        const start = sizeof(T) * offset;
        var value = std.mem.bytesToValue(T, self.bytes[start..start + sizeof(T)]);

        if (builtin.cpu.arch.endian() != .big) {
            std.mem.byteSwapAllFields(T, &value);
        }

        return value;
        
    }

    pub fn readType(self: *ByteReader, T: type) T {
        defer self.index += sizeof(T);
        var value = std.mem.bytesToValue(T, self.bytes[self.index..self.index + sizeof(T)]);

        if (builtin.cpu.arch.endian() != .big) {
            std.mem.byteSwapAllFields(T, &value);
        }

        return value;
    }

    pub fn readTypeSlice(self: *ByteReader, T: type, count: u32) error{OutOfMemory}![]T {
        const allocator = self.allocator orelse return error.OutOfMemory;

        defer self.index += sizeof(T) * count;
        const values = std.mem.bytesAsSlice(T, self.bytes[self.index..self.index + sizeof(T) * count]);
        const res = try allocator.alloc(T, count);
        @memcpy(res, values);

        if (builtin.cpu.arch.endian() != .big) {
            for (res) |*value| {
                std.mem.byteSwapAllFields(T, @alignCast(value));
            }
        }

        return res;
    }

    fn sizeof(T: type) u32 {
        return @bitSizeOf(T) / 8;
    }
};


