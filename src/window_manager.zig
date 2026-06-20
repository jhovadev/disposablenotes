const std = @import("std");
const Allocator = std.mem.Allocator;
const webui = @import("webui");
const events = @import("events.zig");
const Event = events.Event;
const EventType = events.EventType;
const json_writer = @import("json_writer.zig");
const FixedJsonWriter = json_writer.FixedJsonWriter;

/// Busy-wait spinlock wrapping std.atomic.Mutex (which only has tryLock).
const SpinMutex = struct {
    inner: std.atomic.Mutex = .unlocked,

    fn lock(m: *SpinMutex) void {
        while (!std.atomic.Mutex.tryLock(&m.inner)) {}
    }

    fn unlock(m: *SpinMutex) void {
        std.atomic.Mutex.unlock(&m.inner);
    }
};

pub const WindowManager = struct {
    const Self = @This();

    windows: std.ArrayList(webui),
    allocator: Allocator,
    mutex: SpinMutex,

    pub fn init(allocator: Allocator) WindowManager {
        return .{
            .windows = .empty,
            .allocator = allocator,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.windows.deinit(self.allocator);
    }

    pub fn addWindow(self: *Self, window: webui) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.windows.append(self.allocator, window);
    }

    pub fn removeWindow(self: *Self, window: webui) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        const items = self.windows.items;
        for (items, 0..) |w, i| {
            if (std.meta.eql(w, window)) {
                _ = self.windows.orderedRemove(i);
                std.debug.print("[WM] Removed window, {d} remaining\n", .{self.windows.items.len});
                return;
            }
        }
    }

    pub fn count(self: *Self) usize {
        return self.windows.items.len;
    }

    pub fn broadcastEvent(self: *Self, event: Event) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var json_buf: [4096]u8 = undefined;
        const json_part = buildEventJson(&json_buf, event) catch |err| {
            std.debug.print("[WM] build json error: {any}\n", .{err});
            return;
        };
        var js_buf: [8192]u8 = undefined;
        const js = std.fmt.bufPrint(&js_buf,
            "window.dispatchEvent(new CustomEvent('note-event', {{detail: {s}}}))",
            .{json_part},
        ) catch |err| {
            std.debug.print("[WM] js format error: {any}\n", .{err});
            return;
        };
        js_buf[js.len] = 0;
        const js_z: [:0]u8 = js_buf[0..js.len :0];
        const n_windows = self.windows.items.len;
        std.debug.print("[WM] Broadcasting {s} event (id={s}) to {d} windows\n", .{ event.type.toString(), event.id, n_windows });
        for (self.windows.items) |win| {
            win.run(js_z);
        }
    }
};

fn buildEventJson(buf: []u8, event: Event) ![]const u8 {
    var pos: usize = 0;
    try FixedJsonWriter.writeStr(buf, &pos, "{\"type\":\"");
    try FixedJsonWriter.writeStr(buf, &pos, event.type.toString());
    try FixedJsonWriter.writeStr(buf, &pos, "\",\"id\":\"");
    try FixedJsonWriter.writeStr(buf, &pos, event.id);
    try FixedJsonWriter.writeStr(buf, &pos, "\"");
    if (event.name) |name| {
        try FixedJsonWriter.writeStr(buf, &pos, ",\"name\":");
        try FixedJsonWriter.writeEscaped(buf, &pos, name);
    }
    if (event.content) |content| {
        try FixedJsonWriter.writeStr(buf, &pos, ",\"content\":");
        try FixedJsonWriter.writeEscaped(buf, &pos, content);
    }
    if (event.archived) {
        try FixedJsonWriter.writeStr(buf, &pos, ",\"archived\":true");
    }
    if (event.client_id) |client_id| {
        try FixedJsonWriter.writeStr(buf, &pos, ",\"clientId\":");
        try FixedJsonWriter.writeEscaped(buf, &pos, client_id);
    }
    try FixedJsonWriter.writeStr(buf, &pos, "}");
    return buf[0..pos];
}
