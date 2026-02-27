# Cove: Progress Log

> A workspace-oriented terminal for Linux, inspired by [cmux](https://github.com/manaflow-ai/cmux) and built on [Ghostty](https://github.com/ghostty-org/ghostty)'s GTK frontend.
>
> See [plan.md](plan.md) for the full build plan, git strategy, and attribution requirements.

---

## Decision: Strategy 2 — Fork Ghostty's GTK Frontend

After research spikes on both approaches (see `spike-strategy1-gtk4-rewrite.md` and `spike-strategy2-ghostty-fork.md`), we chose **Strategy 2** because:

- Working terminal on Day 1 (Ghostty already runs on Linux)
- 18K lines of proven GTK4/Zig code for free (rendering, input, splits, search, Wayland/X11)
- cmux-specific features (sidebar, notifications, socket API) are net-new code either way
- MIT license — no restrictions
- Build system, Flatpak, snap packaging already exist

---

## Current State

### ✅ Phase 0 — Repository & Attribution (Complete)
- [x] Renamed binary from `ghostty` to `cove` (`GhosttyExe.zig`)
- [x] Changed app ID from `com.mitchellh.ghostty` to `dev.cove.terminal` across all files
- [x] Updated About dialog (name→Cove, developer→Cove Contributors, URLs→anurag-arjun/cove)
- [x] Updated all user-facing strings (notifications, inspector title, debug warnings, menu labels)
- [x] Kept internal GObject class names (`GhosttyApplication`, etc.) unchanged — minimizes rebase conflicts
- [x] Created `README.md` with project description + Ghostty/cmux credits
- [x] Created `THIRD_PARTY_LICENSES.md` with verbatim MIT licenses
- [x] Created GitHub repo: `github.com/anurag-arjun/cove` (public)
- [x] Set up remotes: `origin` → anurag-arjun/cove, `upstream` → ghostty-org/ghostty
- [x] Created `cove/main` branch, pushed and tracking `origin/cove/main`
- [x] `main` branch tracks upstream Ghostty exactly (never commit Cove code here)
- [x] Commit: `6816b450a` — "cove: Phase 0 — rename to Cove, add attribution, set up repo"

### ✅ Phase 1 — Vertical Sidebar (Complete)
- [x] Replaced `AdwTabOverview` + `AdwTabBar` with `GtkPaned` + sidebar `GtkListBox`
- [x] Kept `AdwTabView` internally for page management (key architectural decision — see notes)
- [x] Sidebar shows workspace list with titles bound from tab page titles
- [x] Clicking a sidebar row selects the corresponding workspace
- [x] Tab page selection changes sync to sidebar automatically
- [x] Added `sidebar-visible` property with `win.toggle-sidebar` action
- [x] Added toggle button in header bar (sidebar-show-symbolic icon)
- [x] Added "Toggle Sidebar" entry in main menu
- [x] Removed: `AdwTabOverview`, `AdwTabBar`, tab context menu, tab overview focus timer
- [x] Removed: `tabs-autohide`/`tabs-visible`/`tabs-wide` properties (replaced by sidebar)
- [x] Added `.cove-sidebar` CSS class with `navigation-sidebar` styling
- [x] `toggleTabOverview()` now delegates to `toggleSidebar()` for API compatibility
- [x] Commit: `6363939c4` — "cove: Phase 1 — vertical sidebar replaces tab bar"
- [x] Build verified: `./build.sh` produces working `zig-out/bin/cove` with sidebar

#### Phase 1 Polish (Complete)
- [x] Close button (X) on sidebar row, visible on hover — `GtkEventControllerMotion` enter/leave
- [x] Middle-click sidebar row to close workspace — `GtkGestureClick` button=2
- [x] Right-click context menu on sidebar rows (Rename, Move Up/Down, Close) — plain `GtkPopover` with direct callbacks
- [x] Fixed sidebar not visible by default (bidirectional binding race fix)
- [x] Double-click sidebar row to rename workspace — `GtkGestureClick` n_press=2
- [x] Reorder via context menu Move Up/Down — `AdwTabView.reorderPage()` + `page-reordered` signal + `sidebarRebuild()`
- [x] Keyboard navigation (Up/Down in sidebar, Enter to select) — built into `GtkListBox` with `selection-mode: browse`
- [x] Commit: `febc8fd98` — "cove: Phase 1d — close button, middle-click, context menu"
- [x] Commit: `e0ae72a56` — "cove: Phase 1d — double-click rename, reorder via context menu"
- [x] All Phase 1 manual tests passing (42/42)

#### Phase 1 Deferred (Low Priority)
- [ ] Drag-to-reorder sidebar rows — **attempted, removed** (GTK `DragSource` snapshot crashes with terminal EGL contexts; see session log)
- [ ] Sidebar auto-hide when only 1 workspace — cmux doesn't do this; skipped
- [ ] Persist sidebar width in config — needs `~/.config/cove/config` setup (Phase 3+)

### 🔲 Not Started
- [ ] Phase 2: Notification system (blue badges, desktop notifications, jump-to-unread)
- [ ] Phase 3: Workspace metadata + sidebar UX (git branch, ports, pwd, pin, tab color, multi-select, shortcut hints)
- [ ] Phase 4: Socket API & CLI + metadata commands (`cove +list-workspaces`, status, log, progress, PR, move-to-window)
- [ ] Phase 5: Browser panel (WebKitGTK)
- [ ] Phase 6: Session persistence

---

## Implementation Plan

**Full detail in [plan.md](plan.md).** Summary:

| Phase | Feature | Est. Lines | Status |
|-------|---------|-----------|--------|
| 0 | Repo, build, README, attribution | 100 | ✅ Done |
| 1 | Vertical sidebar (replace AdwTabBar) | 1,700 | ✅ Done |
| 2 | Notification system | 400 | 🔲 Not started |
| 3 | Workspace metadata + sidebar UX (git, ports, pwd, pin, color, multi-select, shortcut hints) | 900 | 🔲 Not started |
| 4 | Socket API & CLI + metadata commands (`cove +cmd`, status, log, progress, PR) | 3,200 | 🔲 Not started |
| 5 | Browser panel (WebKitGTK) | 2,000 | 🔲 Not started |
| 6 | Session persistence | 500 | 🔲 Not started |

---

## Key Architecture Decisions

### Keep AdwTabView internally (Phase 1)

The plan originally called for replacing `AdwTabView` with `GtkStack`. Instead, we kept `AdwTabView` as the internal page container and just removed its visible UI components (`AdwTabBar`, `AdwTabOverview`). Rationale:

- `AdwTabView` handles page ordering, close confirmation, drag-and-drop, signals — all for free
- Replacing it with `GtkStack` would require reimplementing all that page management logic
- Tab.zig's `getTabView()` method (used for close/reorder/navigate actions) continues to work unchanged
- Much smaller diff = much easier rebases against upstream Ghostty
- The sidebar is an additional navigation layer on top, not a replacement of the data model

**Window layout after Phase 1:**
```
AdwApplicationWindow
└── GtkPaned (horizontal, position: 220px)
    ├── [start] GtkBox .cove-sidebar
    │   ├── GtkBox (header: "Workspaces" label + "+" button)
    │   └── GtkScrolledWindow → GtkListBox .navigation-sidebar
    └── [end] AdwToolbarView
        ├── [top] AdwHeaderBar (sidebar toggle + menu)
        └── AdwToastOverlay
            └── AdwTabView (hidden tab bar, managed internally)
```

### Don't use vX.Y.Z tags (Build system)

Ghostty's build system (`GitVersion.zig`) uses `git describe --exact-match --tags` and panics if a tag doesn't match the `vX.Y.Z` format in `build.zig`. Our initial `v0.0.1-scaffold` tag broke the build. Solution: don't tag Cove commits with `v`-prefixed semver tags. Use `cove-*` prefixed tags if needed, or no tags at all.

### Keep GObject class names unchanged

Internal GObject type names (`GhosttyApplication`, `GhosttyWindow`, `GhosttySplitTree`, etc.) are kept as-is. Changing them would be a massive diff touching dozens of files and Blueprint templates, with no user-facing benefit. Only user-visible strings (About dialog, notification titles, menu labels, debug warnings) were updated to "Cove".

---

## Key Files Reference

### Files modified by Cove (potential rebase conflicts)
| File | Phase | Change |
|------|-------|--------|
| `src/build/GhosttyExe.zig` | 0 | Binary name: `cove` |
| `src/apprt/gtk/App.zig` | 0 | App ID: `dev.cove.terminal` |
| `src/apprt/gtk/build/gresource.zig` | 0 | Resource prefix/app_id |
| `src/apprt/gtk/class/application.zig` | 0 | Resource path, notification title, icon |
| `src/apprt/gtk/class/surface.zig` | 0 | Notification icon |
| `src/apprt/gtk/class/window.zig` | 0, 1 | About dialog, sidebar replaces tab bar (heavy) |
| `src/apprt/gtk/ui/1.5/window.blp` | 1 | Full layout rewrite (GtkPaned + sidebar) |
| `src/apprt/gtk/css/style.css` | 1 | `.cove-sidebar` styles |
| `src/apprt/gtk/ipc/new_window.zig` | 0 | Comment updates |
| `src/apprt/gtk/winproto/x11.zig` | 0 | WM_CLASS comment |
| `src/apprt/gtk/ui/1.5/inspector-window.blp` | 0 | Title, icon |
| `src/apprt/gtk/ui/1.2/debug-warning.blp` | 0 | Debug text |
| `src/apprt/gtk/ui/1.3/debug-warning.blp` | 0 | Debug text |

### Files created by Cove (no rebase conflicts)
```
README.md
THIRD_PARTY_LICENSES.md
build.sh
docs/plan.md
docs/progress.md
docs/spike-strategy1-gtk4-rewrite.md
docs/spike-strategy2-ghostty-fork.md
```

### Ghostty GTK files we keep as-is
| File | Role |
|------|------|
| `src/apprt/gtk/class/surface.zig` | Terminal widget (GLArea + input) |
| `src/apprt/gtk/class/split_tree.zig` | Split pane management |
| `src/apprt/gtk/class/tab.zig` | Workspace container (Tab → conceptually "workspace") |
| `src/apprt/gtk/class/search_overlay.zig` | Find-in-terminal |
| `src/apprt/gtk/key.zig` | Keyboard translation |
| `src/apprt/gtk/winproto/` | Wayland/X11 protocol |
| `src/renderer/OpenGL.zig` | GPU renderer |

---

## Environment

- **OS:** CachyOS (Arch-based)
- **Zig:** 0.15.2 (from `cachyos-extra-v3`)
- **GTK4:** 4.20.3
- **libadwaita:** 1.8.4
- **Project dir:** `/home/lighto/code/misc/cmux-try/`
- **GitHub:** `github.com/anurag-arjun/cove` (public)
- **Upstream:** `github.com/ghostty-org/ghostty` (remote: `upstream`)

---

## Git State

```
Remotes:
  origin   → git@github.com:anurag-arjun/cove.git
  upstream → https://github.com/ghostty-org/ghostty.git

Branches:
  cove/main → origin/cove/main (our work)
  main      → upstream/main (tracks Ghostty, never commit here)

Commits (cove/main):
  e0ae72a56 cove: Phase 1d — double-click rename, reorder via context menu
  febc8fd98 cove: Phase 1d — close button, middle-click, context menu
  6363939c4 cove: Phase 1 — vertical sidebar replaces tab bar
  6816b450a cove: Phase 0 — rename to Cove, add attribution, set up repo
  74ba971eb (upstream) Update VOUCHED list (#11028)
```

---

## Notes

- The cmux macOS source was previously cloned to this directory for analysis, then cleaned. The original repo is at `https://github.com/manaflow-ai/cmux` and a cached clone exists at `/tmp/pi-github-repos/manaflow-ai/cmux/`.
- Ghostty's GTK frontend is in `src/apprt/gtk/`. The macOS frontend is in `macos/` (irrelevant for us).
- libghostty's C header is at `include/ghostty.h` — but we use the Zig module interface directly (same as Ghostty's GTK frontend does).
- Both Ghostty and cmux are MIT licensed. No conflicts.
- Sidebar rows store a pointer to their `AdwTabPage` via `gobject.Object.setData("cove-tab-page", page)`. Retrieved via `@ptrCast(@alignCast(getData(...)))` — can't use `gobject.ext.cast` on `*anyopaque`.

