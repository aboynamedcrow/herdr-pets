import AppKit

func studioSelfTest() {
    poolAssignmentSelfTest()
    for mode in ["home", "broadway"] {
        for visible in [false, true] {
            let data = try! JSONSerialization.data(withJSONObject: ["movementMode": mode, "showQuestionBubbles": visible])
            var choice = try! JSONDecoder().decode(Preferences.self, from: data)
            choice.movementMode = mode == "home" ? .broadway : .home
            let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(choice)) as! [String: Any]
            if encoded["showQuestionBubbles"] as? Bool != visible {
                FileHandle.standardError.write(Data("FAIL: Bubble choice must persist across movement changes.\n".utf8))
                exit(1)
            }
        }
    }

    for (legacy, expected) in [("{\"movementMode\":\"home\"}", false), ("{\"movementMode\":\"broadway\"}", true)] {
        let migrated = try! JSONDecoder().decode(Preferences.self, from: Data(legacy.utf8))
        precondition(migrated.showQuestionBubbles == expected)
    }
    print("PASS: Bubble choice persists across movement changes and keeps old settings")
    var sizeSettings = Preferences()
    sizeSettings.customPetSize = 150
    sizeSettings.customSizeShares = ["sample": 0.5]
    sizeSettings.movementMode = .broadway
    let savedSize = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(sizeSettings))
    precondition(savedSize.customSizeShares["sample"] == 0.5 && savedSize.movementMode == .broadway)
    let badSize = try! JSONDecoder().decode(Preferences.self, from: Data("{\"customSizeShares\":{\"a\":-2,\"b\":8}}".utf8))
    precondition(badSize.customSizeShares == ["a": 0, "b": 1])
    let synthetic = bitmap(width: 1536, height: 2288)
    synthetic.setFillColor(NSColor.blue.cgColor)
    for (row, count) in CustomPet.rowLimits.enumerated() {
        for column in 0..<count { synthetic.fill(CGRect(x: column * 192 + 30, y: 2288 - row * 208 - 100, width: 40, height: 80)) }
    }
    let sample = try! CustomPet(sheet: synthetic.makeImage()!, customSizeShare: 0.25)
    let base = sample.frames[.resting]![0].size.height
    precondition(sample.frames(sizePercent: 150, share: 0.5)[.resting]![0].size.height == base * 1.25)
    precondition(sample.frames(sizePercent: 150)[.resting]![0].size.height == base * 1.125)
    print("PASS: Studio size overrides, metadata fallback, bounds, and movement persistence")
    var attention = AttentionCycle(counts: [.resting: 6, .blocked: 6, .jump: 4, .thinking: 8, .working: 6, .sleeping: 6, .walkingLeft: 8, .walkingRight: 8, .celebrate: 5], seed: 7)
    var seen: Set<Pose> = []
    var previous: Pose?
    for index in 0..<80 {
        let sample = attention.sample(at: Double(index) * 0.25)
        precondition(sample.pose != .walkingLeft && sample.pose != .walkingRight && sample.pose != .celebrate)
        if sample.frame == 0 && previous != nil { precondition(sample.pose != previous) }
        previous = sample.pose
        seen.insert(sample.pose)
    }
    precondition(seen.count == 6)
    var fallback = AttentionCycle(counts: [.blocked: 2], seed: 1)
    precondition(fallback.sample(at: 0).pose == .blocked && fallback.sample(at: 4).frame == 0)
    precondition(sample.frames[.walkingLeft]?.count == 8 && sample.frames[.jump]?.count == 4)
    precondition(Sprites.frames(.codex).count == 4)
    print("PASS: Stationary attention variety, complete loops, short-sheet fallback, and four built-in poses")
    let screen = CGRect(x: 0, y: 0, width: 500, height: 700)
    let lane = broadwayBand(screen, area: screen, floor: .bottom, scale: 1.5)
    precondition(lane.minY == 29 && lane.height == 0)
    let large = Pet(id: "broadway", kind: .codex, spot: CGPoint(x: 0.5, y: 0), in: lane)
    large.setCharacter(.custom("large", 1), frames: sample.frames(sizePercent: 200, share: 1))
    large.setStatus("blocked")
    let stage = World(band: lane, path: Perimeter(r: screen.insetBy(dx: 29, dy: 29)), cursor: CGPoint(x: 490, y: 690), scale: 1.5, still: false, broadway: true, usableBounds: screen)
    for tick in 0..<500 { _ = large.step(t: Double(tick) / 30, dt: 1 / 30, world: stage) }
    precondition(large.zRotation == .pi && large.position.y == 671)
    large.setStatus("working")
    var left = false, right = false
    for tick in 500..<3500 {
        _ = large.step(t: Double(tick) / 30, dt: 1 / 30, world: stage)
        if large.zRotation == 0 && abs(large.position.y - 29) < 0.01 {
            left = left || large.position.x < 80; right = right || large.position.x > 420
        }
        let bounce = large.layer.sublayers!.first!.position.y
        let box = CGRect(x: -24, y: -18 + bounce, width: 48, height: 96).applying(large.layer.affineTransform()).offsetBy(dx: large.position.x, dy: large.position.y)
        precondition(screen.insetBy(dx: -0.01, dy: -0.01).contains(box))
    }
    precondition(left && right && large.zRotation == 0)
    let stillStage = World(band: lane, path: Perimeter(r: screen.insetBy(dx: 29, dy: 29)), cursor: stage.cursor, scale: 1.5, still: true, broadway: true, usableBounds: screen)
    large.setStatus("blocked")
    precondition(!large.step(t: 200, dt: 0.1, world: stillStage) && large.position.y == 671 && large.zRotation == .pi)
    print("PASS: Broadway screen-edge approach, large-art margins, edge turns, and Reduce Motion")
    floorSelfTest()
    blockedTextSelfTest()
    attentionTokenSelfTest()
    bubbleSelfTest()
    _ = NSApplication.shared
    let options = [AvatarChoice(token: "builtin:cat", name: "Cat", image: Sprites.thumbnail(.cat)), AvatarChoice(token: "builtin:robot", name: "Robot", image: Sprites.thumbnail(.robot))]
    let tile = AvatarAssignmentTile(choices: options, selection: [], inherited: options)
    var dropped: [String] = []
    tile.choose = { dropped = $0 }
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let dragType = NSPasteboard.PasteboardType("dev.herdr-pets.character")
    board.declareTypes([dragType], owner: nil)
    board.setString("builtin:cat", forType: dragType)
    precondition(tile.acceptDrop(from: board) && dropped == ["builtin:cat"])
    precondition(tile.acceptDrop(from: board) && dropped == ["builtin:cat"])
    board.setString("builtin:robot", forType: dragType)
    precondition(tile.acceptDrop(from: board) && dropped == ["builtin:cat", "builtin:robot"])
    board.setString("custom:unknown", forType: dragType)
    precondition(!tile.acceptDrop(from: board) && dropped == ["builtin:cat", "builtin:robot"])
    print("PASS: Real pasteboard drops start a pool, add a member, deduplicate, and reject unknown art")
    let picker = AssignmentCell(frame: .zero, pullsDown: false)
    picker.addItems(withTitles: ["Use grid and rules", "Cat"])
    picker.tokens = [nil, "builtin:cat"]
    var picked: String? = "builtin:cat"
    picker.choose = { picked = $0 }
    picker.selectItem(at: 0)
    _ = picker.perform(picker.action)
    precondition(picked == nil, "The first live-agent option must clear its override")
    picked = "builtin:cat"
    picker.firstIsPlaceholder = true
    _ = picker.perform(picker.action)
    precondition(picked == "builtin:cat")
    let shortBubble = questionBubbleSize(text: "Apply?", title: "Terminal excerpt", expanded: true, screen: screen.size)
    let longBubble = questionBubbleSize(text: String(repeating: "A longer question with choices. ", count: 30), title: "Terminal excerpt", expanded: true, screen: screen.size)
    precondition(shortBubble.height < longBubble.height && shortBubble.width < longBubble.width && shortBubble.height < 160)
    precondition(longBubble.height <= 688 && longBubble.width <= 488)
    let naturalFit = questionBubbleSize(text: "Preview question: Should I apply these changes?\n1. Apply\n2. Keep the current version", title: "Preview", expanded: true, screen: screen.size)
    let shortFit = questionBubbleSize(text: "Apply?\n1. Apply\n2. Keep", title: "Preview", expanded: true, screen: screen.size)
    if naturalFit.height != shortFit.height {
        FileHandle.standardError.write(Data("FAIL: Equal three-line prompts must have equal bubble heights below the width limit.\n".utf8)); exit(1)
    }
    let firstBubble = bubbleRect(above: CGPoint(x: 495, y: 695), size: CGSize(width: 360, height: 210), screen: screen, occupied: [])
    let secondBubble = bubbleRect(above: CGPoint(x: 495, y: 695), size: CGSize(width: 180, height: 30), screen: screen, occupied: [firstBubble])
    precondition(screen.contains(firstBubble) && screen.contains(secondBubble) && !firstBubble.intersects(secondBubble))
    let savedBinary = ProcessInfo.processInfo.environment["HERDR_BIN_PATH"]
    setenv("HERDR_BIN_PATH", "/usr/bin/yes", 1)
    precondition(boundedHerdrData(["overflow"], limit: 1024) == nil)
    if let savedBinary { setenv("HERDR_BIN_PATH", savedBinary, 1) } else { unsetenv("HERDR_BIN_PATH") }
    print("PASS: Live override clearing, bubble bounds, overlap avoidance, and native output cap")
    if let paneID = ProcessInfo.processInfo.environment["HERDR_PETS_NATIVE_PANE"] {
        struct Response: Decodable { struct Result: Decodable { var pane: Agent }; var result: Result }
        guard let data = boundedHerdrData(["pane", "get", paneID]),
              let native = try? JSONDecoder().decode(Response.self, from: data).result.pane,
              currentPane(native) != nil else { fatalError("Native Herdr pane identity check failed") }
        print("PASS: Native Herdr CLI pipe, JSON decode, and session identity")
    }
    let home = "/fake/home"
    let pane = Agent(terminal_id: "a", agent_status: "working", agent: "codex", label: "Reviewer 2", cwd: "/repo/app")
    var doc = AssignmentDocument()
    doc.cells = [
        GridAssignment(repository: "", role: "", agentType: "", pet: "builtin:cat"),
        GridAssignment(repository: "/repo", role: "", agentType: "codex", pet: "builtin:star"),
        GridAssignment(repository: "/repo", role: "reviewer", agentType: "", pet: "builtin:robot"),
        GridAssignment(repository: "/repo/app", role: "", agentType: "", pet: "builtin:ghost")
    ]
    precondition(AssignmentStore.winner(for: pane, document: doc, home: home)?.pet == "builtin:ghost")
    doc.cells.removeLast()
    precondition(AssignmentStore.winner(for: pane, document: doc, home: home)?.pet == "builtin:robot")
    doc.cells.append(GridAssignment(repository: "/repo", role: "reviewer", agentType: "codex", pet: "builtin:seed"))
    precondition(AssignmentStore.winner(for: pane, document: doc, home: home)?.pet == "builtin:seed")
    let adjacent = Agent(terminal_id: "b", agent_status: "working", agent: "codex", label: "reviewer", cwd: "/repository")
    precondition(AssignmentStore.winner(for: adjacent, document: doc, home: home)?.pet == "builtin:cat")
    let missing = Agent(terminal_id: "c", agent_status: "idle")
    precondition(AssignmentStore.winner(for: missing, document: doc, home: home)?.pet == "builtin:cat")
    doc.cells = [GridAssignment(repository: "~/r/one/", role: "", agentType: "", pet: "agent")]
    let expanded = Agent(terminal_id: "d", agent_status: "idle", cwd: "/fake/home/r/one/branch")
    precondition(AssignmentStore.winner(for: expanded, document: doc, home: home)?.pet == "agent")
    print("PASS: Studio assignment precedence and directory boundaries")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let target = directory.appendingPathComponent("real")
    try! FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let link = directory.appendingPathComponent("link")
    try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let store = AssignmentStore(file: link.appendingPathComponent("assignments.json"))
    precondition(store.load().cells.isEmpty)
    try! store.save(doc, expected: nil)
    precondition(store.load() == doc)
    let baseline = store.snapshot
    let external = Data("{\"version\":1,\"repositories\":[],\"roles\":[],\"cells\":[]}".utf8)
    try! external.write(to: target.appendingPathComponent("assignments.json"))
    do { try store.save(doc, expected: baseline); preconditionFailure("Must reject an external edit") } catch {}
    precondition(try! Data(contentsOf: target.appendingPathComponent("assignments.json")) == external)
    _ = store.load()
    try! store.save(doc, expected: store.snapshot)
    precondition(try! Data(contentsOf: target.appendingPathComponent("assignments.json.bak")) == external)
    try! Data("broken".utf8).write(to: target.appendingPathComponent("assignments.json"))
    precondition(store.load() == doc && store.lastError != nil)
    var duplicate = doc
    duplicate.cells += doc.cells
    do { try store.save(duplicate, expected: store.snapshot); preconditionFailure("Must reject duplicate cells") } catch {}
    print("PASS: Studio atomic save, symlink directory, backup, external conflict, last valid data")

    let preferencesURL = directory.appendingPathComponent("settings.json")
    try! sizeSettings.saveChecked(to: preferencesURL)
    precondition(try! JSONDecoder().decode(Preferences.self, from: Data(contentsOf: preferencesURL)).customSizeShares["sample"] == 0.5)
    do { try sizeSettings.saveChecked(to: preferencesURL.appendingPathComponent("invalid.json")); preconditionFailure("Must report a failed preference write") } catch {}
    var explicitGrid = AssignmentDocument()
    explicitGrid.cells = [GridAssignment(repository: "", role: "", agentType: "", pet: "builtin:robot")]
    try! store.save(explicitGrid, expected: store.snapshot)
    let backup = try? JSONDecoder().decode(AssignmentDocument.self, from: Data(contentsOf: target.appendingPathComponent("assignments.json.bak")))
    if backup != doc { FileHandle.standardError.write(Data("FAIL: A corrupt file must not replace the last valid backup.\n".utf8)); exit(1) }
    let gallery = RolePets(directory: target, log: { _ in })
    gallery.refresh(mode: .custom)
    precondition(gallery.possible(mode: .custom, agents: []).builtin.contains(.robot))
    let roles = RolePets(rules: [PetRule(role: ["reviewer"], pet: "cat")], customPets: [:])
    precondition(roles.character(for: pane, mode: .custom) == .builtin(.cat))
    precondition(roles.resolve("builtin:robot", for: pane) == .builtin(.robot))
    print("PASS: Studio legacy fallback and explicit built-in selection")
    reviewRegressionSelfTest(sample)
}

