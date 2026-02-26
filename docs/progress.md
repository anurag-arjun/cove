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

### ✅ Done
- [x] Analyzed cmux macOS codebase (~65K lines Swift, AppKit/Metal/libghostty)
- [x] Analyzed Ghostty GTK frontend architecture (~18K lines Zig)
- [x] Mapped cmux features → Zig/GTK equivalents (see spike docs)
- [x] Identified libghostty C API surface (ghostty.h) and action system
- [x] Confirmed WebKitGTK 6.0 is mature for in-app browser (P2)
- [x] Confirmed Ghostty MIT license allows forking
- [x] Cloned Ghostty repo into `/home/lighto/code/misc/cmux-try/`
- [x] Confirmed CachyOS has Zig 0.15.2 (exact version needed by `build.zig.zon`)
- [x] Installed all build dependencies on CachyOS

### 🟡 Verified Dependencies (2026-02-26)
All required packages confirmed installed via pacman:
| Package | Version |
|---------|---------|
| zig | 0.15.2 |
| gtk4 | 4.20.3 |
| libadwaita | 1.8.4 |
| blueprint-compiler | 0.18.0 |
| pkgconf | 2.5.1 |
| pandoc-cli | 3.5 |
| gettext | 1.0 |

### ✅ First Build (2026-02-26)
Ghostty builds and runs on CachyOS. Two workarounds needed:

1. **GCC 15 SFrame linker issue:** Zig's LLD and self-hosted linker can't handle `R_X86_64_PC64` relocations in GCC 15's CRT objects (`.sframe` sections). Fix: `objcopy --remove-section=.sframe` on `crt1.o`/`crti.o`/`crtn.o`, then use `--libc` flag pointing to patched CRT dir.
2. **Conda Python conflict:** `blueprint-compiler` uses `#!/usr/bin/env python3` which picks up conda's Python 3.12 (missing `gi` module) instead of system Python 3.14. Fix: override `PATH=/usr/bin:...` during build.

Both workarounds are encapsulated in `./build.sh`:
```bash
./build.sh          # build only
./build.sh run      # build + run
```

### 🔲 Next: Phase 0 — Repository & Attribution
- [ ] Rename project to **Cove** (binary: `cove`, app ID: `dev.cove.terminal`)
- [ ] Write `README.md` with credits for Ghostty and cmux
- [ ] Write `THIRD_PARTY_LICENSES.md`
- [ ] Set up GitHub repo and branch structure (see plan.md)

### 🔲 Not Started
- [ ] Phase 1: Vertical sidebar (replace AdwTabBar)
- [ ] Phase 2: Notification system
- [ ] Phase 3: Workspace metadata (git branch, ports, pwd)
- [ ] Phase 4: Socket API & CLI
- [ ] Phase 5: Browser panel (WebKitGTK)
- [ ] Phase 6: Session persistence

---

## Implementation Plan

**Full detail in [plan.md](plan.md).** Summary:

| Phase | Feature | Est. Lines | Timeline |
|-------|---------|-----------|----------|
| 0 | Repo, build, README, attribution | 100 | Day 1 |
| 1 | Vertical sidebar (replace AdwTabBar) | 1,700 | Week 1–2 |
| 2 | Notification system | 400 | Week 2–3 |
| 3 | Workspace metadata (git, ports, pwd) | 600 | Week 3–4 |
| 4 | Socket API & CLI (`cove +cmd`) | 2,500 | Week 4–6 |
| 5 | Browser panel (WebKitGTK) | 2,000 | Week 6–8 |
| 6 | Session persistence | 500 | Week 8–9 |

---

## Key Files Reference

### Ghostty GTK files we'll heavily modify
| File | Lines | Role |
|------|-------|------|
| `src/apprt/gtk/class/window.zig` | 2,071 | Main window — sidebar goes here |
| `src/apprt/gtk/class/application.zig` | 2,790 | Action dispatch — notification handling |
| `src/apprt/gtk/class/tab.zig` | 570 | Becomes "workspace" |
| `src/apprt/gtk/ui/1.5/window.blp` | ~250 | Window Blueprint — new layout |

### Ghostty GTK files we keep as-is
| File | Lines | Role |
|------|-------|------|
| `src/apprt/gtk/class/surface.zig` | 3,974 | Terminal widget (GLArea + input) |
| `src/apprt/gtk/class/split_tree.zig` | 1,241 | Split pane management |
| `src/apprt/gtk/class/search_overlay.zig` | 493 | Find-in-terminal |
| `src/apprt/gtk/key.zig` | 535 | Keyboard translation |
| `src/apprt/gtk/winproto/` | ~300 | Wayland/X11 protocol |
| `src/renderer/OpenGL.zig` | — | GPU renderer |

### cmux macOS files for feature reference
| Feature | cmux Swift file | Lines |
|---------|----------------|-------|
| Tab/workspace management | `Sources/TabManager.swift` | 3,473 |
| Notifications | `Sources/TerminalNotificationStore.swift` | 512 |
| Session save/restore | `Sources/SessionPersistence.swift` | 474 |
| Workspace model | `Sources/Workspace.swift` | 4,121 |
| Sidebar + main UI | `Sources/ContentView.swift` | 8,843 |
| Socket API | `CLI/cmux.swift` + `Sources/TerminalController.swift` | 5,414 |
| Browser panel | `Sources/Panels/BrowserPanel.swift` | ~2,000 |

---

## Environment

