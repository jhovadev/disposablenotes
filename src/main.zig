const std = @import("std");
const Io = std.Io;
const webui = @import("webui");
const repository = @import("repository.zig");
const events = @import("events.zig");
const persistence = @import("persistence.zig");
const window_manager = @import("window_manager.zig");
const commands = @import("commands.zig");
const queries = @import("queries.zig");
const storage = @import("storage.zig");
const json_storage = @import("json_storage.zig");
const build_options = @import("build_options");

const NoteRepository = repository.NoteRepository;
const EventBus = events.EventBus;
const PersistenceService = persistence.PersistenceService;
const WindowManager = window_manager.WindowManager;
const CommandBus = commands.CommandBus;
const QueryBus = queries.QueryBus;
const StorageFormat = storage.StorageFormat;
const StorageAdapter = storage.StorageAdapter;
const JsonStorage = json_storage.JsonStorage;

var app_repo: NoteRepository = undefined;
var app_event_bus: EventBus = undefined;
var app_wm: WindowManager = undefined;
var app_cmd_bus: CommandBus = undefined;
var app_query_bus: QueryBus = undefined;
var app_persistence: PersistenceService = undefined;
var app_running: bool = true;

fn close_app(_: *webui.Event) void {
    std.debug.print("[Main] Exit requested, closing windows...\n", .{});
    webui.exit();
}

fn handle_close_window(_: *webui.Event) void {
    std.debug.print("[Main] Close window requested.\n", .{});
    webui.exit();
}

fn handle_upsert_note(e: *webui.Event) void {
    std.debug.print("[Main] ⬇ upsert_note called\n", .{});
    app_cmd_bus.handleUpsertNote(e);
    std.debug.print("[Main] upsert_note done\n", .{});
}

fn handle_delete_note(e: *webui.Event) void {
    std.debug.print("[Main] ⬇ delete_note called\n", .{});
    app_cmd_bus.handleDeleteNote(e);
    std.debug.print("[Main] delete_note done\n", .{});
}

fn handle_archive_note(e: *webui.Event) void {
    std.debug.print("[Main] ⬇ archive_note called\n", .{});
    app_cmd_bus.handleArchiveNote(e);
    std.debug.print("[Main] archive_note done\n", .{});
}

fn handle_get_notes(e: *webui.Event) void {
    std.debug.print("[Main] ⬇ get_notes called\n", .{});
    app_query_bus.handleGetNotes(e);
}

fn handle_get_note(e: *webui.Event) void {
    app_query_bus.handleGetNote(e);
}

fn handle_open_new_window(e: *webui.Event) void {
    const note_id = e.getString();
    std.debug.print("[Zig] Opening new window for note: {s}\n", .{note_id});
    var new_win = webui.newWindow();
    bind_window(new_win);
    app_wm.addWindow(new_win) catch |err| {
        std.debug.print("[Zig] Error adding window: {any}\n", .{err});
        return;
    };
    if (build_options.dev_mode) {
        const free_port = webui.getFreePort();
        new_win.setPort(free_port) catch |err| {
            std.debug.print("[Zig] Error setting port {d}: {any}\n", .{free_port, err});
        };
        var url_buf: [128]u8 = undefined;
        const url_str = std.fmt.bufPrint(&url_buf, "http://localhost:{d}/?webui_port={d}", .{build_options.vite_dev_port, free_port}) catch "http://localhost:5173";
        var url_z_buf: [128]u8 = undefined;
        @memcpy(url_z_buf[0..url_str.len], url_str);
        url_z_buf[url_str.len] = 0;
        const url_z: [:0]const u8 = url_z_buf[0..url_str.len :0];
        _ = new_win.showBrowser(url_z, .AnyBrowser) catch {};
    } else {
        _ = new_win.showWv("./frontend/dist") catch {};
    }
    var js_buf: [512]u8 = undefined;
    const js = std.fmt.bufPrint(
        &js_buf,
        \\setTimeout(function(){{history.pushState({{}},'','/{s}');window.dispatchEvent(new PopStateEvent('popstate'))}},150)
    ,
        .{note_id},
    ) catch |err| {
        std.debug.print("[Zig] JS format error: {any}\n", .{err});
        return;
    };
    js_buf[js.len] = 0;
    const js_z: [:0]const u8 = js_buf[0..js.len :0];
    new_win.run(js_z);
    std.debug.print("[Zig] New window navigated to /{s} after page load\n", .{note_id});
}

fn bind_window(window: webui) void {
    _ = window.bind("upsert_note", handle_upsert_note) catch {};
    _ = window.bind("delete_note", handle_delete_note) catch {};
    _ = window.bind("archive_note", handle_archive_note) catch {};
    _ = window.bind("get_notes", handle_get_notes) catch {};
    _ = window.bind("get_note", handle_get_note) catch {};
    _ = window.bind("open_new_window", handle_open_new_window) catch {};
    _ = window.bind("close_window", handle_close_window) catch {};
    _ = window.bind("Exit", close_app) catch {};
}

fn saverLoop() void {
    const linux = std.os.linux;
    while (true) {
        var ts = linux.timespec{ .sec = 5, .nsec = 0 };
        _ = linux.nanosleep(&ts, null);
        if (!app_running) break;
        app_persistence.flush() catch |err| {
            std.debug.print("[Saver] flush error: {any}\n", .{err});
        };
    }
}

const usage =
    \\Usage: zig_disposable_notes [file] [options]
    \\
    \\Arguments:
    \\  file              Path to notes file
    \\                    (default: ~/.disposablenotes/notes.json)
    \\
    \\Options:
    \\  --help            Show this help message
    \\
