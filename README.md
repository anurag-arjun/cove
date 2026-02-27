# Cove

A workspace-oriented terminal for Linux, built on [Ghostty](https://ghostty.org/)'s GTK frontend with features inspired by [cmux](https://cmux.dev/).

Cove adds a vertical sidebar, workspace management, notification system, and more on top of Ghostty's excellent terminal engine — bringing the workspace-first philosophy of cmux to Linux.

## Features

### Implemented

- **Vertical sidebar** with workspace list (replacing the traditional tab bar)
- **Workspace CRUD** — create, close, rename, reorder workspaces
- **Close button on hover** + middle-click to close
- **Right-click context menu** — Rename, Move Up/Down, Close
- **Double-click to rename** workspaces
- **Keyboard navigation** — Up/Down in sidebar, Enter to select, Ctrl+Tab/Alt+1-9 switching
- **Sidebar toggle** — button, menu entry, or hide completely
- **Full Ghostty terminal** — GPU-accelerated rendering, splits, search, Wayland/X11

### Planned

- **Notification rings** on sidebar badges when background processes finish
- **Workspace metadata** — git branch, working directory, listening ports
- **Socket API & CLI** for scripting (`cove +list-workspaces`, `cove +send`, etc.)
- **In-app browser** via WebKitGTK
- **Session persistence** across restarts

## Screenshot

```
┌─────────────────────────────────────────────────────────┐
│ ◀ Cove                                          ☰      │
├──────────────┬──────────────────────────────────────────┤
│ Workspaces + │                                          │
│──────────────│  ~/code/cove $ zig build                 │
│ ▶ zsh        │  Build succeeded.                        │
│   server     │  ~/code/cove $ _                         │
│   logs       │                                          │
│              │                                          │
│              │                                          │
│              │                                          │
└──────────────┴──────────────────────────────────────────┘
```

## Building

**Requirements:** Zig 0.15.2, GTK4 4.14+, libadwaita 1.4+, blueprint-compiler, pkgconf, pandoc, gettext

```bash
# Build
./build.sh

# Build and run
./build.sh run

# Run tests
zig build test
```

### Build Dependencies (Arch/CachyOS)

```bash
sudo pacman -S zig gtk4 libadwaita blueprint-compiler pkgconf pandoc gettext
```

## Configuration

Cove reads your existing Ghostty configuration from `~/.config/ghostty/config`. All terminal settings (fonts, colors, themes, keybinds) work as-is.

## Credits & Acknowledgments

Cove is built on the shoulders of two excellent projects:

### Ghostty

Cove's terminal engine — rendering, input handling, split panes, search, Wayland/X11 support — comes from [Ghostty](https://ghostty.org/) by Mitchell Hashimoto. Ghostty is a fast, feature-rich terminal emulator written in Zig with native GPU-accelerated rendering.

Cove is a fork of Ghostty's GTK frontend with a workspace-oriented UI added on top.

- Website: https://ghostty.org/
- Source: https://github.com/ghostty-org/ghostty
- License: MIT

### cmux

Cove's feature set — vertical sidebar, notification rings, workspace metadata, socket API, in-app browser — is inspired by [cmux](https://github.com/manaflow-ai/cmux) by Manaflow AI. cmux is a native macOS terminal built on libghostty with the same workspace-first philosophy. Cove brings these ideas to Linux.

- Website: https://cmux.dev/
- Source: https://github.com/manaflow-ai/cmux
- License: MIT

## License

Cove is licensed under the MIT License, consistent with both upstream projects. See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for details.
