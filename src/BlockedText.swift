import Foundation
import Darwin

// Each call has a byte limit and a wall-clock limit, including pipe reads.
func boundedCommandData(_ arguments: [String], limit: Int = 65_536, timeout: Double = 2) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    guard (try? process.run()) != nil else { return nil }
    defer {
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        try? pipe.fileHandleForReading.close()
    }
    let fd = pipe.fileHandleForReading.fileDescriptor
    guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { return nil }
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    var bytes = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while ProcessInfo.processInfo.systemUptime < deadline {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
        let milliseconds = max(1, Int32((deadline - ProcessInfo.processInfo.systemUptime) * 1000))
        let ready = poll(&descriptor, 1, milliseconds)
        if ready < 0 { if errno == EINTR { continue }; return nil }
        if ready == 0 { return nil }
        let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
        if count == 0 { break }
        if count < 0 { if errno == EAGAIN || errno == EINTR { continue }; return nil }
        guard bytes.count + count <= limit else { return nil }
        bytes.append(contentsOf: buffer.prefix(count))
    }
    let remaining = max(0, deadline - ProcessInfo.processInfo.systemUptime)
    guard exited.wait(timeout: .now() + remaining) == .success, process.terminationStatus == 0 else { return nil }
    return bytes
}

func boundedHerdrData(_ arguments: [String], limit: Int = 65_536, timeout: Double = 2) -> Data? {
    boundedCommandData([ProcessInfo.processInfo.environment["HERDR_BIN_PATH"] ?? "herdr"] + arguments, limit: limit, timeout: timeout)
}

func machineArguments(_ agent: Agent) -> [String] { agent.machine == "local" ? [] : ["--machine", agent.machine] }