private func blockedTextSelfTest() {
    blockedTextRetrySelfTest()
    var callbacks: [(Agent, (BlockedTextResult?) -> Void)] = []
    var text: [String: String] = [:]
    var now = 0.0
    var reads = 0
    var retry: (deadline: Double, fire: () -> Void)?
    let poller = BlockedTextPoller(clock: { now }, reader: {
        reads += 1
        callbacks.append(($0, $1))
    }, schedule: { delay, fire in
        precondition(retry == nil, "Only one retry timer can run")
        retry = (now + delay, fire)
        return { retry = nil }
    }, onChange: { text = $0 })
    var a = Agent(terminal_id: "same", agent_status: "blocked", agent: "codex", machine: "local", pane_id: "w1:p1",
                  agent_session: AgentSession(value: "one", kind: "id"), revision: 1)
    poller.update([a])
    callbacks.removeFirst().1(.screen("FIRST QUESTION"))
    for tick in 1..<30 { now = Double(tick) * 2; poller.update([a]) }
    precondition(reads == 1 && callbacks.isEmpty && retry == nil, "A good unchanged revision needs one read over 60 seconds")
    print("PASS: Unchanged blocked text needs 1 read (3 Herdr calls) over 60 seconds")

    a.asleep = true
    poller.update([a])
    precondition(text[a.id] == "FIRST QUESTION" && retry == nil, "An asleep machine retains text without reads")
    a.asleep = false
    poller.update([a])
    precondition(callbacks.isEmpty, "The same revision needs no new read after wake")
    now = 60
    a.revision = 2
    poller.update([a])
    precondition(text[a.id] == "FIRST QUESTION", "A revision change keeps the last text")
    callbacks.removeFirst().1(nil)
    precondition(text[a.id] == "FIRST QUESTION" && retry?.deadline == 62, "A nil read keeps text and schedules a retry")
    now = 62
    let fire = retry!.fire
    retry = nil
    fire()
    precondition(callbacks.count == 1 && callbacks[0].0.revision == 2, "The timer retries without an agent poll")
    callbacks.removeFirst().1(.screen("SECOND QUESTION"))
    precondition(text[a.id] == "SECOND QUESTION" && retry == nil, "Success replaces text and stops the timer")

    now = 64
    a.revision = 3
    poller.update([a])
    let previousRevision = callbacks.removeFirst().1
    a.revision = 4
    poller.update([a])
    previousRevision(.screen("THIRD QUESTION"))
    precondition(text[a.id] == "THIRD QUESTION" && retry?.deadline == 66, "A valid read survives a later observed revision")
    now = 66
    let revisionRetry = retry!.fire
    retry = nil
    revisionRetry()
    precondition(callbacks[0].0.revision == 4, "The latest revision still needs a read")
    a.agent_session = AgentSession(value: "two", kind: "id")
    poller.update([a])
    precondition(text.isEmpty, "A new session clears the text")
    callbacks.removeFirst().1(.screen("STALE SESSION"))
    precondition(text.isEmpty && callbacks.isEmpty && retry?.deadline == 68, "An old session cannot publish or bypass the read interval")
    now = 68
    let sessionRetry = retry!.fire
    retry = nil
    sessionRetry()
    callbacks.removeFirst().1(.screen("CURRENT SESSION"))
    precondition(text[a.id] == "CURRENT SESSION" && retry == nil)
    print("PASS: Revisions and nil reads keep text, session changes clear it, and retries need no agent poll")

    var remote = a; remote.machine = "remote"
    now = 70
    a.revision = 5
    poller.update([a, remote])
    precondition(callbacks.count == 2 && Set(callbacks.map { $0.0.machine }) == ["local", "remote"])
    let localLate = callbacks.first { $0.0.machine == "local" }!.1
    let remoteDone = callbacks.first { $0.0.machine == "remote" }!.1
    callbacks.removeAll()
    poller.update([remote])
    localLate(.screen("STALE LOCAL"))
    remoteDone(.screen("REMOTE QUESTION"))
    precondition(text[a.id] == nil && text[remote.id] == "REMOTE QUESTION")
    let idle = Agent(terminal_id: remote.terminal_id, agent_status: "working", agent: remote.agent, machine: remote.machine,
                     pane_id: remote.pane_id, agent_session: remote.agent_session)
    poller.update([idle])
    precondition(text.isEmpty && retry == nil, "The end of attention clears text and cancels retries")
    now = 72
    poller.update([remote])
    callbacks.removeFirst().1(nil)
    precondition(retry != nil)
    poller.update([])
    precondition(text.isEmpty && retry == nil, "Removing a pending entry stops its timer")
    print("PASS: Blocked text rejects disappeared panes and changed status, with separate machines and timer cleanup")
}

