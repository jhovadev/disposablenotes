const std = @import("std");
const webui = @import("webui");
const repository = @import("repository.zig");
const NoteRepository = repository.NoteRepository;
const events = @import("events.zig");
const Event = events.Event;
const EventType = events.EventType;
const EventBus = events.EventBus;
const window_manager = @import("window_manager.zig");
const WindowManager = window_manager.WindowManager;

/// Parsed command payload from frontend JSON.
const CommandPayload = struct {
    id: []const u8,
    name: ?[]const u8,
    content: ?[]const u8,
    created_at: ?[]const u8,
    client_id: ?[]const u8,
};

/// Parse a JSON command payload, extracting id (required) and optional fields.
/// Returns null if JSON is invalid or missing required 'id' field.
fn parseCommandPayload(allocator: std.mem.Allocator, json_str: [:0]const u8) ?CommandPayload {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch return null;
    defer parsed.deinit();
    const root = parsed.value;
    if (root != .object) return null;

    const id = if (root.object.get("id")) |v| switch (v) {
        .string => |s| s,
        else => return null,
    } else return null;

    const name = if (root.object.get("name")) |v| switch (v) {
        .string => |s| s,
        else => null,
    } else null;

    const content = if (root.object.get("content")) |v| switch (v) {
        .string => |s| s,
        else => null,
    } else null;

    const created_at = if (root.object.get("createdAt")) |v| switch (v) {
        .string => |s| s,
        else => null,
    } else null;

    const client_id = if (root.object.get("clientId")) |v| switch (v) {
        .string => |s| s,
        else => null,
    } else null;

    // Dupe strings to outlive parsed scope
    return CommandPayload{
        .id = allocator.dupe(u8, id) catch return null,
        .name = if (name) |n| allocator.dupe(u8, n) catch return null else null,
        .content = if (content) |c| allocator.dupe(u8, c) catch return null else null,
        .created_at = if (created_at) |ca| allocator.dupe(u8, ca) catch return null else null,
        .client_id = if (client_id) |ci| allocator.dupe(u8, ci) catch return null else null,
    };
}

pub const CommandBus = struct {
    const Self = @This();

    repo: *NoteRepository,
    event_bus: *EventBus,
    window_manager: *WindowManager,

    pub fn init(repo: *NoteRepository, bus: *EventBus, wm: *WindowManager) CommandBus {
        return .{
            .repo = repo,
            .event_bus = bus,
            .window_manager = wm,
        };
    }

    pub fn handleUpsertNote(self: *Self, e: *webui.Event) void {
        const json_str = e.getString();
        const payload = parseCommandPayload(self.repo.allocator, json_str) orelse {
            e.returnBool(false);
            return;
        };

        const is_new = self.repo.getNote(payload.id) == null;
        if (is_new) {
            const name = if (payload.name) |n| n else "";
            const content = if (payload.content) |c| c else "";
            const ca = if (payload.created_at) |c| if (c.len > 0) c else "unknown" else "unknown";
            std.debug.print("[Cmd] Creating note id={s} name={s}\n", .{ payload.id, name });
            self.repo.createNote(payload.id, name, content, ca) catch {
                e.returnBool(false);
                return;
            };
            const ev = Event{
                .type = EventType.note_created,
                .id = payload.id,
                .name = if (name.len > 0) name else null,
                .content = if (content.len > 0) content else null,
                .client_id = payload.client_id,
            };
            self.event_bus.publish(ev);
            self.window_manager.broadcastEvent(ev);
        } else {
            std.debug.print("[Cmd] Updating note id={s}\n", .{payload.id});
            self.repo.updateNote(payload.id, payload.name, payload.content, null) catch {
                e.returnBool(false);
                return;
            };
            const ev = Event{
                .type = EventType.note_updated,
                .id = payload.id,
                .name = payload.name,
                .content = payload.content,
                .client_id = payload.client_id,
            };
            self.event_bus.publish(ev);
            self.window_manager.broadcastEvent(ev);
        }
        e.returnBool(true);
    }

    pub fn handleDeleteNote(self: *Self, e: *webui.Event) void {
        const json_str = e.getString();
        const payload = parseCommandPayload(self.repo.allocator, json_str) orelse {
            e.returnBool(false);
            return;
        };

        self.repo.deleteNote(payload.id);
        const ev = Event{
            .type = EventType.note_deleted,
            .id = payload.id,
            .client_id = payload.client_id,
        };
        self.event_bus.publish(ev);
        self.window_manager.broadcastEvent(ev);
        e.returnBool(true);
    }

    pub fn handleArchiveNote(self: *Self, e: *webui.Event) void {
        const json_str = e.getString();
        const payload = parseCommandPayload(self.repo.allocator, json_str) orelse {
            e.returnBool(false);
            return;
        };

        std.debug.print("[Cmd] Archiving note id={s}\n", .{payload.id});
        self.repo.updateNote(payload.id, null, null, true) catch {
            e.returnBool(false);
            return;
        };
        const ev = Event{
            .type = EventType.note_archived,
            .id = payload.id,
            .archived = true,
            .client_id = payload.client_id,
        };
        self.event_bus.publish(ev);
        self.window_manager.broadcastEvent(ev);
        e.returnBool(true);
    }
};