---

## Session Log

### Session 2026-02-26 — Research & Planning Complete

**Key decisions made:**
1. **Strategy 2 (Ghostty fork) selected** over Strategy 1 (GTK4 rewrite from scratch). Rationale: working terminal on Day 1, 18K lines of proven GTK4/Zig code, MIT license.
2. **6-phase implementation plan** defined (Sidebar → Notifications → Metadata → Socket API → Browser → Session Persistence), ~9 weeks estimated.
3. **Architecture mapped**: cmux macOS features → Ghostty GTK equivalents. Key files to modify identified (`window.zig`, `application.zig`, `tab.zig`, `window.blp`).

**Work completed:**
- Full analysis of both cmux macOS (~65K lines Swift) and Ghostty GTK (~18K lines Zig) codebases
- Two spike documents produced: `spike-strategy1-gtk4-rewrite.md`, `spike-strategy2-ghostty-fork.md`
- Ghostty repo cloned (at commit `74ba971eb`, v1.3.0-dev)
- All CachyOS build dependencies installed and verified
- Detailed implementation plan with file-level targets for all 6 phases

### Session 2026-02-26 (cont.) — First Build Successful

**Build issues encountered and resolved:**
1. **GCC 15 SFrame linker error**: Zig 0.15's LLD and self-hosted linker both fail on `R_X86_64_PC64` in `.sframe`. Fix: strip sections via `objcopy`, use `--libc` to point to patched CRT dir.
2. **Conda Python 3.12 vs system Python 3.14**: Fix: `PATH=/usr/bin:...` override.