private func blockedTextRetrySelfTest() {
    var now = 0.0
    var callbacks: [(BlockedTextResult?) -> Void] = []
    var retry: (deadline: Double, fire: () -> Void)?
    var texts: [String: String] = [:]
    let poller = BlockedTextPoller(clock: { now }, reader: { _, done in callbacks.append(done) }, schedule: { delay, fire in
        precondition(retry == nil)
        retry = (now + delay, fire)
        return { retry = nil }
    }, onChange: { texts = $0 })
    var agent = Agent(terminal_id: "retry", agent_status: "blocked", agent: "codex", pane_id: "w1:p1",
                      agent_session: AgentSession(value: "session", kind: "id"), revision: 1)
    func fire(at deadline: Double, result: BlockedTextResult?) {
        precondition(retry?.deadline == deadline, "A failed read uses its backoff deadline")
        now = deadline
        let event = retry!.fire
        retry = nil
        event()
        precondition(callbacks.count == 1)
        callbacks.removeFirst()(result)
    }
    poller.update([agent])
    callbacks.removeFirst()(nil)
    for deadline in [2.0, 6, 14, 30, 46] { fire(at: deadline, result: nil) }
    precondition(retry?.deadline == 62, "Backoff stops growing at 16 seconds")
    now = 48
    agent.revision = 2
    poller.update([agent])
    precondition(callbacks.count == 1, "A new revision ends the old backoff after the two-second cooldown")
    callbacks.removeFirst()(nil)
    precondition(retry?.deadline == 50, "A new revision resets the retry delay to two seconds")
    fire(at: 50, result: .screen("RECOVERED QUESTION"))
    precondition(texts[agent.id] == "RECOVERED QUESTION" && retry == nil)
    now = 52
    agent.revision = 3
    poller.update([agent])
    callbacks.removeFirst()(nil)
    precondition(retry?.deadline == 54, "Success resets the retry delay to two seconds")
    poller.update([])
    precondition(retry == nil)
    print("PASS: Failed reads back off by 2, 4, 8, and 16 seconds, with revision and success resets")

    agent.revision = nil
    now = 54
    poller.update([agent])
    callbacks.removeFirst()(.screen("UNCONFIRMED FIRST"))
    precondition(retry == nil, "A successful read without a revision uses agent polling")
    now = 55
    poller.update([agent])
    precondition(callbacks.isEmpty, "A missing revision does not bypass the cooldown")
    now = 56
    poller.update([agent])
    precondition(callbacks.count == 1, "A missing revision permits another read on the next eligible poll")
    callbacks.removeFirst()(.screen("UNCONFIRMED SECOND"))
    precondition(texts[agent.id] == "UNCONFIRMED SECOND" && retry == nil)
    poller.update([])
    print("PASS: Panes without revisions refresh on eligible polls without a success timer")
}

