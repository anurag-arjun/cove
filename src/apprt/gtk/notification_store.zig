//! Per-workspace notification store for Cove.
//!
//! Pure data structure — no GTK widget dependencies. Stores terminal
//! notifications, maintains precomputed indexes for fast lookups, and
//! provides methods for add/read/clear operations.
//!
//! Owned by Application, passed to windows. Signals for UI updates are
//! dispatched by the caller (Application) after mutations.
//!
//! Design ref: cmux TerminalNotificationStore (~L73–413).

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.notification_store);

/// Unique tab/workspace identifier. Uses the pointer value of the AdwTabPage.
pub const TabId = usize;

/// Unique surface identifier within a tab (for split panes).
pub const SurfaceId = usize;

/// Key for per-tab+surface lookups.
pub const TabSurfaceKey = struct {
    tab_id: TabId,
    surface_id: SurfaceId,
};

pub const Notification = struct {
    id: u64,
    tab_id: TabId,
    surface_id: ?SurfaceId,
    title: []const u8,
    subtitle: []const u8,
    body: []const u8,
    created_at: i64,
    is_read: bool,
};

/// Precomputed lookup indexes, rebuilt on every mutation.
const Indexes = struct {
    unread_count: usize = 0,
    unread_count_by_tab: std.AutoHashMapUnmanaged(TabId, usize) = .{},
    unread_by_tab_surface: std.AutoHashMapUnmanaged(TabSurfaceKey, void) = .{},
    latest_unread_by_tab: std.AutoHashMapUnmanaged(TabId, u64) = .{},
    latest_by_tab: std.AutoHashMapUnmanaged(TabId, u64) = .{},

    fn deinit(self: *Indexes, alloc: Allocator) void {
        self.unread_count_by_tab.deinit(alloc);
        self.unread_by_tab_surface.deinit(alloc);
        self.latest_unread_by_tab.deinit(alloc);
        self.latest_by_tab.deinit(alloc);
    }

    fn clear(self: *Indexes) void {
        self.unread_count = 0;
        self.unread_count_by_tab.clearRetainingCapacity();
        self.unread_by_tab_surface.clearRetainingCapacity();
        self.latest_unread_by_tab.clearRetainingCapacity();
        self.latest_by_tab.clearRetainingCapacity();
    }
};

/// Result from a mutation indicating what changed (for signal dispatch).
pub const MutationResult = struct {
    /// Whether the global unread count changed.
    unread_count_changed: bool,
    /// Previous unread count (valid only if unread_count_changed).
    previous_unread_count: usize,
    /// New unread count (valid only if unread_count_changed).
    new_unread_count: usize,
    /// Whether a notification was added (for notification-added signal).
    notification_added: bool,
};

alloc: Allocator,
/// All notifications, newest-first.
notifications: std.ArrayListUnmanaged(Notification) = .{},
/// Monotonic ID counter.
next_id: u64 = 1,
/// Precomputed indexes.
indexes: Indexes = .{},

const Self = @This();

pub fn init(alloc: Allocator) Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Self) void {
    // Free all owned strings.
    for (self.notifications.items) |n| {
        self.freeNotificationStrings(n);
    }
    self.notifications.deinit(self.alloc);
    self.indexes.deinit(self.alloc);
}

fn freeNotificationStrings(self: *const Self, n: Notification) void {
    if (n.title.len > 0) self.alloc.free(n.title);
    if (n.subtitle.len > 0) self.alloc.free(n.subtitle);
    if (n.body.len > 0) self.alloc.free(n.body);
}

