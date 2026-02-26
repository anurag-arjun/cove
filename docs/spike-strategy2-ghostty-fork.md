# Research Spike: Strategy 2 — Fork Ghostty's GTK Frontend

> Fork Ghostty's existing GTK4/Zig Linux app and add cmux features on top.

---

## 1. Ghostty GTK Frontend Architecture

### Codebase Layout
```
src/apprt/gtk/                    (~18K lines Zig + Blueprint UI)
├── App.zig                       (99)   — Entry point, creates Application
├── Surface.zig                   (103)  — Bridge: apprt Surface → GObject Surface
├── class/                        
│   ├── application.zig           (2,790) — GtkApplication: startup, activate, action dispatch
│   ├── window.zig                (2,071) — THE MAIN WINDOW: AdwApplicationWindow
│   ├── tab.zig                   (570)  — Tab = GtkBox wrapping a SplitTree
│   ├── surface.zig               (3,974) — Terminal widget: GLArea, input, clipboard, resize
│   ├── split_tree.zig            (1,241) — Split pane tree management
│   ├── command_palette.zig       (790)  — Command palette overlay
│   ├── search_overlay.zig        (493)  — Find-in-terminal
│   ├── global_shortcuts.zig      (633)  — Global keybind registration
│   ├── config.zig                (175)  — GObject config wrapper
│   ├── inspector_*.zig           — Terminal inspector (debug)
│   ├── resize_overlay.zig        (338)  — Size indicator during resize
│   ├── key_state_overlay.zig     (342)  — Key state debug overlay
│   ├── *_dialog.zig              — Close confirmation, clipboard, title, config errors
│   └── debug_warning.zig         
├── ui/                           — Blueprint UI definitions
│   ├── 1.5/window.blp            — Main window layout
│   ├── 1.5/tab.blp               — Tab layout
│   ├── 1.5/split-tree*.blp       — Split pane UI
│   ├── 1.2/surface.blp           — Terminal surface layout
│   └── ...overlays, dialogs
├── key.zig                       (535)  — Keyboard event translation
├── winproto/                     — Wayland/X11 protocol specifics
│   ├── wayland.zig
│   ├── x11.zig
│   └── noop.zig
├── ext/                          — GTK extension helpers
├── build/                        — Blueprint + GResource compilation
├── ipc/                          — D-Bus IPC for new-window
├── cgroup.zig                    — Systemd cgroup integration
├── flatpak.zig                   — Flatpak sandbox detection
└── gsettings.zig                 — GNOME settings integration
```

### Window Structure (from `window.blp`)
```
GhosttyWindow (AdwApplicationWindow)
└── AdwTabOverview
    └── AdwToolbarView
        ├── [top] AdwHeaderBar (with new-tab, tab-overview, menu buttons)
        ├── [top] AdwTabBar (horizontal tabs)
        └── AdwToastOverlay
            └── AdwTabView (manages Tab pages)
                └── GhosttyTab (one per tab)
                    └── GhosttyDebugWarning + SplitTree
                        └── GhosttySurface(s)
```

### Key Observation: Horizontal Tabs via AdwTabView

Ghostty uses **`AdwTabView` + `AdwTabBar`** — libadwaita's built-in horizontal tab system. This gives tab dragging, reordering, detaching to new windows, and the tab overview grid for free.

**cmux's vertical sidebar replaces this entirely.** This is the single biggest architectural change.

---

## 2. Ghostty Build System & Dependencies

### Build (Zig Build System)
```bash
# From source tarball (fewer deps):
zig build -Doptimize=ReleaseFast

# From git checkout (more deps):
# Requires: blueprint-compiler >= 0.16.0
zig build
```

### Required Zig Version
Check `build.zig.zon` → currently **Zig 0.14.x**. On Arch/CachyOS:
```bash
sudo pacman -S zig0.14   # or 'zig' if it's the right version
```

### System Dependencies for Arch/CachyOS
```bash
sudo pacman -S gtk4 libadwaita pkgconf blueprint-compiler pandoc-cli gettext
# For browser support, also:
sudo pacman -S webkit2gtk-5.0
```

### Build Commands
```bash
git clone https://github.com/ghostty-org/ghostty
cd ghostty
zig build                            # debug build
zig build -Doptimize=ReleaseFast     # release build  
zig build run                        # build and run
```

### CachyOS Build Notes
- CachyOS has Ghostty in its repos (`sudo pacman -S ghostty`)
- Building from source may hit glibc SFrame linker issues
- Fix: `zig build -Dcpu=baseline` or build in standard Arch chroot
- The `zig0.14` package is available in Arch extra repo

