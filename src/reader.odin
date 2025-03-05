package main;

import "core:encoding/endian"
import "core:mem"

ByteReader :: struct {
  buffer: []u8,
  index: uint,
}

reader_from_bytes :: proc(buffer: []u8) -> ByteReader {
  reader: ByteReader
  reader.buffer = buffer
  reader.index = 0

  return reader
}

read_u32 :: proc(reader: ^ByteReader) -> (u32, Font_Error) {
  defer reader.index += size_of(u32)
  value: u32 = ---
  ok: bool

  value, ok = endian.get_u32(reader.buffer[reader.index:], .Big)

  if !ok {
    return 0, .Number_Read
  }

  return value, nil
}

read_u32_from_offset :: proc(reader: ^ByteReader, offset: uint) -> (u32, Font_Error) {
  value: u32 = ---
  ok: bool

  start := offset * size_of(u32)
  value, ok = endian.get_u32(reader.buffer[start:], .Big)

  if !ok {
    return 0, .Number_Read
  }

  return value, nil
}

read_fixed :: proc(reader: ^ByteReader) -> (value: Fixed, err: Font_Error) {
  value.i = read_u16(reader) or_return
  value.f = read_u16(reader) or_return

  return
}

read_u16 :: proc(reader: ^ByteReader) -> (u16, Font_Error) {
  defer reader.index += size_of(u16)
  value: u16 = ---
  ok: bool

  value, ok = endian.get_u16(reader.buffer[reader.index:], .Big)

  if !ok {
    return 0, .Number_Read
  }

  return value, nil
}

read_u16_from_offset :: proc(reader: ^ByteReader, offset: uint) -> (u16, Font_Error) {
  value: u16 = ---
  ok: bool

  start := offset * size_of(u16)
  value, ok = endian.get_u16(reader.buffer[start:], .Big)

  if !ok {
    return 0, .Number_Read
  }

  return value, nil
}

read_i64 :: proc(reader: ^ByteReader) -> (i64, Font_Error) {
  defer reader.index += size_of(i64)
  value: i64 = ---
  ok: bool

  value, ok = endian.get_i64(reader.buffer[reader.index:], .Big)

  if !ok {
    return 0, .Number_Read
  }

  return value, nil
}

read_i16 :: proc(reader: ^ByteReader) -> (i16, Font_Error) {
  defer reader.index += size_of(i16)
  value: i16 = ---
  ok: bool

  value, ok = endian.get_i16(reader.buffer[reader.index:], .Big)

  if !ok {
    return 0, .Number_Read
  }

  return value, nil
}

read_u8 :: proc(reader: ^ByteReader) -> (u8, Font_Error) {
  defer reader.index += size_of(u8)

  if reader.index >= len(reader.buffer) {
    return 0, .Slice_Read
  }

  return reader.buffer[reader.index], nil
}

read_n :: proc(reader: ^ByteReader, n: uint) -> ([]u8, Font_Error) {
  defer reader.index += n
  value: u16 = ---

  if reader.index + n > len(reader.buffer) {
    return nil, .Slice_Read
  }

  return reader.buffer[reader.index:reader.index + n], nil
}

read_n_u16 :: proc(reader: ^ByteReader, n: uint, allocator := context.allocator) -> (buffer: []u16, err: Font_Error) {
  size := uint(size_of(u16))

  if reader.index + n * size > len(reader.buffer) {
    return nil, .Slice_Read
  }

  alloc_err: mem.Allocator_Error
  buffer, alloc_err = make([]u16, n, allocator)

  if alloc_err != nil {
    return nil, .Out_Of_Memory
  }

  for i in 0..<n {
    buffer[i] = read_u16(reader) or_return
  }

  return buffer, nil
}
