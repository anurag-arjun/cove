//! Socket command dispatch for Cove CLI protocol.
//!
//! Parses JSON requests and dispatches to handler functions.
//! All handlers run on the GTK main thread (GLib FD callbacks are main-thread).
//!
//! Design ref: cmux CLI/cmux.swift command handlers ~L858+.

const std = @import("std");
const Allocator = std.mem.Allocator;
const adw = @import("adw");
const glib = @import("glib");
const gobject = @import("gobject");
const gtk = @import("gtk");

const Application = @import("class/application.zig").Application;
const Window = @import("class/window.zig").Window;
const Tab = @import("class/tab.zig").Tab;
const Surface = @import("class/surface.zig").Surface;
const NotificationStore = @import("notification_store.zig");
const git_branch = @import("git_branch.zig");
const path_shorten = @import("path_shorten.zig");
const SocketServer = @import("socket_server.zig");

const log = std.log.scoped(.socket_commands);

/// Maximum JSON response size.
const max_response = 64 * 1024;

/// Monotonic workspace ID counter. Assigned to tab pages via setData.
var next_workspace_id: u64 = 1;

/// Command handler that plugs into SocketServer.
pub fn createHandler() SocketServer.CommandHandler {
    return .{
        .ctx = undefined,
        .handler = &dispatch,
    };
}

fn dispatch(_: *anyopaque, request: []const u8, response_buf: []u8) usize {
    return dispatchInner(request, response_buf) catch |err| {
        return writeError(response_buf, "internal error", "INTERNAL", err);
    };
}

fn dispatchInner(request: []const u8, response_buf: []u8) !usize {
    const alloc = std.heap.page_allocator;
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, request, .{}) catch {
        return writeErrorSimple(response_buf, "invalid JSON", "PARSE_ERROR");
    };
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) {
        return writeErrorSimple(response_buf, "expected JSON object", "PARSE_ERROR");
    }

    const cmd_val = root.object.get("command") orelse {
        return writeErrorSimple(response_buf, "missing 'command' field", "PARSE_ERROR");
    };
    if (cmd_val != .string) {
        return writeErrorSimple(response_buf, "'command' must be a string", "PARSE_ERROR");
    }
    const cmd = cmd_val.string;

    if (std.mem.eql(u8, cmd, "ping")) return cmdPing(response_buf);
    if (std.mem.eql(u8, cmd, "list-workspaces")) return cmdListWorkspaces(response_buf);
    if (std.mem.eql(u8, cmd, "new-workspace")) return cmdNewWorkspace(response_buf);
    if (std.mem.eql(u8, cmd, "close-workspace")) return cmdCloseWorkspace(root.object, response_buf);
    if (std.mem.eql(u8, cmd, "select-workspace")) return cmdSelectWorkspace(root.object, response_buf);
    if (std.mem.eql(u8, cmd, "rename-workspace")) return cmdRenameWorkspace(root.object, response_buf);
    if (std.mem.eql(u8, cmd, "list-notifications")) return cmdListNotifications(root.object, response_buf);
    if (std.mem.eql(u8, cmd, "mark-read")) return cmdMarkRead(root.object, response_buf);
    if (std.mem.eql(u8, cmd, "notify")) return cmdNotify(root.object, response_buf);
    if (std.mem.eql(u8, cmd, "jump-to-unread")) return cmdJumpToUnread(response_buf);

    return writeErrorSimple(response_buf, "unknown command. Available: ping, list-workspaces, new-workspace, close-workspace, select-workspace, rename-workspace, list-notifications, mark-read, notify, jump-to-unread", "UNKNOWN_COMMAND");
}

// --- Command handlers ---

fn cmdPing(buf: []u8) usize {
    return writeOk(buf);
}