---

## 3. cmux Features → Zig/GTK Mapping

### TabManager (3,473 lines Swift)

**What it does:**
- Manages ordered list of Workspaces (tabs)
- Tracks selected workspace, focus state
- Handles workspace creation, deletion, reordering
- Pin/unpin workspaces
- Navigate: next/previous/by-index/last
- Custom titles and colors per workspace
- Window title updates from focused surface
- Focus history for back/forward navigation

**Ghostty equivalent:** `window.zig` + `tab.zig` manage tabs via `AdwTabView`. The tab model is simpler — no workspaces, no sidebar metadata.

**Zig/GTK implementation:**
- Replace `AdwTabView` with custom `GtkListBox` in a sidebar
- Create `WorkspaceManager` Zig struct with array of Workspace objects
- Each Workspace owns a `SplitTree` (already exists in Ghostty)
- Sidebar row widget shows: title, git branch, notification badge, ports
- Use GObject properties + signals for reactive updates
- Drag-and-drop reorder via `GtkDragSource` + `GtkDropTarget`

**Estimated effort:** ~1,500-2,000 lines Zig

### TerminalNotificationStore (512 lines Swift)

**What it does:**
- Stores notification list per tab/surface
- Tracks read/unread state with indexes
- Delivers desktop notifications via UNUserNotificationCenter
- Dock badge with unread count
- Auto-reorder: moves notifying workspace to top
- Deduplication: replaces prior notification from same tab+surface

**Ghostty equivalent:** Ghostty handles `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` in `application.zig` by calling `g_notification_new()` and sending via `g_application_send_notification()`. No persistence, no badge, no sidebar integration.

**Zig/GTK implementation:**
- Zig struct `NotificationStore` with ArrayList of Notification entries
- On `desktop_notification` action: create entry, update sidebar badge
- Desktop notifications via `libnotify` (`notify_notification_new()` + `notify_notification_show()`)
- Bell action → blue ring CSS class on sidebar row
- Unread count badge on sidebar rows
- Jump-to-unread: find first unread, select that workspace
- No dock badge concept on Linux (but could set urgency hint on window)

**Estimated effort:** ~300-400 lines Zig

### SessionPersistence (474 lines Swift)

**What it does:**
- JSON snapshot of entire app state: windows, workspaces, panels, layout
- Saves sidebar width, selection state
- Saves split tree positions
- Saves terminal scrollback (truncated, ANSI-safe)
- Auto-saves every 8 seconds
- Restore on launch

**Zig/GTK implementation:**
- Zig JSON serialization (std.json) for snapshot structs
- Save to `~/.local/state/cmux/session.json` (XDG spec)
- Timer-based autosave via `g_timeout_add_seconds()`
- On startup: read JSON, reconstruct workspace + split tree + surfaces
- Scrollback restore: write to temp file, replay via initial_input

**Estimated effort:** ~400-500 lines Zig

### Workspace (4,121 lines Swift)

**What it does:**
- Container for one tab's content: split tree + panels
- Panel management: create/close terminal and browser panels
- Surface metadata: git branch, PR, ports, custom status
- Bonsplit integration for split panes
- Focus management across splits
- Session snapshot/restore per workspace

**Ghostty equivalent:** `tab.zig` (570 lines) — just wraps a `SplitTree`. No panel abstraction, no metadata.

**Zig/GTK implementation:**
- Extend Tab into Workspace: add metadata fields (branch, pr, ports, status)
- Panel abstraction: `Panel` union of `TerminalPanel` | `BrowserPanel`
- Each pane in split tree holds a stack of panels (tabbed within pane)
- Git branch detection: parse `.git/HEAD` on PWD change (or shell integration)
- Port scanning: periodic `/proc/net/tcp` scan filtered by terminal PID

**Estimated effort:** ~1,500-2,000 lines Zig

### CLI / Socket API (5,414 lines Swift — cmux.swift + TerminalController)

**What it does:**
- Unix domain socket server (`/tmp/cmux-<user>/socket`)
- V1 protocol: simple text commands
- V2 protocol: structured JSON commands
- Commands: workspace/surface/pane CRUD, send text/keys, notifications
- Browser automation: navigate, click, fill, screenshot, JS eval
- Debug commands for UI testing

**Ghostty equivalent:** D-Bus IPC for `new-window` only (minimal).

**Zig/GTK implementation:**
- Unix domain socket server in Zig (`std.posix.socket()`)
- Integrate with GLib main loop via `g_unix_fd_add()`
- Command parser: `std.json` for V2 protocol
- CLI binary: `cmux` (separate Zig executable or same binary with subcommands)
- Phase 1: workspace/surface CRUD + send-text + notify
- Phase 2: browser automation

