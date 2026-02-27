# Cove: Project Context

> A workspace-oriented terminal for Linux, inspired by [cmux](https://github.com/manaflow-ai/cmux) and built on [Ghostty](https://github.com/ghostty-org/ghostty)'s GTK frontend.
>
> Design details: [plan.md](plan.md) | Task tracking: `br epic status`, `br ready`

---

## Architecture

**Strategy:** Fork Ghostty's GTK frontend, add workspace-oriented UI on top. Kept `AdwTabView` internally for page management, removed its visible UI (tab bar/overview), added sidebar.

**Window layout (after Phase 1):**
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

**Sidebar row layout (after Phase 2/3):**
```
GtkListBoxRow
└── GtkBox (vertical)
    ├── GtkBox (horizontal)
    │   ├── GtkLabel .cove-sidebar-badge  (unread count, hidden when 0)
    │   ├── GtkLabel (title, hexpand, ellipsize)
    │   └── GtkButton .cove-sidebar-close (hidden, shown on hover)
    └── GtkLabel .cove-sidebar-subtitle .dim-label
        (metadata: "🌿 branch  📁 ~/path", hidden when empty)
```

**Key architectural decisions:**
- **AdwTabView kept internally** — handles page ordering, close confirmation, drag-and-drop, pinning, signals. Sidebar is an additional navigation layer, not a replacement.
- **GObject class names unchanged** — `GhosttyApplication`, `GhosttyWindow`, etc. stay as-is. Only user-facing strings say "Cove". Minimizes rebase conflicts.
- **No vX.Y.Z tags** — Ghostty's `GitVersion.zig` panics on non-matching semver. Use `cove-*` prefix or no tags.
- **Sidebar rows store refs** via `gobject.Object.setData()`: `cove-tab-page`, `cove-close-btn`, `cove-subtitle`, `cove-badge`.
- **Workspace IDs** — monotonic u64 counter, stored via `setData("cove-ws-id")` on tab pages. Assigned on first access (lazy). Used by socket protocol.
- **Signal pattern:** Always `TypeName.signals.signal_name.connect(instance, DataType, &callback, data, .{})`. Never `TypeName.connectSignalName()`.
- **Pure data modules** — `notification_store.zig`, `git_branch.zig`, `path_shorten.zig` have zero GTK deps, fully unit-testable with inline `test` blocks.
- **Socket protocol** — newline-delimited JSON over Unix domain socket at `$XDG_RUNTIME_DIR/cove/socket`. GLib main loop integration via `g_unix_fd_add()`.

---

## Environment

- **OS:** CachyOS (Arch-based)
- **Zig:** 0.15.2, **GTK4:** 4.20.3, **libadwaita:** 1.8.4
- **Project dir:** `/home/lighto/code/misc/cmux-try/`
- **Build:** `./build.sh` (wraps `zig build` with GCC SFrame + Python workarounds)
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

Latest commits (cove/main):
  eb1fe4a29 cove: Phase 3 — pin/unpin workspace via context menu
  ba58c85be cove: Phase 2 — jump to latest unread notification
  2ff58114f cove: Phase 2 — desktop notification suppression when focused
  fdfc5c98e cove: Phase 4 — CLI subcommands via Unix socket
  32bec15d4 cove: Phase 4 — socket protocol core commands
  da9d45180 cove: Phase 4 — Unix domain socket server
  f81e845bc cove: Phase 2 — unread badge on sidebar rows
  2ba44a530 cove: Phase 2 — hook libghostty notification actions into store
  e42df82e8 cove: Phase 3 — PWD tracking + path shortening in sidebar
  3afeb85bf cove: Phase 3 — git branch detection with 8 passing tests
  771a3710e cove: Phase 2 — create notification_store.zig with 13 passing tests
```

---

## Key Files

### Modified by Cove (potential rebase conflicts)
| File | Change |
|------|--------|
| `src/build/GhosttyExe.zig` | Binary name: `cove` |
| `src/apprt/gtk/App.zig` | App ID: `dev.cove.terminal` |
| `src/apprt/gtk/class/window.zig` | Sidebar + metadata + badges + pin + jump-to-unread (heaviest changes) |
| `src/apprt/gtk/ui/1.5/window.blp` | Full layout rewrite (GtkPaned + sidebar) |
| `src/apprt/gtk/css/style.css` | `.cove-sidebar`, `.cove-sidebar-badge`, `.cove-sidebar-subtitle` styles |
| `src/apprt/gtk/class/application.zig` | Resource path, notification hooks, socket server, storeNotification() |
| `src/apprt/gtk/build/gresource.zig` | Resource prefix/app_id |
| `src/cli/ghostty.zig` | Cove `+` subcommands registered in Action enum |

### Created by Cove (no conflicts)
```
README.md, THIRD_PARTY_LICENSES.md, build.sh, docs/
src/apprt/gtk/notification_store.zig   — per-workspace notification data (13 tests)
src/apprt/gtk/git_branch.zig           — git branch detection (8 tests)
src/apprt/gtk/path_shorten.zig         — path shortening for sidebar (9 tests)
src/apprt/gtk/socket_server.zig        — Unix domain socket server
src/apprt/gtk/socket_commands.zig      — JSON command dispatch (10 commands)
src/cli/cove_socket.zig                — CLI socket client (+ping, +list-workspaces, etc.)
```

### Never touched (zero conflict risk)
```
src/terminal/, src/renderer/, src/font/, src/input/, src/termio/, src/config/
src/apprt/gtk/winproto/, src/apprt/gtk/key.zig
```

---

## Zig API Notes (0.15.2)

Patterns discovered during implementation:
- **`std.mem.span()`** does not accept `[:0]const u8` — it's already a slice. Use directly.
- **`std.posix.accept()`** takes 4 args: `(sock, addr, addr_size, flags)` — flags include `SOCK.NONBLOCK | SOCK.CLOEXEC`.
- **`std.io.getStdErr()`** doesn't exist. Use `std.fs.File.stderr().writer(&buf)` then `&writer.interface`.
- **`glib.List`** has no iterator. Traverse manually: `node.f_data`, `node.f_next`.
- **`Action` struct** inside `application.zig` is a separate namespace from `Application`. Use `*Application` (not `*Self`) for methods there.
- **`gtk.Window.isActive()`** returns `c_int`, not `bool`. Compare `!= 0`.

---

## cmux Source Reference

Clone: `https://github.com/manaflow-ai/cmux` (cached at `/tmp/pi-github-repos/manaflow-ai/cmux/`)

| Feature | cmux File | Lines |
|---------|-----------|-------|
| Sidebar UI | `Sources/ContentView.swift` | ~8,800 |
| Workspace model | `Sources/Workspace.swift` | ~4,100 |
| Tab management | `Sources/TabManager.swift` | ~3,500 |
| Notifications | `Sources/TerminalNotificationStore.swift` | ~510 |
| Port scanning | `Sources/PortScanner.swift` | ~260 |
| Browser panel | `Sources/Panels/BrowserPanel.swift` | ~3,250 |
| Browser UI | `Sources/Panels/BrowserPanelView.swift` | ~3,700 |
| Session persistence | `Sources/SessionPersistence.swift` | ~470 |
| Socket/CLI | `CLI/cmux.swift` | ~5,400 |

---

## Build Workarounds

1. **GCC 15 SFrame linker error:** Zig's LLD fails on `R_X86_64_PC64` in `.sframe`. Fix: `objcopy --remove-section .sframe` on CRT objects, use `--libc` to point to patched dir.
2. **Conda Python override:** System Python 3.14 needed, not Conda's 3.12. Fix: `PATH=/usr/bin:...`.

Both handled by `build.sh`.

---

## Testing Strategy

**Phase 0/1:** No automated tests (95% GTK API calls). 57 manual tests, all passing.

**Phase 2/3 (current):** Inline unit tests in pure data modules:
- `notification_store.zig` — 13 tests (add, suppress, markRead, clearForTab, etc.)
- `git_branch.zig` — 8 tests (branch ref, detached HEAD, worktree, parent walk)
- `path_shorten.zig` — 9 tests (home replacement, deep truncation, edge cases)
- Run standalone: `zig test src/apprt/gtk/notification_store.zig` (etc.)
- Socket/CLI modules depend on GTK/GLib, can't run standalone.

**Phase 4+ (planned):** Integration tests via Python + Unix socket. CI with `xvfb-run`.

---

## Socket API Commands

Available via CLI (`cove +command`) or direct socket connection:

| Command | Args | Description |
|---------|------|-------------|
| `ping` | — | Connectivity test |
| `list-workspaces` | — | JSON list with id, title, pwd, git_branch, unread_count, selected |
| `new-workspace` | — | Create workspace, returns id |
| `close-workspace` | `id` | Close workspace |
| `select-workspace` | `id` | Switch to workspace |
| `rename-workspace` | `id`, `name` | Rename workspace |
| `list-notifications` | `id?` | List notifications (optionally filtered by workspace) |
| `mark-read` | `id?` | Mark read (workspace or all) |
| `notify` | `id`, `title`, `body?` | Inject notification |
| `jump-to-unread` | — | Jump to workspace with latest unread |

---

## Next Up

Highest-impact unblocked tasks:
1. **cove-21e** — Port scanner via /proc/net/tcp (unblocks: cove-mhz)
2. **cove-2ng** — Unit tests for socket protocol
3. **cove-3ps** — Python integration test framework (unblocks: 4 test tasks + CI)
4. **cove-imt.1** — Set COVE_* env vars in spawned shells
5. **cove-29l** — Session save/restore (Phase 6)
6. **cove-12j** — Add WebKitGTK dependency (Phase 5 entry point)

Phase completion:
- ✅ Phase 0: Repository & Build Foundation
- ✅ Phase 1: Vertical Sidebar
- ✅ Phase 2: Notification System (6/6)
- 🔄 Phase 3: Workspace Metadata & Sidebar UX (5/10)
- 🔄 Phase 4: Socket API & CLI (3/10)
- ⬚ Phase 5: Browser Panel (0/4)
- ⬚ Phase 6: Session Persistence (0/2)
