# Cove: Build Plan

> A workspace-oriented terminal for Linux, inspired by [cmux](https://github.com/manaflow-ai/cmux) and built on [Ghostty](https://github.com/ghostty-org/ghostty)'s GTK frontend.

---

## Naming & Attribution

### Why "Cove"?

A cove is a sheltered place — a workspace where you keep multiple things running. Short, easy to type, no conflicts with existing tools.

- **Binary name:** `cove`
- **App ID:** `dev.cove.terminal` (or `io.github.YOUR_USER.cove`)
- **Socket path:** `$XDG_RUNTIME_DIR/cove/socket`
- **Config dir:** `~/.config/cove/` (falls back to `~/.config/ghostty/config` for terminal settings)
- **State dir:** `~/.local/state/cove/`

### Credits & Attribution (README section)

The README must include a prominent credits section. Draft:

```markdown
## Credits & Acknowledgments

Cove is built on the shoulders of two excellent projects:

### Ghostty
Cove's terminal engine — rendering, input handling, split panes, search,
Wayland/X11 support — comes from [Ghostty](https://ghostty.org/) by
Mitchell Hashimoto. Ghostty is a fast, feature-rich terminal emulator
written in Zig with native GPU-accelerated rendering.

Cove is a fork of Ghostty's GTK frontend with a workspace-oriented UI
added on top. Ghostty is licensed under the MIT License.

- Website: https://ghostty.org/
- Source: https://github.com/ghostty-org/ghostty
- License: MIT

### cmux
Cove's feature set — vertical sidebar, notification rings, workspace
metadata, socket API, in-app browser — is inspired by
[cmux](https://github.com/manaflow-ai/cmux) by Manaflow AI. cmux is
a native macOS terminal built on libghostty with the same workspace-first
philosophy. Cove brings these ideas to Linux using Ghostty's GTK frontend.

- Website: https://cmux.dev/
- Source: https://github.com/manaflow-ai/cmux
- License: MIT

### License
Cove is licensed under the MIT License, consistent with both upstream projects.
```

This must appear:
1. In the top-level `README.md`
2. In the "About" dialog (replace Ghostty's about dialog text)
3. In a `THIRD_PARTY_LICENSES.md` file listing Ghostty and cmux MIT licenses verbatim

---

## Architecture Decision

### Why fork Ghostty, not extend it?

**Ghostty has no extension/plugin system.** Everything is compiled into a single binary. The only customization points are:

- **Custom shaders** (visual only — cursor effects, CRT filters)
- **Custom command palette entries** (map to existing Ghostty actions)
- **Custom CSS** (GTK theming — colors, margins, fonts)
- **Terminal API** (OSC sequences — notifications, images, progress)

None of these allow adding a sidebar widget, modifying the tab system, adding a workspace model, or embedding a browser panel. Those require modifying Ghostty's Zig source directly.

### How cmux macOS does it

cmux macOS takes a **library approach**: it uses `libghostty` (Ghostty's core terminal engine) as a Git submodule, wraps it in a custom Swift/AppKit frontend, and adds ~36K lines of Swift on top. Their Ghostty fork has only ~4 custom commits — minor macOS rendering fixes (display link restart, resize frame gravity). The entire sidebar/workspace/notification/browser/socket system is in their Swift layer.

### cmux Source Reference

The cmux macOS source is our feature reference for every phase. Clone: `https://github.com/manaflow-ai/cmux` (cached at `/tmp/pi-github-repos/manaflow-ai/cmux/`).

**Approach:** Every task item in every phase below includes a `cmux:` annotation pointing to the specific file, line range, and function in the cmux source that implements the equivalent feature. While our Zig/GTK implementation will differ significantly from cmux's Swift/AppKit code, these references document the intended behavior, data structures, edge cases, and UX decisions we should match. Always read the referenced cmux code before implementing a task — it's the spec.

**Key files by feature area:**

| Feature Area | cmux File(s) | Lines | Notes |
|---|---|---|---|
| **Sidebar UI** | `Sources/ContentView.swift` | ~8,800 | Sidebar layout, rows, context menu (~L6040–6850), double-click rename (~L6080), drag reorder, selection state, metadata display, shortcut hints |
| **Sidebar selection** | `Sources/SidebarSelectionState.swift` | 10 | Simple selection state object |
| **Workspace model** | `Sources/Workspace.swift` | ~4,100 | Workspace data: title, pwd, git branch, ports, notifications, progress, custom color, pinned state, metadata blocks |
| **Tab/workspace management** | `Sources/TabManager.swift` | ~3,500 | CRUD, reorder, close-with-confirmation, move between windows, selection logic |
| **Workspace content** | `Sources/WorkspaceContentView.swift` | ~420 | Workspace → split pane content view |
| **Notifications** | `Sources/TerminalNotificationStore.swift` | ~510 | Per-workspace notification list, unread count, mark read/unread |
| **Notification panel** | `Sources/NotificationsPage.swift` | ~250 | Notifications sidebar panel UI |
| **Port scanning** | `Sources/PortScanner.swift` | ~260 | `lsof -iTCP -sTCP:LISTEN` based scanner, per-workspace port list |
| **Browser panel** | `Sources/Panels/BrowserPanel.swift` | ~3,250 | Browser pane model, WebKit integration |
| **Browser UI** | `Sources/Panels/BrowserPanelView.swift` | ~3,700 | Address bar, navigation, split integration |
| **Browser WebView** | `Sources/Panels/CmuxWebView.swift` | — | Custom WebView with key handling |
| **Panel system** | `Sources/Panels/Panel.swift`, `PanelContentView.swift`, `TerminalPanel.swift` | — | Abstraction over terminal vs browser panes |
| **Session persistence** | `Sources/SessionPersistence.swift` | ~470 | Save/restore layout, workspaces, browser URLs |
| **Socket/CLI** | `CLI/cmux.swift` | ~5,400 | CLI subcommands: `notify`, `list-workspaces`, `send`, `browser`, etc. |
| **Socket settings** | `Sources/SocketControlSettings.swift` | ~385 | Socket path, permissions, protocol |
| **Keyboard shortcuts** | `Sources/KeyboardShortcutSettings.swift` | — | Customizable keybindings |
| **App delegate** | `Sources/AppDelegate.swift` | — | Window management, socket server startup, global actions |
| **Terminal view** | `Sources/GhosttyTerminalView.swift`, `Sources/TerminalView.swift` | — | libghostty surface wrapper |

**Context menu items in cmux sidebar** (from `ContentView.swift` ~L6649–6800):
- Pin/Unpin Workspace
- Rename Workspace…
- Remove Custom Workspace Name
- Tab Color (submenu with palette)
- Move Up / Move Down / Move to Top
- Move Workspace to Window (submenu)
- Close Workspace / Close Other / Close Below / Close Above
- Mark as Read / Mark as Unread

### Our approach: fork the GTK frontend

We can't take the same library approach because:

1. **libghostty's GTK embedding is the frontend itself** — on Linux, you don't embed libghostty into a separate GTK app; the Ghostty GTK app *is* the frontend. There's no stable "embed a terminal surface in your own GTK window" API.
2. **The GTK frontend is already excellent** — 18K lines of proven Zig with Wayland/X11 support, splits, search, input handling, OpenGL rendering, Flatpak/snap packaging. Reimplementing this in a wrapper would be worse in every way.

So we fork the whole repo, modify `src/apprt/gtk/` to add Cove features, and periodically rebase on upstream Ghostty.

---

## Git & GitHub Strategy

### Repository setup

```
github.com/anurag-arjun/cove  ← our repo (public)
  ├── upstream remote → ghostty-org/ghostty (read-only, for rebasing)
  └── origin remote   → anurag-arjun/cove
```

**Setup completed.** Current state:
```bash
# Remotes
origin   → git@github.com:anurag-arjun/cove.git
upstream → https://github.com/ghostty-org/ghostty.git

# Branches
cove/main → origin/cove/main  (our work)
main      → upstream/main      (tracks Ghostty exactly)
```

### Branch model

| Branch | Purpose |
|--------|---------|
| `cove/main` | Our primary branch. All Cove features land here. |
| `cove/phase-N-*` | Feature branches per phase (e.g., `cove/phase-1-sidebar`). Merge into `cove/main` when stable. |
| `main` | Tracks upstream `ghostty-org/ghostty:main` exactly. Never commit Cove code here. |

### Upstream sync workflow

Ghostty moves fast. We need to rebase regularly to pick up bug fixes and avoid divergence rot.

```bash
# Sync upstream (do this weekly)
git fetch upstream main
git checkout main
git reset --hard upstream/main

# Rebase our work on top
git checkout cove/main
git rebase main

# If conflicts, resolve them. Our changes are localized to:
#   - src/apprt/gtk/class/  (new files + modified window.zig, application.zig, tab.zig)
#   - src/apprt/gtk/ui/1.5/ (modified window.blp, new .blp files)
#   - src/build/SharedDeps.zig (if we add new deps like WebKitGTK)
#   - build.sh, docs/  (our files, no conflicts)

git push origin cove/main --force-with-lease
```

### Commit conventions

```
cove: short description

Longer explanation if needed.

Phase: 1 (sidebar)
```

Prefix all Cove commits with `cove:` so they're easy to identify during rebases and `git log --oneline --grep="cove:"`.

### What NOT to do

- Don't create PRs against `ghostty-org/ghostty` (per AGENTS.md, and our changes aren't upstreamable)
- Don't merge upstream into `cove/main` (rebase only — keeps history clean for future rebases)
- Don't modify Ghostty core files (`src/terminal/`, `src/renderer/`, `src/font/`, `src/input/`) unless absolutely necessary — these are the hardest to rebase

---

## Phased Build Plan

### Phase 0: Repository & Build Foundation (Day 1) ✅ COMPLETE

**Goal:** Clean repo setup, reproducible build, proper attribution.

- [x] Create GitHub repo `cove` → `github.com/anurag-arjun/cove` (public)
- [x] Set up remotes (`origin` → anurag-arjun/cove, `upstream` → ghostty-org/ghostty)
- [x] Create `cove/main` branch
- [x] Write `README.md` with project description, credits, and build instructions
- [x] Write `THIRD_PARTY_LICENSES.md` with Ghostty and cmux MIT licenses
- [x] Commit `build.sh` and `docs/` (build workarounds, spike docs, this plan)
- [x] Add `.gitignore` entries for `crt-patched/`
- [x] Rename binary output from `ghostty` to `cove` in `GhosttyExe.zig`
- [x] Update app ID from `com.mitchellh.ghostty` to `dev.cove.terminal` (App.zig, gresource.zig, application.zig, surface.zig, window.zig, inspector-window.blp)
- [x] Update About dialog, notification titles, debug warnings to "Cove"
- [x] Verify `./build.sh run` launches the terminal
- [x] ~~Tag: `v0.0.1-scaffold`~~ — **Cannot use vX.Y.Z tags** (Ghostty's GitVersion.zig panics on non-matching semver tags)

**Commit:** `6816b450a`
**Files created:** `README.md`, `THIRD_PARTY_LICENSES.md`, `build.sh`, `docs/`
**Files modified:** `GhosttyExe.zig`, `App.zig`, `gresource.zig`, `application.zig`, `surface.zig`, `window.zig`, `new_window.zig`, `x11.zig`, `inspector-window.blp`, `debug-warning.blp` (×2), `window.blp`

**Lesson learned:** Internal GObject class names (GhosttyApplication, GhosttyWindow, etc.) were intentionally NOT renamed — changing them touches dozens of files/templates and makes rebasing against upstream nearly impossible.

#### Phase 0 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 0.1 | Binary name | `ls zig-out/bin/` | Binary is named `cove`, not `ghostty` | |
| 0.2 | App launches | `./build.sh run` | Window opens with a terminal, no crash | |
| 0.3 | Window title | Look at window title bar / `xdotool getactivewindow getwindowname` | Title contains "Cove" or the shell prompt — NOT "Ghostty" | |
| 0.4 | About dialog | Hamburger menu (☰) → "About Cove" | Dialog shows: name="Cove", developer="Cove Contributors", website URL points to `anurag-arjun/cove` | |
| 0.5 | About dialog credits | In About dialog, check credits/acknowledgments text | Mentions Ghostty and cmux with links | |
| 0.6 | App ID (D-Bus) | While Cove is running: `busctl --user list \| grep cove` | Shows `dev.cove.terminal` — NOT `com.mitchellh.ghostty` | |
| 0.7 | Desktop file icon | Check system tray / app switcher / `Alt+Tab` | App appears as "Cove" (icon may still be Ghostty's — that's OK for now) | |
| 0.8 | Terminal works | Type `echo hello` in the terminal | Output `hello` is displayed, cursor blinks, input works normally | |
| 0.9 | Shell integration | Type `pwd`, `ls`, use tab completion | All basic shell features work identically to Ghostty | |
| 0.10 | Splits work | `Ctrl+Shift+Enter` (or configured split keybind) | Split pane opens, both panes are functional | |
| 0.11 | Config compatibility | Ensure `~/.config/ghostty/config` exists with some setting (e.g., `font-size = 14`) | Cove respects the Ghostty config file — font size matches | |
| 0.12 | Inspector title | Open inspector (if enabled in debug build) | Inspector window title says "Cove" not "Ghostty" | |
| 0.13 | Debug warning text | If debug build shows a warning banner | Warning text references "Cove" not "Ghostty" | |
| 0.14 | README exists | `cat README.md` | Contains project description, Ghostty credits, cmux credits, build instructions | |
| 0.15 | License file | `cat THIRD_PARTY_LICENSES.md` | Contains verbatim MIT licenses for both Ghostty and cmux | |

**Cleanup:** Close Cove with `Ctrl+D` or `exit` in each pane, or `Ctrl+Shift+Q`.

---

### Phase 1: Vertical Sidebar (Week 1–2)

**Goal:** Replace Ghostty's horizontal `AdwTabBar` with a vertical sidebar showing workspace list. This is the biggest single change — it touches the window's core layout.

**cmux reference:** `Sources/ContentView.swift` (sidebar layout ~L1200–1470, sidebar rows ~L6200–6850, context menu ~L6649–6800, double-click rename ~L6080, promptRename ~L7337), `Sources/SidebarSelectionState.swift`, `Sources/TabManager.swift` (workspace CRUD, reorder, close-with-confirmation).

#### 1a–c. Sidebar implementation ✅ COMPLETE

**Actual approach differed from plan:** Instead of creating separate `sidebar.zig`/`sidebar_row.zig` GObject widgets and replacing `AdwTabView` with `GtkStack`, we took a simpler approach:

1. **Kept `AdwTabView` internally** — it handles page ordering, close confirmation, and signals. Much less code than reimplementing with `GtkStack`.
   - cmux: Also keeps its internal tab model (`TabManager.tabs` array in `TabManager.swift` ~L1–3473) separate from the sidebar view. Sidebar is purely a presentation layer over the tab model.
2. **Built sidebar directly in `window.blp`** — a `GtkBox` with `GtkListBox` inside a `GtkPaned`, no separate GObject widget needed.
   - cmux: Sidebar is `SidebarTabList` in `ContentView.swift` ~L5390–5490 (a `VStack` with `ScrollView` → `LazyVStack` → `ForEach` over `tabManager.tabs`); each row is `TabItemView` ~L6191–6850.
3. **Sidebar rows are plain `GtkLabel`s** created programmatically in `window.zig` with title bound via `gobject.Object.bindProperty`. Page reference stored via `gobject.Object.setData("cove-tab-page", page)`.
   - cmux: Each row (`TabItemView` ~L6191) is a rich `VStack` with: unread badge circle (~L6335), pin icon, title text (`.semibold`), close button on hover (~L6360–6370), workspace shortcut hints (⌘1-9 shown when Cmd held), notification subtitle, git branch/directory metadata rows, port pills, log entry, progress bar. **Our rows are minimal (title only) — close button, metadata, badges are deferred to Phase 1d/2/3.**
4. **Did NOT rename Tab → Workspace in code** — kept `Tab` struct name to minimize diff. Only user-facing strings say "Workspace".
   - cmux: Also uses `Tab` internally (`TabManager.tabs: [Tab]`, `Tab` class in implied model) while UI says "Workspace".
5. **Did NOT add metadata fields to tab.zig yet** — deferred to Phase 2/3.
   - cmux: `Workspace.swift` ~L898–972 has `currentDirectory`, `gitBranch`, `listeningPorts`, `progress`, `logEntries`, `statusEntries`, `customColor`, `isPinned`, etc. — all populated from surface snapshots.

**Actual layout:**
```
AdwApplicationWindow
└── GtkPaned (horizontal, position: 220px)
    ├── [start] GtkBox .cove-sidebar
    │   ├── GtkBox (header: "Workspaces" label + "+" button)
    │   └── GtkScrolledWindow → GtkListBox .navigation-sidebar
    └── [end] AdwToolbarView
        ├── [top] AdwHeaderBar (sidebar toggle + menu)
        └── AdwToastOverlay
            └── AdwTabView (kept! tab bar hidden)
```

cmux layout (for comparison, from `ContentView.swift` ~L1470–1800):
```
HSplitView
├── [sidebar] SidebarTabList (VStack → ScrollView → LazyVStack of TabItemView)
│   ├── Traffic light padding (28px)
│   ├── Tab rows (2px spacing, drag reorderable)
│   ├── Empty area (double-click = new workspace, drop target)
│   └── Update pill / dev footer
└── [content] Workspace content (split panes, browser panels)
```

- [x] Remove `AdwTabOverview`, `AdwTabBar` from template and Private struct
  - cmux: N/A — cmux never had horizontal tabs, built sidebar-first. Our removal of Ghostty's tab bar/overview is Cove-specific.
- [x] Add `GtkPaned`, `GtkBox` (sidebar), `GtkListBox` to template and Private struct
  - cmux: Sidebar container is an `HSplitView` with custom drag-resize in `ContentView.swift` ~L1468–1710 (min width 186px, max 1/3 of window). We use `GtkPaned` which provides resize handle natively.
- [x] Sidebar rows created on `page-attached`, removed on `page-detached`
  - cmux: Rows are SwiftUI `ForEach(tabManager.tabs)` — automatically reactive. Our approach with `page-attached`/`page-detached` signals is the Zig/GObject equivalent.
- [x] Bidirectional sync: sidebar selection ↔ AdwTabView selected page
  - cmux: `SidebarSelectionState` in `SidebarSelectionState.swift` (~10 lines — simple enum); selection driven by `tabManager.selectedTabId`; `TabItemView` calls `updateSelection()` on tap ~L6634 which sets `tabManager.selectedTabId`. We use `row-activated` signal → `tab_view.setSelectedPage()` and `notify::selected-page` → `sidebarSyncSelection()`.
- [x] Anti-reentrance guard (`updating_sidebar` flag)
  - cmux: Not needed in SwiftUI — reactive bindings don't cause reentrance. Our GObject signal approach requires the explicit guard.
- [x] `sidebar-visible` property + `win.toggle-sidebar` action + header toggle button
  - cmux: `SidebarState.isVisible` in `ContentView.swift` ~L230–237; toggled via `palette.toggleSidebar` command ~L3985; Cmd+B keybind (see README keyboard shortcuts table). We use a GObject property + GAction + GtkToggleButton.
- [x] `toggleTabOverview()` redirected to `toggleSidebar()`
  - cmux: N/A — cmux doesn't have a tab overview concept. This is Cove-specific for Ghostty API compat.
- [x] Removed dead code: tab overview callbacks, tab bar properties, context menu page
  - cmux: N/A — Cove-specific cleanup of Ghostty's horizontal tab UI code.
- [x] `.cove-sidebar` CSS in `style.css`
  - cmux: Sidebar styling in `ContentView.swift` uses SwiftUI modifiers: `backgroundColor` computed property ~L6803–6820 (accent color for active, clear for inactive), row padding via `.padding()`, corner radius via `RoundedRectangle`. Our CSS uses GNOME `navigation-sidebar` style class with custom padding/margins/radius overrides.

**Commit:** `6363939c4`
**Files modified:** `window.zig` (~85 lines net reduction), `window.blp` (rewritten), `style.css`
**No new files created** (simpler than planned)

**cmux features NOT yet implemented (deferred to later phases):**
- Close button (X) on sidebar row hover → **Phase 1d** ✅ (listed below)
- Drag-to-reorder sidebar rows → **Phase 1d** ✅ (listed below)
- Multi-select (Ctrl+click, Shift+click) → **Phase 3** (useful for bulk close/move when workspace count grows)
- Workspace shortcut hints (show ⌘1-9 when modifier held) → **Phase 3** (sidebar metadata UX)
- Pin/Unpin Workspace → **Phase 3** (workspace metadata — pinned workspaces stay at top)
- Tab Color (custom color per workspace) → **Phase 3** (workspace metadata)
- Move workspace to another window → **Phase 4** (requires socket API for multi-window coordination)
- Status entries (arbitrary key-value metadata from agents/CLI) → **Phase 4** (populated via socket API `cove +status`)
- Log entries (per-workspace log with level) → **Phase 4** (populated via socket API `cove +log`)
- Progress bar (per-workspace) → **Phase 4** (populated via socket API `cove +progress`)
- Pull request status (linked PRs with badges) → **Phase 4** (populated via socket API or git integration)

#### 1d. Sidebar polish ✅ COMPLETE

- [x] Close button (X) on sidebar row, visible on hover
  - cmux: `TabItemView` close button in `ContentView.swift` ~L6360–6370
  - Implementation: `GtkBox` (label + close button); `GtkEventControllerMotion` enter/leave shows/hides button; close button triggers `tab_view.closePage(page)`.
- [x] Middle-click sidebar row to close workspace
  - cmux: `MiddleClickCapture` in `ContentView.swift` ~L8113–8148
  - Implementation: `GtkGestureClick` with button=2.
- [x] Right-click context menu on sidebar rows (Rename, Move Up/Down, Close)
  - cmux: `.contextMenu { ... }` block in `ContentView.swift` ~L6649–6800
  - Implementation: Plain `GtkPopover` with `GtkButton`s + direct callbacks (not `GtkPopoverMenu`+`gio.Menu` — that approach had action dispatch issues). Menu items: Rename Workspace… | Move Up | Move Down | Close Workspace. Move Up/Down greyed at boundaries.
- [x] Double-click sidebar row to rename workspace
  - cmux: Context-menu-only rename. We chose GNOME convention: double-click row = rename.
  - Implementation: `GtkGestureClick` button=1, `n_press == 2` → `performBindingAction(.prompt_tab_title)`.
- [x] Reorder via context menu Move Up/Down
  - Implementation: `AdwTabView.reorderPage()` + `page-reordered` signal → `sidebarRebuild()` (removes all rows, recreates from tab_view).
- [x] Keyboard navigation: Up/Down in sidebar, Enter to select — built into `GtkListBox` with `selection-mode: browse`
- [x] Drag-to-resize via GtkPaned handle — built into `GtkPaned`
- [x] Fixed sidebar not visible by default (bidirectional binding race — explicitly set `sidebar_visible = true` before `syncAppearance()`)

**Deferred:**
- [ ] Drag-to-reorder sidebar rows — **attempted and removed.** GTK `DragSource` creates visual snapshots that crash with terminal EGL contexts (`General protection exception` in `libgobject-2.0.so.0`). Tried deferred rebuild via `glib.idleAdd()` — still crashes during drag start. Revisit if workaround found.
- [ ] Sidebar width persisted in config — needs `~/.config/cove/config` setup (Phase 3+)
  - cmux: `SidebarState.persistedWidth` in `ContentView.swift` ~L232
- [ ] Sidebar auto-hides when only 1 workspace — cmux does NOT auto-hide; skipped to match behavior

**Commits:** `febc8fd98`, `e0ae72a56`
**Est actual:** ~230 lines net new

#### Phase 1 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

**Prerequisites:** Phase 0 tests should all pass first.

##### 1A. Sidebar Basics

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 1.1 | Sidebar visible on launch | `./build.sh run` | Left side of window shows a vertical sidebar panel with header "Workspaces" and a "+" button. One workspace row is listed (the initial terminal). | |
| 1.2 | Sidebar width | Observe sidebar | Sidebar is ~220px wide. A draggable divider separates it from the terminal area. | |
| 1.3 | Sidebar resize | Drag the divider between sidebar and terminal left/right | Sidebar resizes smoothly. Terminal area adjusts. Divider snaps to a reasonable min width (~100px). | |
| 1.4 | Workspace title | Look at the sidebar row text | Row shows the terminal's title (e.g., shell name like `zsh` or `bash`, or the working directory — matches what Ghostty would show in its tab bar). | |
| 1.5 | Title updates | Run `printf '\033]0;My Custom Title\007'` in the terminal | Sidebar row text updates to "My Custom Title" in real time. | |

##### 1B. Workspace CRUD

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 1.6 | New workspace (+ button) | Click the "+" button in the sidebar header | A second workspace row appears in the sidebar. The new workspace is selected (highlighted). A fresh terminal is shown in the content area. | |
| 1.7 | New workspace (keybind) | Press `Ctrl+Shift+T` (default new-tab keybind) | Same as 1.6 — new workspace row appears, is selected, fresh terminal shown. | |
| 1.8 | Switch workspace (click) | With 2+ workspaces, click on a non-selected sidebar row | Content area switches to that workspace's terminal. Sidebar highlights the clicked row. Previous workspace's terminal is no longer visible. | |
| 1.9 | Switch workspace (keybind) | Press `Ctrl+Tab` or `Ctrl+Page_Down` (next-tab keybind) | Workspace switches to the next one. Sidebar selection updates to match. | |
| 1.10 | Switch workspace (numbered) | With 3+ workspaces, press `Alt+1`, `Alt+2`, `Alt+3` (or configured goto_tab keybind) | Jumps to workspace 1, 2, 3 respectively. Sidebar selection updates. | |
| 1.11 | Close workspace (keybind) | With 2+ workspaces, press `Ctrl+Shift+W` (close-tab keybind) in a workspace | That workspace row disappears from the sidebar. Adjacent workspace is selected. If a process was running, a confirmation dialog may appear (Ghostty's built-in behavior). | |
| 1.12 | Close last workspace | With only 1 workspace, press `Ctrl+Shift+W` | Window closes (same as Ghostty behavior when closing the last tab). | |
| 1.13 | Many workspaces | Create 10+ workspaces using the "+" button or `Ctrl+Shift+T` | All rows are visible in the sidebar. Sidebar scrolls if needed (scroll down to see rows that don't fit). Scrollbar appears. | |
| 1.14 | Workspace ordering | Create workspaces A, B, C (set titles with `printf '\033]0;A\007'` etc.) | Sidebar shows them in creation order: A, B, C from top to bottom. | |

##### 1C. Sidebar Toggle

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 1.15 | Toggle button | Click the sidebar toggle button in the header bar (panel/sidebar icon, left side of header) | Sidebar hides. Terminal takes full width. Toggle button appears unpressed/inactive. | |
| 1.16 | Toggle button (show) | Click the toggle button again | Sidebar reappears at its previous width. Toggle button appears pressed/active. | |
| 1.17 | Toggle via menu | Hamburger menu (☰) → "Toggle Sidebar" | Sidebar visibility toggles (same as clicking the toggle button). | |
| 1.18 | Sidebar hidden + workspaces | Hide sidebar, create new workspace with `Ctrl+Shift+T`, switch with `Ctrl+Tab` | Workspace creation and switching still work correctly even with sidebar hidden. | |

##### 1D. Sidebar Polish (Close Button, Middle-Click, Context Menu)

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 1.19 | Close button on hover | With 2+ workspaces, hover mouse over a sidebar row | An "X" close button fades in on the right side of the row. | |
| 1.20 | Close button hidden | Move mouse away from the sidebar row | The "X" button disappears (hidden). | |
| 1.21 | Close button click | Hover over a row, click the "X" button | That workspace is closed. Row disappears. Another workspace is selected. Terminal content switches. | |
| 1.22 | Close button — last workspace | With 1 workspace, hover over the row | Close button should still appear. Clicking it closes the window (same as 1.12). | |
| 1.23 | Middle-click close | With 2+ workspaces, middle-click (scroll wheel click) on a sidebar row | That workspace is closed. Same behavior as clicking the "X" button. | |
| 1.24 | Right-click context menu | Right-click on a sidebar row | A context menu appears with at least: "Rename Workspace…" and "Close Workspace". Menu is positioned at the click location. | |
| 1.25 | Context menu — rename | Right-click → "Rename Workspace…" | A rename dialog appears (Ghostty's title prompt). Type a new name → sidebar row updates to show the new name. | |
| 1.26 | Context menu — close | Right-click → "Close Workspace" | Workspace is closed (same as 1.21). | |
| 1.27 | Context menu — correct target | With 3 workspaces (A, B, C), select A, then right-click on C → "Close Workspace" | Workspace C is closed (not A). The right-click should select C first, then close it. | |
| 1.28 | Context menu dismissal | Right-click to open menu, then click elsewhere (or press Escape) | Menu closes without performing any action. No crash, no orphaned popover. | |
| 1.29 | Multiple context menus | Right-click row A (menu opens), then right-click row B without closing first | First menu closes, second menu opens on row B. No crash or visual glitch. | |

##### 1E. Interaction with Ghostty Features

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 1.30 | Splits within workspace | In a workspace, create splits (`Ctrl+Shift+Enter` or configured keybind) | Splits work within the workspace. Sidebar row still shows one entry for this workspace (splits are internal, not separate workspaces). | |
| 1.31 | Splits + workspace switch | Create splits in workspace A, switch to workspace B, switch back to A | Workspace A still has its splits intact. Split layout is preserved. | |
| 1.32 | Search within workspace | Press `Ctrl+Shift+F` (find keybind) | Search overlay appears in the terminal area, not in the sidebar. Search works normally. | |
| 1.33 | Fullscreen | Press `F11` or configured fullscreen keybind | Window goes fullscreen. Sidebar is still visible (or hidden if it was hidden). Toggle still works in fullscreen. | |
| 1.34 | Multiple windows | Open a second window (`Ctrl+Shift+N`) | Second window has its own sidebar with its own workspace list. Each window is independent. | |
| 1.35 | Window close | Close one window (click X or `Ctrl+Shift+Q`) with the other still open | Only that window closes. The other remains. App doesn't quit until all windows are closed. | |
| 1.36 | Config keybinds | Set a custom keybind in `~/.config/ghostty/config` (e.g., `keybind = ctrl+shift+n=new_tab`) | Custom keybind creates a new workspace as expected. Sidebar updates. | |

##### 1F. Edge Cases & Stress

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 1.37 | Rapid workspace creation | Hold `Ctrl+Shift+T` to create workspaces rapidly (20+) | No crash. All workspaces appear in sidebar. Sidebar scrolls. Performance stays acceptable. | |
| 1.38 | Rapid workspace switching | With 5+ workspaces, rapidly press `Ctrl+Tab` many times | Switching is smooth, no flicker, no crash. Final state: correct workspace is selected and displayed. | |
| 1.39 | Long workspace title | Set a very long title: `printf '\033]0;%s\007' "$(python3 -c "print('A'*200)")"` | Title is shown in sidebar row, truncated with ellipsis. Sidebar doesn't grow horizontally or break layout. | |
| 1.40 | Empty title | `printf '\033]0;\007'` (set empty title) | Sidebar row shows some fallback text or empty row — no crash, no zero-height row. | |
| 1.41 | Unicode title | `printf '\033]0;🚀 Prod Server 日本語\007'` | Unicode characters and emoji render correctly in the sidebar row. | |
| 1.42 | Close during running process | Start a long-running process (`sleep 999`), then close that workspace | Ghostty's close confirmation dialog appears ("Process is still running…"). Confirm → workspace closes. Cancel → workspace stays. | |

**Cleanup:** Close Cove with `Ctrl+Shift+Q` or close all workspaces individually.

---

### Phase 2: Notification System (Week 2–3)

**Goal:** Blue notification rings on sidebar rows, desktop notifications, jump-to-unread.

**cmux reference:** `Sources/TerminalNotificationStore.swift` (~510 lines — per-workspace notification list, unread count, mark read/unread), `Sources/NotificationsPage.swift` (~250 lines — notification panel UI), `Sources/ContentView.swift` (blue ring rendering, unread badge in sidebar rows, mark-read-on-select, jump-to-unread ~Cmd+Shift+U), `Sources/Workspace.swift` (notification fields on workspace model).

- [ ] Create `src/apprt/gtk/class/notification_store.zig`
  - Per-workspace notification list (timestamp, title, body, read/unread)
  - Methods: `add()`, `markRead()`, `unreadCount()`, `clearAll()`
  - GObject signals: `notification-added`, `unread-count-changed`
  - cmux: `TerminalNotificationStore` in `TerminalNotificationStore.swift` ~L73–260; `TerminalNotification` struct ~L61–70 (id, tabId, surfaceId, title, subtitle, body, createdAt, isRead); `NotificationIndexes` ~L80–86 (unreadCount, unreadCountByTabId, latestUnreadByTabId); `addNotification()` ~L177–225, `markRead()` ~L227–265
- [ ] Hook into libghostty actions in `application.zig`:
  - `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` (OSC 9/99/777) → store + desktop notify
  - `GHOSTTY_ACTION_RING_BELL` → increment badge
  - `GHOSTTY_ACTION_COMMAND_FINISHED` → store (with exit code + duration)
  - cmux: Notification triggers are wired through `AppDelegate` and the terminal view's callback system; `addNotification()` suppresses if workspace is focused and app is active (`AppFocusState.isAppFocused()` ~L50–59); auto-reorders workspace to top on notification (`WorkspaceAutoReorderSettings` ~L199)
- [ ] Update `sidebar_row.zig`: blue badge circle showing unread count
  - cmux: Unread badge rendered in sidebar row via `unreadCount(forTabId:)` ~L163 and `hasUnreadNotification(forTabId:surfaceId:)` ~L167; blue ring styling in `ContentView.swift` sidebar row layout
- [ ] Desktop notifications via `g_application_send_notification()` (GLib native, no libnotify needed)
  - cmux: `scheduleUserNotification()` in `TerminalNotificationStore.swift` uses `UNUserNotificationCenter`; also handles dock badge via `dockBadgeLabel()` ~L149–160 and `refreshDockBadge()`
- [ ] "Jump to latest unread" action: `Ctrl+Shift+U`
  - cmux: `palette.jumpToLatestUnread` command; Cmd+Shift+U keybind; finds latest unread via `latestNotification(forTabId:)` ~L173
- [ ] Mark-as-read when workspace is selected
  - cmux: `markRead(forTabId:)` ~L236–249 called when workspace becomes selected; also `markRead(forTabId:surfaceId:)` ~L251–265 for surface-level granularity
- [ ] CSS: blue ring animation on sidebar row (`.sidebar-row.unread { ... }`)
  - cmux: Accent color from `cmuxAccentNSColor()` in `ContentView.swift` ~L42–67; `sidebarSelectedWorkspaceBackgroundNSColor()` ~L76–78

**Files created:** `notification_store.zig`
**Files modified:** `application.zig`, `sidebar_row.zig`, runtime CSS
**Est:** ~400 lines | Tag: `v0.2.0-notifications`

#### Phase 2 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

**Prerequisites:** Phase 1 tests should all pass first. Create at least 2 workspaces for most tests.

##### 2A. Notification Badges

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 2.1 | OSC 9 notification (basic) | In workspace B, switch to workspace A, then in B's terminal (via another terminal or script) send: `printf '\033]9;Build complete\033\\'` | Workspace B's sidebar row shows a blue unread badge (circle or dot) with count "1". | |
| 2.2 | OSC 99 notification (extended) | Switch to workspace A. In workspace B: `printf '\033]99;d=0;Build failed\033\\'` | Badge appears on B's row. | |
| 2.3 | OSC 777 notification (rxvt-style) | Switch to workspace A. In workspace B: `printf '\033]777;notify;Title;Body text\033\\'` | Badge appears on B's row. | |
| 2.4 | Bell notification | Switch to workspace A. In workspace B: `printf '\a'` (BEL character) | Badge appears or increments on B's row. | |
| 2.5 | Badge count increments | Send 3 notifications to unfocused workspace B (any of the above methods) | Badge shows "3" (or 3 dots, depending on design). Count is accurate. | |
| 2.6 | No badge on focused workspace | While viewing workspace A, send a notification in workspace A's terminal: `printf '\033]9;Hello\033\\'` | No badge appears on A's row (it's the active workspace — user is already looking at it). | |
| 2.7 | Badge styling | Observe the badge on an unfocused workspace row | Badge is visually distinct: blue/accent colored circle or ring. Doesn't overlap or obscure the workspace title. | |

##### 2B. Desktop Notifications

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 2.8 | Desktop notification appears | Minimize or background Cove. In a workspace: `printf '\033]9;Important alert\033\\'` | A desktop notification appears (system notification area / notification center). Title mentions "Cove" or the workspace name. Body shows "Important alert". | |
| 2.9 | Desktop notification — app focused | With Cove focused and workspace B active, send notification from workspace B | Desktop notification may or may not appear (depends on design — suppressing when focused is OK). Document actual behavior. | |
| 2.10 | Click desktop notification | Click on a desktop notification | Cove window comes to front. The workspace that sent the notification is selected. | |

##### 2C. Mark-as-Read

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 2.11 | Mark read on select | Workspace B has an unread badge. Click on workspace B in the sidebar. | Badge disappears (or changes to a "read" state). Workspace B is now "read". | |
| 2.12 | Mark read persistence | After clearing B's badge (2.11), switch to A and back to B | Badge does not reappear. B remains "read" until a new notification arrives. | |
| 2.13 | New notification after read | Mark B as read (select it). Switch to A. Send new notification to B. | Badge reappears on B with count "1". | |

##### 2D. Jump to Unread

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 2.14 | Jump to unread | Create 5 workspaces. Send notifications to workspaces 2 and 4. Currently on workspace 1. Press `Ctrl+Shift+U`. | Jumps to the workspace with the most recent unread notification (workspace 4 or 2, whichever got the latest). Sidebar selection updates. | |
| 2.15 | Jump to unread — none | All workspaces are read (no badges). Press `Ctrl+Shift+U`. | Nothing happens (no crash, no switch). Optionally shows a toast "No unread notifications". | |
| 2.16 | Jump to unread — cycles | With unread on workspace 2 and 4: press `Ctrl+Shift+U` to jump to latest (4). Press again. | Jumps to next unread (workspace 2), or stays on 4 if only one jump target. Behavior should be predictable. | |

##### 2E. Edge Cases

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 2.17 | Many notifications | Send 50+ notifications to an unfocused workspace (loop: `for i in $(seq 50); do printf '\033]9;Msg %d\033\\' $i; done`) | Badge shows accurate count (or "50+" if capped). No crash, no memory leak, sidebar doesn't lag. | |
| 2.18 | Notification after close | Send a notification, then close the workspace that received it | No crash. Badge disappears with the row. No orphaned notification data. | |
| 2.19 | Command finished notification | In an unfocused workspace, run `sleep 1` (a command that finishes quickly) | If command-finished notifications are implemented: badge appears with command exit info. If not yet implemented: no crash. | |
| 2.20 | Rapid notifications | Rapidly send notifications (tight loop): `for i in $(seq 20); do printf '\a'; done` | Badge count is correct (20). No UI freeze, no duplicate counts. | |

**Cleanup:** Close Cove.

---

### Phase 3: Workspace Metadata (Week 3–4)

**Goal:** Show git branch, working directory, listening ports in sidebar rows.

**cmux reference:** `Sources/Workspace.swift` (git branch detection, pwd tracking, port list, `sidebarStatusEntriesInDisplayOrder()`, `sidebarMetadataBlocksInDisplayOrder()`), `Sources/PortScanner.swift` (~260 lines — `lsof -iTCP -sTCP:LISTEN`, per-workspace port list with periodic scan), `Sources/ContentView.swift` (metadata display in sidebar rows ~L6400–6470, `SidebarMetadataRows`, `SidebarPathFormatter` ~L6130).

- [ ] Hook `GHOSTTY_ACTION_PWD` in `application.zig` → update workspace's `pwd` field
  - cmux: `Workspace.currentDirectory` published property in `Workspace.swift` ~L898; updated via surface snapshot in `applySnapshot()` ~L485–492; `SidebarPathFormatter.shortenedPath()` in `ContentView.swift` ~L6130–6145 shortens `~/…` for display
- [ ] Hook `GHOSTTY_ACTION_SET_TITLE` → update workspace's display title
  - cmux: `Workspace.processTitle` / `Workspace.customTitle` in `Workspace.swift` ~L898–967; `TabManager.setCustomTitle()` / `clearCustomTitle()` in `TabManager.swift`; `Workspace.title` computed property resolves custom vs process title
- [ ] Git branch detection: read `<pwd>/.git/HEAD` (or `<pwd>/.git` ref for worktrees), parse branch name
  - Trigger on pwd change, not on a timer (efficient)
  - cmux: `Workspace.gitBranch` as `SidebarGitBranchState` (branch + isDirty) in `Workspace.swift` ~L967; updated from surface snapshot ~L537; snapshot includes `gitBranch` field from shell integration
- [ ] Port scanner: read `/proc/net/tcp` + `/proc/net/tcp6`, filter by workspace's child PID tree
  - `g_timeout_add_seconds(5)` periodic scan
  - Show first 3 ports as pills in sidebar row
  - cmux: `PortScanner` in `PortScanner.swift` — batched scanner using `ps -t <ttys>` + `lsof -p <pids>` (not per-shell); kick/coalesce/burst pattern with 200ms coalesce, 6-scan burst at [0.5, 1.5, 3, 5, 7.5, 10]s offsets; `Workspace.listeningPorts` in `Workspace.swift` ~L972; `Workspace.surfaceListeningPorts` per-panel in ~L305
  - Note: On Linux we can read `/proc/net/tcp` directly instead of `lsof` — more efficient
- [ ] Update `sidebar_row.zig` layout:
  ```
  [unread badge] Workspace Title          [close]
                 🌿 feature/sidebar  📁 ~/code/proj
                 🔌 3000, 5173
  ```
  - cmux: Sidebar row layout in `ContentView.swift` ~L6300–6470; `SidebarMetadataRows` view for metadata entries; `sidebarStatusEntriesInDisplayOrder()` and `sidebarMetadataBlocksInDisplayOrder()` in `Workspace.swift` ~L280–360
- [ ] Expandable/collapsible metadata rows (click to toggle detail level)
  - cmux: `sidebarShowMetadata` toggle in `ContentView.swift` ~L6415; metadata conditionally shown with `.transition(.opacity.combined(with: .move(edge: .top)))` animation
- [ ] Pin/Unpin Workspace (pinned workspaces stay at top of sidebar, survive reorder)
  - cmux: `Workspace.isPinned` in `Workspace.swift` ~L972; `TabManager.setPinned()` in `TabManager.swift`; pin icon in sidebar row `Image(systemName: "pin.fill")` in `ContentView.swift` ~L6345; available in context menu ~L6654
- [ ] Tab Color (custom color per workspace, shown as left rail or fill on sidebar row)
  - cmux: `Workspace.customColor` (hex string) in `Workspace.swift`; `WorkspaceTabColorSettings.palette()` for predefined colors; color picker via `promptCustomColor()` in `ContentView.swift`; context menu "Tab Color" submenu ~L6693–6722; two display styles: `leftRail` or `solidFill` via `SidebarActiveTabIndicatorSettings` ~L6228
- [ ] Multi-select sidebar rows (Ctrl+click, Shift+click for bulk operations)
  - cmux: `selectedTabIds: Set<UUID>` in `ContentView.swift` ~L1214; Shift+click selects range, Cmd+click toggles individual; bulk close/move/pin/mark-read operations in context menu use `contextTargetIds()` ~L6649
- [ ] Workspace shortcut hints (show Ctrl+1-9 when modifier held)
  - cmux: `SidebarCommandKeyMonitor` in `ContentView.swift` ~L5658–5710 (monitors Cmd key via `NSEvent.addLocalMonitorForEvents`); `workspaceShortcutLabel` shown as pill on sidebar row ~L6380–6395 when `showsCommandShortcutHints` is true; `WorkspaceShortcutMapper.commandDigitForWorkspace()` maps index to digit

**Files modified:** `application.zig`, `sidebar_row.zig`, `tab.zig`
**Est:** ~900 lines | Tag: `v0.3.0-metadata`

#### Phase 3 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

**Prerequisites:** Phase 2 tests should all pass. For git tests, have a git repository available (e.g., the Cove repo itself).

##### 3A. Working Directory Display

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.1 | PWD shown in sidebar | `cd ~/code/some-project` in a workspace | Sidebar row shows the directory below the title, e.g., `📁 ~/code/some-project`. Path uses `~` shorthand for home. | |
| 3.2 | PWD updates on cd | `cd /tmp` then `cd ~/Documents` | Sidebar row path updates each time to reflect the current directory. | |
| 3.3 | PWD — home directory | `cd ~` | Shows `📁 ~` or `📁 ~/` — not the full `/home/username` path. | |
| 3.4 | PWD — deep path | `cd ~/code/very/deeply/nested/project/directory` | Path is shown, possibly truncated with ellipsis if too long for sidebar width. No layout breakage. | |
| 3.5 | PWD — different workspaces | Workspace A: `cd /tmp`. Workspace B: `cd ~/code`. | Each row shows its own PWD independently. | |

##### 3B. Git Branch Display

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.6 | Git branch shown | `cd` into a git repository (e.g., the Cove project dir) | Sidebar row shows the branch name, e.g., `🌿 cove/main` or `🌿 main`. Displayed near the PWD. | |
| 3.7 | Git branch updates | `git checkout -b test-branch` then `git checkout main` | Branch name in sidebar updates each time. | |
| 3.8 | No git — no branch | `cd /tmp` (not a git repo) | No git branch is displayed. No error icon, just absent. | |
| 3.9 | Git worktree | If using a git worktree, `cd` into it | Correct branch is shown (reads `.git` file → resolves worktree HEAD). | |
| 3.10 | Detached HEAD | `git checkout HEAD~1` (detached HEAD state) | Shows abbreviated commit hash or "detached" instead of a branch name. | |

##### 3C. Port Detection

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.11 | Listening port shown | In a workspace: `python3 -m http.server 8080` | After a few seconds (≤5s scan interval), sidebar row shows `🔌 8080` or similar port indicator. | |
| 3.12 | Multiple ports | Start servers on 3000, 5173, and 8080 in the same workspace | Sidebar shows up to 3 port pills: `🔌 3000, 5173, 8080`. | |
| 3.13 | Port removed | Stop the server (`Ctrl+C` on `python3 -m http.server`) | After the next scan cycle (≤5s), the port indicator disappears from the sidebar row. | |
| 3.14 | Port — correct workspace | Workspace A runs a server on 3000. Workspace B has no server. | Port `3000` only appears on workspace A's row, not B's. | |
| 3.15 | Port — many ports | Start 10 servers on different ports in one workspace | Only first 3 ports shown as pills (to avoid sidebar overflow). Optionally "+7 more" indicator. | |

##### 3D. Sidebar Row Layout (Combined Metadata)

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.16 | Full metadata row | In a workspace: `cd` to a git repo, start a server, have a notification badge | Row shows: `[badge] Title [X]` on first line, `🌿 branch 📁 path` on second line, `🔌 port` on third line. All elements visible and not overlapping. | |
| 3.17 | Minimal metadata row | In a workspace: `cd /tmp` (no git, no server, no notifications) | Row shows just the title. No empty metadata lines, no blank space where metadata would be. | |
| 3.18 | Title updates with metadata | Change the workspace title with `printf '\033]0;New Title\007'` while metadata is showing | Title updates; metadata lines stay intact. | |
| 3.19 | Metadata toggle | If expandable/collapsible metadata is implemented: click to toggle metadata rows | Metadata rows collapse (only title visible) or expand (title + metadata). Animation is smooth. | |

##### 3E. Pin/Unpin Workspace

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.20 | Pin workspace | Right-click workspace B → "Pin Workspace" (if in context menu) | Workspace B moves to the top of the sidebar. A pin icon (📌) appears on its row. | |
| 3.21 | Pinned stays on top | Pin workspace B. Create a new workspace C. | C appears below B (pinned workspaces stay at top). | |
| 3.22 | Unpin workspace | Right-click pinned workspace → "Unpin Workspace" | Pin icon disappears. Workspace moves back to its natural position in the list. | |

##### 3F. Tab Color

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.23 | Set tab color | Right-click workspace → "Tab Color" → choose a color (e.g., red) | Sidebar row shows a colored indicator (left rail or background tint) in the chosen color. | |
| 3.24 | Different colors | Set different colors on 3 workspaces (red, green, blue) | Each row shows its distinct color. Colors are visually distinct. | |
| 3.25 | Remove tab color | Right-click colored workspace → "Tab Color" → "None" or "Default" | Color indicator is removed. Row returns to default styling. | |

##### 3G. Multi-Select

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.26 | Ctrl+click select | With 5 workspaces: click workspace 1, Ctrl+click workspace 3 and 5 | Workspaces 1, 3, 5 are all highlighted/selected. Terminal shows workspace 5 (last clicked). | |
| 3.27 | Shift+click range | Click workspace 1, Shift+click workspace 4 | Workspaces 1, 2, 3, 4 are all selected. | |
| 3.28 | Multi-select close | Select 3 workspaces (Ctrl+click), right-click → "Close Workspaces" | All 3 selected workspaces are closed. Remaining workspaces adjust. | |

##### 3H. Shortcut Hints

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.29 | Show shortcut hints | Hold `Ctrl` (or configured modifier) | Sidebar rows 1-9 show their keyboard shortcut hints (e.g., "Ctrl+1", "Ctrl+2", etc.) as small pills or labels. | |
| 3.30 | Release hides hints | Release `Ctrl` | Shortcut hints disappear. Rows return to normal. | |

##### 3I. Edge Cases

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 3.31 | Git repo with no commits | `mkdir /tmp/empty-git && cd /tmp/empty-git && git init` | No branch shown (or shows "main"/"master" as default). No crash. | |
| 3.32 | Symlinked PWD | `cd` to a symlinked directory | PWD shows either the symlink path or the real path — either is fine, just no crash. | |
| 3.33 | Permission denied | `cd /root` (if not root) — shell may refuse, but test PWD handling | Sidebar shows whatever directory the shell is actually in. No crash from failed git/port detection. | |
| 3.34 | Metadata during rapid switching | Rapidly switch between 5 workspaces while metadata is updating | No crash, no garbled metadata. Each workspace shows its correct metadata when settled. | |

**Cleanup:** Stop any running servers, close Cove.

---

### Phase 4: Socket API & CLI (Week 4–6)

**Goal:** Unix domain socket for scripting, `cove` CLI subcommands.

**cmux reference:** `CLI/cmux.swift` (~5,400 lines — full CLI: `notify`, `list-workspaces`, `new-workspace`, `close-workspace`, `send`, `send-key`, `browser open/navigate/snapshot`, `read-screen`, `list-panes`, `select-workspace`, `rename-workspace`), `Sources/SocketControlSettings.swift` (~385 lines — socket path, permissions, protocol settings), `Sources/AppDelegate.swift` (socket server startup/shutdown).

#### 4a. Socket server

- [ ] Create `src/apprt/gtk/class/socket_server.zig`
  - Listens on `$XDG_RUNTIME_DIR/cove/socket` (fallback: `/tmp/cove-$UID/socket`)
  - GLib main loop integration via `g_unix_fd_add()` for accept + read
  - Newline-delimited JSON protocol (one JSON object per line, response per line)
  - Authentication: file-permission based (socket is `0600`)
  - cmux: `SocketControlSettings` in `SocketControlSettings.swift` ~L1–385; socket path from `CMUX_SOCKET_PATH` env or `/tmp/cmux.sock`; password auth via `CMUX_SOCKET_PASSWORD` env in `CLI/cmux.swift` ~L426
- [ ] Wire into `application.zig`: start server on activate, stop on shutdown
  - cmux: Socket server started in `AppDelegate` on app launch; `CLI/cmux.swift` ~L620–710 shows client-side connection setup

#### 4b. Protocol (V2 JSON)

Core commands (cmux ref: `CLI/cmux.swift` command handlers starting ~L858):
```
ping                    → {"ok": true}
list-workspaces         → [{id, title, pwd, git_branch, unread_count, ...}]
  cmux: ~L858–877 (returns id, title, pwd, gitBranch, listeningPorts, unreadCount, etc.)
new-workspace           → {id, ref}
  cmux: ~L879–913
close-workspace ID      → {ok}
  cmux: ~L1115–1124
select-workspace ID     → {ok}
  cmux: ~L1125–1134
rename-workspace ID NAME → {ok}
  cmux: ~L1135–1155 (also aliased as "rename-window")
list-panes ID           → [{id, pid, pwd, ...}]
  cmux: ~L915–1114
new-split ID DIR        → {id, ref}
send ID TEXT            → {ok}
  cmux: ~L1193–1208
send-key ID KEY         → {ok}
  cmux: ~L1209–1259
notify ID TITLE BODY    → {ok}
  cmux: ~L1260–1459
read-screen ID          → {lines: [...]}
  cmux: ~L1156–1192
browser CMD [ARGS]      → varies
  cmux: ~L1460–2275 (open, navigate, snapshot, click, fill, evaluate-js, etc.)
```

#### 4c. CLI integration

- [ ] Add `+` subcommands to the `cove` binary (same pattern as `ghostty +new-window`)
  - `cove +list-workspaces`, `cove +new-workspace`, `cove +send`, etc.
  - cmux: `CLI/cmux.swift` `run()` function ~L620–710; `SocketClient` connects to socket path; subcommand dispatch ~L858+; help text generation with `--help` per subcommand ~L3559+
- [ ] Environment variables set in spawned shells: `COVE_SOCKET_PATH`, `COVE_WORKSPACE_ID`, `COVE_SURFACE_ID`
  - cmux: `CMUX_SOCKET_PATH`, `CMUX_WORKSPACE_ID` in CLI ~L33–34; also `CMUX_TAG` for tagged run badges in `TerminalNotificationStore.swift` ~L18–28
- [ ] Move workspace to another window (via socket API and context menu)
  - cmux: "Move Workspace to Window" submenu in context menu `ContentView.swift` ~L6735–6760; `AppDelegate.windowMoveTargets()` lists available windows; `moveWorkspacesToNewWindow()` / `moveWorkspaces(toWindow:)` ~L7290–7335
- [ ] Status entries: arbitrary key-value metadata on sidebar rows (set via `cove +status KEY VALUE`)
  - cmux: `SidebarStatusEntry` struct in `Workspace.swift` ~L59–88 (key, value, icon, color, url, priority, format); `Workspace.statusEntries: [String: SidebarStatusEntry]` ~L963; displayed via `SidebarMetadataRows` in `ContentView.swift` ~L7359; set via socket `status` command
- [ ] Log entries: per-workspace log messages (set via `cove +log MESSAGE`)
  - cmux: `SidebarLogEntry` struct in `Workspace.swift` ~L602–607 (message, level, source, timestamp); `Workspace.logEntries` array; displayed as latest entry in sidebar row `ContentView.swift` ~L6445–6455; levels: info, warning, error with icons
- [ ] Progress bar: per-workspace progress indicator (set via `cove +progress VALUE [LABEL]`)
  - cmux: `SidebarProgressState` struct in `Workspace.swift` ~L609–612 (value 0.0–1.0, optional label); displayed as thin capsule bar in sidebar row `ContentView.swift` ~L6458–6480
- [ ] Pull request status: linked PRs shown in sidebar (set via `cove +pr NUMBER URL STATUS`)
  - cmux: `SidebarPullRequestState` struct in `Workspace.swift` ~L625–630 (number, label, url, status: open/merged/closed); `Workspace.pullRequestsByKey` ~L748–768; displayed in sidebar metadata with status color/icon

**Files created:** `socket_server.zig`
**Files modified:** `application.zig`, CLI command registration
**Est:** ~3,200 lines | Tag: `v0.4.0-socket-api`

#### Phase 4 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

**Prerequisites:** Phase 3 tests should all pass. Keep Cove running for CLI tests.

**Socket path:** `$XDG_RUNTIME_DIR/cove/socket` (typically `/run/user/1000/cove/socket`)

##### 4A. Socket Server

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.1 | Socket created on launch | Launch Cove. Check: `ls -la $XDG_RUNTIME_DIR/cove/socket` | Socket file exists with permissions `0600` (only owner can read/write). | |
| 4.2 | Socket permissions | `stat -c '%a' $XDG_RUNTIME_DIR/cove/socket` | Shows `600`. | |
| 4.3 | Socket responds to ping | From another terminal (not inside Cove): `echo '{"command":"ping"}' \| socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/cove/socket` | Responds with `{"ok": true}` (or similar JSON). | |
| 4.4 | Socket cleaned up on exit | Close Cove. Check `ls $XDG_RUNTIME_DIR/cove/socket` | Socket file is removed. Directory may remain but socket is gone. | |
| 4.5 | Multiple connections | Open 2 `socat` connections to the socket simultaneously, send `ping` on both | Both get responses. Neither blocks the other. | |

##### 4B. CLI — Workspace Management

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.6 | List workspaces | `cove +list-workspaces` (from an external terminal) | JSON array of workspaces with id, title, pwd, git_branch, unread_count. Matches what's visible in the sidebar. | |
| 4.7 | New workspace | `cove +new-workspace` | Returns JSON with new workspace id. Sidebar shows a new row. New terminal is visible if that workspace is selected. | |
| 4.8 | Select workspace | `cove +select-workspace <ID>` (use an id from 4.6) | Cove switches to that workspace. Sidebar selection updates. Returns `{"ok": true}`. | |
| 4.9 | Rename workspace | `cove +rename-workspace <ID> "My Server"` | Workspace title in sidebar changes to "My Server". Returns `{"ok": true}`. | |
| 4.10 | Close workspace | With 2+ workspaces: `cove +close-workspace <ID>` | That workspace is closed. Sidebar row disappears. Returns `{"ok": true}`. | |
| 4.11 | Close workspace — last | With 1 workspace: `cove +close-workspace <ID>` | Window closes (or returns an error if closing last is blocked). Behavior should be documented. | |

##### 4C. CLI — Terminal Interaction

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.12 | Send text | `cove +send <ID> "echo hello\n"` | Text `echo hello` + Enter is typed into the workspace's terminal. Output `hello` appears in the terminal. | |
| 4.13 | Send key | `cove +send-key <ID> ctrl+c` | Sends Ctrl+C to the workspace. If a process is running, it's interrupted. | |
| 4.14 | Read screen | `cove +read-screen <ID>` | Returns JSON with `lines` array containing the current visible terminal content. Output matches what's on screen. | |
| 4.15 | List panes | Create splits in a workspace. `cove +list-panes <WORKSPACE_ID>` | Returns JSON array of panes with id, pid, pwd for each split pane. Count matches number of splits. | |
| 4.16 | New split | `cove +new-split <ID> right` | A new split pane appears on the right side of the workspace. Returns new pane id. | |

##### 4D. CLI — Notifications via CLI

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.17 | Notify via CLI | `cove +notify <ID> "Build" "Build complete!"` | Notification appears: badge on sidebar row if workspace is unfocused, desktop notification if app is backgrounded. | |
| 4.18 | Notify — unfocused workspace | Switch to workspace A. `cove +notify <B_ID> "Alert" "Something happened"` | Badge appears on workspace B's sidebar row. | |

##### 4E. Environment Variables

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.19 | COVE_SOCKET_PATH set | In a Cove terminal: `echo $COVE_SOCKET_PATH` | Prints the socket path (e.g., `/run/user/1000/cove/socket`). Not empty. | |
| 4.20 | COVE_WORKSPACE_ID set | In a Cove terminal: `echo $COVE_WORKSPACE_ID` | Prints a workspace ID. Matches the id shown in `cove +list-workspaces` for this workspace. | |
| 4.21 | COVE_SURFACE_ID set | In a Cove terminal: `echo $COVE_SURFACE_ID` | Prints a surface/pane ID. Not empty. | |
| 4.22 | Env vars differ per workspace | Open 2 workspaces. Compare `$COVE_WORKSPACE_ID` in each. | Different IDs. Each workspace has its own unique ID. | |
| 4.23 | Self-referencing commands | In a Cove terminal: `cove +send $COVE_SURFACE_ID "echo self-test\n"` | Text is sent to the current terminal. `self-test` appears in output. (Tests that env vars work with CLI commands.) | |

##### 4F. Metadata Commands (Status, Log, Progress, PR)

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.24 | Set status entry | `cove +status $COVE_WORKSPACE_ID "Build" "passing" --icon=checkmark --color=green` | Sidebar row shows a status entry: green checkmark + "Build: passing". | |
| 4.25 | Update status | `cove +status $COVE_WORKSPACE_ID "Build" "failing" --icon=xmark --color=red` | Status entry updates in-place to red xmark + "Build: failing". | |
| 4.26 | Remove status | `cove +status $COVE_WORKSPACE_ID "Build" --remove` (or empty value) | Status entry disappears from sidebar row. | |
| 4.27 | Log entry | `cove +log $COVE_WORKSPACE_ID "Deployed to staging" --level=info` | Sidebar row shows latest log entry text below the metadata. | |
| 4.28 | Log entry — error | `cove +log $COVE_WORKSPACE_ID "Build failed: exit 1" --level=error` | Log entry appears with error styling (red icon or text). | |
| 4.29 | Progress bar | `cove +progress $COVE_WORKSPACE_ID 0.5 "Building..."` | Sidebar row shows a thin progress bar at 50%, with label "Building...". | |
| 4.30 | Progress complete | `cove +progress $COVE_WORKSPACE_ID 1.0 "Done"` | Progress bar fills to 100%. Label shows "Done". | |
| 4.31 | Progress clear | `cove +progress $COVE_WORKSPACE_ID --clear` | Progress bar disappears from sidebar row. | |
| 4.32 | PR status | `cove +pr $COVE_WORKSPACE_ID 42 "https://github.com/org/repo/pull/42" open --label="Fix sidebar"` | Sidebar row shows PR indicator: "#42 Fix sidebar" with open status icon/color. | |

##### 4G. Move Workspace to Window

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.33 | Move to new window | With 2+ workspaces: right-click workspace B → "Move to New Window" (or via CLI if implemented) | Workspace B disappears from current window's sidebar. A new Cove window opens with workspace B. Terminal content is preserved. | |
| 4.34 | Move between windows | With 2 Cove windows: move a workspace from window 1 to window 2 (via context menu submenu or CLI) | Workspace moves. Appears in window 2's sidebar. Removed from window 1's sidebar. Terminal state preserved. | |

##### 4H. Error Handling

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 4.35 | Invalid workspace ID | `cove +select-workspace nonexistent-id-12345` | Returns a clear JSON error: `{"error": "workspace not found"}` or similar. No crash. | |
| 4.36 | Invalid command | `cove +nonexistent-command` | Returns a clear error or shows help text. No crash. | |
| 4.37 | Malformed JSON to socket | `echo 'not json' \| socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/cove/socket` | Returns JSON error. Socket stays functional for subsequent valid requests. | |
| 4.38 | Socket after Cove restart | Close Cove. Reopen. `cove +list-workspaces` | New socket is created. CLI works with the new instance. Old socket doesn't interfere. | |
| 4.39 | CLI with no Cove running | Close Cove entirely. `cove +list-workspaces` | Clear error message: "Could not connect to Cove (is it running?)" or similar. Exit code ≠ 0. | |

**Cleanup:** Close all Cove windows. Verify socket file is cleaned up.

---

### Phase 5: Browser Panel (Week 6–8)

**Goal:** In-app browser via WebKitGTK 6.0, splittable alongside terminal panes.

**cmux reference:** `Sources/Panels/BrowserPanel.swift` (~3,250 lines — browser pane model, WebKit integration, scriptable API for agents: snapshot accessibility tree, get element refs, click, fill forms, evaluate JS), `Sources/Panels/BrowserPanelView.swift` (~3,700 lines — address bar, navigation buttons, split integration), `Sources/Panels/CmuxWebView.swift` (custom WebView with key equivalent handling), `Sources/Panels/Panel.swift` + `PanelContentView.swift` + `TerminalPanel.swift` (abstraction layer over terminal vs browser panes). See also `docs/agent-browser-port-spec.md` for the scriptable browser API spec.

- [ ] Add `webkit2gtk-6.0` dependency to build system
  - cmux: Uses system WebKit framework (macOS); on Linux we need `webkit2gtk-6.0` pkg-config dep in `SharedDeps.zig`
- [ ] Create `src/apprt/gtk/class/browser_panel.zig`
  - Wraps `WebKitWebView`
  - Address bar (GtkEntry) with navigation buttons (back/forward/reload)
  - Loads URLs, handles navigation
  - cmux: `BrowserPanel` in `Panels/BrowserPanel.swift` ~L1–3257; `BrowserPanelView` in `Panels/BrowserPanelView.swift` ~L1–3698 (address bar = omnibar with search suggestions, navigation buttons, tab history); `CmuxWebView` in `Panels/CmuxWebView.swift` (custom WebView subclass with key equivalent routing); search engine support via `BrowserSearchEngine` enum ~L7–50
- [ ] Integrate into split system: browser panel as a split leaf alongside terminal surfaces
  - May need to modify `split_tree.zig` to support non-terminal leaves (biggest risk)
  - cmux: `Panel` protocol in `Panels/Panel.swift` abstracts terminal vs browser; `PanelContentView` in `Panels/PanelContentView.swift` switches on panel type; `TerminalPanel` / `BrowserPanel` both conform to `Panel`; split tree uses `Bonsplit` library for layout
- [ ] Wire to socket API: `cove +browser open URL`, `cove +browser navigate`, etc.
  - cmux: `CLI/cmux.swift` browser subcommands ~L1460–2275; commands: `open`, `navigate`, `back`, `forward`, `reload`, `snapshot` (accessibility tree), `click`, `fill`, `evaluate-js`, `close`; see also `docs/agent-browser-port-spec.md` for the full scriptable browser API spec
- [ ] Keybind: `Ctrl+Shift+L` to open browser in split
  - cmux: Cmd+Shift+L to open browser; Cmd+L to focus address bar; see keyboard shortcuts table in README

**Files created:** `browser_panel.zig`
**Files modified:** `split_tree.zig` (if needed), `SharedDeps.zig`, `application.zig`
**Est:** ~2,000 lines | Tag: `v0.5.0-browser`

#### Phase 5 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

**Prerequisites:** Phase 4 tests should all pass. Ensure `webkit2gtk-6.0` is installed on the system (`pacman -Qi webkit2gtk-6.0` on Arch/CachyOS).

##### 5A. Basic Browser Panel

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 5.1 | Open browser (keybind) | Press `Ctrl+Shift+L` (or configured keybind) | A browser panel opens as a split pane alongside the terminal. Address bar is visible at the top of the browser pane with back/forward/reload buttons. | |
| 5.2 | Open browser (CLI) | `cove +browser open https://example.com` (from a terminal) | Browser panel opens showing example.com. Address bar shows the URL. | |
| 5.3 | Navigate to URL | Click the address bar, type `https://duckduckgo.com`, press Enter | Browser navigates to DuckDuckGo. Page renders correctly. Address bar updates. | |
| 5.4 | Navigation buttons | Visit a page, click a link, then click the Back button | Goes back to previous page. Forward button becomes active. Click Forward → returns to the page you were on. | |
| 5.5 | Reload | Click the Reload button (or press the reload keybind) | Page reloads. Content refreshes. | |
| 5.6 | Page rendering | Navigate to a complex page (e.g., `https://github.com`) | Page renders with CSS, images, JavaScript. Interactive elements work (dropdowns, buttons). | |

##### 5B. Browser + Terminal Split Integration

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 5.7 | Side-by-side layout | Open browser with `Ctrl+Shift+L` in a workspace with a terminal | Terminal on one side, browser on the other. Both are usable simultaneously. | |
| 5.8 | Resize split | Drag the divider between terminal and browser | Both panes resize smoothly. Content reflows. | |
| 5.9 | Focus switching | Click in the terminal, type a command. Click in the browser, interact with the page. | Focus switches cleanly between terminal and browser. Keyboard input goes to the focused pane. | |
| 5.10 | Browser in different workspace | Open browser in workspace A. Switch to workspace B (terminal only). Switch back to A. | Browser is still there with its content. No reload, no loss of state. | |
| 5.11 | Multiple browsers | Open browsers in workspace A and workspace B with different URLs | Each workspace has its own browser with independent URL/history/state. | |
| 5.12 | Close browser pane | Focus the browser pane, close it (via keybind or split close action) | Browser pane closes. Terminal takes full width. No crash. | |

##### 5C. Browser via Socket API

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 5.13 | Navigate via CLI | `cove +browser navigate <PANE_ID> https://example.com` | Browser navigates to the URL. Address bar updates. | |
| 5.14 | Back/Forward via CLI | `cove +browser back <PANE_ID>` / `cove +browser forward <PANE_ID>` | Browser goes back/forward as expected. | |
| 5.15 | Snapshot (accessibility tree) | `cove +browser snapshot <PANE_ID>` | Returns a text representation of the page's accessibility tree or DOM structure. Useful for agents to read page content. | |
| 5.16 | Evaluate JS | `cove +browser evaluate-js <PANE_ID> "document.title"` | Returns the page title as a string. | |
| 5.17 | Click element | Navigate to a page with a known button. `cove +browser click <PANE_ID> <element_ref>` | Element is clicked. Page responds (e.g., form submits, link navigates). | |
| 5.18 | Fill form | Navigate to a page with a text input. `cove +browser fill <PANE_ID> <element_ref> "hello world"` | Text input is filled with "hello world". | |
| 5.19 | Close browser via CLI | `cove +browser close <PANE_ID>` | Browser pane closes. Terminal takes full space. Returns `{"ok": true}`. | |

##### 5D. Edge Cases

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 5.20 | HTTPS certificate error | Navigate to a site with an invalid certificate (e.g., `https://self-signed.badssl.com/`) | Browser shows a certificate warning or error page. Doesn't crash. | |
| 5.21 | JavaScript-heavy page | Navigate to a JS-heavy SPA (e.g., a React app on `localhost`) | Page renders and is interactive. No freeze. | |
| 5.22 | Large page | Navigate to a very long page | Page scrolls. No excessive memory usage. Browser pane stays responsive. | |
| 5.23 | 404 page | Navigate to `https://example.com/nonexistent-page-12345` | Shows the server's 404 page or a browser error. No crash. | |
| 5.24 | Localhost dev server | Start a dev server in terminal (`python3 -m http.server 8080`). Open browser to `http://localhost:8080`. | Browser loads the local page. Can develop and preview side-by-side. | |
| 5.25 | Browser + notifications | While browser is open in workspace A, switch to B, send a notification to A | Badge appears on A's sidebar row. Switching back shows browser still intact. | |

**Cleanup:** Close all browser panes, stop any dev servers, close Cove.

---

### Phase 6: Session Persistence (Week 8–9)

**Goal:** Save/restore app state across restarts.

**cmux reference:** `Sources/SessionPersistence.swift` (~470 lines — save/restore layout, workspaces, split trees, browser URLs, sidebar width; autosave timer; `--no-restore` flag). Note cmux restores layout + metadata but NOT live process state (same approach we'll take).

- [ ] JSON snapshot to `~/.local/state/cove/session.json`
  - cmux: `SessionPersistenceStore.save()` / `load()` in `SessionPersistence.swift` ~L362–405; writes to `~/Library/Application Support/cmux/session-<bundleId>.json`; `AppSessionSnapshot` → `SessionWindowSnapshot` → `SessionTabManagerSnapshot` → `SessionWorkspaceSnapshot`
- [ ] Save on quit + autosave every 8 seconds (`g_timeout_add_seconds()`)
  - cmux: `SessionPersistencePolicy.autosaveInterval = 8.0` in `SessionPersistence.swift` ~L18
- [ ] Saved state:
  - Window geometry (position, size, maximized)
    - cmux: `SessionWindowSnapshot.frame` as `SessionRectSnapshot` ~L348; `SessionDisplaySnapshot` for multi-monitor ~L167
  - Sidebar width
    - cmux: `SessionSidebarSnapshot` (isVisible, selection, width) ~L193–197
  - Workspace list (order, titles, pwd per pane)
    - cmux: `SessionWorkspaceSnapshot` ~L324–337 (processTitle, customTitle, customColor, isPinned, currentDirectory, focusedPanelId, layout, panels, statusEntries, logEntries, progress, gitBranch)
  - Split layout tree per workspace
    - cmux: `SessionWorkspaceLayoutSnapshot` recursive enum ~L280–315 (.pane / .split); `SessionSplitLayoutSnapshot` (orientation, dividerPosition, first, second) ~L272–278; `SessionPaneLayoutSnapshot` (panelIds, selectedPanelId) ~L268–271
  - Active workspace index
    - cmux: `SessionTabManagerSnapshot.selectedWorkspaceIndex` ~L340
  - Browser URLs (if Phase 5 done)
    - cmux: `SessionBrowserPanelSnapshot` (urlString, shouldRenderWebView, pageZoom, developerToolsVisible, backHistoryURLStrings, forwardHistoryURLStrings) ~L234–241
- [ ] Restore on launch: recreate workspaces, cd to saved pwd, restore splits
  - Don't restore running processes (same as cmux macOS behavior)
  - cmux: `SessionRestorePolicy.shouldAttemptRestore()` ~L118–137; checks `CMUX_DISABLE_SESSION_RESTORE` env and test mode; scrollback replay via `SessionScrollbackReplayStore` ~L418–474 (writes scrollback to temp file, sets `CMUX_RESTORE_SCROLLBACK_FILE` env, shell integration replays it)
- [ ] `--no-restore` CLI flag to skip restore
  - cmux: `CMUX_DISABLE_SESSION_RESTORE=1` env var in `SessionRestorePolicy` ~L120; any explicit launch argument also skips restore ~L133–137

**Files created:** `session_persistence.zig`
**Files modified:** `application.zig`
**Est:** ~500 lines | Tag: `v0.6.0-sessions`

#### Phase 6 — Manual Testing Plan

**Build & launch:**
```bash
./build.sh run
```

**Prerequisites:** Phase 5 tests should all pass. Session file location: `~/.local/state/cove/session.json`.

##### 6A. Basic Save & Restore

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 6.1 | Session file created | Launch Cove. Wait 10 seconds. Check: `cat ~/.local/state/cove/session.json` | JSON file exists with workspace data, window geometry, sidebar state. | |
| 6.2 | Session file format | Inspect the JSON file | Contains: window position/size, sidebar width/visibility, workspace list (titles, pwds), split layouts, active workspace index. Well-formed JSON. | |
| 6.3 | Restore on launch | Set up state: 3 workspaces named "A", "B", "C" (via `printf '\033]0;A\007'` etc.), select workspace B, resize sidebar to ~300px. Close Cove. Relaunch `./build.sh run`. | Cove opens with: 3 workspaces (A, B, C) in sidebar, workspace B is selected, sidebar is ~300px wide. Terminals start fresh shells in the correct directories (PWDs restored). | |
| 6.4 | Window geometry restored | Before closing: move and resize the Cove window to a specific position/size. Close. Relaunch. | Window opens at approximately the same position and size. | |
| 6.5 | Maximized state restored | Maximize the window. Close. Relaunch. | Window opens maximized. | |
| 6.6 | Sidebar visibility restored | Hide the sidebar (toggle off). Close. Relaunch. | Sidebar is hidden on launch. Toggle button is in the "off" state. | |

##### 6B. Workspace State Restoration

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 6.7 | PWD restored per workspace | Workspace A: `cd /tmp`. Workspace B: `cd ~/code`. Close Cove. Relaunch. | Workspace A's terminal starts in `/tmp`. Workspace B's starts in `~/code`. Check with `pwd` in each. | |
| 6.8 | Custom titles restored | Set custom titles on 2 workspaces (via rename). Close. Relaunch. | Custom titles appear in sidebar. Not overwritten by shell prompt. | |
| 6.9 | Split layout restored | Workspace A: create a 2-pane horizontal split. Workspace B: create a 3-pane layout (split right, then split down). Close. Relaunch. | Workspace A has 2 panes side-by-side. Workspace B has 3 panes in the correct arrangement. Fresh shells in each pane. | |
| 6.10 | Active workspace restored | Select workspace 3 out of 5. Close. Relaunch. | Workspace 3 is selected on launch. Its terminal content is visible. | |
| 6.11 | Workspace order preserved | Workspaces in order: A, B, C, D. Close. Relaunch. | Same order: A, B, C, D in sidebar. | |
| 6.12 | Processes NOT restored | Run `sleep 999` in a workspace. Close Cove (confirm close). Relaunch. | The `sleep 999` process is NOT running. A fresh shell is started in that workspace's saved PWD. (We restore layout, not processes.) | |

##### 6C. Metadata Restoration

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 6.13 | Pinned workspace restored | Pin workspace A. Close. Relaunch. | Workspace A is still pinned (at top, with pin icon). | |
| 6.14 | Tab color restored | Set workspace B to red color. Close. Relaunch. | Workspace B shows red color indicator. | |
| 6.15 | Browser URL restored | Open browser in workspace A to `https://example.com`. Close. Relaunch. | Browser panel is restored in workspace A showing `https://example.com` (or a loading state that navigates there). | |

##### 6D. Autosave

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 6.16 | Autosave interval | Create a new workspace. Wait 10 seconds. Check `~/.local/state/cove/session.json` modification time with `stat`. | File was modified within the last 10 seconds (autosave at ~8s interval). | |
| 6.17 | Autosave captures changes | Create a new workspace. Wait 10s. Kill Cove process (`kill -9 $(pidof cove)`) — hard kill, no graceful shutdown. Relaunch. | New workspace is present in the restored session (autosave captured it before the crash). | |
| 6.18 | Save on graceful quit | Create a workspace, immediately close Cove (Ctrl+Shift+Q). Relaunch. | New workspace is restored. (Graceful quit triggers a save before exit.) | |

##### 6E. --no-restore Flag

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 6.19 | Skip restore | Set up 3 workspaces with custom names. Close. Relaunch with `./zig-out/bin/cove --no-restore` (or however the flag is implemented). | Cove opens fresh: 1 workspace, default title, no restored state. | |
| 6.20 | Session file preserved | After launching with `--no-restore`, check `~/.local/state/cove/session.json` before any autosave triggers. | Old session file still exists (not deleted by `--no-restore`). After autosave, it gets overwritten with the new (fresh) state. | |

##### 6F. Edge Cases

| # | Test | Steps | Expected Result | ✅/❌ |
|---|------|-------|-----------------|-------|
| 6.21 | Corrupt session file | Edit `~/.local/state/cove/session.json` to contain `{invalid json`. Launch Cove. | Cove opens with a fresh default state (1 workspace). No crash. Warning in stderr or toast: "Could not restore session". | |
| 6.22 | Missing session file | Delete `~/.local/state/cove/session.json`. Launch Cove. | Cove opens fresh. New session file is created after autosave. | |
| 6.23 | Empty session file | Truncate: `> ~/.local/state/cove/session.json`. Launch Cove. | Same as 6.22 — fresh start, no crash. | |
| 6.24 | Old session format | If session format changes between versions: launch with an old-format session file. | Cove handles gracefully: either migrates the format, or starts fresh with a warning. No crash. | |
| 6.25 | Deleted PWD | Restore a session where a workspace's saved PWD was `/tmp/deleted-dir` (which no longer exists). | Workspace starts with shell in `~` (home directory fallback). No crash or error dialog. | |
| 6.26 | Very large session | Create 50 workspaces with splits. Close. Relaunch. | Session restores all 50 workspaces. May take a moment but completes without crash. Launch time is reasonable (< 5 seconds). | |
| 6.27 | Multiple windows | Open 2 Cove windows with different workspace setups. Close both. Relaunch. | Both windows are restored with their respective workspaces and layouts. (Or if single-window restore: at least the primary window's state is restored.) | |

**Cleanup:** `rm ~/.local/state/cove/session.json` if you want a fresh start for future testing.

---

## Milestone Summary

| Phase | Feature | Est. Lines | Status | Notes |
|-------|---------|-----------|--------|-------|
| 0 | Repo, build, attribution | 100 | ✅ Done | Commit `6816b450a` |
| 1 | Vertical sidebar | 1,700 | ✅ Done | Commits `6363939c4`, `febc8fd98`, `e0ae72a56`. All 42 tests passing. |
| 2 | Notifications | 400 | 🔲 | |
| 3 | Workspace metadata + sidebar UX | 900 | 🔲 | +pin, tab color, multi-select, shortcut hints |
| 4 | Socket API & CLI + metadata commands | 3,200 | 🔲 | +status, log, progress, PR, move-to-window |
| 5 | Browser panel | 2,000 | 🔲 | |
| 6 | Session persistence | 500 | 🔲 | |

**Note:** Cannot use `vX.Y.Z` tags — Ghostty's build system panics on non-matching semver tags. Use `cove-*` prefixed tags if needed.

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Ghostty upstream refactors `window.zig` or tab system | High — rebase pain | Rebase weekly. Our changes are additive (new files) where possible; modifications to existing files are surgical. |
| `split_tree.zig` doesn't support non-terminal leaves (Phase 5) | Medium — browser panel architecture | Inspect `split_tree.zig` early. Worst case: browser opens in separate pane outside the split tree. |
| WebKitGTK 6.0 not available on all distros | Low — Phase 5 only | Make browser panel a compile-time optional feature (`-Dbrowser=true`). |
| GCC/Zig SFrame linker issue persists | Low — build only | `build.sh` workaround is stable. Track upstream Zig for proper fix. |
| Ghostty adds their own sidebar/workspace feature | Low probability, high impact | Monitor upstream. If it happens, evaluate adopting their implementation vs. keeping ours. |
| Ghostty build system rejects our git tags | Low — build only | **Already hit:** `vX.Y.Z` tags cause `GitVersion.zig` to panic. Never use `v`-prefixed semver tags for Cove. Use `cove-*` prefix or no tags. |

---

## File Impact Map

Files we **created** (no rebase conflicts):
```
README.md                                  (Phase 0) ✅
THIRD_PARTY_LICENSES.md                    (Phase 0) ✅
build.sh                                   (Phase 0) ✅
docs/plan.md                               (Phase 0) ✅
docs/progress.md                           (Phase 0) ✅
docs/spike-strategy1-gtk4-rewrite.md       (Phase 0) ✅
docs/spike-strategy2-ghostty-fork.md       (Phase 0) ✅
src/apprt/gtk/class/notification_store.zig (Phase 2) 🔲
src/apprt/gtk/class/socket_server.zig      (Phase 4) 🔲
src/apprt/gtk/class/browser_panel.zig      (Phase 5) 🔲
src/apprt/gtk/class/session_persistence.zig (Phase 6) 🔲
```

**Note:** Separate `sidebar.zig`/`sidebar_row.zig` files were NOT needed — sidebar is built directly in `window.blp` + `window.zig`.

Files we **modified** (potential rebase conflicts):
```
src/build/GhosttyExe.zig                (Phase 0 — binary name) ✅
src/apprt/gtk/App.zig                   (Phase 0 — app ID) ✅
src/apprt/gtk/build/gresource.zig       (Phase 0 — resource prefix) ✅
src/apprt/gtk/class/application.zig     (Phase 0 — resource path, notifications) ✅
src/apprt/gtk/class/surface.zig         (Phase 0 — notification icon) ✅
src/apprt/gtk/class/window.zig          (Phase 0, 1 — about dialog + sidebar, heavy) ✅
src/apprt/gtk/ui/1.5/window.blp         (Phase 1 — full layout rewrite) ✅
src/apprt/gtk/css/style.css             (Phase 1 — sidebar CSS) ✅
src/apprt/gtk/ipc/new_window.zig        (Phase 0 — comment updates) ✅
src/apprt/gtk/winproto/x11.zig          (Phase 0 — WM_CLASS comment) ✅
src/apprt/gtk/ui/1.5/inspector-window.blp (Phase 0 — title, icon) ✅
src/apprt/gtk/ui/1.2/debug-warning.blp  (Phase 0 — debug text) ✅
src/apprt/gtk/ui/1.3/debug-warning.blp  (Phase 0 — debug text) ✅
src/apprt/gtk/class/tab.zig             (Phase 3 — metadata fields) 🔲
src/apprt/gtk/class/split_tree.zig      (Phase 5 — maybe browser leaves) 🔲
src/build/SharedDeps.zig                (Phase 5 — add webkit dep) 🔲
```

Files we **never touch** (zero conflict risk):
```
src/terminal/           — VT parser, state machine
src/renderer/           — OpenGL, Metal
src/font/               — font discovery, shaping
src/input/              — key encoding, bindings
src/termio/             — pty I/O, exec
src/config/             — config parsing
src/apprt/gtk/winproto/ — Wayland/X11
src/apprt/gtk/key.zig   — keyboard translation
```

---

## Build & Test

```bash
# Build
./build.sh

# Build + run
./build.sh run

# Run Zig unit tests (Ghostty's + ours)
./build.sh test

# Release build
./build.sh -Doptimize=ReleaseFast

# Run Cove integration tests (Phase 4+, requires running instance)
python3 tests/run_all.py

# Run a single integration test
python3 tests/test_sidebar_basics.py
```

---

## Automated Test Strategy

### What Ghostty already provides

Ghostty has a **comprehensive unit test suite** — ~2,473 Zig `test` blocks across 166 files. These cover the terminal engine extensively:

| Area | Tests | Key files |
|------|-------|-----------|
| Terminal/VT parser | ~365 | `Terminal.zig`, `stream.zig`, `sgr.zig` |
| Page/screen management | ~384 | `PageList.zig`, `Screen.zig`, `page.zig` |
| Config parsing | ~110 | `Config.zig`, `key.zig`, `path.zig` |
| Input/keybinding encoding | ~168 | `key_encode.zig`, `Binding.zig` |
| OSC sequence parsers | ~136 | `osc9.zig`, `semantic_prompt.zig`, `kitty_clipboard_protocol.zig` |
| Font shaping/rendering | ~27+ | `coretext.zig`, font subsystem |
| GTK bindings/utilities | ~17 | `adw_version.zig`, `gtk_version.zig`, `key.zig`, `actions.zig`, `slice.zig`, `gsettings.zig`, `config.zig`, `surface.zig` |

Ghostty also has a CI pipeline (`.github/workflows/test.yml`) with:
- `zig build test` (core unit tests) on Linux and macOS
- `zig build test` with GTK runtime (X11/Wayland matrix: `test-gtk`)
- SIMD on/off matrix (`test-simd`)
- Sentry on/off matrix (`test-sentry-linux`)
- Build verification on Linux, macOS, Windows, FreeBSD, Flatpak, snap, Nix, Debian 13, Android
- Valgrind leak checking
- Linters: `zig fmt`, `prettier`, `swiftlint`, `typos`, `shellcheck`, `alejandra` (Nix), `blueprint-compiler`
- macOS XCTest suite (split tree, UI, etc.)

**We inherit all of this for free.** Running `zig build test` exercises Ghostty's full test suite. Our modifications to GTK files (`window.zig`, `application.zig`) are tested indirectly — if we break GObject signal signatures, binding patterns, or widget hierarchy, the GTK test subset catches it at compile time (Zig's comptime checks) or at `zig build test` runtime.

### What cmux has for reference

cmux has three test layers (~15,500 lines total):

**1. Unit tests** (`cmuxTests/`, 8 files, ~11,670 lines) — XCTest:
- `SessionPersistenceTests.swift` — save/restore round-trips, corrupt file handling, format migration
- `WorkspaceManualUnreadTests.swift` — mark-as-read/unread logic
- `GhosttyConfigTests.swift` — config parsing, key event mapping
- `CmuxWebViewKeyEquivalentTests.swift` — browser keyboard routing (~7,700 lines, very thorough)
- `AppDelegateShortcutRoutingTests.swift` — keyboard shortcut dispatch
- Others: CJK input, update pill visibility, workspace content view

**2. UI tests** (`cmuxUITests/`, 10 files, ~3,837 lines) — XCUITest (Xcode UI automation):
- `AutomationSocketUITests.swift` — socket API end-to-end
- `BrowserOmnibarSuggestionsUITests.swift` — browser address bar
- `CloseWorkspaceCmdDUITests.swift` / `CloseWorkspaceConfirmDialogUITests.swift` — workspace close flows
- `JumpToUnreadUITests.swift` — notification jump
- `SidebarResizeUITests.swift` — sidebar drag resize
- `MultiWindowNotificationsUITests.swift` — cross-window notifications
- Others: browser navigation keybinds, menu routing, update pill

**3. Integration/regression tests** (`tests/`, ~80 Python scripts) — socket-driven:
- Python client library (`cmux.py`) connects to the Unix socket
- Tests spawn/control the app: create workspaces, send keys, verify state
- Covers: notifications, sidebar metadata (PWD, git, ports, PRs), session restore, browser, splits, focus, signals, CPU usage, visual screenshots
- Some are shell scripts (CI guard checks, `ctrl_signals.sh`, `homebrew_sha.sh`)

**CI:** cmux only runs `UpdatePillUITests` in CI (self-hosted macOS runner). The Python integration tests and most XCUITests are run manually/locally.

### Cove's automated test plan

We adopt a similar 3-layer strategy adapted for Zig/GTK/Linux:

#### Layer 1: Zig Unit Tests (`zig build test`)

**Inherited from Ghostty:** 2,473 tests run automatically. We don't modify these.

**Cove-specific unit tests** — added inline in new Zig files using `test "..."` blocks:

| Phase | File | Tests to add |
|-------|------|--------------|
| 2 | `notification_store.zig` | `add()` stores notification; `markRead()` clears unread flag; `unreadCount()` is accurate; `clearAll()` empties list; notification with same ID deduplicates; max notifications cap |
| 3 | `window.zig` or helper | Git branch parser: `refs/heads/main` → `main`; detached HEAD → short hash; worktree `.git` file → resolve; non-git dir → `null` |
| 3 | `window.zig` or helper | Port scanner: parse `/proc/net/tcp` line → port number; filter by inode → PID matching; IPv6 parsing |
| 4 | `socket_server.zig` | JSON command parser: valid `ping` → `{"ok":true}`; unknown command → error; malformed JSON → error; empty input → error |
| 6 | `session_persistence.zig` | Round-trip: serialize → deserialize → equal; corrupt JSON → graceful fallback; missing fields → defaults; empty file → fresh state |

**Run with:** `zig build test` (or `./build.sh test` which wraps it).

**When:** Every commit. Must pass before merging to `cove/main`.

#### Layer 2: Python Integration Tests (`tests/`)

Socket-driven tests that launch Cove and interact with it programmatically. Available from **Phase 4** onward (requires socket API).

**Infrastructure:**

```
tests/
├── cove.py                          # Python client library (socket wrapper)
├── conftest.py                      # Shared fixtures: launch/teardown Cove
├── run_all.py                       # Test runner
├── test_workspace_crud.py           # Phase 4: create, list, rename, close, select
├── test_workspace_send.py           # Phase 4: send text, send key, read screen
├── test_workspace_splits.py         # Phase 4: new split, list panes, split directions
├── test_notifications.py            # Phase 4: notify via CLI, unread count, mark read
├── test_metadata.py                 # Phase 4: status, log, progress, PR entries
├── test_env_vars.py                 # Phase 4: COVE_SOCKET_PATH, WORKSPACE_ID, SURFACE_ID
├── test_browser.py                  # Phase 5: open, navigate, snapshot, evaluate-js
├── test_session_restore.py          # Phase 6: save, kill, relaunch, verify state
└── test_error_handling.py           # Phase 4: invalid IDs, bad JSON, missing socket
```

**`cove.py` client library** (modeled on cmux's `cmux.py`):
```python
class CoveClient:
    def connect(socket_path=None)      # Connect to Unix socket
    def ping() -> dict                 # {"ok": true}
    def list_workspaces() -> list      # [{id, title, pwd, ...}]
    def new_workspace() -> dict        # {id, ref}
    def close_workspace(id) -> dict
    def select_workspace(id) -> dict
    def rename_workspace(id, name)
    def send(id, text)                 # Send text to terminal
    def send_key(id, key)              # Send key combo
    def read_screen(id) -> list        # Terminal screen content
    def list_panes(id) -> list
    def new_split(id, direction)
    def notify(id, title, body)
    def set_status(id, key, value, **kwargs)
    def set_progress(id, value, label=None)
    def browser_open(url)              # Phase 5
    def browser_navigate(pane_id, url) # Phase 5
    def browser_snapshot(pane_id)      # Phase 5
```

**Example test** (`test_workspace_crud.py`):
```python
def test_create_and_list():
    c = CoveClient()
    c.connect()
    initial = c.list_workspaces()
    assert len(initial) >= 1

    result = c.new_workspace()
    assert "id" in result

    after = c.list_workspaces()
    assert len(after) == len(initial) + 1

    c.close_workspace(result["id"])
    final = c.list_workspaces()
    assert len(final) == len(initial)

def test_rename():
    c = CoveClient()
    c.connect()
    ws = c.new_workspace()
    c.rename_workspace(ws["id"], "My Server")
    workspaces = c.list_workspaces()
    found = [w for w in workspaces if w["id"] == ws["id"]]
    assert found[0]["title"] == "My Server"
    c.close_workspace(ws["id"])

def test_send_and_read():
    c = CoveClient()
    c.connect()
    ws = c.new_workspace()
    time.sleep(0.5)  # wait for shell prompt
    c.send(ws["id"], "echo COVE_TEST_MARKER\n")
    time.sleep(0.5)
    screen = c.read_screen(ws["id"])
    assert any("COVE_TEST_MARKER" in line for line in screen)
    c.close_workspace(ws["id"])

def test_invalid_workspace_id():
    c = CoveClient()
    c.connect()
    result = c.select_workspace("nonexistent-id-12345")
    assert "error" in result
```

**Run with:** `python3 tests/run_all.py` (requires Cove running with socket enabled).

**When:** Before each phase release. Can be run in CI with a headless display server (`xvfb-run` or `weston --backend=headless`).

#### Layer 3: Visual/E2E Smoke Tests (Future, Optional)

These are the hardest to automate on Linux. Options:

1. **Screenshot comparison** — launch Cove under `xvfb-run`, take screenshots with `import` (ImageMagick) or `grim` (Wayland), compare against reference images with perceptual diff.
2. **Accessibility tree inspection** — use `AT-SPI2` (Linux accessibility framework) to query widget tree, verify sidebar has expected rows/labels. GTK exposes all widgets via AT-SPI.
3. **`xdotool` / `ydotool` automation** — send mouse clicks and keyboard input to the running Cove window, then verify state via socket API.

**We defer this layer** until Phase 4+ when we have the socket API. The socket API makes E2E testing tractable — instead of fragile pixel-based assertions, we verify state through the API after simulating user actions.

**Potential CI approach:**
```bash
# Launch Cove headless
export GDK_BACKEND=x11
xvfb-run -a -s "-screen 0 1920x1080x24" ./zig-out/bin/cove &
COVE_PID=$!
sleep 3  # wait for startup + socket

# Run integration tests
python3 tests/run_all.py

# Cleanup
kill $COVE_PID
```

#### Test pyramid summary

```
                    ┌─────────────────┐
                    │  E2E / Visual   │  ← Future (Phase 4+)
                    │  Screenshot +   │     xvfb + socket API + xdotool
                    │  AT-SPI queries │     ~10 tests
                    ├─────────────────┤
                    │  Integration    │  ← Phase 4+ (socket-driven)
                    │  Python scripts │     cove.py client + assertions
                    │  via socket API │     ~50 tests across 10 files
                    ├─────────────────┤
                    │  Unit Tests     │  ← Phase 0+ (zig build test)
                    │  Zig test blocks│     Ghostty: 2,473 inherited
                    │  in .zig files  │     Cove: ~30-50 new tests
                    └─────────────────┘
```

#### CI plan (GitHub Actions)

We'll add `.github/workflows/cove-test.yml`:

```yaml
name: Cove Tests
on:
  push:
    branches: [cove/main]
  pull_request:
    branches: [cove/main]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libgtk-4-dev libadwaita-1-dev
      - name: Run unit tests
        run: zig build test

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libgtk-4-dev libadwaita-1-dev xvfb python3
      - name: Build Cove
        run: zig build
      - name: Run integration tests
        run: |
          xvfb-run -a ./zig-out/bin/cove &
          sleep 3
          python3 tests/run_all.py
          kill %1
```

**Note:** This CI config is aspirational — we'll refine it when we actually set up the GitHub Actions. The main complexity is the Zig toolchain + GTK/Adwaita deps on the runner, and the GCC SFrame workaround. We may need a custom Docker image or Nix shell.

#### What we intentionally DON'T test

- **Ghostty terminal engine correctness** — Ghostty's 2,473 tests cover VT parsing, rendering, fonts, input. We inherit these and trust them.
- **GTK/Adwaita widget behavior** — We don't test that `GtkListBox` handles selection correctly or that `GtkPaned` resizes. Those are GNOME platform guarantees.
- **Pixel-perfect rendering** — Terminal rendering is Ghostty's OpenGL renderer. We don't verify pixel output.
- **Wayland/X11 protocol compliance** — Ghostty handles this via `winproto/`. We don't modify it.

---

## Ghostty Config Compatibility

Cove reads `~/.config/ghostty/config` for terminal settings (fonts, colors, themes, keybinds). Cove-specific settings (sidebar width, notification preferences) go in `~/.config/cove/config`. Users don't need to duplicate their Ghostty config.