**Estimated effort:** ~2,000-3,000 lines Zig (phased)

### ContentView / Sidebar (8,843 lines Swift)

**What it does:**
- Main window layout: sidebar + content area
- Sidebar with vertical tab list
- Each sidebar row shows: title, git branch, PR badge, notification badge, ports, working dir
- Sidebar resizing (drag handle)
- Drag-and-drop workspace reorder
- Notification panel view
- Keyboard shortcuts for workspace switching

**This is the most custom UI work.**

**Zig/GTK implementation:**
- `GtkPaned` for sidebar + content split
- `GtkListBox` for sidebar workspace list
- Custom `GtkBox` row widget with labels + badges
- CSS for notification ring, unread indicator, selected state
- `GtkDragSource` + `GtkDropTarget` for reorder
- Notification panel: `GtkStack` to swap between tabs and notifications view

**Estimated effort:** ~2,000-3,000 lines Zig + Blueprint UI

---

## 4. Ghostty's Extensibility

### Plugin/Extension System: None ❌

Ghostty has no plugin system. Everything is compiled into the binary. Adding features means modifying Ghostty source directly.

### How Hard to Add a Sidebar?

**The core change:** Replace `AdwTabBar` (horizontal) with a vertical sidebar.

Looking at `window.blp`, the current layout is:
```
AdwToolbarView
├── [top] AdwHeaderBar
├── [top] AdwTabBar     ← REPLACE THIS
└── content area (AdwTabView)
```

To add a vertical sidebar:
```
GtkPaned (horizontal)
├── [start] sidebar (GtkBox)
│   ├── sidebar header
│   ├── GtkListBox (workspace rows)
│   └── notification panel toggle
└── [end] AdwToolbarView
    ├── [top] AdwHeaderBar (simplified)
    └── content area (workspace content, no longer AdwTabView)
```

**Impact:** This is a significant refactor of `window.zig` and `window.blp`. The `AdwTabView` tab lifecycle management would need to be replaced with custom workspace management.

### What Can Be Kept As-Is from Ghostty

| Component | Reusable? | Notes |
|-----------|-----------|-------|
| `surface.zig` | ✅ Yes | Terminal widget — core of the app |
| `split_tree.zig` | ✅ Yes | Split pane management |
| `search_overlay.zig` | ✅ Yes | Find-in-terminal |
| `key.zig` | ✅ Yes | Keyboard translation |
| `winproto/` | ✅ Yes | Wayland/X11 handling |
| `command_palette.zig` | ⚠️ Partially | Would need workspace-aware commands |
| `application.zig` | ⚠️ Major changes | Action handling needs cmux features |
| `window.zig` | ⚠️ Major rewrite | Sidebar replaces tab bar |
| `tab.zig` | ⚠️ Evolves | Becomes "workspace" with metadata |
| `config.zig` | ✅ Yes | GObject config wrapper |
| `build/` | ✅ Yes | Blueprint + GResource pipeline |

---

## 5. Ghostty License

### MIT License ✅

```
MIT License
Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
```

**Fully permissive.** We can:
- ✅ Fork and modify
- ✅ Distribute modified versions
- ✅ Use commercially
- ✅ Sublicense
- Only requirement: include the copyright notice

