import Foundation

struct Agent: Decodable {
    let terminal_id: String    // Key that identifies a pet. Stays the same when the pane moves
    let agent_status: String   // idle, working, blocked, done, unknown
    var agent: String? = nil   // claude, codex …
}

func fetchAgents() -> [Agent]? {
    struct Response: Decodable {
        struct Result: Decodable { let agents: [Agent] }
        let result: Result
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [ProcessInfo.processInfo.environment["HERDR_BIN_PATH"] ?? "herdr", "agent", "list"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    DispatchQueue.global().asyncAfter(deadline: .now() + 10) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }   // A hung process would block polling forever
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    return try? JSONDecoder().decode(Response.self, from: data).result.agents
}

// --demo: one fake agent per character. Status changes every 12 seconds.
func demoAgents() -> [Agent] {
    let states = ["working", "blocked", "working", "done", "idle"]
    let tick = Int(Date().timeIntervalSince1970 / 12)
    return PetKind.allCases.enumerated().map { i, kind in
        Agent(terminal_id: "demo-\(kind.rawValue)", agent_status: states[(tick + i) % states.count], agent: kind.rawValue)
    }
}
