//! Cove socket CLI client.
//!
//! Handles all `cove +<command>` subcommands by connecting to the
//! Cove Unix domain socket and sending JSON commands.

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;

const log = std.log.scoped(.cove_cli);

pub const Options = struct {
    _arena: ?std.heap.ArenaAllocator = null,
    _diagnostics: @import("diagnostics.zig").DiagnosticList = .{},

    pub fn deinit(self: *Options) void {
        if (self._arena) |arena| arena.deinit();
        self.* = undefined;
    }

    pub fn help(comptime _: @This()) []const u8 {
        return "";
    }
};

/// All supported Cove socket subcommands.
pub const Subcommand = enum {
    ping,
    @"list-workspaces",
    @"new-workspace",
    @"close-workspace",
    @"select-workspace",
    @"rename-workspace",
    @"list-notifications",
    @"mark-read",
    notify,
};

/// Cove socket client. Connects to the running Cove instance via Unix socket
/// and sends commands. Available subcommands: +ping, +list-workspaces,
/// +new-workspace, +close-workspace, +select-workspace, +rename-workspace,
/// +list-notifications, +mark-read, +notify.
pub fn run(alloc: Allocator) !u8 {
    return runInner(alloc) catch {
        return printUsageErr("Error running cove socket command\n");
    };
}

fn runInner(_: Allocator) !u8 {
    return 0;
}

/// Generic socket client for any Cove command.
/// Send a JSON command and print the response.
pub fn sendCommand(alloc: Allocator, command: []const u8, params: ?std.json.ObjectMap) !u8 {
    _ = alloc;
    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;
    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;

    // Connect to socket.
    const socket_path = resolveSocketPath();
    const fd = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch {
        try stderr.writeAll("Could not connect to Cove (is it running?)\n");
        try stderr.flush();
        return 1;
    };
    defer posix.close(fd);

    var addr: posix.sockaddr.un = .{ .path = undefined };
    if (socket_path.len >= addr.path.len) {
        try stderr.writeAll("Socket path too long\n");
        try stderr.flush();
        return 1;
    }
    @memcpy(addr.path[0..socket_path.len], socket_path);
    addr.path[socket_path.len] = 0;

    posix.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch {
        try stderr.writeAll("Could not connect to Cove (is it running?)\n");
        try stderr.flush();
        return 1;
    };

    // Build JSON request.
    var request_buf: [4096]u8 = undefined;
    var pos: usize = 0;

    pos += copyStr(request_buf[pos..], "{\"command\":\"");
    pos += copyStr(request_buf[pos..], command);
    pos += copyStr(request_buf[pos..], "\"");

    if (params) |p| {
        var it = p.iterator();
        while (it.next()) |entry| {
            pos += copyStr(request_buf[pos..], ",\"");
            pos += copyStr(request_buf[pos..], entry.key_ptr.*);
            pos += copyStr(request_buf[pos..], "\":");
            switch (entry.value_ptr.*) {
                .string => |s| {
                    pos += copyStr(request_buf[pos..], "\"");
                    pos += copyStr(request_buf[pos..], s);
                    pos += copyStr(request_buf[pos..], "\"");
                },
                .integer => |i| {
                    const len = (std.fmt.bufPrint(request_buf[pos..], "{}", .{i}) catch break).len;
                    pos += len;
                },
                else => {},
            }
        }
    }

    pos += copyStr(request_buf[pos..], "}\n");

    // Send request.
    _ = posix.write(fd, request_buf[0..pos]) catch {
        try stderr.writeAll("Failed to send command\n");
        try stderr.flush();
        return 1;
    };

    // Read response.
    var response_buf: [64 * 1024]u8 = undefined;
    const bytes_read = posix.read(fd, &response_buf) catch {
        try stderr.writeAll("Failed to read response\n");
        try stderr.flush();
        return 1;
    };

    if (bytes_read == 0) {
        try stderr.writeAll("No response from Cove\n");
        try stderr.flush();
        return 1;
    }

    const response = response_buf[0..bytes_read];

    // Print response.
    try stdout.writeAll(response);
    try stdout.flush();

    // Check if error.
    if (std.mem.indexOf(u8, response, "\"error\"")) |_| {
        return 1;
    }

    return 0;
}

fn printUsageErr(msg: []const u8) u8 {
    var buf: [1024]u8 = undefined;
    var w = std.fs.File.stderr().writer(&buf);
    w.interface.writeAll(msg) catch {};
    w.interface.flush() catch {};
    return 1;
}