**Created:** `build.sh` — wrapper script encapsulating both workarounds.

### Session 2026-02-26 (cont.) — Naming & Plan Finalized

**Decisions:** Project renamed to "Cove". Binary: `cove`, App ID: `dev.cove.terminal`. Git rebase-only workflow. Created `docs/plan.md`.

### Session 2026-02-26 (cont.) — Phase 0 & Phase 1 Complete

**Phase 0 completed:**
- Binary renamed `ghostty` → `cove` (`GhosttyExe.zig`)
- App ID changed to `dev.cove.terminal` across 10+ files (App.zig, gresource.zig, application.zig, surface.zig, window.zig, inspector-window.blp, etc.)
- About dialog updated: name→Cove, developer→Cove Contributors, URLs→anurag-arjun/cove
- README.md and THIRD_PARTY_LICENSES.md created
- GitHub repo created at `github.com/anurag-arjun/cove` (public)
- Remotes set up: `origin` (our repo) + `upstream` (Ghostty)
- `cove/main` branch created and pushed

**Phase 1 (sidebar) completed (core):**
- Removed `AdwTabOverview` (grid overview) and `AdwTabBar` (horizontal tab bar) from window layout
- Added `GtkPaned` with sidebar `GtkBox` containing `GtkListBox` (`.navigation-sidebar` style)
- Sidebar rows are created dynamically when pages attach, removed when pages detach
- Row titles bound to `AdwTabPage` title property via `gobject.Object.bindProperty`
- Sidebar selection syncs bidirectionally with `AdwTabView` selected page
- Anti-reentrance guard (`updating_sidebar` flag) prevents signal loops
- `sidebar-visible` property with bidirectional binding to toggle button
- `win.toggle-sidebar` action + main menu entry
- `toggleTabOverview()` redirected to `toggleSidebar()` for Ghostty action compatibility
- Removed dead code: `tabOverviewCreateTab`, `tabOverviewOpen`, `tabOverviewFocusTimer`, `setupTabMenu`, `closureTitlebarStyleIsTab`, `actionPromptContextTabTitle`, `context_menu_page` field, `tab_overview_focus_timer` field

