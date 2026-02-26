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

---

### Phase 1: Vertical Sidebar (Week 1–2)

**Goal:** Replace Ghostty's horizontal `AdwTabBar` with a vertical sidebar showing workspace list. This is the biggest single change — it touches the window's core layout.

#### 1a–c. Sidebar implementation ✅ COMPLETE

**Actual approach differed from plan:** Instead of creating separate `sidebar.zig`/`sidebar_row.zig` GObject widgets and replacing `AdwTabView` with `GtkStack`, we took a simpler approach:

1. **Kept `AdwTabView` internally** — it handles page ordering, close confirmation, and signals. Much less code than reimplementing with `GtkStack`.
2. **Built sidebar directly in `window.blp`** — a `GtkBox` with `GtkListBox` inside a `GtkPaned`, no separate GObject widget needed.
3. **Sidebar rows are plain `GtkLabel`s** created programmatically in `window.zig` with title bound via `gobject.Object.bindProperty`. Page reference stored via `gobject.Object.setData("cove-tab-page", page)`.
4. **Did NOT rename Tab → Workspace in code** — kept `Tab` struct name to minimize diff. Only user-facing strings say "Workspace".
5. **Did NOT add metadata fields to tab.zig yet** — deferred to Phase 2/3.

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

- [x] Remove `AdwTabOverview`, `AdwTabBar` from template and Private struct
- [x] Add `GtkPaned`, `GtkBox` (sidebar), `GtkListBox` to template and Private struct
- [x] Sidebar rows created on `page-attached`, removed on `page-detached`
- [x] Bidirectional sync: sidebar selection ↔ AdwTabView selected page
- [x] Anti-reentrance guard (`updating_sidebar` flag)
- [x] `sidebar-visible` property + `win.toggle-sidebar` action + header toggle button
- [x] `toggleTabOverview()` redirected to `toggleSidebar()`
- [x] Removed dead code: tab overview callbacks, tab bar properties, context menu page
- [x] `.cove-sidebar` CSS in `style.css`

**Commit:** `6363939c4`
**Files modified:** `window.zig` (~85 lines net reduction), `window.blp` (rewritten), `style.css`
**No new files created** (simpler than planned)

#### 1d. Sidebar polish (NOT YET DONE)

- [ ] Sidebar width persisted in config
- [ ] Drag-to-resize via GtkPaned handle (already works — built into GtkPaned)
- [ ] Keyboard navigation: Up/Down in sidebar, Enter to select
- [ ] Middle-click sidebar row to close workspace
- [ ] Right-click context menu on sidebar rows (rename, close)
- [ ] Sidebar auto-hides when only 1 workspace (config option)
- [ ] Double-click sidebar row to rename workspace

**Est:** ~200 lines

---

### Phase 2: Notification System (Week 2–3)

**Goal:** Blue notification rings on sidebar rows, desktop notifications, jump-to-unread.

- [ ] Create `src/apprt/gtk/class/notification_store.zig`
  - Per-workspace notification list (timestamp, title, body, read/unread)
  - Methods: `add()`, `markRead()`, `unreadCount()`, `clearAll()`
  - GObject signals: `notification-added`, `unread-count-changed`
- [ ] Hook into libghostty actions in `application.zig`:
  - `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` (OSC 9/99/777) → store + desktop notify
  - `GHOSTTY_ACTION_RING_BELL` → increment badge
  - `GHOSTTY_ACTION_COMMAND_FINISHED` → store (with exit code + duration)
- [ ] Update `sidebar_row.zig`: blue badge circle showing unread count
- [ ] Desktop notifications via `g_application_send_notification()` (GLib native, no libnotify needed)
- [ ] "Jump to latest unread" action: `Ctrl+Shift+U`
- [ ] Mark-as-read when workspace is selected
- [ ] CSS: blue ring animation on sidebar row (`.sidebar-row.unread { ... }`)

**Files created:** `notification_store.zig`
**Files modified:** `application.zig`, `sidebar_row.zig`, runtime CSS
**Est:** ~400 lines | Tag: `v0.2.0-notifications`

---

### Phase 3: Workspace Metadata (Week 3–4)

**Goal:** Show git branch, working directory, listening ports in sidebar rows.

- [ ] Hook `GHOSTTY_ACTION_PWD` in `application.zig` → update workspace's `pwd` field
- [ ] Hook `GHOSTTY_ACTION_SET_TITLE` → update workspace's display title
- [ ] Git branch detection: read `<pwd>/.git/HEAD` (or `<pwd>/.git` ref for worktrees), parse branch name
  - Trigger on pwd change, not on a timer (efficient)
- [ ] Port scanner: read `/proc/net/tcp` + `/proc/net/tcp6`, filter by workspace's child PID tree
  - `g_timeout_add_seconds(5)` periodic scan
  - Show first 3 ports as pills in sidebar row
- [ ] Update `sidebar_row.zig` layout:
  ```
  [unread badge] Workspace Title          [close]
                 🌿 feature/sidebar  📁 ~/code/proj
                 🔌 3000, 5173
  ```