- **OS:** CachyOS (Arch-based)
- **Zig:** 0.15.2 (from `cachyos-extra-v3`)
- **GTK4:** via pacman
- **Project dir:** `/home/lighto/code/misc/cmux-try/`
- **Upstream:** `https://github.com/ghostty-org/ghostty` (cloned, not forked on GitHub yet)

---

## Notes

- The cmux macOS source was previously cloned to this directory for analysis, then cleaned. The original repo is at `https://github.com/manaflow-ai/cmux` and a cached clone exists at `/tmp/pi-github-repos/manaflow-ai/cmux/`.
- Ghostty's GTK frontend is in `src/apprt/gtk/`. The macOS frontend is in `macos/` (irrelevant for us).
- libghostty's C header is at `include/ghostty.h` — but we use the Zig module interface directly (same as Ghostty's GTK frontend does).
- Both Ghostty and cmux are MIT licensed. No conflicts.

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

**What was NOT done:**
- No source modifications made — repo is stock Ghostty

**Next actions (in order):**
1. ~~Run `zig build run` to verify Ghostty builds and runs on CachyOS~~ ✅ Done
2. Phase 0: set up repo as "Cove", write README with Ghostty/cmux credits, create GitHub repo
3. Begin Phase 1: create sidebar widget, modify `window.zig` to replace `AdwTabBar` with `GtkPaned` + sidebar

### Session 2026-02-26 (cont.) — First Build Successful

**Build issues encountered and resolved:**
1. **GCC 15 SFrame linker error** (`R_X86_64_PC64` in `crt1.o:.sframe`): Zig 0.15's LLD *and* self-hosted linker both fail. `-Dcpu=baseline` and `use_lld=false` don't help. Fix: strip `.sframe`/`.rela.sframe` from CRT objects via `objcopy`, use `--libc` to point Zig to patched CRT dir.
2. **Conda Python 3.12 vs system Python 3.14**: `blueprint-compiler` uses `#!/usr/bin/env python3` → finds conda python without `gi` module → silent crash. Fix: `PATH=/usr/bin:...` override.

**Created:** `build.sh` — wrapper script encapsulating both workarounds.

**Verified:** Ghostty launches on Wayland (KDE/CachyOS), detects OpenGL 4.6, starts fish shell, renders terminal.

### Session 2026-02-26 (cont.) — Naming & Plan Finalized

**Decisions:**
1. **Project renamed to "Cove"** — `cmux` is Manaflow AI's brand (cmux.dev, GitHub, Homebrew). Using it for an unofficial Linux port would be confusing/problematic. "Cove" is short, unique, no conflicts.
2. **Binary:** `cove`, **App ID:** `dev.cove.terminal`, **Socket:** `$XDG_RUNTIME_DIR/cove/socket`
3. **Attribution required:** README must prominently credit Ghostty (terminal engine) and cmux (feature inspiration). `THIRD_PARTY_LICENSES.md` with verbatim MIT licenses.
4. **Git strategy:** `upstream` remote tracks `ghostty-org/ghostty`, `origin` is our repo. `cove/main` branch for our work, `main` tracks upstream exactly. Rebase weekly, never merge. Commits prefixed `cove:`.
5. **Ghostty config compatibility:** Cove reads `~/.config/ghostty/config`. Cove-specific settings go in `~/.config/cove/config`.

**Created:** `docs/plan.md` — comprehensive build plan (naming, attribution, git strategy, 7 phases, risk register, file impact map).

**Next:** Phase 0 — create GitHub repo, README, THIRD_PARTY_LICENSES.md, rename binary

### Session 2026-02-26 (cont.) — Session State Snapshot

**Summary of all sessions today:** Three sessions covering research → first build → naming/planning.

**All key decisions (consolidated):**
1. Fork Ghostty's GTK frontend (Strategy 2) — not a from-scratch rewrite
2. Project name: **Cove** (not cmux — that's Manaflow AI's brand)
3. Binary: `cove`, App ID: `dev.cove.terminal`
4. Git: rebase-only workflow, `cove/main` branch, `cove:` commit prefix
5. Must credit Ghostty (engine) and cmux (inspiration) prominently in README
6. Reads `~/.config/ghostty/config` for terminal settings, `~/.config/cove/config` for Cove-specific

**All work products:**
- `docs/spike-strategy1-gtk4-rewrite.md` — research spike (GTK4 rewrite option)
- `docs/spike-strategy2-ghostty-fork.md` — research spike (Ghostty fork option, chosen)
- `docs/plan.md` — full build plan (naming, attribution, git strategy, 7 phases, risk register, file map)
- `docs/progress.md` — this file
- `build.sh` — build wrapper (CachyOS SFrame + conda Python workarounds)
- `crt-patched/` — patched CRT objects for GCC 15 compatibility (gitignored)

**Repo state:** Stock Ghostty at commit `74ba971eb` (v1.3.0-dev). No source modifications. Builds and runs via `./build.sh run`.

**Next actions (in order):**
1. **Phase 0:** Create GitHub repo `cove`, set up remotes + branch structure
2. **Phase 0:** Write `README.md` (project description + Ghostty/cmux credits)
3. **Phase 0:** Write `THIRD_PARTY_LICENSES.md` (verbatim MIT licenses)
4. **Phase 0:** Rename binary from `ghostty` to `cove` in build system, update app ID
5. **Phase 0:** Commit everything, tag `v0.0.1-scaffold`
6. **Phase 1:** Begin vertical sidebar implementation
