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

**Key architectural decisions:**
- **AdwTabView kept internally** — handles page ordering, close confirmation, drag-and-drop, signals. Sidebar is an additional navigation layer, not a replacement.
- **GObject class names unchanged** — `GhosttyApplication`, `GhosttyWindow`, etc. stay as-is. Only user-facing strings say "Cove". Minimizes rebase conflicts.
- **No vX.Y.Z tags** — Ghostty's `GitVersion.zig` panics on non-matching semver. Use `cove-*` prefix or no tags.
- **Sidebar rows store tab page ref** via `gobject.Object.setData("cove-tab-page", page)`.
- **Signal pattern:** Always `TypeName.signals.signal_name.connect(instance, DataType, &callback, data, .{})`. Never `TypeName.connectSignalName()`.

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
  e0ae72a56 cove: Phase 1d — double-click rename, reorder via context menu
  febc8fd98 cove: Phase 1d — close button, middle-click, context menu
  6363939c4 cove: Phase 1 — vertical sidebar replaces tab bar
  6816b450a cove: Phase 0 — rename to Cove, add attribution, set up repo
```

---

## Key Files

### Modified by Cove (potential rebase conflicts)
| File | Change |
|------|--------|
| `src/build/GhosttyExe.zig` | Binary name: `cove` |
| `src/apprt/gtk/App.zig` | App ID: `dev.cove.terminal` |
| `src/apprt/gtk/class/window.zig` | About dialog + sidebar (heaviest changes) |
| `src/apprt/gtk/ui/1.5/window.blp` | Full layout rewrite (GtkPaned + sidebar) |
| `src/apprt/gtk/css/style.css` | `.cove-sidebar` styles |
| `src/apprt/gtk/class/application.zig` | Resource path, notification title |
| `src/apprt/gtk/build/gresource.zig` | Resource prefix/app_id |

### Created by Cove (no conflicts)
```
README.md, THIRD_PARTY_LICENSES.md, build.sh, docs/
```

### Never touched (zero conflict risk)
```
src/terminal/, src/renderer/, src/font/, src/input/, src/termio/, src/config/
src/apprt/gtk/winproto/, src/apprt/gtk/key.zig
```

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
