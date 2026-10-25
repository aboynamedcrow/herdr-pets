import AppKit

func studioSelfTest() {
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

    let roles = RolePets(rules: [PetRule(role: ["reviewer"], pet: "cat")], customPets: [:])
    precondition(roles.character(for: pane, mode: .custom) == .builtin(.cat))
    precondition(roles.resolve("builtin:robot", for: pane) == .builtin(.robot))
    print("PASS: Studio legacy fallback and explicit built-in selection")
}
