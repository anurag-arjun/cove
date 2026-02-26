# Research Spike: Strategy 1 — GTK4 Rewrite

> Build a new Linux app from scratch using GTK4/Adwaita + libghostty, reimplementing cmux's features.

---

## 1. libghostty C Embedding API Analysis

The `ghostty.h` header (~850 lines) exposes a clean, platform-agnostic C API. Key observations:

### API Surface

| Category | Functions | Notes |
|----------|-----------|-------|
| **Init** | `ghostty_init()` | Global init, called once |
| **Config** | `ghostty_config_new/free/clone/get/finalize`, `ghostty_config_load_*` | Loads `~/.config/ghostty/config` automatically |
| **App** | `ghostty_app_new/free/tick/set_focus/key/update_config` | App is the top-level container |
| **Surface** | `ghostty_surface_new/free/draw/refresh/set_size/set_focus` | Each surface = one terminal instance |
| **Input** | `ghostty_surface_key/text/preedit/mouse_button/mouse_pos/mouse_scroll` | Full input pipeline |
| **Clipboard** | Read/write clipboard callbacks via `ghostty_runtime_config_s` | Consumer implements clipboard |
| **Selection** | `ghostty_surface_has_selection/read_selection/read_text` | Text extraction |
| **Actions** | 60+ action types via `ghostty_action_tag_e` | Splits, tabs, notifications, search, etc. |

### Platform Abstraction

The `ghostty_surface_config_s` has a `platform_tag` and `platform` union:
```c
typedef enum {
  GHOSTTY_PLATFORM_INVALID,
  GHOSTTY_PLATFORM_MACOS,
  GHOSTTY_PLATFORM_IOS,
} ghostty_platform_e;
```

**Critical finding:** There is NO `GHOSTTY_PLATFORM_LINUX` in the enum. However, Ghostty's GTK frontend doesn't use this C header at all — it links to libghostty as a Zig library directly, bypassing the C API. The C header is specifically for the macOS/Swift consumer.

### Runtime Callbacks

The consumer must provide these callbacks in `ghostty_runtime_config_s`:
- `wakeup_cb` — wake the event loop
- `action_cb` — handle 60+ action types (notifications, title changes, splits, etc.)
- `read_clipboard_cb` / `write_clipboard_cb` — clipboard access
- `confirm_read_clipboard_cb` — security prompt for OSC 52
- `close_surface_cb` — surface wants to close

### Key Actions for cmux Features

| cmux Feature | Ghostty Action |
|-------------|----------------|
| Desktop notifications | `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` (has title + body) |
| Tab title | `GHOSTTY_ACTION_SET_TITLE` |
| Working directory | `GHOSTTY_ACTION_PWD` |
| Bell/ring | `GHOSTTY_ACTION_RING_BELL` |
| Child process exit | `GHOSTTY_ACTION_SHOW_CHILD_EXITED` (has exit code + duration) |
| Command finished | `GHOSTTY_ACTION_COMMAND_FINISHED` (exit code + duration) |
| Progress | `GHOSTTY_ACTION_PROGRESS_REPORT` (state + percentage) |
| Splits | `GHOSTTY_ACTION_NEW_SPLIT`, `GHOSTTY_ACTION_GOTO_SPLIT` |
| Config reload | `GHOSTTY_ACTION_RELOAD_CONFIG`, `GHOSTTY_ACTION_CONFIG_CHANGE` |
| Color changes | `GHOSTTY_ACTION_COLOR_CHANGE` (fg/bg/cursor + RGB) |

**Verdict:** The action system already delivers everything cmux needs for notifications, title tracking, PWD tracking, and progress — the consumer just needs to handle them in `action_cb`.

---

## 2. How cmux Uses libghostty (GhosttyTerminalView.swift)

cmux's integration lives primarily in `GhosttyTerminalView.swift` (~3,900 lines). Key patterns:

### Initialization Flow
1. Call `ghostty_init()` once
2. Create config: `ghostty_config_new()` → loads user config → `ghostty_config_finalize()`
3. Set up `ghostty_runtime_config_s` with callbacks
4. Create app: `ghostty_app_new(&runtimeConfig, config)`
5. For each terminal: `ghostty_surface_new(app, &surfaceConfig)`

### Rendering (macOS-specific)
- Uses **Metal + IOSurface** for GPU rendering
- `ghostty_surface_draw()` triggers rendering to an IOSurface
- The IOSurface is displayed via a `CALayer` in the NSView
- This is completely macOS-specific and **not relevant for Linux**

