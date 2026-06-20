const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const repository = @import("repository.zig");
const Note = repository.Note;
const NoteRepository = repository.NoteRepository;
const storage_mod = @import("storage.zig");
const StorageAdapter = storage_mod.StorageAdapter;
const json_writer = @import("json_writer.zig");
const Jw = json_writer.JsonWriter;

pub const PersistenceService = struct {
    const Self = @This();

    repo: *NoteRepository,
    adapter: StorageAdapter,
    io: Io,

    pub fn init(repo: *NoteRepository, adapter: StorageAdapter) PersistenceService {
        return .{
            .repo = repo,
            .adapter = adapter,
            .io = undefined,
        };
    }

    pub fn setIo(self: *Self, io: Io) void {
        self.io = io;
    }

    pub fn flush(self: *Self) !void {
        if (!self.repo.dirty) {
            std.debug.print("[Persistence] Flush skipped (not dirty).\n", .{});
            return;
        }
        std.debug.print("[Persistence] Flushing {d} notes via {s} adapter...\n", .{ self.repo.notes.count(), self.adapter.adapterName() });
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(self.repo.allocator);
        try serializeNotes(self.repo, &buf, self.repo.allocator);
        if (buf.items.len > 0) {
            const preview = buf.items[0..@min(buf.items.len, 200)];
            std.debug.print("[Persistence] Serialized ({d} bytes): {s}\n", .{ buf.items.len, preview });
        }
        try self.adapter.save(buf.items, self.io);
        self.repo.dirty = false;
        std.debug.print("[Persistence] Flush complete.\n", .{});
    }

    pub fn loadFromDisk(self: *Self) !void {
        const content = self.adapter.load(self.repo.allocator, self.io) catch |err| {
            std.debug.print("[Persistence] Load error (starting fresh): {any}\n", .{err});
            return;
        };
        if (content.len == 0) {
            std.debug.print("[Persistence] No data, starting fresh.\n", .{});
            return;
        }
        std.debug.print("[Persistence] Read {d} bytes from {s} adapter.\n", .{ content.len, self.adapter.adapterName() });
        if (content.len > 0) {
            const preview = content[0..@min(content.len, 300)];
            std.debug.print("[Persistence] Raw data: {s}\n", .{preview});
        }
        self.repo.loadFromJson(content) catch |err| {
            std.debug.print("[Persistence] Parse error: {any}\n", .{err});
            return err;
        };
        self.repo.dirty = false;
        std.debug.print("[Persistence] Loaded {d} notes.\n", .{self.repo.notes.count()});
    }
};

fn serializeNotes(repo: *NoteRepository, buf: *std.ArrayList(u8), allocator: Allocator) !void {
    try Jw.writeStr(buf, allocator, "{\"notes\":{");
    var iter = repo.notes.iterator();
    var first = true;
    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const note = entry.value_ptr.*;
        if (!first) try Jw.writeStr(buf, allocator, ",");
        first = false;
        try Jw.writeKey(buf, allocator, key);
        try Jw.writeStr(buf, allocator, ":{\"id\":\"");
        try Jw.writeStr(buf, allocator, note.id);
        try Jw.writeStr(buf, allocator, "\",\"name\":");
        try Jw.writeEscaped(buf, allocator, note.name);
        try Jw.writeStr(buf, allocator, ",\"content\":");
        try Jw.writeEscaped(buf, allocator, note.content);
        try Jw.writeStr(buf, allocator, ",\"createdAt\":\"");
        try Jw.writeStr(buf, allocator, note.created_at);
        try Jw.writeStr(buf, allocator, "\",\"archived\":");
        if (note.archived) {
            try Jw.writeStr(buf, allocator, "true");
        } else {
            try Jw.writeStr(buf, allocator, "false");
        }
        try Jw.writeStr(buf, allocator, "}");
    }
    try Jw.writeStr(buf, allocator, "}}");
}