**Build issues encountered:**
- `v0.0.1-scaffold` tag broke build — Ghostty's `GitVersion.zig` panics on non-matching `vX.Y.Z` tags. Solution: deleted tag, don't use `v`-prefixed tags for Cove.
- GTK/GObject type mismatches: `setHexpand(true)` needs `@intFromBool(true)` (c_int, not bool); `getData()` returns `*anyopaque` requiring `@ptrCast` not `gobject.ext.cast`.

**Next actions (in order):**
1. **Phase 1 polish:** Close button on hover, keyboard nav, middle-click close, right-click context menu, drag-reorder, rename, persist width
2. **Phase 2:** Notification system — blue badges on sidebar rows, desktop notifications via GLib
3. **Phase 3:** Workspace metadata + sidebar UX — git branch, pwd, ports, pin, tab color, multi-select, shortcut hints

### Session 2026-02-26 (cont.) — cmux Source Audit & Plan Hardening

**Key decisions made:**
1. **cmux source code is the behavioral spec.** Every task item in `plan.md` now has a `cmux:` annotation pointing to the exact file, line range, and function in the cmux macOS source (`github.com/manaflow-ai/cmux`, cached at `/tmp/pi-github-repos/manaflow-ai/cmux/`). Always read the referenced cmux code before implementing a task.
2. **Phase scope expanded after cmux audit.** Deep comparison of our Phase 1 sidebar vs cmux's `TabItemView` revealed missing features. These were triaged into later phases rather than blocking Phase 1.
3. **Phase 1d expanded** — added close button (X) on hover and drag-to-reorder as explicit task items (were previously only in a "deferred" note).
4. **Phase 3 expanded** (600→900 lines) — absorbed deferred sidebar UX items: pin/unpin workspace, tab color, multi-select, workspace shortcut hints.
5. **Phase 4 expanded** (2,500→3,200 lines) — absorbed deferred metadata commands from cmux: status entries, log entries, progress bar, PR status, move-workspace-to-window.
6. **Double-click behavior difference noted:** cmux does NOT double-click sidebar rows to rename — double-click on empty sidebar area creates a new workspace. Rename is context menu or command palette only. Decision still open for Cove (double-click row to rename is more conventional in GNOME).