private func reviewRegressionSelfTest(_ sample: CustomPet) {
    var failures: [String] = []
    let screen = CGRect(x: 0, y: 0, width: 500, height: 700)
    for (index, band) in [CGRect(x: 50, y: 300, width: 100, height: 30), CGRect(x: 20, y: 20, width: 40, height: 12), CGRect(x: 20, y: 620, width: 40, height: 12)].enumerated() {
        let pet = Pet(id: "entry-\(index)", kind: .codex, spot: CGPoint(x: 0.5, y: 0.5), in: band)
        pet.setCharacter(.custom("large-entry", 1), frames: sample.frames(sizePercent: 200, share: 1))
        pet.setStatus("blocked")
        let world = World(band: band, path: Perimeter(r: screen.insetBy(dx: 29, dy: 29)), cursor: CGPoint(x: 0, y: 350), scale: 1.5, still: false, usableBounds: screen)
        for tick in 0..<500 { _ = pet.step(t: Double(tick) / 30, dt: 1 / 30, world: world) }
        if pet.isDashing || abs(pet.zRotation + .pi / 2) > 0.01 { failures.append("Large custom pet cannot enter the left edge from home case \(index).") }
    }
    let narrow = CGRect(x: 470, y: 200, width: 20, height: 10)
    let idle = Pet(id: "narrow-home", kind: .codex, spot: CGPoint(x: 0.5, y: 0.5), in: narrow)
    idle.setCharacter(.custom("large-home", 1), frames: sample.frames(sizePercent: 200, share: 1))
    idle.setStatus("idle")
    let narrowWorld = World(band: narrow, path: Perimeter(r: screen.insetBy(dx: 29, dy: 29)), cursor: .zero, scale: 1.5, still: false, usableBounds: screen)
    var idleMoves = false
    for tick in 0..<500 { idleMoves = idle.step(t: Double(tick) / 30, dt: 1 / 30, world: narrowWorld) }
    if idleMoves { failures.append("A large idle pet never settles in a narrow home near the screen edge.") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("assignments.json")
    let store = AssignmentStore(file: url)
    var original = AssignmentDocument()
    original.cells = [GridAssignment(repository: "", role: "", agentType: "", pet: "builtin:cat")]
    try! store.save(original, expected: nil)
    var next = original; next.cells[0].pet = "builtin:robot"
    try! store.save(next, expected: store.snapshot)
    try! Data("broken".utf8).write(to: url)
    let restarted = AssignmentStore(file: url)
    if restarted.load() != original { failures.append("A restart did not recover the valid backup.") }
    next.cells[0].pet = "builtin:seed"
    try! restarted.save(next, expected: restarted.snapshot)
    let backup = try? JSONDecoder().decode(AssignmentDocument.self, from: Data(contentsOf: url.appendingPathExtension("bak")))
    if backup != original { failures.append("Repair after restart replaced the valid backup.") }

    var clock = 0.0
    var requests: [(Agent, (BlockedTextResult?) -> Void)] = []
    let queue = BlockedTextPoller(clock: { clock }, reader: { requests.append(($0, $1)) }, onChange: { _ in })
    let agents = ["A", "B", "C"].map { Agent(terminal_id: $0, agent_status: "blocked", agent: "codex", pane_id: "w1:p" + $0, agent_session: AgentSession(value: $0, kind: "id")) }
    queue.update(agents)
    clock = 3
    let complete = requests[0].1
    complete(nil)
    if requests.count != 3 || requests[2].0.terminal_id != "C" { failures.append("A slow read retried before the waiting third pane.") }
    if !failures.isEmpty {
        for message in failures { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)) }
        exit(1)
    }
    print("PASS: Large home pets reach edges, backup survives restart, and slow reads do not starve waiting panes")
}