- [ ] Expandable/collapsible metadata rows (click to toggle detail level)

**Files modified:** `application.zig`, `sidebar_row.zig`, `tab.zig`
**Est:** ~600 lines | Tag: `v0.3.0-metadata`

---

### Phase 4: Socket API & CLI (Week 4–6)

**Goal:** Unix domain socket for scripting, `cove` CLI subcommands.

#### 4a. Socket server

- [ ] Create `src/apprt/gtk/class/socket_server.zig`
  - Listens on `$XDG_RUNTIME_DIR/cove/socket` (fallback: `/tmp/cove-$UID/socket`)
  - GLib main loop integration via `g_unix_fd_add()` for accept + read
  - Newline-delimited JSON protocol (one JSON object per line, response per line)
  - Authentication: file-permission based (socket is `0600`)
- [ ] Wire into `application.zig`: start server on activate, stop on shutdown

#### 4b. Protocol (V2 JSON)

Core commands:
```
ping                    → {"ok": true}
list-workspaces         → [{id, title, pwd, git_branch, unread_count, ...}]
new-workspace           → {id, ref}
close-workspace ID      → {ok}
select-workspace ID     → {ok}
rename-workspace ID NAME → {ok}
list-panes ID           → [{id, pid, pwd, ...}]
new-split ID DIR        → {id, ref}
send ID TEXT            → {ok}
send-key ID KEY         → {ok}
notify ID TITLE BODY    → {ok}
read-screen ID          → {lines: [...]}
```

#### 4c. CLI integration

- [ ] Add `+` subcommands to the `cove` binary (same pattern as `ghostty +new-window`)
  - `cove +list-workspaces`, `cove +new-workspace`, `cove +send`, etc.
- [ ] Environment variables set in spawned shells: `COVE_SOCKET_PATH`, `COVE_WORKSPACE_ID`, `COVE_SURFACE_ID`

**Files created:** `socket_server.zig`
**Files modified:** `application.zig`, CLI command registration
**Est:** ~2,500 lines | Tag: `v0.4.0-socket-api`

---

### Phase 5: Browser Panel (Week 6–8)

**Goal:** In-app browser via WebKitGTK 6.0, splittable alongside terminal panes.

- [ ] Add `webkit2gtk-6.0` dependency to build system
- [ ] Create `src/apprt/gtk/class/browser_panel.zig`
  - Wraps `WebKitWebView`
  - Address bar (GtkEntry) with navigation buttons (back/forward/reload)
  - Loads URLs, handles navigation
- [ ] Integrate into split system: browser panel as a split leaf alongside terminal surfaces
  - May need to modify `split_tree.zig` to support non-terminal leaves (biggest risk)
- [ ] Wire to socket API: `cove +browser open URL`, `cove +browser navigate`, etc.
- [ ] Keybind: `Ctrl+Shift+L` to open browser in split

**Files created:** `browser_panel.zig`
**Files modified:** `split_tree.zig` (if needed), `SharedDeps.zig`, `application.zig`
**Est:** ~2,000 lines | Tag: `v0.5.0-browser`

---

### Phase 6: Session Persistence (Week 8–9)

**Goal:** Save/restore app state across restarts.

- [ ] JSON snapshot to `~/.local/state/cove/session.json`
- [ ] Save on quit + autosave every 8 seconds (`g_timeout_add_seconds()`)
- [ ] Saved state:
  - Window geometry (position, size, maximized)
  - Sidebar width
  - Workspace list (order, titles, pwd per pane)
  - Split layout tree per workspace
  - Active workspace index
  - Browser URLs (if Phase 5 done)
- [ ] Restore on launch: recreate workspaces, cd to saved pwd, restore splits
  - Don't restore running processes (same as cmux macOS behavior)
- [ ] `--no-restore` CLI flag to skip restore

**Files created:** `session_persistence.zig`
**Files modified:** `application.zig`
**Est:** ~500 lines | Tag: `v0.6.0-sessions`

---

## Milestone Summary

| Phase | Feature | Est. Lines | Status | Notes |
|-------|---------|-----------|--------|-------|
| 0 | Repo, build, attribution | 100 | ✅ Done | Commit `6816b450a` |
| 1 | Vertical sidebar | 1,700 | 🟡 Core done | Commit `6363939c4`. Polish (1d) remaining. |
| 2 | Notifications | 400 | 🔲 | |
| 3 | Workspace metadata | 600 | 🔲 | |
| 4 | Socket API & CLI | 2,500 | 🔲 | |
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

# Run tests (once we add them)
./build.sh test

# Release build
./build.sh -Doptimize=ReleaseFast
```

Future: add integration tests using the socket API (Phase 4) — spawn Cove, connect to socket, verify workspace CRUD.

---

## Ghostty Config Compatibility

Cove reads `~/.config/ghostty/config` for terminal settings (fonts, colors, themes, keybinds). Cove-specific settings (sidebar width, notification preferences) go in `~/.config/cove/config`. Users don't need to duplicate their Ghostty config.
