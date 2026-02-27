//! Git branch detection for Cove sidebar metadata.
//!
//! Pure functions — no GTK dependencies. Reads `.git/HEAD` to determine
//! the current branch name. Handles regular repos, worktrees, and detached HEAD.
//!
//! Triggered on PWD change. Walks up parent directories to find the repo root.
//!
//! Design ref: cmux `Workspace.gitBranch` / `SidebarGitBranchState` in Workspace.swift ~L967.

const std = @import("std");
const fs = std.fs;
const mem = std.mem;

const log = std.log.scoped(.git_branch);

/// Maximum number of parent directories to walk up when searching for .git.
const max_parent_walk: usize = 10;

/// Result of git branch detection.
pub const GitBranch = union(enum) {
    /// On a named branch (e.g. "main", "feature/sidebar").
    branch: []const u8,
    /// Detached HEAD — short commit hash (7 chars).
    detached: []const u8,
};

/// Detect the git branch for the given working directory.
///
/// Returns null if not in a git repository or on any error.
/// The returned slices point into `buf` and are valid until `buf` is reused.
pub fn detect(pwd: []const u8, buf: *[4096]u8) ?GitBranch {
    // Walk up from pwd looking for .git.
    var dir = pwd;
    var depth: usize = 0;
    while (depth < max_parent_walk) : (depth += 1) {
        if (checkGitDir(dir, buf)) |result| return result;

        // Go to parent.
        if (mem.lastIndexOfScalar(u8, dir, '/')) |idx| {
            if (idx == 0) {
                // Check root "/" as final attempt.
                if (depth + 1 < max_parent_walk) {
                    if (checkGitDir("/", buf)) |result| return result;
                }
                break;
            }
            dir = dir[0..idx];
        } else {
            break;
        }
    }
    return null;
}

/// Check a single directory for .git and parse HEAD.
fn checkGitDir(dir: []const u8, buf: *[4096]u8) ?GitBranch {
    // Build path: dir + "/.git"
    const git_path = concatPath(dir, ".git", buf) orelse return null;

    // Try to stat the path.
    const stat = fs.cwd().statFile(git_path) catch return null;

    if (stat.kind == .directory) {
        // Regular repo: read dir/.git/HEAD
        const head_path = concatPath(dir, ".git/HEAD", buf) orelse return null;
        return parseHeadFile(head_path, buf);
    } else if (stat.kind == .file) {
        // Worktree: .git is a file containing "gitdir: <path>"
        return handleWorktree(git_path, buf);
    }
    return null;
}

/// Parse a .git file (worktree) to find the actual gitdir, then read HEAD.
fn handleWorktree(git_file_path: []const u8, buf: *[4096]u8) ?GitBranch {
    const content = readFileIntoBuf(git_file_path, buf) orelse return null;

    // Format: "gitdir: <path>\n"
    const trimmed = mem.trimRight(u8, content, "\r\n ");
    const prefix = "gitdir: ";
    if (!mem.startsWith(u8, trimmed, prefix)) return null;

    const gitdir = trimmed[prefix.len..];
    if (gitdir.len == 0) return null;

    // Read <gitdir>/HEAD
    const head_path = concatPath(gitdir, "HEAD", buf) orelse return null;
    return parseHeadFile(head_path, buf);
}

/// Read and parse a HEAD file.
fn parseHeadFile(head_path: []const u8, buf: *[4096]u8) ?GitBranch {
    const content = readFileIntoBuf(head_path, buf) orelse return null;
    return parseHeadContent(content);
}

/// Parse the content of a HEAD file.
///
/// - "ref: refs/heads/<branch>" → branch name
/// - 40-char hex → detached HEAD (first 7 chars)
pub fn parseHeadContent(content: []const u8) ?GitBranch {
    const trimmed = mem.trimRight(u8, content, "\r\n ");

    // Symbolic ref: "ref: refs/heads/<branch>"
    const ref_prefix = "ref: refs/heads/";
    if (mem.startsWith(u8, trimmed, ref_prefix)) {
        const branch = trimmed[ref_prefix.len..];
        if (branch.len > 0) return .{ .branch = branch };
        return null;
    }

    // Detached HEAD: 40-char hex SHA.
    if (trimmed.len >= 40 and isHexString(trimmed[0..40])) {
        return .{ .detached = trimmed[0..7] };
    }

    return null;
}

fn isHexString(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

fn readFileIntoBuf(path: []const u8, buf: *[4096]u8) ?[]const u8 {
    // We need a sentinel-terminated path for openFileAbsolute.
    // Use a stack buffer for the path.
    var path_buf: [4096]u8 = undefined;
    if (path.len >= path_buf.len) return null;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [:0]const u8 = path_buf[0..path.len :0];

    const file = fs.openFileAbsoluteZ(path_z, .{}) catch return null;
    defer file.close();
    const bytes_read = file.read(buf) catch return null;
    if (bytes_read == 0) return null;
    return buf[0..bytes_read];
}

fn concatPath(base: []const u8, suffix: []const u8, buf: *[4096]u8) ?[]const u8 {
    // base + "/" + suffix
    const need = base.len + 1 + suffix.len;
    if (need >= buf.len) return null;
    @memcpy(buf[0..base.len], base);
    buf[base.len] = '/';
    @memcpy(buf[base.len + 1 ..][0..suffix.len], suffix);
    return buf[0..need];
}

// =============================================================================
// Tests
// =============================================================================

test "parseHeadContent — branch ref" {
    const result = parseHeadContent("ref: refs/heads/main\n").?;
    switch (result) {
        .branch => |b| try std.testing.expectEqualStrings("main", b),
        .detached => return error.WrongVariant,
    }
}

test "parseHeadContent — feature branch with slash" {
    const result = parseHeadContent("ref: refs/heads/feature/sidebar\n").?;
    switch (result) {
        .branch => |b| try std.testing.expectEqualStrings("feature/sidebar", b),
        .detached => return error.WrongVariant,
    }
}

test "parseHeadContent — detached HEAD" {
    const result = parseHeadContent("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n").?;
    switch (result) {
        .detached => |h| try std.testing.expectEqualStrings("a1b2c3d", h),
        .branch => return error.WrongVariant,
    }
}

test "parseHeadContent — empty" {
    try std.testing.expect(parseHeadContent("") == null);
    try std.testing.expect(parseHeadContent("\n") == null);
}

test "parseHeadContent — invalid content" {
    try std.testing.expect(parseHeadContent("something random") == null);
    try std.testing.expect(parseHeadContent("ref: refs/heads/") == null); // empty branch name
}

test "parseHeadContent — short hash (not 40 chars)" {
    // Only 20 hex chars — should not match.
    try std.testing.expect(parseHeadContent("a1b2c3d4e5f6a1b2c3d4") == null);
}

test "detect — finds branch in current dir" {
    // This test works if run from within a git repo (which this project is).
    var buf: [4096]u8 = undefined;
    const cwd = std.fs.cwd().realpathAlloc(std.testing.allocator, ".") catch return;
    defer std.testing.allocator.free(cwd);

    if (detect(cwd, &buf)) |result| {
        switch (result) {
            .branch => |b| try std.testing.expect(b.len > 0),
            .detached => |h| try std.testing.expect(h.len == 7),
        }
    }
    // null is also acceptable (e.g., if run outside a git repo).
}

test "detect — non-existent directory returns null" {
    var buf: [4096]u8 = undefined;
    try std.testing.expect(detect("/tmp/nonexistent_dir_cove_test_12345", &buf) == null);
}