func poolAssignmentSelfTest() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("assignments.json")
    let data = Data("{\"version\":1,\"repositories\":[],\"roles\":[],\"cells\":[{\"repository\":\"\",\"role\":\"\",\"agentType\":\"codex\",\"pet\":\"builtin:cat\",\"pets\":[\"builtin:cat\",\"builtin:robot\"]}]}".utf8)
    try! data.write(to: file)
    let catalog = RolePets(directory: folder, log: { _ in })
    catalog.reload()
    let agents = (0..<100).map { Agent(terminal_id: "pool-\($0)", agent_status: "working", agent: "codex") }
    let choices = agents.map { catalog.character(for: $0, mode: .custom) }
    if !choices.contains(.builtin(.cat)) || !choices.contains(.builtin(.robot)) {
        FileHandle.standardError.write(Data("FAIL: A rule pool must select from both configured pets.\n".utf8))
        exit(1)
    }
    precondition(zip(agents, choices).allSatisfy { catalog.character(for: $0.0, mode: .custom) == $0.1 })
    precondition(choices.allSatisfy { $0 == .builtin(.cat) || $0 == .builtin(.robot) })
    let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog.assignments.document)) as! [String: Any]
    let cells = encoded["cells"] as! [[String: Any]]
    precondition(cells[0]["pet"] as? String == "builtin:cat")
    precondition(cells[0]["pets"] as? [String] == ["builtin:cat", "builtin:robot"])
    func savePool(_ tokens: [String]) {
        var doc = catalog.assignments.document
        doc.setPool(tokens, repository: "", role: "", agentType: "codex")
        try! catalog.assignments.save(doc, expected: catalog.assignments.snapshot)
        catalog.reload()
    }
    savePool(["builtin:robot", "builtin:cat"])
    precondition(zip(agents, choices).allSatisfy { catalog.character(for: $0.0, mode: .custom) == $0.1 })
    savePool(["builtin:cat", "builtin:robot", "builtin:star"])
    let added = agents.map { catalog.character(for: $0, mode: .custom) }
    precondition(zip(choices, added).allSatisfy { $0.0 == $0.1 || $0.1 == .builtin(.star) })
    precondition(added.contains(.builtin(.star)))
    savePool(["builtin:cat", "builtin:star"])
    precondition(zip(agents, added).allSatisfy {
        $0.1 == .builtin(.robot) || catalog.character(for: $0.0, mode: .custom) == $0.1
    })
    savePool(["custom:missing", "builtin:cat"])
    precondition(agents.allSatisfy { catalog.character(for: $0, mode: .custom) == .builtin(.cat) })
    savePool(["builtin:cat", "builtin:robot", "builtin:cat"])
    precondition(catalog.assignments.document.cells[0].pets == ["builtin:cat", "builtin:robot"])
    precondition(catalog.possible(mode: .custom, agents: []).builtin.isSuperset(of: [.cat, .robot]))
    var invalid = catalog.assignments.document
    invalid.cells[0].pets = ["builtin:cat", "builtin:cat"]
    let beforeInvalid = try! Data(contentsOf: file)
    do { try catalog.assignments.save(invalid, expected: catalog.assignments.snapshot); fatalError("Duplicate raw pool accepted") }
    catch AssignmentError.invalid {} catch { fatalError("Unexpected pool save error") }
    precondition((try! Data(contentsOf: file)) == beforeInvalid)
    var old = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    var oldCell = (old["cells"] as! [[String: Any]])[0]; oldCell.removeValue(forKey: "pets"); old["cells"] = [oldCell]
    try! JSONSerialization.data(withJSONObject: old).write(to: file)
    catalog.reload()
    precondition(catalog.assignments.document.cells[0].pets == ["builtin:cat"])
    precondition(agents.allSatisfy { catalog.character(for: $0, mode: .custom) == .builtin(.cat) })
    savePool([])
    precondition(catalog.assignments.document.cells.isEmpty)
    precondition(catalog.character(for: agents[0], mode: .custom) == .builtin(.codex))
    var aliases = AssignmentDocument()
    aliases.setPool(["builtin:cat"], repository: "~/pool-project/", role: "", agentType: "codex")
    aliases.setPool(["builtin:robot"], repository: NSHomeDirectory() + "/pool-project", role: "", agentType: "codex")
    precondition(aliases.cells.count == 1 && aliases.cells[0].pets == ["builtin:robot"])
    print("PASS: Rule pool distribution, stable picks, allowed members, and legacy first pet")
}