**Work completed:**
- Cloned cmux repo (`github.com/manaflow-ai/cmux`) for reference
- Added comprehensive "cmux Source Reference" section to `plan.md` with file-by-feature table (18 rows covering all ~31K lines of key cmux Swift source)
- Added `cmux:` annotations to all 57 task items across all 6 phases (71 total annotations)
- Annotated all 9 completed Phase 1a-c `[x]` items with cmux equivalents or "N/A — Cove-specific"
- Added cmux sidebar layout diagram for visual comparison
- Documented "cmux features NOT yet implemented" with explicit target phases for each
- Identified cmux features we hadn't planned for: status entries, log entries, progress bar, PR status, multi-select, shortcut hints, pin, tab color, move-to-window
- Updated milestone estimates in both `plan.md` and `progress.md`

**No code changes this session** — documentation/planning only.

**Next actions (in order):**
1. **Phase 1d polish** — start with close button on hover (highest UX impact), then middle-click close, right-click context menu, drag-reorder
2. Read cmux `ContentView.swift` ~L6191–6850 (`TabItemView`) and ~L8113–8148 (`MiddleClickCapture`) before implementing
3. For close button: change `sidebarAddRow()` from plain `GtkLabel` to `GtkBox` (label + button), add `GtkEventControllerMotion` for hover
4. For middle-click: add `GtkGestureClick` with button=2 to sidebar rows
5. For context menu: create `GtkPopoverMenu` with `GMenu` model (Rename, Close, Close Others)
6. Build and test after each item: `./build.sh run`

### Session 2026-02-26 (cont.) — Phase 1d Implementation Started

**Work completed (in progress, not yet committed):**
- Rewrote `sidebarAddRow()` in `window.zig`: sidebar rows changed from plain `GtkLabel` to `GtkBox` (horizontal) with title label + close button
  - Close button: `window-close-symbolic` icon, flat+circular style, hidden by default, shown on hover via `GtkEventControllerMotion`
  - Middle-click close: `GtkGestureClick` with button=2 on each row
  - Right-click context menu: `GtkGestureClick` with button=3 → builds `GtkPopoverMenu` from `gio.Menu` (Rename Workspace, Close Workspace)
  - Data stored on each `GtkListBoxRow` via `setData()`: `cove-tab-page` (page ref), `cove-close-btn` (button ref), `cove-motion-ctrl` (motion controller ref)
- Added ~110 lines of new callback functions:
  - `sidebarRowGetCloseBtn()` — retrieve close button from row data
  - `sidebarRowFromController()` — find `GtkListBoxRow` from event controller's widget
  - `sidebarCloseClicked()` — walks up widget tree to find row, then calls `tab_view.closePage()`
  - `sidebarRowEnter()` / `sidebarRowLeave()` — show/hide close button on hover
  - `sidebarMiddleClick()` — close workspace on middle-click
  - `sidebarRightClick()` — build and show context menu popover
  - `sidebarPopoverClosed()` — unparent popover on close (cleanup)
- Added CSS for `.cove-sidebar-close` button (small, low opacity, full opacity on hover)

**Build error encountered — NOT YET RESOLVED:**
- `gtk4.Button has no member named 'connectClicked'` — the zig-gobject bindings use `TypeName.signals.signal_name.connect()` pattern, NOT `TypeName.connectSignalName()`.
- Same issue applies to `EventControllerMotion.connectEnter/connectLeave` and `GestureClick.connectReleased`.
- Fix needed: change all 5 signal connections in `sidebarAddRow()` to use the `signals.X.connect()` pattern (e.g., `gtk.Button.signals.clicked.connect(close_btn, ...)`).
- Reference for correct pattern: `Tab.signals.@"close-request".connect(tab, *Self, tabCloseRequest, self, .{})` at window.zig ~L1420.

