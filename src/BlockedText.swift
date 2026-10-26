import Foundation
import Darwin

// Each call has a byte limit and a wall-clock limit, including pipe reads.
func boundedHerdrData(_ arguments: [String], limit: Int = 65_536, timeout: Double = 2) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [ProcessInfo.processInfo.environment["HERDR_BIN_PATH"] ?? "herdr"] + arguments
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

func machineArguments(_ agent: Agent) -> [String] { agent.machine == "local" ? [] : ["--machine", agent.machine] }

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
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        let attention = after.tokens?["attention"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return attention?.isEmpty == false ? attention : nil
    }
    var lines = text.components(separatedBy: "\n")
    while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { lines.removeFirst() }
    while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true { lines.removeLast() }
    return lines.joined(separator: "\n")
}

func focusPetAgent(_ agent: Agent, complete: @escaping (Bool) -> Void) {
    DispatchQueue.global().async {
        let valid = currentPane(agent) != nil
        let result = valid && agent.pane_id.map { boundedHerdrData(machineArguments(agent) + ["agent", "focus", $0]) != nil } == true
        DispatchQueue.main.async { complete(result) }
    }
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