### The Ghostty GTK frontend uses a completely different renderer
- **OpenGL via `GtkGLArea`** widget
- `ghostty_surface_draw()` renders to the GLArea's framebuffer
- This is the proven Linux rendering path

### Input Forwarding
- Keyboard: Convert native key events → `ghostty_input_key_s` → `ghostty_surface_key()`
- Mouse: `ghostty_surface_mouse_button/pos/scroll()`
- Text/IME: `ghostty_surface_text()` / `ghostty_surface_preedit()`
- Mods: Uses W3C-style key codes (GHOSTTY_KEY_A, etc.) — platform-independent

### Action Handling
The `action_cb` receives a target (app or surface) + action. cmux handles:
- `GHOSTTY_ACTION_DESKTOP_NOTIFICATION` → feeds `TerminalNotificationStore`
- `GHOSTTY_ACTION_SET_TITLE` → updates sidebar tab titles
- `GHOSTTY_ACTION_PWD` → updates working directory display
- `GHOSTTY_ACTION_COLOR_CHANGE` → syncs window chrome colors
- `GHOSTTY_ACTION_NEW_SPLIT` → creates split panes via Bonsplit
- `GHOSTTY_ACTION_RING_BELL` → notification ring animation

---

## 3. Ghostty's GTK4 Frontend (Reference Implementation)

Ghostty already has a working GTK4 Linux frontend. Key findings:

### Architecture (~18K lines Zig)
```
src/apprt/gtk/
├── App.zig              (99 lines)  — Application entry, wraps GObject Application
├── Surface.zig          (103 lines) — Thin bridge to GObject Surface  
├── class/
│   ├── application.zig  (2,790 lines) — GtkApplication subclass, action handling
│   ├── window.zig       (2,071 lines) — AdwApplicationWindow, tabs, headerbar
│   ├── tab.zig          (570 lines)   — Tab widget (horizontal tabs via AdwTabView)
│   ├── surface.zig      (3,974 lines) — Terminal surface, GLArea, input, clipboard
│   ├── split_tree.zig   (1,241 lines) — Split pane management
│   └── ...dialogs, overlays, search, etc.
├── ui/                  — Blueprint UI files (.blp)
│   ├── 1.5/window.blp   — Window layout with AdwTabBar, headerbar, menus
│   └── ...
└── winproto/            — Wayland/X11 protocol handling
```

### Key Widgets Used
- **`AdwApplicationWindow`** — Main window (libadwaita)
- **`AdwTabView` + `AdwTabBar`** — Horizontal tab management  
- **`AdwTabOverview`** — Tab overview grid
- **`GtkGLArea`** — OpenGL rendering surface for terminal
- **`AdwHeaderBar`** — Native GNOME header bar
- **Blueprint files** — Declarative UI (compiled at build time)

### How Ghostty Renders on Linux
From `class/surface.zig`:
- Each terminal surface has a `GtkGLArea`
- `gl_area.queueRender()` triggers redraws
- `gl_area.makeCurrent()` + OpenGL calls for actual rendering
- Content scale from `gtk.Widget.getScaleFactor()` for HiDPI

### What Ghostty GTK DOESN'T Have (= what cmux adds)
- ❌ Vertical sidebar with workspace tabs
- ❌ Notification rings/badges on tabs
- ❌ Notification panel
- ❌ Git branch / PR status in sidebar
- ❌ Working directory / listening ports display
- ❌ In-app browser
- ❌ Socket API for scripting
- ❌ Session persistence with scrollback
- ❌ Workspace concept (tabs within tabs)

---

## 4. GTK4 Rendering: How to Display libghostty Output

### Option A: Use libghostty's OpenGL Renderer via GtkGLArea ✅ (Proven)

This is exactly what Ghostty does. The OpenGL renderer in `src/renderer/OpenGL.zig` renders terminal content into a GL framebuffer, and `GtkGLArea` displays it.

- **Proven path** — Ghostty ships this today
- **GPU-accelerated** — same performance as Ghostty
- **Requires linking libghostty as a Zig library** (not the C API)

### Option B: Use the C Embedding API + Custom GL Widget

If building a non-Zig app (Rust, C, etc.):
1. Create a `GtkGLArea` widget
2. On `realize`: initialize OpenGL context, call `ghostty_surface_new()`
3. On `render`: call `ghostty_surface_draw()` (renders to current GL context)
4. Forward GTK input events → ghostty input functions

**Problem:** The C API's `ghostty_surface_draw()` expects to render into the current context, but the OpenGL renderer details (shaders, buffers) are internal to libghostty. The C API may not expose enough to use the OpenGL renderer from an external consumer.