fn cmdListWorkspaces(buf: []u8) usize {
    const window = getWindow() orelse return writeErrorSimple(buf, "no window", "NO_WINDOW");
    const tab_view = window.getTabView();
    const n_pages = tab_view.getNPages();
    const app = Application.default();
    const store = app.notificationStore();
    const home = std.posix.getenv("HOME") orelse "";

    // Build JSON array manually into buffer.
    var pos: usize = 0;
    pos += writeStr(buf[pos..], "{\"ok\":true,\"data\":[");

    var i: c_int = 0;
    while (i < n_pages) : (i += 1) {
        if (i > 0) pos += writeStr(buf[pos..], ",");

        const page = tab_view.getNthPage(i);
        const ws_id = getOrAssignWorkspaceId(page);
        const title: []const u8 = std.mem.span(page.getTitle());
        const tab_id: NotificationStore.TabId = @intFromPtr(page);
        const unread = store.unreadCountForTab(tab_id);

        // Get PWD and git branch from active surface.
        var pwd_str: []const u8 = "";
        var branch_str: []const u8 = "";
        var shorten_buf: [512]u8 = undefined;
        var git_buf: [4096]u8 = undefined;

        const child = page.getChild();
        if (gobject.ext.cast(Tab, child)) |tab| {
            if (tab.getActiveSurface()) |surface| {
                if (surface.getPwd()) |pwd_raw| {
                    const pwd: []const u8 = pwd_raw;
                    pwd_str = path_shorten.shorten(pwd, home, &shorten_buf, 3);
                    if (git_branch.detect(pwd, &git_buf)) |info| {
                        branch_str = switch (info) {
                            .branch => |b| b,
                            .detached => |h| h,
                        };
                    }
                }
            }
        }

        const is_selected = if (tab_view.getSelectedPage()) |sel| sel == page else false;

        // Write workspace JSON object.
        pos += writeStr(buf[pos..], "{\"id\":");
        pos += writeInt(buf[pos..], ws_id);
        pos += writeStr(buf[pos..], ",\"title\":");
        pos += writeJsonString(buf[pos..], title);
        pos += writeStr(buf[pos..], ",\"pwd\":");
        pos += writeJsonString(buf[pos..], pwd_str);
        pos += writeStr(buf[pos..], ",\"git_branch\":");
        pos += writeJsonString(buf[pos..], branch_str);
        pos += writeStr(buf[pos..], ",\"unread_count\":");
        pos += writeInt(buf[pos..], unread);
        pos += writeStr(buf[pos..], ",\"selected\":");
        pos += writeStr(buf[pos..], if (is_selected) "true" else "false");
        pos += writeStr(buf[pos..], "}");
    }

    pos += writeStr(buf[pos..], "]}\n");
    return pos;
}

fn cmdNewWorkspace(buf: []u8) usize {
    const window = getWindow() orelse return writeErrorSimple(buf, "no window", "NO_WINDOW");
    window.newTab(null);

    // The new tab was added — find it (it's the selected page now).
    const tab_view = window.getTabView();
    if (tab_view.getSelectedPage()) |page| {
        const ws_id = getOrAssignWorkspaceId(page);
        var pos: usize = 0;
        pos += writeStr(buf[pos..], "{\"ok\":true,\"id\":");
        pos += writeInt(buf[pos..], ws_id);
        pos += writeStr(buf[pos..], "}\n");
        return pos;
    }

    return writeOk(buf);
}

fn cmdCloseWorkspace(obj: std.json.ObjectMap, buf: []u8) usize {
    const id = getIdParam(obj) orelse return writeErrorSimple(buf, "missing 'id' parameter", "MISSING_PARAM");
    const page = findPageById(id) orelse return writeErrorSimple(buf, "workspace not found", "NOT_FOUND");
    const window = getWindow() orelse return writeErrorSimple(buf, "no window", "NO_WINDOW");
    const tab_view = window.getTabView();
    tab_view.closePage(page);
    return writeOk(buf);
}

fn cmdSelectWorkspace(obj: std.json.ObjectMap, buf: []u8) usize {
    const id = getIdParam(obj) orelse return writeErrorSimple(buf, "missing 'id' parameter", "MISSING_PARAM");
    const page = findPageById(id) orelse return writeErrorSimple(buf, "workspace not found", "NOT_FOUND");
    const window = getWindow() orelse return writeErrorSimple(buf, "no window", "NO_WINDOW");
    window.getTabView().setSelectedPage(page);
    return writeOk(buf);
}

