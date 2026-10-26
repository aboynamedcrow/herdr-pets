import AppKit

func attentionTokenSelfTest() {
    let reason = "word: Choose the synthetic option."
    var pane: [String: Any] = [
        "terminal_id": "synthetic-terminal", "pane_id": "w1:p1", "agent_status": "blocked",
        "agent": "attention", "agent_session": ["value": "synthetic-session", "kind": "id", "agent": "codex"],
        "revision": 1, "tokens": ["attention": reason]
    ]
    func data(_ pane: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["result": ["pane": pane]])
    }
    struct Response: Decodable { struct Result: Decodable { var pane: Agent }; var result: Result }
    var expected = try! JSONDecoder().decode(Response.self, from: data(pane)).result.pane
    expected.agent = "codex"
    var screen: Data?
    var second: [String: Any]?
    var gets = 0
    let fetch: PaneFetcher = { arguments, _ in
        if arguments.contains("read") { return screen }
        gets += 1
        return data(gets % 2 == 0 ? second ?? pane : pane)
    }
    var bubbleTexts: [String: String] = [:]
    let reader = BlockedTextPoller(reader: { agent, complete in complete(readBlockedText(agent, fetch: fetch)) },
                                   onChange: { bubbleTexts = $0 })
    reader.update([expected])
    precondition(bubbleTexts[expected.id] == reason)
    screen = Data("\nSynthetic screen question\n".utf8)
    precondition(readBlockedText(expected, fetch: fetch) == "Synthetic screen question")
    screen = Data(" \n".utf8)
    precondition(readBlockedText(expected, fetch: fetch) == reason)
    screen = nil
    for (key, value) in [("pane_id", "w1:p2"), ("terminal_id", "other-terminal"), ("agent_status", "working")] {
        var changed = pane; changed[key] = value
        second = changed; gets = 0
        precondition(readBlockedText(expected, fetch: fetch) == nil)
    }
    var changed = pane
    changed["agent_session"] = ["value": "other-session", "kind": "id", "agent": "codex"]
    second = changed; gets = 0
    precondition(readBlockedText(expected, fetch: fetch) == nil)
    changed = pane; changed["revision"] = 2
    second = changed; gets = 0
    precondition(readBlockedText(expected, fetch: fetch) == nil)
    second = nil; gets = 0
    pane["tokens"] = [:]
    precondition(readBlockedText(expected, fetch: fetch) == nil)
    pane["agent"] = "claude"; gets = 0
    precondition(currentPane(expected, fetch: fetch) == nil)
    pane["agent"] = "codex"; gets = 0
    var held = expected; held.agent = "attention"
    precondition(currentPane(held, fetch: fetch) != nil)
    var remote = expected; remote.machine = "synthetic-remote"
    let remoteFetch: PaneFetcher = { arguments, _ in
        precondition(arguments.starts(with: ["--machine", "synthetic-remote"]))
        return arguments.contains("read") ? nil : data(pane)
    }
    pane["tokens"] = ["attention": reason]
    precondition(readBlockedText(remote, fetch: remoteFetch) == reason)
    print("PASS: Attention fallback keeps pane, session, revision, status, machine, and screen priority checks")

    let saved = preferences
    defer { preferences = saved }
    preferences.visible = false
    preferences.showQuestionBubbles = false
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let roles = RolePets(directory: directory, log: { _ in })
    var assignments = AssignmentDocument()
    assignments.cells = [GridAssignment(repository: "", role: "", agentType: "codex", pet: "builtin:robot")]
    try! roles.assignments.save(assignments, expected: nil)
    let scene = PetScene(root: CALayer(), roles: roles)
    for mode in CharacterMode.allCases {
        preferences.characterMode = mode
        scene.apply([expected])
        let pet = scene.pets[expected.id]!, character = scene.pets[expected.id]!.character
        let position = pet.position, spot = pet.spot
        if mode == .agent { precondition(character == .builtin(.codex)) }
        if mode == .custom { precondition(character == .builtin(.robot)) }
        for label in ["attention", "attention", "codex"] {
            var observed = expected
            observed.agent = label
            // Check history as well as the native provider field.
            observed.agent_session?.agent = nil
            scene.apply([observed])
            precondition(scene.pets[expected.id] === pet && pet.character == character)
            precondition(pet.position == position && pet.spot == spot)
        }
    }
    preferences.characterMode = .custom
    roles.agentOverrides[expected.sessionKey!] = "builtin:cat"
    scene.apply([held])
    precondition(scene.pets[expected.id]!.character == .builtin(.cat))
    let fresh = PetScene(root: CALayer(), roles: roles)
    held.agent_session?.agent = "codex"
    roles.agentOverrides = [:]
    fresh.apply([held])
    precondition(fresh.pets[expected.id]!.character == .builtin(.robot))
    scene.stop(); fresh.stop()
    print("PASS: Attention label transitions preserve pet, art, position, assignment, and session override")
}