**Current reality:** The C API is designed for macOS (Metal/IOSurface). For Linux, you'd need to either:
- Use libghostty as a Zig library (like Ghostty does)
- Or extend the C API to support OpenGL contexts (significant work)

### Option C: Use libghostty-vt (Terminal State Only) + Own Renderer

Ghostty is developing `libghostty-vt` — a standalone VT parser/state library:
- Available for C, Zig, and WASM
- Handles escape sequences, terminal state, screen buffer
- You'd need your own OpenGL/Vulkan renderer for the actual display

**Too much work** for our purposes — we'd be reimplementing the entire renderer.

### Verdict: Option A is the only practical path

This means the core terminal widget must be written in Zig (or tightly linked to Zig-built libghostty). The UI shell around it can be in any GTK4-compatible language.

---

## 5. Language Choice for the GTK4 App

### Option: Zig (extend Ghostty's GTK code) ⭐ RECOMMENDED

**Pros:**
- libghostty is Zig — zero FFI overhead, direct access to internals
- Ghostty's GTK frontend is already Zig — proven patterns to follow
- GObject/GTK bindings work well in Ghostty's codebase
- Single language for everything
- Comptime + manual memory = terminal-grade performance

**Cons:**
- Zig ecosystem is immature (no package manager stability yet)
- Steep learning curve if team doesn't know Zig
- Blueprint UI files must be compiled with `blueprint-compiler`

### Option: Rust (gtk4-rs) 

**Pros:**
- `gtk4-rs` is mature and well-maintained
- Strong type safety, great tooling (cargo, rust-analyzer)
- WebKitGTK Rust bindings exist
- Large community

**Cons:**
- FFI to libghostty (C or Zig) adds complexity
- Need to solve the OpenGL rendering bridge (Option B above — unclear if possible)
- Two build systems (cargo + zig build)

### Option: C

**Pros:**
- Native GTK4 language, zero abstraction overhead
- Easiest FFI to libghostty's C API

**Cons:**
- Manual memory management without Zig's safety features
- Verbose for complex UI logic (cmux has 65K lines of Swift logic)
- Same C API limitations as Rust

### Option: Python (PyGObject)

**Cons:** Too slow for a terminal emulator. Ruled out.

### Option: Vala

**Pros:** Nice GObject syntax, compiles to C
**Cons:** Small community, hard to FFI with Zig

### Verdict: Zig is the clear winner

Using Zig means we can directly use libghostty's internals (the Zig module interface, not just the C API), use the proven OpenGL renderer, and follow Ghostty's existing GTK patterns. Any other language hits the wall of "how do I render libghostty output in a GtkGLArea?"

---

## 6. WebKitGTK for In-App Browser

### Status: Mature and Ready ✅

- **API:** `webkitgtk-6.0` (not `webkit2gtk-4.x` which is GTK3)
- **Latest release:** WebKitGTK 2.50.5 (Feb 2026)
- **Features:** Full WebKit engine, developer tools, JavaScript API
- **Sandboxing:** Mandatory in 6.0 (good for security)
- **Dependencies:** libsoup 3 (required)

### Integration Pattern
```
// Pseudocode
webkit_web_view = webkit_web_view_new()
gtk_paned_set_end_child(split, webkit_web_view)
```

WebKitGTK is a standard GTK4 widget — it drops into any container. The cmux browser features (navigate, snapshot, JS eval, cookie API) map directly to WebKitGTK's C API.

### cmux Browser Feature Mapping

| cmux Feature | WebKitGTK Equivalent |
|-------------|---------------------|
| Navigate to URL | `webkit_web_view_load_uri()` |
| Back/Forward | `webkit_web_view_go_back/forward()` |
| JS evaluation | `webkit_web_view_evaluate_javascript()` |
| Page title | `notify::title` signal |
| Dev tools | `webkit_web_inspector_show()` |
| Screenshots | `webkit_web_view_get_snapshot()` |
| Cookies | `WebKitCookieManager` API |

---

## 7. Build System & Dependencies for CachyOS/Arch

### Required Packages
```bash
sudo pacman -S zig gtk4 libadwaita webkit2gtk-5.0 blueprint-compiler \
               pkgconf pandoc-cli gettext
```

Note: `webkit2gtk-5.0` is the Arch package name for webkitgtk-6.0 API.

### Build System
Zig build system (`build.zig`) — same as Ghostty. Would need to:
1. Build libghostty (Zig library)
2. Compile Blueprint UI files
3. Compile GResources
4. Link everything together