fn cmdRenameWorkspace(obj: std.json.ObjectMap, buf: []u8) usize {
    const id = getIdParam(obj) orelse return writeErrorSimple(buf, "missing 'id' parameter", "MISSING_PARAM");
    const page = findPageById(id) orelse return writeErrorSimple(buf, "workspace not found", "NOT_FOUND");

    const name_val = obj.get("name") orelse return writeErrorSimple(buf, "missing 'name' parameter", "MISSING_PARAM");
    if (name_val != .string) return writeErrorSimple(buf, "'name' must be a string", "INVALID_PARAM");

    // Set title on the tab page.
    const child = page.getChild();
    if (gobject.ext.cast(Tab, child)) |tab| {
        // Use the tab's title override mechanism.
        const alloc = std.heap.page_allocator;
        const name_z = alloc.dupeZ(u8, name_val.string) catch return writeErrorSimple(buf, "allocation failed", "INTERNAL");
        defer alloc.free(name_z);
        tab.setTitleOverride(name_z);
    }

    return writeOk(buf);
}

fn cmdListNotifications(obj: std.json.ObjectMap, buf: []u8) usize {
    const app = Application.default();
    const store = app.notificationStore();

    // Optional workspace_id filter.
    const filter_id = getIdParam(obj);
    const filter_tab: ?NotificationStore.TabId = if (filter_id) |id| blk: {
        const page = findPageById(id) orelse return writeErrorSimple(buf, "workspace not found", "NOT_FOUND");
        break :blk @intFromPtr(page);
    } else null;

    var pos: usize = 0;
    pos += writeStr(buf[pos..], "{\"ok\":true,\"data\":[");

    var first = true;
    for (store.notifications.items) |n| {
        if (filter_tab) |ft| {
            if (n.tab_id != ft) continue;
        }
        if (!first) pos += writeStr(buf[pos..], ",");
        first = false;

        pos += writeStr(buf[pos..], "{\"id\":");
        pos += writeInt(buf[pos..], n.id);
        pos += writeStr(buf[pos..], ",\"title\":");
        pos += writeJsonString(buf[pos..], n.title);
        pos += writeStr(buf[pos..], ",\"body\":");
        pos += writeJsonString(buf[pos..], n.body);
        pos += writeStr(buf[pos..], ",\"is_read\":");
        pos += writeStr(buf[pos..], if (n.is_read) "true" else "false");
        pos += writeStr(buf[pos..], ",\"created_at\":");
        pos += writeInt(buf[pos..], @as(u64, @intCast(n.created_at)));
        pos += writeStr(buf[pos..], "}");
    }

    pos += writeStr(buf[pos..], "]}\n");
    return pos;
}

fn cmdMarkRead(obj: std.json.ObjectMap, buf: []u8) usize {
    const id = getIdParam(obj) orelse {
        // Mark all read if no id specified.
        const app = Application.default();
        const store = app.notificationStore();
        _ = store.markAllRead();
        return writeOk(buf);
    };
    const page = findPageById(id) orelse return writeErrorSimple(buf, "workspace not found", "NOT_FOUND");
    const tab_id: NotificationStore.TabId = @intFromPtr(page);
    const app = Application.default();
    const store = app.notificationStore();
    _ = store.markReadForTab(tab_id);
    return writeOk(buf);
}

fn cmdNotify(obj: std.json.ObjectMap, buf: []u8) usize {
    const id = getIdParam(obj) orelse return writeErrorSimple(buf, "missing 'id' parameter (workspace_id)", "MISSING_PARAM");
    const page = findPageById(id) orelse return writeErrorSimple(buf, "workspace not found", "NOT_FOUND");
    const tab_id: NotificationStore.TabId = @intFromPtr(page);

    const title_val = obj.get("title") orelse return writeErrorSimple(buf, "missing 'title'", "MISSING_PARAM");
    if (title_val != .string) return writeErrorSimple(buf, "'title' must be a string", "INVALID_PARAM");

    var body: []const u8 = "";
    if (obj.get("body")) |body_val| {
        if (body_val == .string) body = body_val.string;
    }

    const app = Application.default();
    const store = app.notificationStore();
    _ = store.add(tab_id, null, title_val.string, "", body, null, false) catch {
        return writeErrorSimple(buf, "failed to add notification", "INTERNAL");
    };

    return writeOk(buf);
}

fn cmdJumpToUnread(buf: []u8) usize {
    const window = getWindow() orelse return writeErrorSimple(buf, "no window", "NO_WINDOW");
    if (window.jumpToUnread()) {
        return writeOk(buf);
    }
    return writeErrorSimple(buf, "no unread notifications", "NO_UNREAD");
}

