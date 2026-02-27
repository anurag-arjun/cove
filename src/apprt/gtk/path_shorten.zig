//! Path shortening for Cove sidebar display.
//!
//! Pure function — no GTK dependencies. Replaces $HOME with ~,
//! truncates deep paths to show last N components.
//!
//! Design ref: cmux `SidebarPathFormatter.shortenedPath()` in ContentView.swift ~L6130–6145.

const std = @import("std");
const mem = std.mem;

/// Shorten a path for sidebar display.
///
/// - Replaces home prefix with "~"
/// - For paths deeper than `max_components`, shows "~/…/<last components>"
/// - Returns a slice into `buf`.
pub fn shorten(path: []const u8, home: []const u8, buf: *[512]u8, max_components: usize) []const u8 {
    if (path.len == 0) return "";

    // Replace home prefix with ~
    var display = path;
    var has_home = false;
    if (home.len > 0 and mem.startsWith(u8, path, home)) {
        const rest = path[home.len..];
        if (rest.len == 0 or rest[0] == '/') {
            display = rest;
            has_home = true;
        }
    }

    // Count path components (skip leading /).
    const trimmed = if (display.len > 0 and display[0] == '/') display[1..] else display;

    if (trimmed.len == 0) {
        // Path is exactly $HOME.
        if (has_home) {
            buf[0] = '~';
            return buf[0..1];
        }
        buf[0] = '/';
        return buf[0..1];
    }

    // Split into components.
    var components: [64][]const u8 = undefined;
    var count: usize = 0;
    var iter = mem.splitScalar(u8, trimmed, '/');
    while (iter.next()) |comp| {
        if (comp.len == 0) continue;
        if (count < 64) {
            components[count] = comp;
            count += 1;
        }
    }

    if (count == 0) {
        if (has_home) {
            buf[0] = '~';
            return buf[0..1];
        }
        buf[0] = '/';
        return buf[0..1];
    }

    // If within max_components, show full (with ~ prefix if applicable).
    if (count <= max_components) {
        return formatPath(buf, if (has_home) "~" else "", display);
    }

    // Truncate: show ~/…/<last max_components components>
    const prefix: []const u8 = if (has_home) "~/\xe2\x80\xa6" else "/\xe2\x80\xa6"; // "…" is 3 bytes UTF-8
    var pos: usize = 0;
    if (pos + prefix.len > buf.len) return path; // overflow safety
    @memcpy(buf[pos..][0..prefix.len], prefix);
    pos += prefix.len;

    const start = count - max_components;
    for (start..count) |i| {
        buf[pos] = '/';
        pos += 1;
        const comp = components[i];
        if (pos + comp.len > buf.len) return path;
        @memcpy(buf[pos..][0..comp.len], comp);
        pos += comp.len;
    }

    return buf[0..pos];
}

fn formatPath(buf: *[512]u8, prefix: []const u8, path: []const u8) []const u8 {
    var pos: usize = 0;
    if (prefix.len > 0) {
        @memcpy(buf[pos..][0..prefix.len], prefix);
        pos += prefix.len;
    }
    if (pos + path.len > buf.len) return path;
    @memcpy(buf[pos..][0..path.len], path);
    pos += path.len;
    return buf[0..pos];
}

// =============================================================================
// Tests
// =============================================================================

test "home replacement" {
    var buf: [512]u8 = undefined;
    const result = shorten("/home/user/code", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("~/code", result);
}

test "exact home" {
    var buf: [512]u8 = undefined;
    const result = shorten("/home/user", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("~", result);
}

test "deep path truncation" {
    var buf: [512]u8 = undefined;
    const result = shorten("/home/user/code/very/deep/project", "/home/user", &buf, 2);
    try std.testing.expectEqualStrings("~/\xe2\x80\xa6/deep/project", result);
}

test "no home prefix" {
    var buf: [512]u8 = undefined;
    const result = shorten("/opt/data/stuff", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("/opt/data/stuff", result);
}

test "no home deep truncation" {
    var buf: [512]u8 = undefined;
    const result = shorten("/opt/a/b/c/d/e", "/home/user", &buf, 2);
    try std.testing.expectEqualStrings("/\xe2\x80\xa6/d/e", result);
}

test "root path" {
    var buf: [512]u8 = undefined;
    const result = shorten("/", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("/", result);
}

test "empty path" {
    var buf: [512]u8 = undefined;
    const result = shorten("", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("", result);
}

test "within max components" {
    var buf: [512]u8 = undefined;
    const result = shorten("/home/user/code/proj", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("~/code/proj", result);
}

test "home not partial match" {
    var buf: [512]u8 = undefined;
    // /home/username should NOT match /home/user
    const result = shorten("/home/username/code", "/home/user", &buf, 3);
    try std.testing.expectEqualStrings("/home/username/code", result);
}
