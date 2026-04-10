import Cocoa
import SwiftTerm

// MARK: - Tab Model

class Tab {
    let id = UUID()
    let directory: String
    let terminalView: LocalProcessTerminalView
    var title: String

    init(directory: String) {
        self.directory = directory
        self.title = (directory as NSString).lastPathComponent
        self.terminalView = LocalProcessTerminalView(frame: .zero)

        // Configure terminal appearance
        terminalView.nativeForegroundColor = creamColor
        terminalView.nativeBackgroundColor = bgColor
        terminalView.layer?.backgroundColor = bgColor.cgColor
        terminalView.font = terminalFont

        // Hide the scrollbar visually but keep the NSScroller in the hierarchy so
        // SwiftTerm's wheel/trackpad scrolling continues to work. Setting isHidden
        // would remove it from event routing in some configurations.
        for subview in terminalView.subviews {
            if subview is NSScroller {
                subview.alphaValue = 0
            }
        }

        // Start shell
        let shell = defaultShell()
        terminalView.startProcess(
            executable: shell,
            args: ["-l"],
            environment: buildShellEnvironment(),
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: directory
        )
    }

    func sendCommand(_ command: String) {
        // Small delay to let the shell initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let bytes = Array((command + "\n").utf8)
            self.terminalView.send(source: self.terminalView, data: bytes[...])
        }
    }

    func terminate() {
        terminalView.terminate()
    }
}

// MARK: - Tab Manager

class TabManager {
    private(set) var tabs: [Tab] = []
    private(set) var activeIndex: Int = -1

    var activeTab: Tab? {
        guard activeIndex >= 0, activeIndex < tabs.count else { return nil }
        return tabs[activeIndex]
    }

    func createTab(directory: String) -> Tab {
        let tab = Tab(directory: directory)
        tabs.append(tab)
        activeIndex = tabs.count - 1
        return tab
    }

    func closeTab(at index: Int) -> Tab? {
        guard index >= 0, index < tabs.count else { return nil }
        let tab = tabs.remove(at: index)
        tab.terminate()
        if tabs.isEmpty {
            activeIndex = -1
        } else if activeIndex >= tabs.count {
            activeIndex = tabs.count - 1
        }
        return tab
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeIndex = index
    }
}
