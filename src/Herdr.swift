import Foundation

let localPollInterval = 2.0
let machinePollInterval = 6.0
let machineListInterval = 60.0
let machineHoldInterval = 60.0

struct AgentSession: Decodable {
    var value: String?
    var kind: String?
    var agent: String? = nil
}

struct Agent: Decodable {
    let terminal_id: String    // Stable inside one Herdr server
    let agent_status: String   // idle, working, blocked, done, unknown
    var agent: String? = nil   // claude, codex …
    var label: String? = nil
    var cwd: String? = nil
    var machine = "local"
    var asleep = false         // Its machine stopped answering. The pet stays, dimmed, until the machine answers or leaves the list

    var pane_id: String? = nil
    var agent_session: AgentSession? = nil
    var revision: Int? = nil
    var tokens: [String: String]? = nil
    var attentionReason: String? {
        guard let reason = tokens?["attention"]?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else { return nil }
        return reason
    }
    var needsAttention: Bool { agent_status == "blocked" || attentionReason != nil }
    var sessionKey: String? {
        guard let value = agent_session?.value, !value.isEmpty else { return nil }
        return "\(id):\(value.utf8.count):\(value)"
    }

    // The length keeps separators inside either ID from causing a collision.
    var id: String { "\(machine.utf8.count):\(machine):\(terminal_id)" }
    private enum CodingKeys: String, CodingKey { case terminal_id, agent_status, agent, label, cwd, pane_id, agent_session, revision, tokens }
}

struct Machine: Decodable {
    let id: String
    let enabled: Bool
}

func herdrData(_ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [ProcessInfo.processInfo.environment["HERDR_BIN_PATH"] ?? "herdr"] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }   // A hung process would block polling forever
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? data : nil
}

func decodePanes(_ data: Data) throws -> [Agent] {
    struct Response: Decodable {
        struct Result: Decodable { let panes: [Agent] }
        let result: Result
    }
    return try JSONDecoder().decode(Response.self, from: data).result.panes.filter { $0.agent != nil }
}

func fetchAgents(machine: String? = nil) -> [Agent]? {
    guard let data = herdrData((machine.map { ["--machine", $0] } ?? []) + ["pane", "list"]) else { return nil }
    return try? decodePanes(data)
}

func fetchMachines() -> [Machine]? {
    guard let data = herdrData(["machine", "list", "--json"]) else { return nil }
    return try? JSONDecoder().decode([Machine].self, from: data)
}

// State and completions stay on the main thread. Only fetchers run in the background.
final class AgentPoller {
    typealias AgentFetcher = (String?, @escaping ([Agent]?) -> Void) -> Void
    typealias MachineFetcher = (@escaping ([Machine]?) -> Void) -> Void

    private final class Remote {
        var agents: [Agent] = []
        var failedSince: Double?
        var nextPoll = 0.0
    }

    private let clock: () -> Double
    private let readAgents: AgentFetcher
    private let readMachines: MachineFetcher
    private let launchedByPlugin: Bool
    private let onUpdate: ([Agent], Bool, Bool) -> Void
    private var local: [Agent] = []
    private var remotes: [String: Remote] = [:]
    private var remoteInFlight: Set<String> = []
    private var localInFlight = false
    private var listInFlight = false
    private var nextLocal = 0.0
    private var nextList = 0.0
    private var generation = 0
    private var otherMachines = false
    private var localConnected = true
    private(set) var localFailures = 0

    init(launchedByPlugin: Bool,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         readAgents: @escaping AgentFetcher = { machine, complete in
             DispatchQueue.global().async {
                 let agents = fetchAgents(machine: machine)
                 DispatchQueue.main.async { complete(agents) }
             }
         },
         readMachines: @escaping MachineFetcher = { complete in
             DispatchQueue.global().async {
                 let machines = fetchMachines()
                 DispatchQueue.main.async { complete(machines) }
             }
         },
         onUpdate: @escaping ([Agent], Bool, Bool) -> Void) {
        self.launchedByPlugin = launchedByPlugin
        self.clock = clock
        self.readAgents = readAgents
        self.readMachines = readMachines
        self.onUpdate = onUpdate
    }

    func tick(otherMachines: Bool) {
        if self.otherMachines != otherMachines {
            self.otherMachines = otherMachines
            generation += 1
            remotes.removeAll()
            nextList = 0
        }
        let now = clock()
        if !localInFlight && now >= nextLocal {
            localInFlight = true
            nextLocal = now + localPollInterval
            readAgents(nil) { agents in
                self.localInFlight = false
                self.localConnected = agents != nil
                self.localFailures = agents == nil ? self.localFailures + 1 : 0
                if let agents { self.local = self.scoped(agents, machine: "local") }
                self.publish()
            }
        }
        if otherMachines && !listInFlight && now >= nextList {
            listInFlight = true
            nextList = now + machineListInterval
            let generation = generation
            readMachines { machines in
                self.listInFlight = false
                guard self.otherMachines && self.generation == generation else { return }
                if let machines {
                    let enabled = Set(machines.filter { $0.enabled && $0.id != "local" }.map(\.id))
                    self.remotes = self.remotes.filter { enabled.contains($0.key) }
                    for id in enabled where self.remotes[id] == nil { self.remotes[id] = Remote() }
                }
                self.pollRemotes()
                self.publish()
            }
        }
        pollRemotes()
        publish()   // Expire stale pets even when a fetch is still pending.
    }

    private func pollRemotes() {
        guard otherMachines else { return }
        let now = clock()
        for id in remotes.keys.sorted() {
            let remote = remotes[id]!
            guard !remoteInFlight.contains(id) && now >= remote.nextPoll else { continue }
            remoteInFlight.insert(id)
            remote.nextPoll = now + machinePollInterval
            readAgents(id) { agents in
                self.remoteInFlight.remove(id)
                guard self.remotes[id] === remote else { return }   // Ignore a removed machine's late reply.
                if let agents {
                    remote.agents = self.scoped(agents, machine: id)
                    remote.failedSince = nil
                } else if remote.failedSince == nil {
                    remote.failedSince = self.clock()
                }
                self.publish()
            }
        }
    }

    private func scoped(_ agents: [Agent], machine: String) -> [Agent] {
        agents.map { agent in
            var agent = agent
            agent.machine = machine
            return agent
        }
    }

    private func publish() {
        let now = clock()
        let agents = local + remotes.keys.sorted().flatMap { id -> [Agent] in
            let remote = remotes[id]!
            guard let failed = remote.failedSince, now - failed >= machineHoldInterval else { return remote.agents }
            return remote.agents.map { agent in
                var agent = agent
                agent.asleep = true
                return agent
            }
        }
        onUpdate(agents, localConnected, launchedByPlugin && localFailures >= 15)
    }
}

// --demo: one fake agent per character. Status changes every 12 seconds.
func demoAgents() -> [Agent] {
    let states = ["working", "blocked", "working", "done", "idle"]
    let tick = Int(Date().timeIntervalSince1970 / 12)
    return PetKind.allCases.enumerated().map { i, kind in
        Agent(terminal_id: "demo-\(kind.rawValue)", agent_status: states[(tick + i) % states.count], agent: kind.rawValue)
    }
}
