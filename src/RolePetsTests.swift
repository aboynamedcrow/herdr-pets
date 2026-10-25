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
        chooseCharacter(pane, rules: list, home: home, fallback: petKind(ofType: pane.agent)) {
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
    var unusedLogs: [String] = []
    let withoutRules = RolePets(directory: directory.appendingPathComponent("absent"), clock: { now }, log: { unusedLogs.append($0) })
    for mode in [CharacterMode.agent, .random, .village] { withoutRules.refresh(mode: mode) }
    precondition(unusedLogs.isEmpty)
    withoutRules.refresh(mode: .custom)
    precondition(unusedLogs.count == 1)
    let catalog = RolePets(directory: directory, home: home, clock: { now }, log: { logs.append($0) })
    let pane = Agent(terminal_id: "a", agent_status: "idle", agent: "claude", label: "reviewer")
    catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude) && logs.count == 2)
    writeRules("bad json")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude) && logs.count == 2)
    writeRules("[{\"pet\":\"missing\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude) && logs.count == 3)
    writeRules("[{\"role\":\"reviewer\",\"pet\":\"sample\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude) && logs.count == 3)
    now += 60; catalog.refresh()
    precondition(logs.count == 3)
    print("PASS: role pets 4/10 missing rules, bad rules, missing id, missing sheet, one log per file")

    let sheetURL = folder.appendingPathComponent("sheet.png")
    let destination = CGImageDestinationCreateWithURL(sheetURL as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, sheet, nil)
    precondition(CGImageDestinationFinalize(destination))
    catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude))
    now += 60; catalog.refresh()
    let custom = catalog.character(for: pane, mode: .custom)
    guard case .custom("sample", _) = custom else { preconditionFailure() }
    precondition(catalog.frames(for: custom)![.working]!.count == 2)
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == custom)
    precondition(catalog.character(for: pane, mode: .agent) == .builtin(.claude))
    preferences.characterMode = .random
    precondition(catalog.character(for: pane, mode: .random) == .builtin(petKind(for: pane)))
    writeRules("[{\"pet\":\"agent\"}]")
    now += 60; catalog.refresh(mode: .custom)
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(petKind(ofType: pane.agent)))
    preferences.characterMode = .custom
    print("PASS: role pets 5/10 PNG decode, 60-second reload, cached art, modes, agent fallback")

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
    precondition(scene.pets[pane.id] === pet && pet.character == catalog.character(for: pane, mode: .custom))
    let unruledFolder = directory.appendingPathComponent("unruled")
    try! FileManager.default.createDirectory(at: unruledFolder, withIntermediateDirectories: true)
    try! Data("{\"id\":\"unruled\",\"displayName\":\"Unruled sample\",\"spriteVersionNumber\":2,\"spritesheetPath\":\"sheet.png\"}".utf8)
        .write(to: unruledFolder.appendingPathComponent("pet.json"))
    try! FileManager.default.copyItem(at: sheetURL, to: unruledFolder.appendingPathComponent("sheet.png"))
    now += 60; catalog.refresh()
    precondition(catalog.customIDs == ["sample", "unruled"] && catalog.thumbnail("unruled")?.title == "Unruled sample")
    let restarted = RolePets(directory: directory, home: home, clock: { now }, log: { _ in })
    restarted.refresh()
    for index in 0..<100 {
        let candidate = Agent(terminal_id: "scan-\(index)", agent_status: "idle", agent: "codex")
        let old = catalog.character(for: candidate, mode: .village), fresh = restarted.character(for: candidate, mode: .village)
        if case .custom(let id, _) = old {
            guard case .custom(let other, _) = fresh else { preconditionFailure() }
            precondition(id == other)
        } else { precondition(old == fresh) }
    }
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
    precondition(old.characterMode == .custom && old.maxPets == 20)
    var saved = old
    saved.characterMode = .agent; saved.maxPets = 60
    let restored = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(saved))
    precondition(restored.characterMode == .agent && restored.maxPets == 60 && restored.size == 32)
    for (input, expected) in [(0, 10), (100, 60)] {
        let value = try! JSONDecoder().decode(Preferences.self, from: Data("{\"maxPets\":\(input)}".utf8))
        precondition(value.maxPets == expected)
    }
    preferences = Preferences()
    print("PASS: role pets 8/10 preference defaults, persistence, and bounds")

    writeRules("[{\"pet\":\"sample\"}]")
    try! Data("{}".utf8).write(to: metadata)
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude))
    writeRules("[{\"pet\":\"../outside\"}]")
    now += 60; catalog.refresh()
    precondition(catalog.character(for: pane, mode: .custom) == .builtin(.claude))
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
    precondition(orchestration.character(for: pane, mode: .custom) == .builtin(.claude))
    modesSelfTest(art)
    preferences = Preferences()
    print("PASS: role pets 10/10 cwd position and bad custom override fallback")
}