;

const CliArgs = struct {
    file_path: []const u8,
};

fn parseArgs(args: []const [:0]const u8) CliArgs {
    var file_path: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print("{s}", .{usage});
            std.process.exit(0);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            std.debug.print("[Main] error: unknown option '{s}'\n", .{arg});
            std.process.exit(1);
        } else {
            file_path = arg;
        }
    }
    if (file_path) |fp| {
        return .{ .file_path = fp };
    }
    return .{ .file_path = "~/.disposablenotes/notes.json" };
}

fn resolvePath(allocator: std.mem.Allocator, path: []const u8, environ_map: std.process.Environ.Map) ![]const u8 {
    if (std.mem.startsWith(u8, path, "~")) {
        const home = environ_map.get("HOME") orelse {
            std.debug.print("[Main] warning: HOME environment variable not set, using path as-is\n", .{});
            return try allocator.dupe(u8, path);
        };
        if (std.mem.startsWith(u8, path, "~/")) {
            return try std.fs.path.join(allocator, &[_][]const u8{ home, path[2..] });
        } else if (std.mem.startsWith(u8, path, "~\\")) {
            return try std.fs.path.join(allocator, &[_][]const u8{ home, path[2..] });
        } else if (std.mem.eql(u8, path, "~")) {
            return try allocator.dupe(u8, home);
        } else {
            return try std.fs.path.join(allocator, &[_][]const u8{ home, path[1..] });
        }
    }
    return try allocator.dupe(u8, path);
}

pub fn main(init: std.process.Init) !void {
    std.debug.print("[Zig] Starting CQRS-based notes app...\n", .{});
    const allocator = init.arena.allocator();
    const args_slice = try init.minimal.args.toSlice(allocator);
    const cli = parseArgs(args_slice);

    if (build_options.dev_mode) {
        webui.setConfig(.use_cookies, false);
        webui.setConfig(.multi_client, true);
    }

    const resolved_path = try resolvePath(allocator, cli.file_path, init.environ_map.*);
    std.debug.print("[Main] File: {s}, Format: json\n", .{resolved_path});

    // Auto-create parent directory if missing
    if (std.fs.path.dirname(resolved_path)) |dir_path| {
        if (dir_path.len > 0) {
            Io.Dir.createDirPath(.cwd(), init.io, dir_path) catch |err| {
                std.debug.print("[Main] warning: failed to create directory '{s}': {any}\n", .{ dir_path, err });
            };
        }
    }

    app_repo = NoteRepository.init(allocator);
    app_event_bus = EventBus.init(allocator);
    app_wm = WindowManager.init(allocator);
    app_cmd_bus = CommandBus.init(&app_repo, &app_event_bus, &app_wm);
    app_query_bus = QueryBus.init(&app_repo);

    const store = try allocator.create(JsonStorage);
    store.* = JsonStorage.init(resolved_path);
    const adapter = store.adapter();
    app_persistence = PersistenceService.init(&app_repo, adapter);
    app_persistence.setIo(init.io);
    app_persistence.loadFromDisk() catch |err| {
        std.debug.print("[Main] Load error (starting fresh): {any}\n", .{err});
    };
    std.debug.print("[Main] Notes in repo after load: {d}\n", .{app_repo.notes.count()});
    const saver = try std.Thread.spawn(.{}, saverLoop, .{});

    var bun_child: ?std.process.Child = null;
    if (build_options.dev_mode) {
        std.debug.print("[Main] Spawning frontend dev server (bun run dev)...\n", .{});
        bun_child = std.process.spawn(init.io, .{
            .argv = &[_][]const u8{ "bun", "run", "dev" },
            .cwd = .{ .path = "frontend" },
        }) catch |err| blk: {
            std.debug.print("[Main] warning: failed to spawn frontend dev server: {any}\n", .{err});
            break :blk null;
        };
    }

    var main_window = webui.newWindow();
    if (build_options.dev_mode) {
        main_window.setPort(build_options.webui_port) catch |err| {
            std.debug.print("[Main] warning: failed to set webui port {d}: {any}\n", .{ build_options.webui_port, err });
        };
    }
    bind_window(main_window);
    app_wm.addWindow(main_window) catch |err| {
        std.debug.print("[Main] Error adding main window: {any}\n", .{err});
    };
    if (build_options.dev_mode) {
        var url_buf: [128]u8 = undefined;
        const url_str = std.fmt.bufPrint(&url_buf, "http://localhost:{d}", .{build_options.vite_dev_port}) catch "http://localhost:5173";
        var url_z_buf: [128]u8 = undefined;
        @memcpy(url_z_buf[0..url_str.len], url_str);
        url_z_buf[url_str.len] = 0;
        const url_z: [:0]const u8 = url_z_buf[0..url_str.len :0];
        _ = main_window.showBrowser(url_z, .AnyBrowser) catch {};
    } else {
        _ = main_window.showWv("./frontend/dist") catch {};
    }
    std.debug.print("[Main] Window opened, waiting...\n", .{});
    webui.wait();
    std.debug.print("[Main] Shutting down...\n", .{});
    app_running = false;
    saver.join();
    std.debug.print("[Main] Flushing final state...\n", .{});
    app_persistence.flush() catch |err| {
        std.debug.print("[Main] Final flush error: {any}\n", .{err});
    };
    if (bun_child) |*c| {
        std.debug.print("[Main] Killing frontend dev server...\n", .{});
        c.kill(init.io);
    }
    app_repo.deinit();
    std.debug.print("[Main] Shutdown complete.\n", .{});
    webui.clean();
}
