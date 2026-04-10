import Foundation
import SwiftTerm

// MARK: - Shell Environment

func buildShellEnvironment() -> [String] {
    var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
    let userEnv = ProcessInfo.processInfo.environment
    for (key, value) in userEnv {
        if key == "TERM" || key == "COLORTERM" { continue }
        env.append("\(key)=\(value)")
    }
    return env
}

func defaultShell() -> String {
    ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
}