/// Add a notification. Returns mutation result for signal dispatch.
///
/// **Suppression:** If `focused_tab` matches `tab_id` and `app_active` is true,
/// the notification is suppressed — instead, existing unread for that
/// tab+surface are marked as read.
pub fn add(
    self: *Self,
    tab_id: TabId,
    surface_id: ?SurfaceId,
    title: []const u8,
    subtitle: []const u8,
    body: []const u8,
    focused_tab: ?TabId,
    app_active: bool,
) !MutationResult {
    const old_unread = self.indexes.unread_count;

    // Suppression: workspace is focused and app is active.
    if (app_active) {
        if (focused_tab) |ft| {
            if (ft == tab_id) {
                // Mark existing unread for this tab+surface as read instead of adding.
                if (surface_id) |sid| {
                    self.markReadForTabSurfaceInternal(tab_id, sid);
                } else {
                    self.markReadForTabInternal(tab_id);
                }
                self.rebuildIndexes();
                const new_unread = self.indexes.unread_count;
                return .{
                    .unread_count_changed = old_unread != new_unread,
                    .previous_unread_count = old_unread,
                    .new_unread_count = new_unread,
                    .notification_added = false,
                };
            }
        }
    }

    const id = self.next_id;
    self.next_id += 1;

    const n = Notification{
        .id = id,
        .tab_id = tab_id,
        .surface_id = surface_id,
        .title = try self.dupeStr(title),
        .subtitle = try self.dupeStr(subtitle),
        .body = try self.dupeStr(body),
        .created_at = std.time.timestamp(),
        .is_read = false,
    };

    // Insert at front (newest-first).
    try self.notifications.insert(self.alloc, 0, n);
    self.rebuildIndexes();

    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = true,
    };
}