### CachyOS-Specific Caveat
CachyOS ships modified glibc with SFrame support. Zig's linker sometimes chokes on this. Workaround: build with `--system-compiler` flag or in a clean chroot. Ghostty users on CachyOS have reported this and documented fixes.

---

## 8. Feature Complexity Assessment

| cmux Feature | Lines (Swift) | GTK4/Zig Complexity | Priority |
|-------------|--------------|-------------------|----------|
| **Terminal rendering** | ~3,900 | Already done (copy from Ghostty GTK) | P0 |
| **Vertical sidebar** | ~1,200 | Medium — custom GtkListBox or GtkColumnView | P0 |
| **Workspace/tab management** | ~3,500 | Medium — data model + sidebar sync | P0 |
| **Notification system** | ~500 | Low — handle action_cb + libnotify | P0 |
| **Split panes** | ~1,200 (Bonsplit) | Medium — GtkPaned or port Bonsplit | P1 |
| **Socket API / CLI** | ~5,400 | Medium-High — Unix socket server | P1 |
| **Session persistence** | ~475 | Low — JSON save/restore | P2 |
| **In-app browser** | ~6,000+ | High — WebKitGTK integration | P2 |
| **Settings UI** | ~2,000 | Medium — AdwPreferencesWindow | P3 |
| **Auto-update** | ~2,000 | Not needed (pacman/AUR) | Skip |

---

## 9. Architectural Plan

```
cmux-linux/
├── build.zig              — Build system
├── src/
│   ├── main.zig           — Entry point
│   ├── app.zig            — GtkApplication, window management
│   ├── window.zig         — Main window with sidebar + content
│   ├── sidebar/
│   │   ├── sidebar.zig    — Vertical sidebar widget
│   │   ├── workspace_row.zig — Single workspace entry (title, branch, badge)
│   │   └── notification_panel.zig
│   ├── workspace/
│   │   ├── workspace.zig  — Workspace (= cmux Tab) data model
│   │   ├── manager.zig    — Workspace CRUD, selection, reordering
│   │   └── content.zig    — Workspace content area (splits + panels)
│   ├── terminal/
│   │   ├── surface.zig    — Copy from Ghostty's surface.zig + customizations
│   │   └── panel.zig      — Terminal panel wrapper
│   ├── browser/
│   │   ├── panel.zig      — WebKitGTK browser panel
│   │   └── omnibar.zig    — Address bar
│   ├── notifications/
│   │   ├── store.zig      — Notification state management
│   │   └── desktop.zig    — libnotify integration
│   ├── socket/
│   │   ├── server.zig     — Unix domain socket server
│   │   └── commands.zig   — Command parsing and dispatch
│   ├── session/
│   │   └── persistence.zig — JSON save/restore
│   └── config.zig         — Ghostty config + cmux-specific config
├── ui/
│   ├── window.blp         — Main window Blueprint
│   ├── sidebar.blp        — Sidebar Blueprint
│   └── ...
└── resources/
    └── cmux.gresource.xml
```

---

## 10. Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| libghostty internals change | High | Pin to specific Ghostty commit, track upstream |
| Zig breaking changes | Medium | Pin Zig version, same as Ghostty does |
| CachyOS linker issues | Low | Document workarounds, test in CI |
| WebKitGTK complexity | Medium | Defer browser to P2, ship terminal-only first |
| Rendering differences | Low | Using same OpenGL renderer as Ghostty |
| Performance parity | Low | Same Zig + OpenGL path, should be identical |

---

## 11. Summary

**Strategy 1 is viable and architecturally clean.** The key insight is:

1. **libghostty + OpenGL rendering is proven on Linux** via Ghostty's GTK frontend
2. **Must use Zig** to access libghostty's Zig module interface (the C API alone isn't sufficient for Linux rendering)
3. **GTK4 + libadwaita** provides all needed widgets (sidebar, tabs, paned, WebKitGTK)
4. **cmux's core value (notifications + sidebar)** maps cleanly to Ghostty's existing action system
5. **In-app browser** is feasible via WebKitGTK 6.0

The main difference from Strategy 2 is: Strategy 1 builds a *new* GTK app that *uses* libghostty, while Strategy 2 *modifies* Ghostty's existing GTK app. In practice, since we must use Zig and Ghostty's GTK patterns anyway, Strategy 1 converges toward "write new Zig GTK code that heavily references Ghostty's GTK code" — which is very similar to Strategy 2 but with a cleaner separation.
