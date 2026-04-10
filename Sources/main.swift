import Cocoa

// MARK: - Menu helpers

/// Convert an `NSEvent` function-key constant (e.g. `NSRightArrowFunctionKey`)
/// into a key-equivalent string. Returns `""` on failure so a malformed
/// constant degrades to "no shortcut" instead of crashing the app.
private func functionKeyEquivalent(_ functionKey: Int) -> String {
    Unicode.Scalar(functionKey).map { String($0) } ?? ""
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Menu bar
let mainMenu = NSMenu()

// App menu
let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "About Terminos", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
appMenu.addItem(NSMenuItem.separator())
appMenu.addItem(withTitle: "Quit Terminos", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu

// Shell menu
let shellMenuItem = NSMenuItem()
mainMenu.addItem(shellMenuItem)
let shellMenu = NSMenu(title: "Shell")
shellMenu.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t")
shellMenu.addItem(withTitle: "Close Tab", action: #selector(AppDelegate.closeTab(_:)), keyEquivalent: "w")
shellMenu.addItem(NSMenuItem.separator())
let nextTabItem = NSMenuItem(title: "Next Tab", action: #selector(AppDelegate.nextTab(_:)), keyEquivalent: functionKeyEquivalent(NSRightArrowFunctionKey))
nextTabItem.keyEquivalentModifierMask = [.command, .shift]
shellMenu.addItem(nextTabItem)
let prevTabItem = NSMenuItem(title: "Previous Tab", action: #selector(AppDelegate.prevTab(_:)), keyEquivalent: functionKeyEquivalent(NSLeftArrowFunctionKey))
prevTabItem.keyEquivalentModifierMask = [.command, .shift]
shellMenu.addItem(prevTabItem)
shellMenuItem.submenu = shellMenu

// Edit menu
let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu

app.mainMenu = mainMenu
app.run()
