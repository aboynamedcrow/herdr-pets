import AppKit

func attentionTokenSelfTest() {
    attentionRetrySelfTest()
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
    precondition(readBlockedText(expected, fetch: fetch) == .screen("Synthetic screen question"))
    screen = Data(" \n".utf8)
    precondition(readBlockedText(expected, fetch: fetch) == .fallback(reason))
    screen = nil
    for (key, value) in [("pane_id", "w1:p2"), ("terminal_id", "other-terminal"), ("agent_status", "working")] {
        var changed = pane; changed[key] = value
        if key == "agent_status" { changed["tokens"] = [:] }
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
    precondition(readBlockedText(remote, fetch: remoteFetch) == .fallback(reason))
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

    pane["agent"] = "codex"
    pane["agent_status"] = "idle"
    expected = try! JSONDecoder().decode(Response.self, from: data(pane)).result.pane
    gets = 0
    reader.update([expected])
    precondition(bubbleTexts[expected.id] == reason)
    screen = Data("Synthetic idle question?".utf8)
    precondition(readBlockedText(expected, fetch: fetch) == .screen("Synthetic idle question?"))
    screen = Data(" \n".utf8)
    precondition(readBlockedText(expected, fetch: fetch) == .fallback(reason))
    screen = nil
    scene.apply([expected])
    let tokenPet = scene.pets[expected.id]!
    let world = World(band: CGRect(x: 0, y: 0, width: 200, height: 40), path: Perimeter(r: CGRect(x: 0, y: 0, width: 500, height: 500)), cursor: .zero, scale: 1, still: true)
    _ = tokenPet.step(t: 0, dt: 0, world: world)
    precondition(tokenPet.status == "blocked" && !tokenPet.badge.isHidden)
    _ = NSApplication.shared
    let bubbles = SpeechBubbles()
    let visibleBefore = Set(NSApp.windows.filter(\.isVisible).map(ObjectIdentifier.init))
    bubbles.update(agents: [expected], pets: scene.pets, texts: bubbleTexts, origin: .zero, screen: world.path.r)
    let opened = NSApp.windows.filter { $0.isVisible && !visibleBefore.contains(ObjectIdentifier($0)) }
    precondition(opened.count == 1)
    print("PASS: Idle attention token shows the badge and bubble, with screen text first")

    var cleared = pane
    cleared["tokens"] = [:]
    second = cleared; gets = 0
    precondition(readBlockedText(expected, fetch: fetch) == nil)
    pane = cleared; second = nil
    expected = try! JSONDecoder().decode(Response.self, from: data(pane)).result.pane
    reader.update([expected])
    precondition(bubbleTexts.isEmpty)
    scene.apply([expected])
    _ = tokenPet.step(t: 1, dt: 0, world: world)
    precondition(tokenPet.status == "idle" && tokenPet.badge.isHidden)
    bubbles.update(agents: [expected], pets: scene.pets, texts: bubbleTexts, origin: .zero, screen: world.path.r)
    precondition(opened.allSatisfy { !$0.isVisible })
    print("PASS: Clearing the idle attention token removes the badge, bubble, and text")

    var done = Agent(terminal_id: expected.terminal_id, agent_status: "done", agent: "codex", tokens: ["attention": reason])
    scene.apply([done])
    precondition(tokenPet.status == "blocked")
    done.tokens = ["attention": " \n"]
    scene.apply([done])
    precondition(tokenPet.status == "done")
    scene.stop()
    print("PASS: Attention token suppresses done celebration and ignores empty values")
}

private func attentionRetrySelfTest() {
    var pane: [String: Any] = [
        "terminal_id": "fallback", "pane_id": "w1:p1", "agent_status": "blocked", "agent": "codex",
        "agent_session": ["value": "session", "kind": "id"], "revision": 1,
        "tokens": ["attention": "Short reason"]
    ]
    var agent = Agent(terminal_id: "fallback", agent_status: "blocked", agent: "codex", pane_id: "w1:p1",
                      agent_session: AgentSession(value: "session", kind: "id"), revision: 1)
    var now = 0.0
    var screen: Data?
    var paneChecks = 0
    var screenReads = 0
    var texts: [String: String] = [:]
    var retry: (deadline: Double, fire: () -> Void)?
    let fetch: PaneFetcher = { args, _ in
        if args.contains("read") { screenReads += 1; return screen }
        paneChecks += 1
        return try! JSONSerialization.data(withJSONObject: ["result": ["pane": pane]])
    }
    let poller = BlockedTextPoller(clock: { now }, reader: { agent, done in done(readBlockedText(agent, fetch: fetch)) },
                                   schedule: { delay, fire in
        precondition(retry == nil)
        retry = (now + delay, fire)
        return { retry = nil }
    }, onChange: { texts = $0 })
    poller.update([agent])
    precondition(texts[agent.id] == "Short reason" && paneChecks == 2 && screenReads == 1)
    precondition(retry?.deadline == 2, "The fallback keeps a retry pending after both pane checks succeed")
    now = 2
    screen = Data("Full question?\n1. Apply\n2. Keep".utf8)
    let recover = retry!.fire
    retry = nil
    recover()
    precondition(texts[agent.id] == "Full question?\n1. Apply\n2. Keep" && paneChecks == 4 && screenReads == 2)
    precondition(retry == nil, "A full question confirms the same revision without another agent poll")

    now = 4
    agent.revision = 2
    pane["revision"] = 2
    screen = nil
    poller.update([agent])
    precondition(texts[agent.id] == "Full question?\n1. Apply\n2. Keep", "A fallback cannot replace stored screen text")
    precondition(retry?.deadline == 6)
    now = 6
    screen = Data("New full question?\n1. Continue\n2. Stop".utf8)
    let replace = retry!.fire
    retry = nil
    replace()
    precondition(texts[agent.id] == "New full question?\n1. Continue\n2. Stop" && retry == nil)
    print("PASS: Attention fallback retries recover the full question and preserve existing screen text")
}
