const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Note = struct {
    id: []const u8,
    name: []const u8,
    content: []const u8,
    created_at: []const u8,
    archived: bool,
};

pub const NoteRepository = struct {
    allocator: Allocator,
    notes: std.StringHashMap(Note),
    dirty: bool,

    pub fn init(allocator: Allocator) NoteRepository {
        return .{
            .allocator = allocator,
            .notes = std.StringHashMap(Note).init(allocator),
            .dirty = false,
        };
    }

    pub fn deinit(self: *NoteRepository) void {
        self.notes.deinit();
    }

    pub fn createNote(self: *NoteRepository, id: []const u8, name: []const u8, content: []const u8, created_at: []const u8) !void {
        const note = Note{
            .id = try self.allocator.dupe(u8, id),
            .name = try self.allocator.dupe(u8, name),
            .content = try self.allocator.dupe(u8, content),
            .created_at = try self.allocator.dupe(u8, created_at),
            .archived = false,
        };
        try self.notes.put(try self.allocator.dupe(u8, id), note);
        self.dirty = true;
    }

    pub fn updateNote(self: *NoteRepository, id: []const u8, name: ?[]const u8, content: ?[]const u8, archived: ?bool) !void {
        const note = self.notes.getPtr(id) orelse return error.NoteNotFound;

        // Optimization: reuse existing buffer when new string fits,
        // reducing arena memory waste. Only allocate when the new
        // string is longer than the old one.
        if (name) |n| {
            note.*.name = try dupeOrReuse(self.allocator, note.*.name, n);
        }
        if (content) |c| {
            note.*.content = try dupeOrReuse(self.allocator, note.*.content, c);
        }
        if (archived) |a| note.*.archived = a;
        if (name != null or content != null or archived != null) self.dirty = true;
    }

    pub fn deleteNote(self: *NoteRepository, id: []const u8) void {
        _ = self.notes.remove(id);
        self.dirty = true;
    }

    pub fn getNote(self: *NoteRepository, id: []const u8) ?Note {
        return self.notes.get(id);
    }

    pub fn count(self: *NoteRepository) usize {
        return self.notes.count();
    }

    pub fn loadFromJson(self: *NoteRepository, json_bytes: []const u8) !void {
        if (json_bytes.len == 0) return;
        const parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, json_bytes, .{});
        defer parsed.deinit();
        const root = parsed.value;
        if (root != .object) return error.InvalidFormat;
        const notes_field = root.object.get("notes") orelse return;
        if (notes_field != .object) return;
        var iter = notes_field.object.iterator();
        while (iter.next()) |entry| {
            const id = entry.key_ptr.*;
            const nv = entry.value_ptr.*;
            if (nv != .object) continue;
            const name = nv.object.get("name") orelse continue;
            const content_val = nv.object.get("content") orelse continue;
            const created_at = nv.object.get("createdAt") orelse continue;
            if (name != .string or content_val != .string or created_at != .string) continue;
            const archived_val = nv.object.get("archived");
            const note = Note{
                .id = try self.allocator.dupe(u8, id),
                .name = try self.allocator.dupe(u8, name.string),
                .content = try self.allocator.dupe(u8, content_val.string),
                .created_at = try self.allocator.dupe(u8, created_at.string),
                .archived = if (archived_val) |a| a == .bool and a.bool else false,
            };
            try self.notes.put(try self.allocator.dupe(u8, id), note);
        }
        self.dirty = false;
    }
};

/// Reuse existing buffer when new data fits, avoiding unnecessary allocations.
/// With arena allocator, old buffers can't be individually freed, so reuse
/// reduces total memory consumed over the app lifetime.
fn dupeOrReuse(allocator: Allocator, old: []const u8, new: []const u8) ![]const u8 {
    if (new.len <= old.len) {
        // Reuse: overwrite existing buffer (safe because we own it)
        const writable = @as([*]u8, @ptrFromInt(@intFromPtr(old.ptr)));
        @memcpy(writable[0..new.len], new);
        // Return a slice of the original buffer with the new length
        return writable[0..new.len];
    }
    // New string is longer: must allocate (old buffer is leaked with arena, accepted trade-off)
    return try allocator.dupe(u8, new);
}

// ─── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;

test "NoteRepository: create and get note" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    try repo.createNote("id-1", "My Note", "Hello world", "2026-01-01T00:00:00Z");
    try testing.expect(repo.dirty);
    try testing.expectEqual(@as(usize, 1), repo.count());

    const note = repo.getNote("id-1") orelse return error.TestFailed;
    try testing.expectEqualStrings("My Note", note.name);
    try testing.expectEqualStrings("Hello world", note.content);
    try testing.expectEqualStrings("2026-01-01T00:00:00Z", note.created_at);
    try testing.expect(!note.archived);
}

test "NoteRepository: update note" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    try repo.createNote("id-1", "Original", "Content", "2026-01-01T00:00:00Z");
    repo.dirty = false;

    try repo.updateNote("id-1", "Updated", null, null);
    try testing.expect(repo.dirty);

    const note = repo.getNote("id-1") orelse return error.TestFailed;
    try testing.expectEqualStrings("Updated", note.name);
    try testing.expectEqualStrings("Content", note.content); // unchanged
}

test "NoteRepository: update note reuses buffer for shorter strings" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    try repo.createNote("id-1", "LongName", "LongContent", "2026-01-01T00:00:00Z");
    // Update with shorter name — should reuse buffer
    try repo.updateNote("id-1", "Hi", null, null);

    const note = repo.getNote("id-1") orelse return error.TestFailed;
    try testing.expectEqualStrings("Hi", note.name);
}

test "NoteRepository: delete note" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    try repo.createNote("id-1", "Note", "Content", "2026-01-01T00:00:00Z");
    try testing.expectEqual(@as(usize, 1), repo.count());

    repo.deleteNote("id-1");
    try testing.expectEqual(@as(usize, 0), repo.count());
    try testing.expect(repo.getNote("id-1") == null);
}

test "NoteRepository: update non-existent note returns error" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    const result = repo.updateNote("nonexistent", "name", null, null);
    try testing.expectError(error.NoteNotFound, result);
}

test "NoteRepository: loadFromJson" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    const json =
        \\{"notes":{"abc123":{"id":"abc123","name":"Test","content":"Hello","createdAt":"2026-01-01T00:00:00Z","archived":false}}}
    ;
    try repo.loadFromJson(json);
    try testing.expect(!repo.dirty); // loadFromJson sets dirty = false
    try testing.expectEqual(@as(usize, 1), repo.count());

    const note = repo.getNote("abc123") orelse return error.TestFailed;
    try testing.expectEqualStrings("Test", note.name);
    try testing.expectEqualStrings("Hello", note.content);
    try testing.expect(!note.archived);
}

test "NoteRepository: loadFromJson empty string" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    try repo.loadFromJson("");
    try testing.expectEqual(@as(usize, 0), repo.count());
}

test "NoteRepository: archive note" {
    var repo = NoteRepository.init(testing.allocator);
    defer repo.deinit();

    try repo.createNote("id-1", "Note", "Content", "2026-01-01T00:00:00Z");
    try repo.updateNote("id-1", null, null, true);

    const note = repo.getNote("id-1") orelse return error.TestFailed;
    try testing.expect(note.archived);
}
