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

### ✅ Phase 1 — Vertical Sidebar (Core Complete, Polish Remaining)
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

#### Phase 1 Polish (Not Yet Done)
- [ ] Keyboard navigation (Up/Down in sidebar, Enter to select)
- [ ] Middle-click sidebar row to close workspace
- [ ] Right-click context menu on sidebar rows (rename, close)
- [ ] Sidebar auto-hide when only 1 workspace (config option)
- [ ] Double-click sidebar row to rename workspace
- [ ] Persist sidebar width in config

### 🔲 Not Started
- [ ] Phase 2: Notification system (blue badges, desktop notifications)
- [ ] Phase 3: Workspace metadata (git branch, ports, pwd in sidebar rows)
- [ ] Phase 4: Socket API & CLI (`cove +list-workspaces`, etc.)
- [ ] Phase 5: Browser panel (WebKitGTK)
- [ ] Phase 6: Session persistence

---

## Implementation Plan

**Full detail in [plan.md](plan.md).** Summary:

| Phase | Feature | Est. Lines | Status |
|-------|---------|-----------|--------|
| 0 | Repo, build, README, attribution | 100 | ✅ Done |
| 1 | Vertical sidebar (replace AdwTabBar) | 1,700 | 🟡 Core done, polish remaining |
| 2 | Notification system | 400 | 🔲 Not started |
| 3 | Workspace metadata (git, ports, pwd) | 600 | 🔲 Not started |
| 4 | Socket API & CLI (`cove +cmd`) | 2,500 | 🔲 Not started |
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
1. **Phase 1 polish:** Keyboard nav, middle-click close, right-click context menu, auto-hide, rename, persist width
2. **Phase 2:** Notification system — blue badges on sidebar rows, desktop notifications via GLib
3. **Phase 3:** Workspace metadata — git branch, pwd, ports in sidebar rows