// --- Helpers ---

fn getWindow() ?*Window {
    const app = Application.default();
    // Get the first window by traversing the GList.
    var node: ?*glib.List = app.as(gtk.Application).getWindows();
    while (node) |n| {
        if (n.f_data) |data| {
            const obj: *gobject.Object = @ptrCast(@alignCast(data));
            if (gobject.ext.cast(Window, obj)) |window| return window;
        }
        node = n.f_next;
    }
    return null;
}

fn getIdParam(obj: std.json.ObjectMap) ?u64 {
    const val = obj.get("id") orelse return null;
    return switch (val) {
        .integer => @intCast(@as(u64, @bitCast(val.integer))),
        .float => @intFromFloat(val.float),
        else => null,
    };
}

fn findPageById(ws_id: u64) ?*adw.TabPage {
    const window = getWindow() orelse return null;
    const tab_view = window.getTabView();
    const n_pages = tab_view.getNPages();

    var i: c_int = 0;
    while (i < n_pages) : (i += 1) {
        const page = tab_view.getNthPage(i);
        const page_id = getWorkspaceId(page) orelse continue;
        if (page_id == ws_id) return page;
    }
    return null;
}

fn getOrAssignWorkspaceId(page: *adw.TabPage) u64 {
    if (getWorkspaceId(page)) |id| return id;
    const id = next_workspace_id;
    next_workspace_id += 1;
    // Store as pointer-sized data.
    page.as(gobject.Object).setData("cove-ws-id", @ptrFromInt(id));
    return id;
}

fn getWorkspaceId(page: *adw.TabPage) ?u64 {
    const raw = page.as(gobject.Object).getData("cove-ws-id") orelse return null;
    return @intFromPtr(raw);
}

// --- JSON writing helpers ---

fn writeStr(buf: []u8, s: []const u8) usize {
    if (s.len > buf.len) return 0;
    @memcpy(buf[0..s.len], s);
    return s.len;
}

fn writeInt(buf: []u8, val: u64) usize {
    return (std.fmt.bufPrint(buf, "{}", .{val}) catch return 0).len;
}

fn writeJsonString(buf: []u8, s: []const u8) usize {
    var pos: usize = 0;
    if (pos >= buf.len) return 0;
    buf[pos] = '"';
    pos += 1;

    for (s) |c| {
        switch (c) {
            '"' => {
                if (pos + 2 > buf.len) return pos;
                buf[pos] = '\\';
                buf[pos + 1] = '"';
                pos += 2;
            },
            '\\' => {
                if (pos + 2 > buf.len) return pos;
                buf[pos] = '\\';
                buf[pos + 1] = '\\';
                pos += 2;
            },
            '\n' => {
                if (pos + 2 > buf.len) return pos;
                buf[pos] = '\\';
                buf[pos + 1] = 'n';
                pos += 2;
            },
            '\r' => {
                if (pos + 2 > buf.len) return pos;
                buf[pos] = '\\';
                buf[pos + 1] = 'r';
                pos += 2;
            },
            '\t' => {
                if (pos + 2 > buf.len) return pos;
                buf[pos] = '\\';
                buf[pos + 1] = 't';
                pos += 2;
            },
            else => {
                if (pos >= buf.len) return pos;
                buf[pos] = c;
                pos += 1;
            },
        }
    }

    if (pos >= buf.len) return pos;
    buf[pos] = '"';
    pos += 1;
    return pos;
}

fn writeOk(buf: []u8) usize {
    return writeStr(buf, "{\"ok\":true}\n");
}

fn writeErrorSimple(buf: []u8, message: []const u8, code: []const u8) usize {
    var pos: usize = 0;
    pos += writeStr(buf[pos..], "{\"error\":");
    pos += writeJsonString(buf[pos..], message);
    pos += writeStr(buf[pos..], ",\"code\":");
    pos += writeJsonString(buf[pos..], code);
    pos += writeStr(buf[pos..], "}\n");
    return pos;
}

fn writeError(buf: []u8, message: []const u8, code: []const u8, err: anyerror) usize {
    _ = err;
    return writeErrorSimple(buf, message, code);
}