private func modesSelfTest(_ art: CustomPet) {
    let rules = [PetRule(role: ["reviewer"], pet: "sample"), PetRule(role: ["oracle"], pet: "generic")]
    let first = RolePets(rules: rules, customPets: ["sample": art, "unruled": art])
    let second = RolePets(rules: rules, customPets: ["unruled": art, "sample": art])
    let empty = RolePets(rules: [], customPets: [:])
    for type in ["claude", "codex", "opencode"] {
        let pane = Agent(terminal_id: "modes", agent_status: "idle", agent: type, label: "reviewer")
        for mode in CharacterMode.allCases {
            let value = first.character(for: pane, mode: mode)
            precondition(value == second.character(for: pane, mode: mode))
            switch mode {
            case .agent: precondition(value == .builtin(petKind(ofType: type)))
            case .random: precondition(value == .builtin(pick(PetKind.allCases, by: pane.id)))
            case .custom: precondition(value == .custom("sample", 1))
            case .village: precondition(value == first.character(for: pane, mode: mode))
            }
        }
        precondition(empty.character(for: pane, mode: .village) == empty.character(for: pane, mode: .random))
        precondition(empty.character(for: pane, mode: .custom) == first.character(for: pane, mode: .agent))
        let fallback = Agent(terminal_id: "fallback", agent_status: "idle", agent: type)
        precondition(first.character(for: fallback, mode: .custom) == .builtin(petKind(ofType: type)))
        let agentRule = RolePets(rules: [PetRule(pet: "agent")], customPets: [:])
        precondition(agentRule.character(for: pane, mode: .custom) == .builtin(petKind(ofType: type)))
    }
    let unruled = (0..<1000).map { Agent(terminal_id: "village-\($0)", agent_status: "idle", agent: "claude") }
        .first { first.character(for: $0, mode: .village) == .custom("unruled", 1) }!
    precondition(first.character(for: unruled, mode: .village) == second.character(for: unruled, mode: .village))
    let removedLoser = RolePets(rules: [], customPets: ["unruled": art])
    precondition(first.character(for: unruled, mode: .village) == removedLoser.character(for: unruled, mode: .village))
    let possible = first.possible(mode: .custom, agents: [])
    precondition(possible.custom == ["sample"] && possible.builtin == Set(PetKind.allCases))
    precondition(first.possible(mode: .random, agents: []).custom.isEmpty)
    precondition(first.possible(mode: .village, agents: []).custom == ["sample", "unruled"])
    print("PASS: modes 1/4 four modes, three agent types, unruled Village pet, stable instances, empty fallbacks, gallery")

    let rows: [(String, CharacterMode)] = [
        ("{}", .custom), ("{\"allCharacters\":false}", .custom), ("{\"rolePets\":true,\"allCharacters\":false}", .custom),
        ("{\"rolePets\":true,\"allCharacters\":true}", .custom), ("{\"allCharacters\":true}", .custom),
        ("{\"rolePets\":false,\"allCharacters\":true}", .random),
        ("{\"rolePets\":false,\"allCharacters\":false}", .agent), ("{\"rolePets\":false}", .agent),
        ("{\"characterMode\":\"village\",\"rolePets\":true}", .village),
    ]
    for (json, mode) in rows {
        let value = try! JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
        precondition(value.characterMode == mode)
        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
        precondition(encoded["rolePets"] == nil && encoded["allCharacters"] == nil && encoded["characterMode"] as? String == mode.rawValue)
    }
    for (input, expected) in [(50, 100), (300, 200)] {
        let value = try! JSONDecoder().decode(Preferences.self, from: Data("{\"customPetSize\":\(input)}".utf8))
        precondition(value.customPetSize == expected)
    }
    precondition(Preferences().characterMode == .custom && Preferences().customPetSize == 130)
    print("PASS: modes 2/4 legacy migration, new keys, size defaults and clamps")

    preferences.visible = false
    let scene = PetScene(root: CALayer(), roles: first)
    let pane = Agent(terminal_id: "size", agent_status: "blocked", agent: "claude", label: "reviewer")
    preferences.characterMode = .custom
    scene.apply([pane])
    let pet = scene.pets[pane.id]!, spot = scene.pets[pane.id]!.spot, position = scene.pets[pane.id]!.position
    let base = art.frames[.resting]![0]
    let builtin = Sprites.frames(.claude)[.resting]![0].size
    var offset: CGFloat = 0
    for percent in [100, 130, 200] {
        preferences.customPetSize = percent
        scene.apply([pane])
        let frame = first.frames(for: pet.character)![.resting]![0]
        let factor = CGFloat(percent) / 100
        precondition(abs(frame.size.height - base.size.height * factor) < 0.001)
        precondition(abs(frame.size.width - base.size.width * factor) < 0.001)
        precondition(frame.image === base.image && CGFloat(frame.image.height) >= frame.size.height * 3)
        precondition(pet.artSize == frame.size && pet.badgeOffset > offset)
        precondition(pet.badgeOffset > (frame.size.height - footOffset) * petScale)
        precondition(scene.pets[pane.id] === pet && pet.position == position && pet.spot == spot)
        precondition(Sprites.frames(.claude)[.resting]![0].size == builtin)
        offset = pet.badgeOffset
    }
    for mode in CharacterMode.allCases {
        preferences.characterMode = mode
        scene.apply([pane])
        precondition(scene.pets[pane.id] === pet && pet.position == position && pet.spot == spot)
        precondition(pet.character == first.character(for: pane, mode: mode))
    }
    print("PASS: modes 3/4 custom sizes 100/130/200, shared pixels, built-in size, badge, immediate scene updates")

    for language in ["en", "ko"] {
        let control = characterControl(language: language)
        precondition(control.fittingSize.width <= 300)
        print("PASS: modes 4/4 \(language) character labels fit \(control.fittingSize.width) pt of 300 pt at 11 pt")
    }
}
