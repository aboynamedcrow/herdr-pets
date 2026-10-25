import AppKit
import ImageIO

func rolePetsSelfTest() {
    preferences = Preferences()
    let response = Data("""
    {"id":"test","result":{"type":"pane_list","panes":[
      {"terminal_id":"shell","agent_status":"idle","label":"Shell"},
      {"terminal_id":"a","agent_status":"working","agent":"claude","label":"🔧 ImPlEmEnTeR 1 · Task","cwd":"/repo"},
      {"terminal_id":"b","agent_status":"blocked","agent":"codex"}
    ]}}
    """.utf8)
    let panes = try! decodePanes(response)
    precondition(panes.count == 2 && panes[0].cwd == "/repo" && panes[1].label == nil)
    precondition(roleWord(panes[0].label) == "implementer")
    precondition(roleWord("🧙‍♂️ ReViEwEr 11 · Task") == "reviewer")
    precondition(roleWord(nil) == nil && roleWord("Personal pane") == "personal")
    precondition(roleWord("123 reviewer") == nil)
    print("PASS: role pets 1/10 pane decode and role words")

    let home = "/fake/home"
    let repos = ["autointegrate-takehome", "dotfiles", "gtm", "hsys", "hsys-agents", "interviews", "tom-takehome", "toolbox"]
    let paths = ["~/r/hsysai/"] + repos.map { "~/r/worktrees/\($0)/" }
    let rules = [
        PetRule(role: ["implementer"], pet: "agent"),
        PetRule(role: ["reviewer"], agent: ["claude"], pet: "sample-a"),
        PetRule(role: ["reviewer"], agent: ["codex"], pet: "sample-b"),
        PetRule(role: ["researcher", "explorer"], pet: "sample-c"),
        PetRule(role: ["oracle"], pet: "generic"),
        PetRule(role: ["orchestrator"], agent: ["claude"], cwd: paths, pet: "sample-d"),
        PetRule(role: ["orchestrator"], agent: ["codex"], cwd: paths, pet: "sample-e"),
        PetRule(role: ["orchestrator"], pet: "sample-f"),
    ]
    func choose(_ pane: Agent, _ list: [PetRule] = rules) -> PetCharacter {
        chooseCharacter(pane, rules: list, home: home, fallback: petKind(for: pane)) {
            $0.hasPrefix("sample-") ? .custom($0, 1) : nil
        }
    }
    for type in ["claude", "codex"] {
        let fallback = PetCharacter.builtin(petKind(ofType: type))
        for role in ["implementer", "other", ""] {
            precondition(choose(Agent(terminal_id: "x", agent_status: "idle", agent: type, label: role)) == fallback)
        }
        for (role, expected) in [("reviewer", type == "claude" ? "sample-a" : "sample-b"),
                                 ("researcher", "sample-c"), ("explorer", "sample-c")] {
            precondition(choose(Agent(terminal_id: "x", agent_status: "idle", agent: type, label: role)) == .custom(expected, 1))
        }
        let oracle = Agent(terminal_id: "oracle", agent_status: "idle", agent: type, label: "oracle")
        guard case .builtin(let kind) = choose(oracle) else { preconditionFailure() }
        precondition(PetKind.generic.contains(kind) && choose(oracle) == choose(oracle))
        for path in [home + "/r/hsysai/project"] + repos.map({ home + "/r/worktrees/\($0)/branch" }) {
            precondition(choose(Agent(terminal_id: "x", agent_status: "idle", agent: type, label: "orchestrator", cwd: path)) == .custom(type == "claude" ? "sample-d" : "sample-e", 1))
        }
        for path in [home + "/r/hsysaix", home + "/r/worktrees/hsys-other/branch", "/other"] {
            precondition(choose(Agent(terminal_id: "x", agent_status: "idle", agent: type, label: "orchestrator", cwd: path)) == .custom("sample-f", 1))
        }
    }
    precondition(PetRule(cwd: ["~/r/hsysai"], pet: "agent").matches(Agent(terminal_id: "x", agent_status: "idle", cwd: home + "/r/hsysai/x"), home: home))
    let parsed = try! JSONDecoder().decode([PetRule].self, from: Data("""
    [{"role":"REVIEWER","agent":["codex"],"cwd":"~/r/hsysai/","pet":"cat"}]
    """.utf8))
    let reviewer = Agent(terminal_id: "x", agent_status: "idle", agent: "codex", label: "reviewer", cwd: home + "/r/hsysai/x")
    precondition(choose(reviewer, parsed) == .builtin(.cat))
    precondition(choose(reviewer, [PetRule(pet: "missing"), PetRule(pet: "cat")]) == .builtin(.codex))
    precondition(chooseCharacter(reviewer, rules: [PetRule(pet: "cat")], home: home, fallback: .codex, custom: { _ in .custom("cat", 1) }) == .custom("cat", 1))
    print("PASS: role pets 2/10 role table, ordered rules, custom precedence, path boundaries")

    let pixels = bitmap(width: 1536, height: 2288)
    pixels.setFillColor(NSColor.red.cgColor)
    // CGContext's origin is at the bottom. Sheet rows start at the top.
    for (row, count) in CustomPet.rowLimits.enumerated() {
        let used = row == 7 ? 2 : count
        for column in 0..<used {
            pixels.fill(CGRect(x: column * 192 + 20 + column, y: 2288 - row * 208 - 80, width: 30, height: 40))
        }
    }
    let sheet = pixels.makeImage()!
    let art = try! CustomPet(sheet: sheet)
    precondition(art.counts == [6, 8, 8, 4, 5, 8, 6, 2, 6])
    precondition(art.crop == CGRect(x: 20, y: 40, width: 37, height: 40))
    precondition(art.frames[.working]!.count == 2 && art.frames[.blocked]!.count == 6 && art.frames[.celebrate]!.count == 5 && art.frames[.resting]!.count == 6)
    let frames = art.frames.values.flatMap { $0 }
    precondition(frames.allSatisfy { $0.size == frames[0].size && $0.anchorX == 0.5 && $0.image.width == frames[0].image.width })
    do { _ = try CustomPet(sheet: bitmap(width: 10, height: 10).makeImage()!); preconditionFailure() } catch {}
    do { _ = try CustomPet(sheet: bitmap(width: 1536, height: 2288).makeImage()!); preconditionFailure() } catch {}
    print("PASS: role pets 3/10 synthetic alpha counts, short row, shared crop, invalid sheets")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let folder = directory.appendingPathComponent("sample")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let metadata = folder.appendingPathComponent("pet.json")
    try! Data("""
    {"id":"sample","displayName":"Sample","spriteVersionNumber":2,"spritesheetPath":"sheet.png"}
    """.utf8).write(to: metadata)
    let rulesFile = directory.appendingPathComponent("rules.json")
    var stamp = 1.0
    func writeRules(_ text: String) {
        try! Data(text.utf8).write(to: rulesFile)
        stamp += 1
        try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: stamp)], ofItemAtPath: rulesFile.path)
    }
    var now = 0.0, logs: [String] = []
    let catalog = RolePets(directory: directory, home: home, clock: { now }, log: { logs.append($0) })
    let pane = Agent(terminal_id: "a", agent_status: "idle", agent: "claude", label: "reviewer")
    catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude) && logs.count == 1)
    writeRules("bad json")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude) && logs.count == 1)
    writeRules("[{\"pet\":\"missing\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude) && logs.count == 2)
    writeRules("[{\"role\":\"reviewer\",\"pet\":\"sample\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude) && logs.count == 3)
    now += 60; catalog.refresh()
    precondition(logs.count == 3)
    print("PASS: role pets 4/10 missing rules, bad rules, missing id, missing sheet, one log per file")

    let sheetURL = folder.appendingPathComponent("sheet.png")
    let destination = CGImageDestinationCreateWithURL(sheetURL as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, sheet, nil)
    precondition(CGImageDestinationFinalize(destination))
    catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude))
    now += 60; catalog.refresh()
    let custom = catalog.character(for: pane, enabled: true)
    guard case .custom("sample", _) = custom else { preconditionFailure() }
    precondition(catalog.frames(for: custom)![.working]!.count == 2)
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == custom)
    precondition(catalog.character(for: pane, enabled: false) == .builtin(.claude))
    preferences.allCharacters = true
    precondition(catalog.character(for: pane, enabled: false) == .builtin(petKind(for: pane)))
    writeRules("[{\"pet\":\"agent\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(petKind(for: pane)))
    preferences.allCharacters = false
    print("PASS: role pets 5/10 PNG decode, 60-second reload, cached art, role toggle, agent setting")

    writeRules("[{\"role\":\"reviewer\",\"pet\":\"sample\"}]")
    now += 60; catalog.refresh()
    preferences.visible = false
    let scene = PetScene(root: CALayer(), roles: catalog)
    scene.apply([pane])
    let pet = scene.pets[pane.id]!
    let position = pet.position, spot = pet.spot
    var renamed = pane
    renamed.label = "Implementer 1"
    scene.apply([renamed])
    precondition(scene.pets[pane.id] === pet && pet.position == position && pet.spot == spot && pet.character == .builtin(.claude))
    scene.apply([pane])
    precondition(scene.pets[pane.id] === pet && pet.character == catalog.character(for: pane, enabled: true))
    try! FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: sheetURL.path)
    now += 60; scene.apply([pane])
    precondition(pet.character != custom && scene.pets[pane.id] === pet && pet.position == position)
    try! FileManager.default.removeItem(at: sheetURL)
    now += 60; scene.apply([pane])
    precondition(pet.character == .builtin(.claude) && scene.pets[pane.id] === pet)
    print("PASS: role pets 6/10 label and art changes keep pet, key, position, and spot")

    for limit in [10, 20, 60] {
        preferences.maxPets = limit
        let scene = PetScene(root: CALayer())
        let idle = (0..<70).map { Agent(terminal_id: "idle-\($0)", agent_status: "idle") }
        let blocked = Agent(terminal_id: "blocked", agent_status: "blocked")
        let sleeper = Agent(terminal_id: "sleep", agent_status: "blocked", asleep: true)
        scene.apply([sleeper] + idle + [blocked])
        precondition(scene.pets.count == limit && scene.pets[blocked.id] != nil && scene.pets[sleeper.id] == nil)
        scene.apply([sleeper, blocked])
        precondition(scene.pets.count == 2 && scene.pets[sleeper.id]?.status == "asleep")
    }
    print("PASS: role pets 7/10 max pets 10, 20, 60 and awake/asleep order")

    let old = try! JSONDecoder().decode(Preferences.self, from: Data("{\"size\":32}".utf8))
    precondition(old.rolePets && old.maxPets == 20)
    var saved = old
    saved.rolePets = false; saved.maxPets = 60
    let restored = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(saved))
    precondition(!restored.rolePets && restored.maxPets == 60 && restored.size == 32)
    for (input, expected) in [(0, 10), (100, 60)] {
        let value = try! JSONDecoder().decode(Preferences.self, from: Data("{\"maxPets\":\(input)}".utf8))
        precondition(value.maxPets == expected)
    }
    preferences = Preferences()
    print("PASS: role pets 8/10 preference defaults, persistence, and bounds")

    writeRules("[{\"pet\":\"sample\"}]")
    try! Data("{}".utf8).write(to: metadata)
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude))
    writeRules("[{\"pet\":\"../outside\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, enabled: true) == .builtin(.claude))
    print("PASS: role pets 9/10 bad metadata and invalid folder fallback")

    let orchestration = RolePets(directory: directory, home: home, clock: { now }, log: { _ in })
    writeRules("[{\"role\":\"orchestrator\",\"cwd\":\"~/r/hsysai/\",\"pet\":\"cat\"}]")
    orchestration.refresh()
    preferences.visible = false
    let movedScene = PetScene(root: CALayer(), roles: orchestration)
    var orchestrator = Agent(terminal_id: "o", agent_status: "idle", agent: "codex", label: "orchestrator", cwd: "/other")
    movedScene.apply([orchestrator])
    let moving = movedScene.pets[orchestrator.id]!, originalPosition = movedScene.pets[orchestrator.id]!.position
    orchestrator.cwd = home + "/r/hsysai/x"
    movedScene.apply([orchestrator])
    precondition(movedScene.pets[orchestrator.id] === moving && moving.position == originalPosition && moving.character == .builtin(.cat))
    let override = directory.appendingPathComponent("cat")
    try! FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
    writeRules("[{\"pet\":\"cat\"}]")
    now += 60; orchestration.refresh()
    precondition(orchestration.character(for: pane, enabled: true) == .builtin(.claude))
    preferences = Preferences()
    print("PASS: role pets 10/10 cwd position and bad custom override fallback")
}
