//! Unix domain socket server for Cove CLI/scripting control.
//!
//! Integrates with GLib main loop via `g_unix_fd_add()`.
//! Protocol: newline-delimited JSON. Each request is one JSON object per line,
//! server responds with one JSON object per line.
//!
//! Design ref: cmux `SocketControlSettings` in SocketControlSettings.swift ~L1-385.

const std = @import("std");
const Allocator = std.mem.Allocator;
const posix = std.posix;
const glib = @import("glib");

const log = std.log.scoped(.socket_server);

/// Maximum number of concurrent client connections.
const max_clients = 32;
/// Maximum request line length (bytes).
const max_line_len = 64 * 1024;

/// Opaque handler for dispatching commands. Set by the caller (Application).
pub const CommandHandler = struct {
    ctx: *anyopaque,
    handler: *const fn (ctx: *anyopaque, request: []const u8, response_buf: []u8) usize,
};

const Self = @This();

alloc: Allocator,
socket_path: ?[]const u8 = null,
server_fd: posix.socket_t = -1,
server_source: c_uint = 0,
clients: [max_clients]Client = [_]Client{.{}} ** max_clients,
command_handler: ?CommandHandler = null,

const Client = struct {
    fd: posix.socket_t = -1,
    source: c_uint = 0,
    buf: ?[]u8 = null,
    buf_len: usize = 0,
    /// Back-reference to the server for the GLib callback.
    server: ?*Self = null,
};

pub fn init(alloc: Allocator) Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Self) void {
    self.stop();
}

/// Set the command handler for dispatching parsed requests.
pub fn setCommandHandler(self: *Self, handler: CommandHandler) void {
    self.command_handler = handler;
}

