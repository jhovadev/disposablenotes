const std = @import("std");
const Allocator = std.mem.Allocator;

/// JSON writer that works with ArrayList(u8) buffers (heap-allocated).
/// Used by PersistenceService and QueryBus for dynamic-length serialization.
pub const JsonWriter = struct {
    /// Write a raw string slice to the buffer.
    pub fn writeStr(buf: *std.ArrayList(u8), allocator: Allocator, str: []const u8) !void {
        try buf.appendSlice(allocator, str);
    }

    /// Write a single byte to the buffer.
    pub fn writeByte(buf: *std.ArrayList(u8), allocator: Allocator, byte: u8) !void {
        try buf.append(allocator, byte);
    }

    /// Write a JSON-escaped string (with surrounding quotes).
    /// Handles all control characters 0x00–0x1F per RFC 8259.
    pub fn writeEscaped(buf: *std.ArrayList(u8), allocator: Allocator, str: []const u8) !void {
        try writeByte(buf, allocator, '"');
        for (str) |c| {
            switch (c) {
                '"' => try writeStr(buf, allocator, "\\\""),
                '\\' => try writeStr(buf, allocator, "\\\\"),
                '\n' => try writeStr(buf, allocator, "\\n"),
                '\r' => try writeStr(buf, allocator, "\\r"),
                '\t' => try writeStr(buf, allocator, "\\t"),
                0...8, 11, 12, 14...31 => {
                    // All control chars except \t(9), \n(10), \r(13) which are handled above
                    try writeStr(buf, allocator, "\\u00");
                    const hex = "0123456789abcdef";
                    try writeByte(buf, allocator, hex[(c >> 4) & 0xf]);
                    try writeByte(buf, allocator, hex[c & 0xf]);
                },
                else => try writeByte(buf, allocator, c),
            }
        }
        try writeByte(buf, allocator, '"');
    }

    /// Write a JSON object key (escaped, with surrounding quotes).
    /// Only escapes double-quotes inside the key (keys are typically simple identifiers).
    pub fn writeKey(buf: *std.ArrayList(u8), allocator: Allocator, key: []const u8) !void {
        try writeByte(buf, allocator, '"');
        for (key) |c| {
            if (c == '"') try writeStr(buf, allocator, "\\\"") else try writeByte(buf, allocator, c);
        }
        try writeByte(buf, allocator, '"');
    }
};

/// Fixed-buffer JSON writer for stack-allocated buffers.
/// Used by WindowManager for event broadcasting where allocation is undesirable.
pub const FixedJsonWriter = struct {
    /// Write a raw string slice to the fixed buffer.
    pub fn writeStr(buf: []u8, pos: *usize, s: []const u8) !void {
        if (pos.* + s.len > buf.len) return error.OutOfMemory;
        @memcpy(buf[pos.*..][0..s.len], s);
        pos.* += s.len;
    }

    /// Write a single byte to the fixed buffer.
    pub fn writeByte(buf: []u8, pos: *usize, b: u8) !void {
        if (pos.* + 1 > buf.len) return error.OutOfMemory;
        buf[pos.*] = b;
        pos.* += 1;
    }

    /// Write a JSON-escaped string (with surrounding quotes) to the fixed buffer.
    /// Handles all control characters 0x00–0x1F per RFC 8259.
    pub fn writeEscaped(buf: []u8, pos: *usize, s: []const u8) !void {
        try writeByte(buf, pos, '"');
        for (s) |c| {
            switch (c) {
                '"' => try writeStr(buf, pos, "\\\""),
                '\\' => try writeStr(buf, pos, "\\\\"),
                '\n' => try writeStr(buf, pos, "\\n"),
                '\r' => try writeStr(buf, pos, "\\r"),
                '\t' => try writeStr(buf, pos, "\\t"),
                0...8, 11, 12, 14...31 => {
                    try writeStr(buf, pos, "\\u00");
                    const hex = "0123456789abcdef";
                    try writeByte(buf, pos, hex[(c >> 4) & 0xf]);
                    try writeByte(buf, pos, hex[c & 0xf]);
                },
                else => try writeByte(buf, pos, c),
            }
        }
        try writeByte(buf, pos, '"');
    }
};

// ─── Tests ─────────────────────────────────────────────
const testing = std.testing;

test "JsonWriter.writeEscaped handles quotes" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try JsonWriter.writeEscaped(&buf, testing.allocator, "hello \"world\"");
    const result = buf.items;
    try testing.expectEqualStrings("\"hello \\\"world\\\"\"", result);
}

test "JsonWriter.writeEscaped handles newlines and tabs" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try JsonWriter.writeEscaped(&buf, testing.allocator, "line1\nline2\ttab");
    const result = buf.items;
    try testing.expectEqualStrings("\"line1\\nline2\\ttab\"", result);
}

test "JsonWriter.writeEscaped handles control characters" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    // Test with ASCII control char 0x01 (SOH)
    try JsonWriter.writeEscaped(&buf, testing.allocator, &[_]u8{0x01});
    const result = buf.items;
    try testing.expectEqualStrings("\"\\u0001\"", result);
}

test "JsonWriter.writeKey escapes quotes in keys" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try JsonWriter.writeKey(&buf, testing.allocator, "my\"key");
    const result = buf.items;
    try testing.expectEqualStrings("\"my\\\"key\"", result);
}

test "JsonWriter.writeEscaped empty string" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try JsonWriter.writeEscaped(&buf, testing.allocator, "");
    try testing.expectEqualStrings("\"\"", buf.items);
}

test "JsonWriter.writeEscaped handles backslash" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try JsonWriter.writeEscaped(&buf, testing.allocator, "path\\to\\file");
    try testing.expectEqualStrings("\"path\\\\to\\\\file\"", buf.items);
}

test "JsonWriter.writeEscaped handles carriage return" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try JsonWriter.writeEscaped(&buf, testing.allocator, "line1\r\nline2");
    try testing.expectEqualStrings("\"line1\\r\\nline2\"", buf.items);
}

test "JsonWriter.writeEscaped handles high control chars (0x1F)" {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    // 0x1F = Unit Separator, should be escaped as \u001f
    try JsonWriter.writeEscaped(&buf, testing.allocator, &[_]u8{0x1F});
    try testing.expectEqualStrings("\"\\u001f\"", buf.items);
}

test "FixedJsonWriter.writeEscaped works with stack buffer" {
    var buf: [256]u8 = undefined;
    var pos: usize = 0;
    try FixedJsonWriter.writeEscaped(&buf, &pos, "hello");
    try testing.expectEqualStrings("\"hello\"", buf[0..pos]);
}

test "FixedJsonWriter.writeStr overflow returns error" {
    var buf: [3]u8 = undefined;
    var pos: usize = 0;
    const result = FixedJsonWriter.writeStr(&buf, &pos, "toolong");
    try testing.expectError(error.OutOfMemory, result);
}

test "FixedJsonWriter.writeEscaped handles control chars" {
    var buf: [256]u8 = undefined;
    var pos: usize = 0;
    try FixedJsonWriter.writeEscaped(&buf, &pos, &[_]u8{ 0x00, 0x1F });
    try testing.expectEqualStrings("\"\\u0000\\u001f\"", buf[0..pos]);
}

test "FixedJsonWriter.writeByte overflow returns error" {
    var buf: [0]u8 = undefined;
    var pos: usize = 0;
    const result = FixedJsonWriter.writeByte(&buf, &pos, 'x');
    try testing.expectError(error.OutOfMemory, result);
}