**Key decisions made:**
1. **Sidebar row layout:** `GtkBox` (horizontal) with `GtkLabel` (hexpand) + `GtkButton` (close, hidden until hover). Simpler than creating a custom GObject widget. Matches cmux's `HStack` pattern in `TabItemView`.
2. **Close button visibility:** Controlled by `GtkEventControllerMotion` enter/leave on the `GtkListBoxRow` (not the hbox). Controller uses `.capture` phase to ensure it fires before child widget events.
3. **Context menu approach:** Programmatic `gio.Menu` + `gtk.PopoverMenu` created on-demand per right-click. Menu is parented to the row, unparented on close. Simpler than a template-based approach since menu items will expand in later phases.
4. **Right-click selects row first:** Before showing context menu, the clicked row's page is selected in `AdwTabView`. This ensures `win.close-tab` and `win.prompt-tab-title` actions target the correct workspace.

**Files modified (uncommitted):**
- `src/apprt/gtk/class/window.zig` — `sidebarAddRow()` rewritten, 7 new callback functions added
- `src/apprt/gtk/css/style.css` — `.cove-sidebar-close` styles added
- `docs/plan.md` — cmux annotations (from previous session work)
- `docs/progress.md` — session log

**Next actions (in order):**
1. ~~**Fix signal connection syntax**~~ → **DONE** (see next session)
2. **Build and test** — `./build.sh run`, verify close button appears on hover, middle-click closes, right-click shows menu
3. ~~**Fix callback signatures if needed**~~ → **Not needed** (signatures were already correct)
4. **After build succeeds:** Test all three features, then move on to remaining Phase 1d items (drag-reorder, keyboard nav, sidebar width persistence)
5. **Commit** when close button + middle-click + context menu all work

### Session 2026-02-26 (cont.) — Signal Fix, Build Passes, Test Plans & Automated Test Strategy

**Work completed:**

1. **Fixed all 6 signal connection calls in `window.zig`** — the zig-gobject bindings use `TypeName.signals.signal_name.connect()`, NOT `TypeName.connectSignalName()`. Changed:
   - `gtk.Button.connectClicked(...)` → `gtk.Button.signals.clicked.connect(...)`
   - `gtk.EventControllerMotion.connectEnter(...)` → `gtk.EventControllerMotion.signals.enter.connect(...)`
   - `gtk.EventControllerMotion.connectLeave(...)` → `gtk.EventControllerMotion.signals.leave.connect(...)`
   - `gtk.GestureClick.connectReleased(...)` → `gtk.GestureClick.signals.released.connect(...)` (×2, for middle-click and right-click)
   - `gtk.Popover.connectClosed(...)` → `gtk.Popover.signals.closed.connect(...)` (in `sidebarRightClick`)
   - Callback signatures were already correct — no changes needed there.
   - **Build now passes.** Binary at `zig-out/bin/cove` (150MB debug build).

2. **Added manual testing plans to `plan.md`** — 202 test cases across all 7 phases:
   - Phase 0: 15 tests (binary name, app ID, About dialog, D-Bus, config compat)
   - Phase 1: 42 tests (sidebar basics, workspace CRUD, toggle, close/middle-click/context menu, splits interaction, edge cases)
   - Phase 2: 20 tests (notification badges, desktop notifications, mark-as-read, jump-to-unread)
   - Phase 3: 34 tests (PWD, git branch, ports, combined metadata, pin, tab color, multi-select, shortcut hints)
   - Phase 4: 39 tests (socket server, CLI workspace management, terminal interaction, env vars, metadata commands, error handling)
   - Phase 5: 25 tests (browser panel, split integration, socket API for browser)
   - Phase 6: 27 tests (save/restore, autosave, --no-restore, corrupt files, edge cases)

3. **Added automated test strategy to `plan.md`** — researched both Ghostty's and cmux's test infrastructure:
   - **Ghostty:** 2,473 Zig unit tests across 166 files, comprehensive CI (GTK X11/Wayland matrix, Valgrind, 10+ linters, multi-platform builds). We inherit all of this.
   - **cmux:** 3 test layers (~15,500 lines total): 8 XCTest unit test files (~11,670 lines), 10 XCUITest UI test files (~3,837 lines), ~80 Python integration scripts in `tests/` using a `cmux.py` socket client library. CI only runs `UpdatePillUITests`.
   - **Cove strategy (3 layers):**
     - Layer 1: Zig unit tests (`zig build test`) — inherited 2,473 + ~30-50 new for notification store, git parser, port scanner, socket protocol, session serialization
     - Layer 2: Python integration tests (`tests/`) — socket-driven `cove.py` client modeled on cmux's `cmux.py`, ~50 tests across 10 files, available from Phase 4+
     - Layer 3: Visual/E2E (future) — `xvfb-run` + socket API + AT-SPI accessibility queries
   - CI plan: GitHub Actions with `zig build test` + `xvfb-run` integration tests

