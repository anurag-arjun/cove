# Cove

A workspace-oriented terminal for Linux, built on [Ghostty](https://ghostty.org/)'s GTK frontend with features inspired by [cmux](https://cmux.dev/).

Cove adds a vertical sidebar, workspace management, notification system, and more on top of Ghostty's excellent terminal engine — bringing the workspace-first philosophy of cmux to Linux.

## Features (Planned)

- **Vertical sidebar** with workspace list (replacing the traditional tab bar)
- **Notification rings** on sidebar badges when background processes finish
- **Workspace metadata** — git branch, working directory, listening ports
- **Socket API & CLI** for scripting (`cove +list-workspaces`, `cove +send`, etc.)
- **In-app browser** via WebKitGTK
- **Session persistence** across restarts

## Current State

Cove is in early development. The terminal engine (rendering, input, splits, search, Wayland/X11 support) is fully functional — inherited from Ghostty.

## Building

**Requirements:** Zig 0.15.2, GTK4, libadwaita, blueprint-compiler, pkgconf, pandoc, gettext

```bash
# Build
./build.sh

# Build and run
./build.sh run
```

## Configuration

Cove reads your existing Ghostty configuration from `~/.config/ghostty/config`. Cove-specific settings (sidebar width, notification preferences) will go in `~/.config/cove/config`.

## Credits & Acknowledgments

Cove is built on the shoulders of two excellent projects:

### Ghostty

Cove's terminal engine — rendering, input handling, split panes, search, Wayland/X11 support — comes from [Ghostty](https://ghostty.org/) by Mitchell Hashimoto. Ghostty is a fast, feature-rich terminal emulator written in Zig with native GPU-accelerated rendering.

Cove is a fork of Ghostty's GTK frontend with a workspace-oriented UI added on top. Ghostty is licensed under the MIT License.

- Website: https://ghostty.org/
- Source: https://github.com/ghostty-org/ghostty
- License: MIT

### cmux

Cove's feature set — vertical sidebar, notification rings, workspace metadata, socket API, in-app browser — is inspired by [cmux](https://github.com/manaflow-ai/cmux) by Manaflow AI. cmux is a native macOS terminal built on libghostty with the same workspace-first philosophy. Cove brings these ideas to Linux using Ghostty's GTK frontend.

- Website: https://cmux.dev/
- Source: https://github.com/manaflow-ai/cmux
- License: MIT

## License

Cove is licensed under the MIT License, consistent with both upstream projects. See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for details.
