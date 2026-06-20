const std = @import("std");
const Allocator = std.mem.Allocator;
const webui = @import("webui");
const repository = @import("repository.zig");
const Note = repository.Note;
const NoteRepository = repository.NoteRepository;
const json_writer = @import("json_writer.zig");
const Jw = json_writer.JsonWriter;

pub const QueryBus = struct {
    const Self = @This();

    repo: *NoteRepository,
    /// Reusable scratch buffer to avoid repeated allocations across queries.
    /// Cleared (retaining capacity) between calls.
    scratch: std.ArrayList(u8),

    pub fn init(repo: *NoteRepository) QueryBus {
        return .{
            .repo = repo,
            .scratch = .empty,
        };
    }

    pub fn deinit(self: *Self) void {
        self.scratch.deinit(self.repo.allocator);
    }

    pub fn handleGetNotes(self: *Self, e: *webui.Event) void {
        self.scratch.clearRetainingCapacity();
        serializeNotesBrief(self.repo, &self.scratch, self.repo.allocator) catch {
            e.returnString("{}");
            return;
        };
        const owned = self.scratch.toOwnedSliceSentinel(self.repo.allocator, 0) catch {
            e.returnString("{}");
            return;
        };
        e.returnString(owned);
    }

    pub fn handleGetNote(self: *Self, e: *webui.Event) void {
        const id = e.getString();
        const note = self.repo.getNote(id) orelse {
            e.returnString("null");
            return;
        };
        self.scratch.clearRetainingCapacity();
        serializeNote(&note, &self.scratch, self.repo.allocator) catch {
            e.returnString("null");
            return;
        };
        const owned = self.scratch.toOwnedSliceSentinel(self.repo.allocator, 0) catch {
            e.returnString("null");
            return;
        };
        e.returnString(owned);
    }

    pub fn handleSearchNotes(self: *Self, e: *webui.Event) void {
        const query = e.getString();
        self.scratch.clearRetainingCapacity();
        Jw.writeStr(&self.scratch, self.repo.allocator, "{\"notes\":{") catch {
            e.returnString("{}");
            return;
        };
        var iter = self.repo.notes.iterator();
        var first = true;
        while (iter.next()) |entry| {
            const note = entry.value_ptr.*;
            if (note.archived) continue;

            // Zero-allocation case-insensitive substring search
            const name_match = containsIgnoreCase(note.name, query);
            const content_match = containsIgnoreCase(note.content, query);
            if (!name_match and !content_match) continue;

            if (!first) Jw.writeStr(&self.scratch, self.repo.allocator, ",") catch break;
            first = false;
            Jw.writeKey(&self.scratch, self.repo.allocator, entry.key_ptr.*) catch break;
            Jw.writeStr(&self.scratch, self.repo.allocator, ":") catch break;
            serializeNote(&note, &self.scratch, self.repo.allocator) catch break;
        }
        Jw.writeStr(&self.scratch, self.repo.allocator, "}}") catch {
            e.returnString("{}");
            return;
        };
        const owned = self.scratch.toOwnedSliceSentinel(self.repo.allocator, 0) catch {
            e.returnString("{}");
            return;
        };
        e.returnString(owned);
    }
};

/// Case-insensitive substring search — zero allocations.
/// Returns true if `needle` is found within `haystack` (ASCII case-insensitive).
fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    const end = haystack.len - needle.len + 1;
    for (0..end) |i| {
        if (matchIgnoreCase(haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

/// Compare two equal-length slices case-insensitively (ASCII).
fn matchIgnoreCase(a: []const u8, b: []const u8) bool {
    for (a, b) |ca, cb| {
        if (std.ascii.toLower(ca) != std.ascii.toLower(cb)) return false;
    }
    return true;
}

fn serializeNote(note: *const Note, buf: *std.ArrayList(u8), allocator: Allocator) !void {
    try Jw.writeStr(buf, allocator, "{\"id\":\"");
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

fn serializeNotesBrief(repo: *NoteRepository, buf: *std.ArrayList(u8), allocator: Allocator) !void {
    try Jw.writeStr(buf, allocator, "{\"notes\":{");
    var iter = repo.notes.iterator();
    var first = true;
    while (iter.next()) |entry| {
        const note = entry.value_ptr.*;
        if (note.archived) continue;
        if (!first) try Jw.writeStr(buf, allocator, ",");
        first = false;
        try Jw.writeKey(buf, allocator, entry.key_ptr.*);
        try Jw.writeStr(buf, allocator, ":");
        try serializeNote(&note, buf, allocator);
    }
    try Jw.writeStr(buf, allocator, "}}");
}

// ─── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;

test "containsIgnoreCase: basic match" {
    try testing.expect(containsIgnoreCase("Hello World", "hello"));
    try testing.expect(containsIgnoreCase("Hello World", "WORLD"));
    try testing.expect(containsIgnoreCase("Hello World", "lo Wo"));
}

test "containsIgnoreCase: no match" {
    try testing.expect(!containsIgnoreCase("Hello World", "xyz"));
    try testing.expect(!containsIgnoreCase("Hi", "Hello"));
}

test "containsIgnoreCase: empty needle" {
    try testing.expect(containsIgnoreCase("anything", ""));
    try testing.expect(containsIgnoreCase("", ""));
}

test "containsIgnoreCase: exact match" {
    try testing.expect(containsIgnoreCase("abc", "abc"));
    try testing.expect(containsIgnoreCase("ABC", "abc"));
}

test "matchIgnoreCase: equal length slices" {
    try testing.expect(matchIgnoreCase("Hello", "hELLO"));
    try testing.expect(!matchIgnoreCase("Hello", "World"));
}

test "serializeNote: produces valid JSON" {
    const note = Note{
        .id = "test-1",
        .name = "My Note",
        .content = "Hello \"world\"",
        .created_at = "2026-01-01",
        .archived = false,
    };
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(testing.allocator);
    try serializeNote(&note, &buf, testing.allocator);
    const result = buf.items;
    // Verify it contains expected fields
    try testing.expect(std.mem.indexOf(u8, result, "\"id\":\"test-1\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"name\":\"My Note\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\"archived\":false") != null);
    // Verify escaped quotes in content
    try testing.expect(std.mem.indexOf(u8, result, "\\\"world\\\"") != null);
}
