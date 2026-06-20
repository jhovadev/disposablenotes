const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EventType = enum {
    note_created,
    note_updated,
    note_deleted,
    note_archived,

    pub fn toString(self: EventType) []const u8 {
        return switch (self) {
            .note_created => "note_created",
            .note_updated => "note_updated",
            .note_deleted => "note_deleted",
            .note_archived => "note_archived",
        };
    }
};

pub const Event = struct {
    type: EventType,
    id: []const u8,
    name: ?[]const u8 = null,
    content: ?[]const u8 = null,
    archived: bool = false,
    client_id: ?[]const u8 = null,
};

pub const Listener = *const fn (event: Event) void;

pub const EventBus = struct {
    listeners: std.ArrayList(Listener),
    allocator: Allocator,

    pub fn init(allocator: Allocator) EventBus {
        return .{
            .listeners = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EventBus) void {
        self.listeners.deinit(self.allocator);
    }

    pub fn subscribe(self: *EventBus, listener: Listener) void {
        self.listeners.append(self.allocator, listener) catch |err| {
            std.debug.print("[EventBus] subscribe error: {any}\n", .{err});
        };
    }

    pub fn publish(self: *EventBus, event: Event) void {
        for (self.listeners.items) |listener| {
            listener(event);
        }
    }

    pub fn listenerCount(self: *EventBus) usize {
        return self.listeners.items.len;
    }
};

// ─── Tests ──────────────────────────────────────────────────────────

const testing = std.testing;

var test_event_count: usize = 0;
var test_last_event_type: ?EventType = null;
var test_last_event_id: ?[]const u8 = null;

fn testListener(event: Event) void {
    test_event_count += 1;
    test_last_event_type = event.type;
    test_last_event_id = event.id;
}

var test_second_count: usize = 0;

fn testSecondListener(_: Event) void {
    test_second_count += 1;
}

test "EventBus: subscribe and publish" {
    test_event_count = 0;
    test_last_event_type = null;
    test_last_event_id = null;

    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    bus.subscribe(testListener);
    try testing.expectEqual(@as(usize, 1), bus.listenerCount());

    const event = Event{
        .type = .note_created,
        .id = "test-id-1",
        .name = "Test Note",
    };
    bus.publish(event);

    try testing.expectEqual(@as(usize, 1), test_event_count);
    try testing.expect(test_last_event_type.? == .note_created);
    try testing.expectEqualStrings("test-id-1", test_last_event_id.?);
}

test "EventBus: multiple listeners" {
    test_event_count = 0;
    test_second_count = 0;

    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    bus.subscribe(testListener);
    bus.subscribe(testSecondListener);
    try testing.expectEqual(@as(usize, 2), bus.listenerCount());

    bus.publish(Event{ .type = .note_deleted, .id = "del-1" });

    try testing.expectEqual(@as(usize, 1), test_event_count);
    try testing.expectEqual(@as(usize, 1), test_second_count);
}

test "EventBus: publish with no listeners" {
    var bus = EventBus.init(testing.allocator);
    defer bus.deinit();

    // Should not crash
    bus.publish(Event{ .type = .note_updated, .id = "no-listener" });
}

test "EventType.toString returns correct strings" {
    try testing.expectEqualStrings("note_created", EventType.note_created.toString());
    try testing.expectEqualStrings("note_updated", EventType.note_updated.toString());
    try testing.expectEqualStrings("note_deleted", EventType.note_deleted.toString());
    try testing.expectEqualStrings("note_archived", EventType.note_archived.toString());
}