// Flush edges choose the floor, survive a move to another screen size, and carry Broadway and clusters with them.
func floorSelfTest() {
    let walls = CGRect(x: 0, y: 0, width: 1000, height: 700)
    precondition(floorEdge(of: CGRect(x: 300, y: 640, width: 260, height: 60), in: walls) == .top)
    precondition(floorEdge(of: CGRect(x: 300, y: 637, width: 260, height: 60), in: walls) == .bottom)   // A 3 pt gap stays upright
    precondition(floorEdge(of: CGRect(x: 0, y: 0, width: 260, height: 60), in: walls) == .bottom)       // Corner: the longer side wins
    precondition(floorEdge(of: CGRect(x: 0, y: 0, width: 60, height: 260), in: walls) == .left)
    let saved = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode({ () -> Preferences in
        var value = Preferences()
        value.selectScreen("A", placement: ScreenArea(CGRect(x: 0, y: 640, width: 260, height: 60), in: walls))
        value.clusterMode = .project
        value.shortcuts = [ShortcutAction.toggleMovement.rawValue: Shortcut(keyCode: 11, modifiers: NSEvent.ModifierFlags([.command, .option, .control, .shift]).rawValue, key: "B")]
        return value
    }()))
    let taller = CGRect(x: 0, y: 0, width: 1400, height: 900)
    precondition(saved.screenAreas["A"]!.rect(in: taller) == CGRect(x: 0, y: 840, width: 260, height: 60))
    precondition(saved.clusterMode == .project && saved.shortcuts["toggleMovement"]?.title == "⌃⌥⇧⌘B")
    let old = try! JSONDecoder().decode(Preferences.self, from: Data("{\"movementMode\":\"broadway\",\"screenAreas\":{\"A\":{\"right\":20,\"bottom\":8,\"width\":260,\"height\":60}}}".utf8))
    precondition(old.movementMode == .broadway && old.clusterMode == .off && old.shortcuts.isEmpty && old.screenAreas["A"]!.rect(in: walls).minY == 8)
    precondition(projectName("/Users/ic/r/worktrees/dot/ingwon--ic-1757/bin") == "dot" && projectName("/home/me/r/herdr-pets/src") == "herdr-pets"
        && projectName("~/notes") == "notes" && projectName(nil) == nil)

    // A top-floor Broadway pet walks its group's part of the line upside down and stays inside it.
    let area = CGRect(x: 300, y: 640, width: 260, height: 60)
    let lane = broadwayBand(walls, area: area, floor: .top, scale: 1)
    let parts = segments(of: lane, floor: .top, weights: [1, 1], gap: 24)
    precondition(lane.minY == 700 - footOffset - 2 && parts[0].maxX + 24 == parts[1].minX)
    let pet = Pet(id: "top", kind: .codex, spot: CGPoint(x: 0.5, y: 0), in: parts[1], floor: .top)
    pet.setStatus("working")
    let world = World(band: parts[1], path: Perimeter(r: walls.insetBy(dx: footOffset + 2, dy: footOffset + 2)), cursor: .zero, scale: 1, still: false,
                      broadway: true, usableBounds: walls, floor: .top)
    var low = CGFloat.infinity, high = -CGFloat.infinity
    for tick in 0..<3000 {
        _ = pet.step(t: Double(tick) / 30, dt: 1 / 30, world: world)
        if tick > 300 {
            precondition(pet.zRotation == .pi && abs(pet.position.y - lane.minY) < 0.01 && parts[1].insetBy(dx: -1.5, dy: -1).contains(pet.position))
            low = min(low, pet.position.x); high = max(high, pet.position.x)
        }
    }
    precondition(low < parts[1].minX + 40 && high > parts[1].maxX - 40)

    // Large pets under an area 3 pt below the top: the art cannot reach the lane, but working pets still walk and resting pets stop.
    let nearTop = broadwayBand(walls, area: CGRect(x: 300, y: 637, width: 260, height: 60), floor: .bottom, scale: 1.5)
    let tall = World(band: nearTop, path: world.path, cursor: .zero, scale: 1.5, still: false, broadway: true, usableBounds: walls, floor: .bottom)
    let walker = Pet(id: "walker", kind: .codex, spot: CGPoint(x: 0.5, y: 0), in: nearTop), rester = Pet(id: "rester", kind: .claude, spot: CGPoint(x: 0.3, y: 0), in: nearTop)
    walker.setStatus("working"); rester.setStatus("idle")
    var left = CGFloat.infinity, right = -CGFloat.infinity, resting = false
    for tick in 0..<3000 {
        _ = walker.step(t: Double(tick) / 30, dt: 1 / 30, world: tall)
        resting = !rester.step(t: Double(tick) / 30, dt: 1 / 30, world: tall)
        if tick > 300 { left = min(left, walker.position.x); right = max(right, walker.position.x) }
    }
    // Check the span, not distinct x values. A fast random walk speed skips whole points.
    precondition(left < nearTop.minX + 100 && right > nearTop.maxX - 100 && resting && walker.position.y < nearTop.minY)
    print("PASS: Flush-edge floors, saved snaps and shortcuts, project names, a clustered top-floor Broadway walk, and a walk under a wall")
}
