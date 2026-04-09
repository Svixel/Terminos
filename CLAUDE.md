# Terminos

A native macOS terminal emulator built with Swift and SwiftTerm.

## Project Brief

**Goal**: Build a lightweight, native macOS terminal app that looks and feels like Terminal.app but adds developer-focused features on top.

### Phase 1 (current) -- Minimal Terminal
- Embedded terminal using SwiftTerm (LocalProcessTerminalView)
- Spawns the user's default shell as a login shell
- Native look and feel, standard keyboard shortcuts (Cmd+C/V/Q)
- Must be able to run Claude Code (interactive TUI apps)

### Phase 2 (planned) -- Server Dashboard
- Sidebar showing running servers (port, process name, PID)
- Auto-detect listening ports via `lsof`
- Show which app owns each port (Next.js, Vite, Express, etc.)
- Clickable to open in browser

### Phase 3 (planned) -- Multi-terminal
- Tabs / split panes
- Per-tab process tracking
- Named sessions

## Tech Stack
- **Language**: Swift 5.9+
- **UI**: AppKit (NSWindow, NSView)
- **Terminal**: SwiftTerm (LocalProcessTerminalView)
- **Build**: Swift Package Manager
- **Min OS**: macOS 13 (Ventura)

## Build & Run
```bash
swift build && .build/debug/Terminos
```

## Architecture
Single-file for now (`Sources/main.swift`). Will split into proper modules when complexity warrants it.
