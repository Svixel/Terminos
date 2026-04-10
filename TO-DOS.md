# Terminos - TO-DOS

## Interactive File Paths in Terminal - 2026-04-09 23:07

- **Implement clickable file paths** - Cmd-click file paths in terminal output to open/preview them. **Problem:** Terminal output contains file paths that aren't interactive; users must manually copy paths and open them elsewhere. **Files:** `Sources/main.swift` (subclass `LocalProcessTerminalView`), `.build/checkouts/SwiftTerm/Sources/SwiftTerm/Mac/MacTerminalView.swift` (reference for override points). **Solution:** Subclass `LocalProcessTerminalView`, override `mouseUp(with:)` and use `calculateMouseHit(with:)` to get grid position. Parse text at click as file path (match absolute `/`, `~/`, `./` paths). Route by type: images -> `NSPopover` preview, directories -> `cd`, others -> `NSWorkspace.open()`. Start with absolute paths only, expand detection later.