fn resolveSocketPath() []const u8 {
    if (std.posix.getenv("COVE_SOCKET_PATH")) |path| return path;
    if (std.posix.getenv("XDG_RUNTIME_DIR")) |xdg| {
        // We need a static buffer since we can't allocate here easily.
        const S = struct {
            var buf: [256]u8 = undefined;
        };
        const suffix = "/cove/socket";
        if (xdg.len + suffix.len < S.buf.len) {
            @memcpy(S.buf[0..xdg.len], xdg);
            @memcpy(S.buf[xdg.len..][0..suffix.len], suffix);
            return S.buf[0 .. xdg.len + suffix.len];
        }
    }
    return "/tmp/cove-socket";
}

fn copyStr(buf: []u8, s: []const u8) usize {
    if (s.len > buf.len) return 0;
    @memcpy(buf[0..s.len], s);
    return s.len;
}

// Individual command runners (called from Action dispatch).

pub fn runPing(alloc: Allocator) !u8 {
    return sendCommand(alloc, "ping", null);
}

pub fn runListWorkspaces(alloc: Allocator) !u8 {
    return sendCommand(alloc, "list-workspaces", null);
}

pub fn runNewWorkspace(alloc: Allocator) !u8 {
    return sendCommand(alloc, "new-workspace", null);
}

pub fn runCloseWorkspace(alloc: Allocator) !u8 {
    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();
    _ = args_iter.next(); // binary
    _ = args_iter.next(); // +close-workspace
    const id_str = args_iter.next() orelse return printUsageErr("Usage: cove +close-workspace <ID>\n");
    const id = std.fmt.parseInt(i64, id_str, 10) catch return printUsageErr("Invalid workspace ID\n");

    var map = std.json.ObjectMap.init(alloc);
    defer map.deinit();
    try map.put("id", .{ .integer = id });
    return sendCommand(alloc, "close-workspace", map);
}

pub fn runSelectWorkspace(alloc: Allocator) !u8 {
    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();
    _ = args_iter.next();
    _ = args_iter.next();
    const id_str = args_iter.next() orelse return printUsageErr("Usage: cove +select-workspace <ID>\n");
    const id = std.fmt.parseInt(i64, id_str, 10) catch return printUsageErr("Invalid workspace ID\n");

    var map = std.json.ObjectMap.init(alloc);
    defer map.deinit();
    try map.put("id", .{ .integer = id });
    return sendCommand(alloc, "select-workspace", map);
}

pub fn runRenameWorkspace(alloc: Allocator) !u8 {
    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();
    _ = args_iter.next();
    _ = args_iter.next();
    const id_str = args_iter.next() orelse return printUsageErr("Usage: cove +rename-workspace <ID> <NAME>\n");
    const name = args_iter.next() orelse return printUsageErr("Usage: cove +rename-workspace <ID> <NAME>\n");
    const id = std.fmt.parseInt(i64, id_str, 10) catch return printUsageErr("Invalid workspace ID\n");

    var map = std.json.ObjectMap.init(alloc);
    defer map.deinit();
    try map.put("id", .{ .integer = id });
    try map.put("name", .{ .string = name });
    return sendCommand(alloc, "rename-workspace", map);
}

pub fn runListNotifications(alloc: Allocator) !u8 {
    return sendCommand(alloc, "list-notifications", null);
}

pub fn runMarkRead(alloc: Allocator) !u8 {
    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();
    _ = args_iter.next();
    _ = args_iter.next();

    // Optional workspace ID.
    if (args_iter.next()) |id_str| {
        const id = std.fmt.parseInt(i64, id_str, 10) catch return printUsageErr("Invalid workspace ID\n");
        var map = std.json.ObjectMap.init(alloc);
        defer map.deinit();
        try map.put("id", .{ .integer = id });
        return sendCommand(alloc, "mark-read", map);
    }

    return sendCommand(alloc, "mark-read", null);
}

pub fn runNotify(alloc: Allocator) !u8 {
    var args_iter = try std.process.argsWithAllocator(alloc);
    defer args_iter.deinit();
    _ = args_iter.next();
    _ = args_iter.next();

    const id_str = args_iter.next() orelse return printUsageErr("Usage: cove +notify <WORKSPACE_ID> <TITLE> [BODY]\n");
    const title = args_iter.next() orelse return printUsageErr("Usage: cove +notify <WORKSPACE_ID> <TITLE> [BODY]\n");
    const body = args_iter.next() orelse "";
    const id = std.fmt.parseInt(i64, id_str, 10) catch return printUsageErr("Invalid workspace ID\n");

    var map = std.json.ObjectMap.init(alloc);
    defer map.deinit();
    try map.put("id", .{ .integer = id });
    try map.put("title", .{ .string = title });
    try map.put("body", .{ .string = body });
    return sendCommand(alloc, "notify", map);
}