**Key decisions made:**
1. **zig-gobject signal pattern:** Always use `TypeName.signals.signal_name.connect(instance, DataType, &callback, data, .{})`. Never use `TypeName.connectSignalName()` — that method doesn't exist in the bindings. Discovered by inspecting the generated binding source at `~/.cache/zig/p/gobject-0.3.0-*/src/gtk4/gtk4.zig`.
2. **Callback signatures match the signal definition exactly:** `clicked` = `fn(*Button, *Self) callconv(.c) void`; `enter` = `fn(*EventControllerMotion, f64, f64, *Self) callconv(.c) void`; `leave` = `fn(*EventControllerMotion, *Self) callconv(.c) void`; `released` = `fn(*GestureClick, c_int, f64, f64, *Self) callconv(.c) void`; `closed` = `fn(*Popover, *PopoverMenu) callconv(.c) void`. These were already correct in our code.
3. **Test strategy:** 3-layer pyramid matching cmux's approach but adapted for Zig/GTK/Linux. Manual testing plans serve as the spec until socket API enables automated integration tests in Phase 4.

**Files modified (uncommitted):**
- `src/apprt/gtk/class/window.zig` — 6 signal connection calls fixed (from previous session: `sidebarAddRow()` rewrite + 7 callbacks)
- `src/apprt/gtk/css/style.css` — `.cove-sidebar-close` styles (from previous session)
- `docs/plan.md` — added 202 manual test cases (7 phase testing plans), automated test strategy section, cmux/Ghostty test infrastructure analysis
- `docs/progress.md` — session log updates

**Build state:** ✅ Passes. `zig-out/bin/cove` exists. Not yet runtime-tested.

**Next actions (in order):**
1. ~~**Runtime test Phase 1d features**~~ → **DONE** (see next session)
2. ~~**Fix runtime issues**~~ → **DONE** (see next session)
3. ~~**Commit**~~ → **DONE** (see next session)

### Session 2026-02-26 (cont.) — Phase 1 Complete, All Tests Passing

**Work completed:**

1. **Runtime tested all Phase 1 features (42/42 tests passing):**
   - Sidebar basics: visible on launch (after fix), correct width, resize works, title display + updates
   - Workspace CRUD: new workspace (+button and Ctrl+Shift+T), click/keybind/numbered switching, close, ordering, scrolling with 10+
   - Sidebar toggle: button, menu entry, hidden+workspaces still functional
   - Close button on hover: appears/disappears correctly, click closes workspace
   - Middle-click close: works
   - Right-click context menu: Rename and Close both work, correct target selection, Escape dismissal
   - Splits within workspaces preserved across switches
   - Search overlay, fullscreen (Ctrl+Enter), multiple windows all work
   - Edge cases: rapid creation (20+), rapid switching, long/empty/unicode titles all handled

2. **Bugs found and fixed during testing:**
   - **Sidebar not visible by default:** Bidirectional binding between `sidebar-visible` property and `GtkToggleButton.active` raced during template init. Fix: explicitly set `priv.sidebar_visible = true` before `syncAppearance()`.
   - **Context menu actions not firing (GMenu approach):** `GtkPopoverMenu` with `gio.Menu` model didn't properly dispatch `win.close-tab::this` and `win.prompt-tab-title` actions. Fix: replaced `GtkPopoverMenu`+`gio.Menu` with plain `GtkPopover` containing `GtkButton`s with direct click callbacks (`sidebarContextRename`, `sidebarContextClose`). Actions now call `self.performBindingAction(...)` directly.
   - **Context menu popover not tracking:** Right-clicking row B while row A's menu was open required two clicks (first click dismissed A's menu, second opened B's). This is standard GTK popover grab behavior — accepted as-is.

3. **Implemented double-click to rename:**
   - Added `GtkGestureClick` with button=1 on each sidebar row
   - `sidebarDoubleClick` callback checks `n_press == 2`, then calls `performBindingAction(.prompt_tab_title)`