/// Mark a single notification as read by ID.
pub fn markRead(self: *Self, id: u64) MutationResult {
    const old_unread = self.indexes.unread_count;
    for (self.notifications.items) |*n| {
        if (n.id == id) {
            n.is_read = true;
            break;
        }
    }
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Mark all notifications for a tab as read.
pub fn markReadForTab(self: *Self, tab_id: TabId) MutationResult {
    const old_unread = self.indexes.unread_count;
    self.markReadForTabInternal(tab_id);
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Mark all notifications for a specific tab+surface as read.
pub fn markReadForTabSurface(self: *Self, tab_id: TabId, surface_id: SurfaceId) MutationResult {
    const old_unread = self.indexes.unread_count;
    self.markReadForTabSurfaceInternal(tab_id, surface_id);
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Mark all notifications as read.
pub fn markAllRead(self: *Self) MutationResult {
    const old_unread = self.indexes.unread_count;
    for (self.notifications.items) |*n| {
        n.is_read = true;
    }
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Global unread count.
pub fn unreadCount(self: *const Self) usize {
    return self.indexes.unread_count;
}

/// Per-tab unread count.
pub fn unreadCountForTab(self: *const Self, tab_id: TabId) usize {
    return self.indexes.unread_count_by_tab.get(tab_id) orelse 0;
}

/// Per-surface unread check.
pub fn hasUnread(self: *const Self, tab_id: TabId, surface_id: SurfaceId) bool {
    return self.indexes.unread_by_tab_surface.contains(.{ .tab_id = tab_id, .surface_id = surface_id });
}

/// Latest notification for a tab: returns latest unread, or latest overall if all read.
pub fn latestNotification(self: *const Self, tab_id: TabId) ?*const Notification {
    // Try latest unread first.
    if (self.indexes.latest_unread_by_tab.get(tab_id)) |id| {
        return self.findById(id);
    }
    // Fall back to latest overall.
    if (self.indexes.latest_by_tab.get(tab_id)) |id| {
        return self.findById(id);
    }
    return null;
}

/// Remove a single notification by ID.
pub fn remove(self: *Self, id: u64) MutationResult {
    const old_unread = self.indexes.unread_count;
    for (self.notifications.items, 0..) |n, i| {
        if (n.id == id) {
            self.freeNotificationStrings(n);
            _ = self.notifications.orderedRemove(i);
            break;
        }
    }
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Clear all notifications.
pub fn clearAll(self: *Self) MutationResult {
    const old_unread = self.indexes.unread_count;
    for (self.notifications.items) |n| {
        self.freeNotificationStrings(n);
    }
    self.notifications.clearRetainingCapacity();
    self.rebuildIndexes();
    return .{
        .unread_count_changed = old_unread != 0,
        .previous_unread_count = old_unread,
        .new_unread_count = 0,
        .notification_added = false,
    };
}

/// Clear all notifications for a specific tab (e.g., on workspace close).
pub fn clearForTab(self: *Self, tab_id: TabId) MutationResult {
    const old_unread = self.indexes.unread_count;
    var i: usize = 0;
    while (i < self.notifications.items.len) {
        if (self.notifications.items[i].tab_id == tab_id) {
            self.freeNotificationStrings(self.notifications.items[i]);
            _ = self.notifications.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Clear all notifications for a specific tab+surface.
pub fn clearForTabSurface(self: *Self, tab_id: TabId, surface_id: SurfaceId) MutationResult {
    const old_unread = self.indexes.unread_count;
    var i: usize = 0;
    while (i < self.notifications.items.len) {
        const n = self.notifications.items[i];
        if (n.tab_id == tab_id and n.surface_id != null and n.surface_id.? == surface_id) {
            self.freeNotificationStrings(n);
            _ = self.notifications.orderedRemove(i);
        } else {
            i += 1;
        }
    }
    self.rebuildIndexes();
    const new_unread = self.indexes.unread_count;
    return .{
        .unread_count_changed = old_unread != new_unread,
        .previous_unread_count = old_unread,
        .new_unread_count = new_unread,
        .notification_added = false,
    };
}

/// Total number of stored notifications.
pub fn count(self: *const Self) usize {
    return self.notifications.items.len;
}

// --- Internal helpers ---

fn markReadForTabInternal(self: *Self, tab_id: TabId) void {
    for (self.notifications.items) |*n| {
        if (n.tab_id == tab_id) {
            n.is_read = true;
        }
    }
}

fn markReadForTabSurfaceInternal(self: *Self, tab_id: TabId, surface_id: SurfaceId) void {
    for (self.notifications.items) |*n| {
        if (n.tab_id == tab_id and n.surface_id != null and n.surface_id.? == surface_id) {
            n.is_read = true;
        }
    }
}

fn rebuildIndexes(self: *Self) void {
    self.indexes.clear();

    for (self.notifications.items) |n| {
        // latest_by_tab: first occurrence wins (newest-first order).
        _ = self.indexes.latest_by_tab.getOrPut(self.alloc, n.tab_id) catch continue;
        const latest_entry = self.indexes.latest_by_tab.getPtr(n.tab_id).?;
        // Only set if not already present (first = newest).
        if (!self.indexes.latest_by_tab.contains(n.tab_id)) {
            latest_entry.* = n.id;
        }
        // Actually, getOrPut returns entry — let's fix this logic.
    }

    // Rebuild properly: clear and iterate.
    self.indexes.clear();

    for (self.notifications.items) |n| {
        // latest_by_tab: first occurrence = newest.
        const latest_result = self.indexes.latest_by_tab.getOrPut(self.alloc, n.tab_id) catch continue;
        if (latest_result.found_existing == false) {
            latest_result.value_ptr.* = n.id;
        }

        if (!n.is_read) {
            self.indexes.unread_count += 1;

            // unread_count_by_tab
            const tab_result = self.indexes.unread_count_by_tab.getOrPut(self.alloc, n.tab_id) catch continue;
            if (!tab_result.found_existing) {
                tab_result.value_ptr.* = 0;
            }
            tab_result.value_ptr.* += 1;

            // unread_by_tab_surface
            if (n.surface_id) |sid| {
                self.indexes.unread_by_tab_surface.put(self.alloc, .{ .tab_id = n.tab_id, .surface_id = sid }, {}) catch {};
            }

            // latest_unread_by_tab: first occurrence = newest unread.
            const unread_result = self.indexes.latest_unread_by_tab.getOrPut(self.alloc, n.tab_id) catch continue;
            if (!unread_result.found_existing) {
                unread_result.value_ptr.* = n.id;
            }
        }
    }
}

fn findById(self: *const Self, id: u64) ?*const Notification {
    for (self.notifications.items) |*n| {
        if (n.id == id) return n;
    }
    return null;
}

fn dupeStr(self: *const Self, s: []const u8) ![]const u8 {
    if (s.len == 0) return "";
    return try self.alloc.dupe(u8, s);
}

// =============================================================================
// Tests
// =============================================================================

test "add and unread count" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    const result = try store.add(1, null, "title", "", "body", null, false);
    try std.testing.expect(result.notification_added);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());
    try std.testing.expectEqual(@as(usize, 1), store.unreadCountForTab(1));
    try std.testing.expectEqual(@as(usize, 0), store.unreadCountForTab(99));
}

test "add suppression when focused and active" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    // Add initial unread notification for tab 1.
    _ = try store.add(1, null, "first", "", "body1", null, false);
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());

    // Add with suppression: focused_tab=1, app_active=true.
    // Should NOT add, should mark existing as read.
    const result = try store.add(1, null, "suppressed", "", "body2", @as(?TabId, 1), true);
    try std.testing.expect(!result.notification_added);
    try std.testing.expectEqual(@as(usize, 1), store.count()); // Still just 1 notification.
    try std.testing.expectEqual(@as(usize, 0), store.unreadCount()); // Marked as read.
}

test "add not suppressed when different tab focused" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    const result = try store.add(1, null, "title", "", "body", @as(?TabId, 2), true);
    try std.testing.expect(result.notification_added);
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());
}

test "markRead single" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "a", "", "body", null, false);
    _ = try store.add(1, null, "b", "", "body", null, false);
    try std.testing.expectEqual(@as(usize, 2), store.unreadCount());

    // Mark the first one (id=1) as read.
    const result = store.markRead(1);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());
}