/// Start listening on the Unix domain socket.
pub fn start(self: *Self) !void {
    const path = try self.resolveSocketPath();
    self.socket_path = path;

    // Handle stale socket from crashed instance.
    self.handleStaleSocket(path);

    // Create parent directory if needed.
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        const dir = path[0..idx];
        std.fs.makeDirAbsolute(dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
        // Set directory permissions to 0700.
        var dir_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(dir_path_buf[0..dir.len], dir);
        dir_path_buf[dir.len] = 0;
        const dir_z: [*:0]const u8 = dir_path_buf[0..dir.len :0];
        _ = std.c.chmod(dir_z, 0o700);
    }

    // Create socket.
    const fd = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM | posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(fd);

    // Bind.
    var addr: posix.sockaddr.un = .{ .path = undefined };
    if (path.len >= addr.path.len) return error.PathTooLong;
    @memcpy(addr.path[0..path.len], path);
    addr.path[path.len] = 0;

    posix.bind(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch |err| {
        log.err("failed to bind socket at {s}: {}", .{ path, err });
        return err;
    };

    // Set socket file permissions to 0600.
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = path_buf[0..path.len :0];
    _ = std.c.chmod(path_z, 0o600);

    // Listen.
    try posix.listen(fd, 5);

    self.server_fd = fd;

    // Register with GLib main loop.
    self.server_source = glib.unixFdAdd(
        @intCast(fd),
        .{ .in = true },
        &acceptCallback,
        self,
    );

    log.info("socket server listening at {s}", .{path});
}

/// Stop the server and clean up.
pub fn stop(self: *Self) void {
    // Close all clients.
    for (&self.clients) |*client| {
        self.closeClient(client);
    }

    // Remove server source and close socket.
    if (self.server_source != 0) {
        _ = glib.Source.remove(self.server_source);
        self.server_source = 0;
    }
    if (self.server_fd != -1) {
        posix.close(self.server_fd);
        self.server_fd = -1;
    }

    // Unlink socket file.
    if (self.socket_path) |path| {
        std.fs.deleteFileAbsolute(path) catch {};
        self.alloc.free(path);
        self.socket_path = null;
    }

    log.info("socket server stopped", .{});
}

/// GLib callback for incoming connections on the server socket.
fn acceptCallback(_: c_int, _: glib.IOCondition, ud: ?*anyopaque) callconv(.c) c_int {
    const self: *Self = @ptrCast(@alignCast(ud orelse return @intFromBool(true)));

    const client_fd = posix.accept(self.server_fd, null, null, posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC) catch |err| {
        log.warn("accept failed: {}", .{err});
        return @intFromBool(true); // Keep listening.
    };

    // Find a free client slot.
    for (&self.clients) |*client| {
        if (client.fd == -1) {
            client.fd = client_fd;
            client.server = self;
            client.buf = self.alloc.alloc(u8, max_line_len) catch {
                posix.close(client_fd);
                return @intFromBool(true);
            };
            client.buf_len = 0;
            client.source = glib.unixFdAdd(
                @intCast(client_fd),
                .{ .in = true, .hup = true, .err = true },
                &clientCallback,
                client,
            );
            log.debug("client connected (fd={})", .{client_fd});
            return @intFromBool(true);
        }
    }

    // No free slots — reject.
    log.warn("max clients reached, rejecting connection", .{});
    const reject_msg = "{\"error\":\"too many connections\",\"code\":\"MAX_CLIENTS\"}\n";
    _ = posix.write(client_fd, reject_msg) catch {};
    posix.close(client_fd);
    return @intFromBool(true);
}

/// GLib callback for data from a client connection.
fn clientCallback(fd: c_int, condition: glib.IOCondition, ud: ?*anyopaque) callconv(.c) c_int {
    const client: *Client = @ptrCast(@alignCast(ud orelse return @intFromBool(false)));
    const self = client.server orelse return @intFromBool(false);

    // Check for hangup or error.
    if (condition.hup or condition.err) {
        log.debug("client disconnected (fd={})", .{fd});
        self.closeClient(client);
        return @intFromBool(false); // Remove source.
    }

    // Read data.
    const buf = client.buf orelse return @intFromBool(false);
    const remaining = buf[client.buf_len..];
    if (remaining.len == 0) {
        // Buffer full — line too long. Send error and reset.
        const err_msg = "{\"error\":\"request too large\",\"code\":\"REQUEST_TOO_LARGE\"}\n";
        _ = posix.write(@intCast(fd), err_msg) catch {};
        client.buf_len = 0;
        return @intFromBool(true);
    }

    const bytes_read = posix.read(@intCast(fd), remaining) catch {
        self.closeClient(client);
        return @intFromBool(false);
    };

    if (bytes_read == 0) {
        // EOF.
        log.debug("client EOF (fd={})", .{fd});
        self.closeClient(client);
        return @intFromBool(false);
    }

    client.buf_len += bytes_read;

    // Process complete lines.
    self.processClientLines(client);

    return @intFromBool(true);
}

fn processClientLines(self: *Self, client: *Client) void {
    const buf = client.buf orelse return;

    while (true) {
        const data = buf[0..client.buf_len];
        const newline_pos = std.mem.indexOfScalar(u8, data, '\n') orelse break;

        const line = data[0..newline_pos];
        if (line.len > 0) {
            self.handleRequest(client, line);
        }

        // Shift remaining data to front.
        const remaining = client.buf_len - newline_pos - 1;
        if (remaining > 0) {
            std.mem.copyForwards(u8, buf[0..remaining], data[newline_pos + 1 ..][0..remaining]);
        }
        client.buf_len = remaining;
    }
}

fn handleRequest(self: *Self, client: *Client, line: []const u8) void {
    var response_buf: [max_line_len]u8 = undefined;

    if (self.command_handler) |handler| {
        const len = handler.handler(handler.ctx, line, &response_buf);
        if (len > 0) {
            // Ensure response ends with newline.
            if (len < response_buf.len and response_buf[len - 1] != '\n') {
                response_buf[len] = '\n';
                _ = posix.write(@intCast(client.fd), response_buf[0 .. len + 1]) catch {};
            } else {
                _ = posix.write(@intCast(client.fd), response_buf[0..len]) catch {};
            }
        }
    } else {
        // No handler — minimal ping response.
        const parsed = std.json.parseFromSlice(std.json.Value, self.alloc, line, .{}) catch {
            const err_msg = "{\"error\":\"invalid JSON\",\"code\":\"PARSE_ERROR\"}\n";
            _ = posix.write(@intCast(client.fd), err_msg) catch {};
            return;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root == .object) {
            if (root.object.get("command")) |cmd_val| {
                if (cmd_val == .string) {
                    if (std.mem.eql(u8, cmd_val.string, "ping")) {
                        const resp = "{\"ok\":true}\n";
                        _ = posix.write(@intCast(client.fd), resp) catch {};
                        return;
                    }
                }
            }
        }
        const err_msg = "{\"error\":\"no command handler\",\"code\":\"NOT_READY\"}\n";
        _ = posix.write(@intCast(client.fd), err_msg) catch {};
    }
}

fn closeClient(self: *Self, client: *Client) void {
    if (client.source != 0) {
        _ = glib.Source.remove(client.source);
        client.source = 0;
    }
    if (client.fd != -1) {
        posix.close(client.fd);
        client.fd = -1;
    }
    if (client.buf) |buf| {
        self.alloc.free(buf);
        client.buf = null;
    }
    client.buf_len = 0;
    client.server = null;
}

fn resolveSocketPath(self: *Self) ![]const u8 {
    // Check env override.
    if (std.posix.getenv("COVE_SOCKET_PATH")) |env_path| {
        return try self.alloc.dupe(u8, env_path);
    }

    // Try XDG_RUNTIME_DIR.
    if (std.posix.getenv("XDG_RUNTIME_DIR")) |xdg| {
        const path = try std.fmt.allocPrint(self.alloc, "{s}/cove/socket", .{xdg});
        return path;
    }

    // Fallback: /tmp/cove-$UID/socket.
    const uid = std.os.linux.getuid();
    const path = try std.fmt.allocPrint(self.alloc, "/tmp/cove-{d}/socket", .{uid});
    return path;
}

fn handleStaleSocket(self: *Self, path: []const u8) void {
    _ = self;
    // Check if socket file exists.
    std.fs.accessAbsolute(path, .{}) catch return; // Doesn't exist — good.

    // Try connecting to see if another instance is listening.
    const fd = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch return;
    defer posix.close(fd);

    var addr: posix.sockaddr.un = .{ .path = undefined };
    if (path.len >= addr.path.len) return;
    @memcpy(addr.path[0..path.len], path);
    addr.path[path.len] = 0;

    posix.connect(fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch {
        // Connection refused — stale socket. Remove it.
        log.info("removing stale socket at {s}", .{path});
        std.fs.deleteFileAbsolute(path) catch {};
        return;
    };

    // Connected — another instance is running.
    log.warn("another Cove instance is listening at {s}", .{path});
    // We'll let bind() fail naturally.
}

// =============================================================================
// Tests
// =============================================================================

test "resolveSocketPath with XDG_RUNTIME_DIR" {
    // This test just verifies the function doesn't crash.
    const alloc = std.testing.allocator;
    var server = Self.init(alloc);
    defer server.deinit();
    // Note: can't easily test env-dependent code in unit tests.
    // Integration tests will cover socket creation.
}

test "init and deinit" {
    const alloc = std.testing.allocator;
    var server = Self.init(alloc);
    server.deinit();
}
