const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const storage = @import("storage.zig");
const StorageAdapter = storage.StorageAdapter;

/// JSON file storage adapter.
/// Reads and writes raw JSON bytes to/from a file on disk.
pub const JsonStorage = struct {
    file_path: []const u8,
    dir: Io.Dir,

    pub fn init(file_path: []const u8) JsonStorage {
        return .{
            .file_path = file_path,
            .dir = .cwd(),
        };
    }

    /// Create a StorageAdapter interface from this JsonStorage instance.
    pub fn adapter(self: *JsonStorage) StorageAdapter {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    fn loadImpl(ptr: *anyopaque, allocator: Allocator, io: Io) anyerror![]const u8 {
        const self: *JsonStorage = @ptrCast(@alignCast(ptr));
        const file = Io.Dir.openFile(self.dir, io, self.file_path, .{}) catch |err| {
            std.debug.print("[JsonStorage] No data file ({any}), returning empty.\n", .{err});
            return "";
        };
        defer file.close(io);
        const stat = try file.stat(io);
        if (stat.size == 0) {
            std.debug.print("[JsonStorage] File is empty, returning empty.\n", .{});
            return "";
        }
        const buffer = try allocator.alloc(u8, @as(usize, @intCast(stat.size)));
        const bytes_read = try file.readPositionalAll(io, buffer, 0);
        std.debug.print("[JsonStorage] Read {d} bytes from '{s}'.\n", .{ bytes_read, self.file_path });
        return buffer[0..bytes_read];
    }

    fn saveImpl(ptr: *anyopaque, data: []const u8, io: Io) anyerror!void {
        const self: *JsonStorage = @ptrCast(@alignCast(ptr));
        const file = Io.Dir.createFile(self.dir, io, self.file_path, .{}) catch |err| {
            std.debug.print("[JsonStorage] createFile error: {any}\n", .{err});
            return err;
        };
        defer file.close(io);
        try file.writePositionalAll(io, data, 0);
        std.debug.print("[JsonStorage] Wrote {d} bytes to '{s}'.\n", .{ data.len, self.file_path });
    }

    fn nameImpl(_: *anyopaque) []const u8 {
        return "json";
    }

    const vtable: StorageAdapter.VTable = .{
        .load = &loadImpl,
        .save = &saveImpl,
        .name = &nameImpl,
    };
};
