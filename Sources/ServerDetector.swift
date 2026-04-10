import Foundation

// MARK: - Server Detection

struct ServerInfo: Equatable {
    let port: Int
    let pid: Int32
    let processName: String
    let friendlyName: String
    /// Working directory of the listening process, resolved via `lsof -d cwd`.
    /// Nil if the lookup failed or the process has no cwd. Used to associate a
    /// running server with a project folder in the sidebar.
    let cwd: String?

    static func == (lhs: ServerInfo, rhs: ServerInfo) -> Bool {
        lhs.port == rhs.port && lhs.pid == rhs.pid
    }
}

class ServerDetector {
    var onServersChanged: (([ServerInfo]) -> Void)?

    private var timer: DispatchSourceTimer?
    private var lastServers: [ServerInfo] = []
    private let backgroundQueue = DispatchQueue(label: "server-detector", qos: .utility)

    private let ignoredProcesses: Set<String> = [
        "rapportd", "ControlCe", "mDNSResponder", "launchd",
        "sharingd", "AirPlayXPCHelper", "WiFiAgent", "bluetoothd"
    ]

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: backgroundQueue)
        timer.schedule(deadline: .now(), repeating: 5.0)
        timer.setEventHandler { [weak self] in self?.scan() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func scan() {
        let lsofOutput = runCommand("/usr/sbin/lsof", args: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])

        var seenPorts = Set<Int>()
        var rawEntries: [(pid: Int32, processName: String, port: Int)] = []

        for line in lsofOutput.split(separator: "\n").dropFirst() {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            guard cols.count >= 9 else { continue }

            let processName = String(cols[0])
            guard !ignoredProcesses.contains(processName) else { continue }
            guard let pid = Int32(cols[1]) else { continue }

            // lsof appends "(LISTEN)" as its own whitespace-separated column, so the
            // address (e.g. "127.0.0.1:5174", "*:3000", "[::1]:5432") sits second-to-last.
            let name = String(cols[cols.count - 2])
            guard let colonIdx = name.lastIndex(of: ":"),
                  let port = Int(name[name.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)),
                  port >= 1024 else { continue }

            guard !seenPorts.contains(port) else { continue }
            seenPorts.insert(port)
            rawEntries.append((pid, processName, port))
        }

        var pidArgs: [Int32: String] = [:]
        for pid in Set(rawEntries.map(\.pid)) {
            pidArgs[pid] = runCommand("/bin/ps", args: ["-p", "\(pid)", "-o", "args="]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Batch cwd lookup: one lsof call for every PID we care about. The -Fn output
        // groups fields by process record (lines starting with `p`), followed by a
        // single `fcwd` descriptor and its `n` (path) field.
        var pidCwds: [Int32: String] = [:]
        let uniquePids = Set(rawEntries.map(\.pid))
        if !uniquePids.isEmpty {
            let pidsArg = uniquePids.map(String.init).joined(separator: ",")
            let cwdOutput = runCommand("/usr/sbin/lsof", args: ["-a", "-d", "cwd", "-Fn", "-p", pidsArg])
            var currentPid: Int32?
            for line in cwdOutput.split(separator: "\n") {
                let s = String(line)
                if s.hasPrefix("p") {
                    currentPid = Int32(s.dropFirst())
                } else if s.hasPrefix("n"), let pid = currentPid {
                    pidCwds[pid] = String(s.dropFirst())
                }
            }
        }

        let servers = rawEntries.map { entry -> ServerInfo in
            let args = pidArgs[entry.pid] ?? ""
            let friendly = identifyFramework(processName: entry.processName, args: args)
            return ServerInfo(
                port: entry.port,
                pid: entry.pid,
                processName: entry.processName,
                friendlyName: friendly,
                cwd: pidCwds[entry.pid]
            )
        }.sorted { $0.port < $1.port }

        if servers != lastServers {
            lastServers = servers
            DispatchQueue.main.async { [weak self] in
                self?.onServersChanged?(servers)
            }
        }
    }

    private func identifyFramework(processName: String, args: String) -> String {
        let argsLower = args.lowercased()
        switch processName {
        case "node":
            if argsLower.contains("next") { return "Next.js" }
            if argsLower.contains("vite") { return "Vite" }
            if argsLower.contains("nuxt") { return "Nuxt" }
            if argsLower.contains("remix") { return "Remix" }
            if argsLower.contains("express") { return "Express" }
            if argsLower.contains("firebase") { return "Firebase" }
            if argsLower.contains("astro") { return "Astro" }
            if argsLower.contains("webpack-dev-server") || argsLower.contains("react-scripts") { return "React" }
            return "Node"
        case "python", "python3":
            if argsLower.contains("flask") { return "Flask" }
            if argsLower.contains("django") || argsLower.contains("manage.py") { return "Django" }
            if argsLower.contains("uvicorn") || argsLower.contains("fastapi") { return "FastAPI" }
            return "Python"
        case "ruby":
            if argsLower.contains("rails") { return "Rails" }
            return "Ruby"
        case "php":
            if argsLower.contains("artisan") { return "Laravel" }
            return "PHP"
        case "java":
            if argsLower.contains("spring") { return "Spring" }
            return "Java"
        case "go": return "Go"
        case "postgres": return "Postgres"
        case "redis-server": return "Redis"
        default: return processName
        }
    }

    private func runCommand(_ path: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