### Fork Implications
- Must keep the MIT license notice
- Should rename to avoid confusion (we're "cmux" not "Ghostty")
- Can diverge freely from upstream
- Merging upstream changes is our responsibility (no obligation from Ghostty)

### cmux License
cmux itself is also MIT licensed:
```
MIT License
Copyright (c) 2025 Manaflow, Inc.
```

No license conflicts.

---

## 6. Upstream Sync Strategy

### The Merge Problem

Ghostty's GTK frontend is actively developed. If we fork, we need to track upstream for:
- Security fixes
- Terminal emulation improvements
- Rendering performance improvements
- New libghostty features

### Approach: Fork with Minimal Core Changes

1. **Keep `surface.zig` changes minimal** — this is the most active upstream file
2. **Add new files** for sidebar, workspace, notifications — these won't conflict
3. **Modify `window.zig`/`application.zig`** — accept these will diverge significantly
4. **Use git subtree or submodule** for tracking upstream

### Estimated Upstream Sync Effort
- **Low-conflict files** (surface, split_tree, key, winproto): auto-merge usually works
- **High-conflict files** (window, application): manual merge per upstream release
- Expect ~2-4 hours per upstream Ghostty release for sync

---

## 7. Comparison: Strategy 1 vs Strategy 2

| Dimension | Strategy 1 (New GTK4 App) | Strategy 2 (Fork Ghostty) |
|-----------|--------------------------|--------------------------|
| **Starting point** | Empty project, reference Ghostty code | 18K lines of working GTK code |
| **Terminal rendering** | Must wire up libghostty manually | Already working |
| **Input handling** | Must implement key/mouse forwarding | Already working |
| **Wayland/X11** | Must handle both | Already handled |
| **Split panes** | Must implement or copy | Already working |
| **Search** | Must implement or copy | Already working |
| **Sidebar** | Build from scratch | Replace tab bar |
| **Upstream sync** | N/A (we own everything) | Ongoing merge work |
| **Build system** | Must set up from scratch | Already working |
| **Flatpak/Snap** | Must create | Already exists |
| **Time to first working terminal** | Weeks | Hours (it's already Ghostty) |
| **Time to first cmux feature** | Weeks (after terminal works) | Days (start on sidebar) |
| **Code ownership** | 100% ours | Fork with upstream dependency |
| **Community** | New project | Could contribute back (unlikely for sidebar) |

---

## 8. Recommended Fork Approach

If choosing Strategy 2:

### Phase 0: Fork & Build (Day 1)
```bash
git clone https://github.com/ghostty-org/ghostty cmux-linux
cd cmux-linux
zig build run   # Verify it works on CachyOS
```

### Phase 1: Vertical Sidebar (Week 1-2)
1. Create `src/apprt/gtk/class/sidebar.zig` — custom sidebar widget
2. Create `src/apprt/gtk/class/workspace_row.zig` — sidebar row widget
3. Create `src/apprt/gtk/ui/1.5/sidebar.blp` — sidebar Blueprint
4. Modify `window.zig` + `window.blp`: replace AdwTabBar with GtkPaned + sidebar
5. Create `workspace_manager.zig` — replaces AdwTabView's tab model
6. Wire keyboard shortcuts: Ctrl+1-9, Ctrl+Tab, etc.

### Phase 2: Notifications (Week 2-3)
1. Create `src/apprt/gtk/class/notification_store.zig`
2. Modify `application.zig`: handle `desktop_notification` action → store
3. Add CSS for notification ring (blue border on sidebar row)
4. Add unread badge to sidebar rows
5. Desktop notification via libnotify
6. Jump-to-unread shortcut

### Phase 3: Workspace Metadata (Week 3-4)
1. Parse git branch from `.git/HEAD` on PWD change
2. Port scanning via `/proc/net/tcp`
3. Display in sidebar rows
4. Working directory display

### Phase 4: Socket API & CLI (Week 4-6)
1. Unix domain socket server
2. Core commands: workspace CRUD, send-text, notify
3. CLI binary with subcommands

### Phase 5: Browser Panel (Week 6-8)
1. Add WebKitGTK dependency to build.zig
2. Create browser panel widget
3. Omnibar (address bar)
4. Wire to socket API for automation

### Phase 6: Session Persistence (Week 8-9)
1. JSON snapshot serialization
2. Autosave timer
3. Restore on launch

---

## 9. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Upstream Ghostty diverges significantly | High | Pin to specific commit, scheduled sync |
| AdwTabView removal breaks assumptions | Medium | Audit all code paths that reference tab_view |
| Zig version changes break build | Medium | Pin Zig version, track Ghostty's requirements |
| Ghostty project objects to fork | Low | MIT license, they can't block it |
| CachyOS-specific build failures | Low | CI on both standard Arch + CachyOS |
| Performance regression from sidebar | Low | GTK4 is efficient, sidebar is lightweight |

---

## 10. Summary

**Strategy 2 is faster to ship but creates an ongoing maintenance burden.**

**Strengths:**
- Working terminal on Day 1 (it's just Ghostty)
- All the hard problems (rendering, input, Wayland/X11, splits) are solved
- Build system, Flatpak, and packaging infrastructure exist
- Can ship a usable product in ~4-6 weeks

**Weaknesses:**
- Ongoing upstream merge work (~2-4 hours per Ghostty release)
- `window.zig` and `application.zig` will diverge heavily
- Risk of upstream architecture changes that break our modifications
- Fork perception: users may see it as "modified Ghostty" not a new product

**The key convergence with Strategy 1:** In both strategies, you end up writing Zig code that extends Ghostty's GTK patterns. Strategy 2 just starts with more working code. The sidebar, notifications, workspace manager, and socket API are all net-new code either way.
