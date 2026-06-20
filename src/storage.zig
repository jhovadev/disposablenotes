const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

/// Storage adapter interface for pluggable persistence backends.
/// Implementations: JsonStorage (current), SqliteStorage (TODO)
pub const StorageAdapter = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Load raw data from storage. Returns the bytes read.
        /// Caller owns the returned slice (allocated with `allocator`).
        load: *const fn (ptr: *anyopaque, allocator: Allocator, io: Io) anyerror![]const u8,
        /// Save raw data to storage.
        save: *const fn (ptr: *anyopaque, data: []const u8, io: Io) anyerror!void,
        /// Return a human-readable name for this adapter (e.g., "json")
        name: *const fn (ptr: *anyopaque) []const u8,
    };

    pub fn load(self: StorageAdapter, allocator: Allocator, io: Io) anyerror![]const u8 {
        return self.vtable.load(self.ptr, allocator, io);
    }

    pub fn save(self: StorageAdapter, data: []const u8, io: Io) anyerror!void {
        return self.vtable.save(self.ptr, data, io);
    }

    pub fn adapterName(self: StorageAdapter) []const u8 {
        return self.vtable.name(self.ptr);
    }
};

/// Storage format enum for CLI argument parsing.
pub const StorageFormat = enum {
    json,
    // sqlite, // TODO: implement SqliteStorage

    pub fn fromString(str: []const u8) ?StorageFormat {
        if (std.mem.eql(u8, str, "json")) return .json;
        return null;
    }

    pub fn inferFromPath(path: []const u8) StorageFormat {
        if (std.mem.endsWith(u8, path, ".json")) return .json;
        return .json;
    }

    pub fn extension(self: StorageFormat) []const u8 {
        return switch (self) {
            .json => ".json",
        };
    }

    pub fn toString(self: StorageFormat) []const u8 {
        return switch (self) {
            .json => "json",
        };
    }
};

// ─── Tests ─────────────────────────────────────────────
const testing = std.testing;

test "StorageFormat.fromString parses json" {
    const fmt = StorageFormat.fromString("json");
    try testing.expect(fmt != null);
    try testing.expect(fmt.? == .json);
}

test "StorageFormat.fromString returns null for unknown" {
    const fmt = StorageFormat.fromString("xml");
    try testing.expect(fmt == null);
}

test "StorageFormat.inferFromPath detects json" {
    try testing.expect(StorageFormat.inferFromPath("notes.json") == .json);
}

test "StorageFormat.inferFromPath defaults to json" {
    try testing.expect(StorageFormat.inferFromPath("notes.xyz") == .json);
    try testing.expect(StorageFormat.inferFromPath("notes") == .json);
}

test "StorageFormat.extension returns correct extension" {
    try testing.expectEqualStrings(".json", StorageFormat.json.extension());
}

test "StorageFormat.toString returns correct name" {
    try testing.expectEqualStrings("json", StorageFormat.json.toString());
}