// Visible terminal output is not a conversation API. Prefer its last question and choices.
func latestAttentionText(_ raw: String) -> String? {
    let plain = raw.replacingOccurrences(of: "\u{001B}\\[[0-?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    let borders = CharacterSet(charactersIn: " │┃║\t\r")
    var lines = plain.components(separatedBy: "\n").map { $0.trimmingCharacters(in: borders) }.filter { line in
        if !line.isEmpty, line.unicodeScalars.allSatisfy({ CharacterSet.whitespaces.contains($0) || (0x2500...0x257F).contains($0.value) }) { return false }
        let lower = line.lowercased()
        if line.contains("?"), !lower.hasPrefix("? for shortcuts") { return true }
        if line.range(of: "^[❯›>●○ ]*\\d+[.)]\\s", options: .regularExpression) != nil { return true }
        if (lower.hasPrefix("gpt-") || lower.hasPrefix("hi ·")), lower.contains("context") { return false }
        return !["esc to", "enter to select", "enter to confirm", "shift+tab", "bypass permissions", "? for shortcuts"].contains(where: lower.contains)
    }
    while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
    guard !lines.isEmpty else { return nil }
    func option(_ line: String) -> Bool { line.range(of: "^[❯›>●○ ]*\\d+[.)]\\s", options: .regularExpression) != nil }
    let lastOption = lines.lastIndex(where: option)
    let lastTurn = lines.indices.last { (lines[$0].hasPrefix("• ") || lines[$0].hasPrefix("⏺ ") || lines[$0].hasPrefix("› ") || lines[$0].hasPrefix("❯ ")) && !option(lines[$0]) }
    let question = lines.indices.last { lines[$0].contains("?") && !option(lines[$0]) && $0 >= (lastTurn ?? 0) && (lastOption == nil || $0 >= lastOption! - 18) }
    var start = question ?? max(0, lines.count - 10)
    if let question {
        while start > max(0, question - 3), !lines[start - 1].isEmpty, !option(lines[start - 1]),
              !lines[start - 1].hasPrefix("›"), !lines[start - 1].hasPrefix("❯"), !lines[start - 1].hasPrefix("⏺"), !lines[start - 1].hasPrefix("•") { start -= 1 }
    } else if let lastOption {
        var first = lastOption
        while let previous = lines[..<first].lastIndex(where: option), lines[(previous + 1)..<first].allSatisfy({ $0.isEmpty }) { first = previous }
        start = first
        while start > max(0, first - 6), lines[start - 1].isEmpty { start -= 1 }
        while start > max(0, first - 6), !lines[start - 1].isEmpty, !option(lines[start - 1]) { start -= 1 }
    } else {
        if let turn = lastTurn { start = max(start, turn) }
        if let paragraph = lines.indices.last(where: { lines[$0].isEmpty }) { start = max(start, paragraph + 1) }
    }
    let excerpt = lines.dropFirst(start).prefix(18).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !excerpt.isEmpty else { return nil }
    return excerpt.count > 1600 ? String(excerpt.prefix(1600)) + "\n… Open the agent for more." : excerpt
}

func attentionQuestionPreview(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    let question = lines.lastIndex { $0.contains("?") && $0.range(of: "^[❯›>●○ ]*\\d+[.)]\\s", options: .regularExpression) == nil }
    var start = question ?? lines.firstIndex(where: { !$0.isEmpty }) ?? 0
    if let question {
        while start > max(0, question - 2), !lines[start - 1].isEmpty,
              lines[start - 1].range(of: "^[❯›>●○ ]*\\d+[.)]\\s", options: .regularExpression) == nil,
              !lines[start - 1].hasPrefix("• "), !lines[start - 1].hasPrefix("⏺ ") { start -= 1 }
    }
    let value = lines[start...(question ?? start)].filter { !$0.isEmpty }.joined(separator: " ")
    if value.isEmpty { return "Waiting for a question. Open the agent." }
    if value.count <= 180 { return value }
    return String(value.prefix(177)) + "…"
}

typealias PaneFetcher = ([String], Int) -> Data?

func currentPane(_ expected: Agent, fetch: PaneFetcher = { boundedHerdrData($0, limit: $1) }) -> Agent? {
    guard let pane = expected.pane_id, expected.sessionKey != nil,
          let data = fetch(machineArguments(expected) + ["pane", "get", pane], 65_536) else { return nil }
    struct Response: Decodable { struct Result: Decodable { var pane: Agent }; var result: Result }
    guard var current = try? JSONDecoder().decode(Response.self, from: data).result.pane else { return nil }
    current.machine = expected.machine
    guard current.id == expected.id, current.pane_id == expected.pane_id,
          current.sessionKey == expected.sessionKey,
          current.agent == expected.agent || current.agent == "attention" || expected.agent == "attention" else { return nil }
    return current
}

func readBlockedText(_ agent: Agent, fetch: PaneFetcher = { boundedHerdrData($0, limit: $1) }) -> String? {
    guard let pane = agent.pane_id, let before = currentPane(agent, fetch: fetch), before.agent_status == "blocked" else { return nil }
    let data = fetch(machineArguments(agent) + ["pane", "read", pane, "--source", "visible", "--lines", "100", "--format", "text"], 32_768)
    guard let after = currentPane(agent, fetch: fetch), after.agent_status == "blocked",
          before.revision == after.revision else { return nil }
    // The daemon owns tokens.attention. See docs/ATTENTION.md for its contract.
    guard let data, let text = String(data: data, encoding: .utf8),
          let excerpt = latestAttentionText(text) else {
        let attention = after.tokens?["attention"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return attention?.isEmpty == false ? attention : nil
    }
    return excerpt
}

func focusPetAgent(_ agent: Agent, complete: @escaping (Bool) -> Void) {
    DispatchQueue.global().async {
        let valid = currentPane(agent) != nil
        let focused = valid && agent.pane_id.map { boundedHerdrData(machineArguments(agent) + ["agent", "focus", $0]) != nil } == true
        let result = focused && (agent.machine == "local" || (currentPane(agent) != nil && openRemoteHerdrWindow(machine: agent.machine)))
        DispatchQueue.main.async { complete(result) }
    }
}

// CLI focus changes the remote server. A fresh client must attach to that same host and session.
func openRemoteHerdrWindow(machine: String) -> Bool {
    struct Profile: Decodable { let id: String; let target: String; let session: String; let enabled: Bool }
    guard machine != "local", let data = boundedHerdrData(["machine", "list", "--json"]),
          let profiles = try? JSONDecoder().decode([Profile].self, from: data),
          let profile = profiles.first(where: { $0.id == machine && $0.enabled }), !profile.target.isEmpty, !profile.session.isEmpty else { return false }
    let executable = ProcessInfo.processInfo.environment["HERDR_BIN_PATH"] ?? "herdr"
    let paths = executable.contains("/") ? [executable] : (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":").map { $0 + "/" + executable }
    let directory = FileManager.default.currentDirectoryPath
    guard let binary = paths.map({ $0.hasPrefix("/") ? $0 : directory + "/" + $0 })
        .map({ URL(fileURLWithPath: $0).standardizedFileURL.path })
        .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
    func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    let command = "exec \(quote(binary)) --remote \(quote(profile.target)) --session \(quote(profile.session))"
    let script = """
    on run argv
        tell application "Ghostty"
            set cfg to new surface configuration
            set initial input of cfg to (item 1 of argv) & linefeed
            set w to new window with configuration cfg
            activate window w
            return id of w
        end tell
    end run
    """
    guard let data = boundedCommandData(["/usr/bin/osascript", "-e", script, "--", command], timeout: 5),
          let windowID = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
    return !windowID.isEmpty
}

final class BlockedTextPoller {
    typealias Reader = (Agent, @escaping (String?) -> Void) -> Void
    private struct Entry {
        var agent: Agent
        var generation: Int
        var nextRead = -Double.infinity
        var text: String?
    }
    private let clock: () -> Double
    private let reader: Reader
    private let onChange: ([String: String]) -> Void
    private var entries: [String: Entry] = [:]
    private var requests: [Int: String] = [:]
    private var sequence = 0
    private var pumping = false

    init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         reader: @escaping Reader = { agent, complete in
             DispatchQueue.global().async {
                 let text = readBlockedText(agent)
                 DispatchQueue.main.async { complete(text) }
             }
         }, onChange: @escaping ([String: String]) -> Void) {
        self.clock = clock; self.reader = reader; self.onChange = onChange
    }

    func update(_ agents: [Agent]) {
        let blocked = agents.filter { $0.agent_status == "blocked" && !$0.asleep && $0.sessionKey != nil }
        let ids = Set(blocked.map(\.id))
        entries = entries.filter { ids.contains($0.key) }
        for agent in blocked {
            if entries[agent.id]?.agent.sessionKey != agent.sessionKey || entries[agent.id]?.agent.revision != agent.revision {
                sequence += 1
                entries[agent.id] = Entry(agent: agent, generation: sequence)
            } else { entries[agent.id]?.agent = agent }
        }
        publish(); pump()
    }

    private func publish() { onChange(entries.compactMapValues(\.text)) }

    private func pump() {
        guard !pumping else { return }
        pumping = true
        defer { pumping = false }
        for id in entries.keys.sorted() where requests.count < 2 {
            guard var entry = entries[id], clock() >= entry.nextRead, !requests.values.contains(id) else { continue }
            entry.nextRead = clock() + 2
            entries[id] = entry
            sequence += 1
            let request = sequence, generation = entry.generation
            requests[request] = id
            reader(entry.agent) { [weak self] text in
                guard let self else { return }
                self.requests[request] = nil
                if self.entries[id]?.generation == generation {
                    self.entries[id]?.text = text
                    self.entries[id]?.nextRead = self.clock() + 2
                }
                self.publish(); self.pump()
            }
        }
    }
}