test "markReadForTab" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "a", "", "body", null, false);
    _ = try store.add(1, null, "b", "", "body", null, false);
    _ = try store.add(2, null, "c", "", "body", null, false);
    try std.testing.expectEqual(@as(usize, 3), store.unreadCount());

    const result = store.markReadForTab(1);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());
    try std.testing.expectEqual(@as(usize, 0), store.unreadCountForTab(1));
    try std.testing.expectEqual(@as(usize, 1), store.unreadCountForTab(2));
}

test "markReadForTabSurface" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, @as(?SurfaceId, 10), "a", "", "body", null, false);
    _ = try store.add(1, @as(?SurfaceId, 20), "b", "", "body", null, false);
    try std.testing.expectEqual(@as(usize, 2), store.unreadCount());

    const result = store.markReadForTabSurface(1, 10);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());
    try std.testing.expect(!store.hasUnread(1, 10));
    try std.testing.expect(store.hasUnread(1, 20));
}

test "markAllRead" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "a", "", "body", null, false);
    _ = try store.add(2, null, "b", "", "body", null, false);
    const result = store.markAllRead();
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 0), store.unreadCount());
}

test "latestNotification returns unread then overall" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "older", "", "body1", null, false); // id=1
    _ = try store.add(1, null, "newer", "", "body2", null, false); // id=2

    // Latest unread should be newest (id=2, inserted at front).
    const latest = store.latestNotification(1).?;
    try std.testing.expectEqual(@as(u64, 2), latest.id);

    // Mark all read — should still return latest overall (id=2).
    _ = store.markAllRead();
    const latest2 = store.latestNotification(1).?;
    try std.testing.expectEqual(@as(u64, 2), latest2.id);
}

test "remove" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "a", "", "body", null, false);
    _ = try store.add(1, null, "b", "", "body", null, false);
    try std.testing.expectEqual(@as(usize, 2), store.count());

    const result = store.remove(1);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqual(@as(usize, 1), store.unreadCount());
}

test "clearAll" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "a", "", "body", null, false);
    _ = try store.add(2, null, "b", "", "body", null, false);
    const result = store.clearAll();
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 0), store.count());
    try std.testing.expectEqual(@as(usize, 0), store.unreadCount());
}

test "clearForTab" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "a", "", "body", null, false);
    _ = try store.add(2, null, "b", "", "body", null, false);
    const result = store.clearForTab(1);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 1), store.count());
    try std.testing.expectEqual(@as(usize, 1), store.unreadCountForTab(2));
}

test "clearForTabSurface" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, @as(?SurfaceId, 10), "a", "", "body", null, false);
    _ = try store.add(1, @as(?SurfaceId, 20), "b", "", "body", null, false);
    _ = try store.add(1, null, "c", "", "body", null, false); // No surface_id — should NOT be removed.
    const result = store.clearForTabSurface(1, 10);
    try std.testing.expect(result.unread_count_changed);
    try std.testing.expectEqual(@as(usize, 2), store.count());
}

test "newest-first ordering" {
    const alloc = std.testing.allocator;
    var store = Self.init(alloc);
    defer store.deinit();

    _ = try store.add(1, null, "first", "", "body", null, false);
    _ = try store.add(1, null, "second", "", "body", null, false);
    _ = try store.add(1, null, "third", "", "body", null, false);

    // Newest (id=3) should be at index 0.
    try std.testing.expectEqual(@as(u64, 3), store.notifications.items[0].id);
    try std.testing.expectEqual(@as(u64, 2), store.notifications.items[1].id);
    try std.testing.expectEqual(@as(u64, 1), store.notifications.items[2].id);
}