4. **Implemented reorder via context menu (Move Up/Down):**
   - Context menu now has: Rename | separator | Move Up | Move Down | separator | Close
   - Move Up/Down greyed out at list boundaries (first/last position)
   - `sidebarContextMoveUp`/`sidebarContextMoveDown` call `AdwTabView.reorderPage()`
   - Connected `page-reordered` signal in `window.blp` → `tabViewPageReordered` handler calls `sidebarRebuild()` which clears and recreates all sidebar rows from `AdwTabView` page list

5. **Drag-to-reorder attempted and removed:**
   - Implemented `GtkDragSource` (prepare signal returning `ContentProvider` with row index) + `GtkDropTarget` (drop signal calling `reorderPage`)
   - **Crashed on every drag attempt** — `General protection exception` in `libgobject-2.0.so.0`
   - Root cause: GTK's `DragSource` creates a visual snapshot of the dragged widget for the drag icon. The sidebar rows are near terminal surfaces with EGL/OpenGL contexts. The snapshot operation triggers EGL context creation/destruction cycles that corrupt GObject state.
   - Tried deferred rebuild via `glib.idleAdd()` — still crashed (crash happens during drag start, not during drop)
   - **Decision: removed drag-to-reorder entirely.** Context menu Move Up/Down is sufficient and reliable. Drag-to-reorder can be revisited later if a workaround is found (e.g., custom drag icon that avoids snapshotting, or GtkListBox row with a simpler widget tree).

**Key decisions made:**
1. **Context menu uses plain `GtkPopover` + `GtkButton`s, not `GtkPopoverMenu` + `gio.Menu`.** The GMenu/PopoverMenu approach had action dispatch issues (actions with string parameters like `win.close-tab::this` didn't fire). Direct button callbacks are simpler and more reliable. Menu items call `self.performBindingAction(...)` directly.
2. **Reorder via context menu, not drag-and-drop.** GTK DragSource + terminal EGL contexts = crash. Move Up/Down menu items are safe and work. cmux uses drag-to-reorder via SwiftUI's `.draggable()` modifier + custom `SidebarTabDropDelegate` (~130 lines), but their Swift/AppKit stack doesn't have the EGL snapshot issue.
3. **`sidebarRebuild()` is the canonical way to sync sidebar ↔ tab_view order.** It removes all rows and recreates them from `AdwTabView.getNthPage()`. Used after reorder and potentially useful for future operations (restore from session, etc.).
4. **Double-click row = rename (GNOME convention).** cmux uses double-click on empty sidebar area to create a new workspace; rename is context-menu-only. We chose the GNOME convention (double-click row to rename) since it's more discoverable for Linux users.
5. **Default keybinds differ from test plan assumptions:** Splits are `Ctrl+Shift+O` (right) / `Ctrl+Shift+E` (down), not `Ctrl+Shift+Enter`. Fullscreen is `Ctrl+Enter`, not `F11`. Updated test plan notes.

**Commits:**
- `febc8fd98` — "cove: Phase 1d — close button, middle-click, context menu"
- `e0ae72a56` — "cove: Phase 1d — double-click rename, reorder via context menu"

**Files modified:**
- `src/apprt/gtk/class/window.zig` — `sidebarAddRow()` rewrite (row = hbox + label + close btn), 12 new callback functions, `sidebarRebuild()`, `tabViewPageReordered` handler, `sidebar_context_popover` field
- `src/apprt/gtk/css/style.css` — `.cove-sidebar-close` styles
- `src/apprt/gtk/ui/1.5/window.blp` — added `page-reordered` signal binding
- `docs/plan.md` — cmux annotations, 202 manual test cases, automated test strategy
- `docs/progress.md` — session log

**Phase 1 is now fully complete.** All features implemented, all tests passing, pushed to `origin/cove/main`.

**Next actions (in order):**
1. **Phase 2: Notification system** — create `notification_store.zig`, hook `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` / `RING_BELL` / `COMMAND_FINISHED` in `application.zig`, add blue badge to sidebar rows, desktop notifications via `g_application_send_notification()`, mark-as-read on workspace select, jump-to-unread action (`Ctrl+Shift+U`)
2. Read cmux `TerminalNotificationStore.swift` (~510 lines) and `NotificationsPage.swift` (~250 lines) before implementing
3. Start with the data model (`notification_store.zig`) then wire up signals, then UI (badges + desktop notify)
