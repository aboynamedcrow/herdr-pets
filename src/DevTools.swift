import AppKit
import ImageIO

// Lay frames side by side on the app's anchor, then overlay them all in the last cell to spot jitter.
func exportFrames(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cell: CGFloat = 160, scale: CGFloat = 2.5
    for kind in PetKind.allCases {
        for (pose, frames) in Sprites.frames(kind) where frames.count > 1 {
            let context = bitmap(width: Int(cell) * (frames.count + 1), height: Int(cell))
            context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
            func draw(_ f: Frame, centerX: CGFloat, alpha: CGFloat) {
                let w = f.size.width * scale, h = f.size.height * scale
                context.setAlpha(alpha)
                context.draw(f.image, in: CGRect(x: centerX - w * f.anchorX, y: 16, width: w, height: h))
            }
            for (i, f) in frames.enumerated() { draw(f, centerX: cell * (CGFloat(i) + 0.5), alpha: 1) }
            let onion = cell * (CGFloat(frames.count) + 0.5)
            for f in frames { draw(f, centerX: onion, alpha: 0.35) }
            context.setAlpha(1)
            context.setStrokeColor(CGColor(red: 0.8, green: 0.3, blue: 0.3, alpha: 0.6))
            context.stroke(CGRect(x: 0, y: 16, width: context.width, height: 0))   // baseline
            context.stroke(CGRect(x: onion, y: 0, width: 0, height: cell))         // centroid line
            let url = directory.appendingPathComponent("\(kind.rawValue)-\(pose.rawValue).png")
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, context.makeImage()!, nil)
            CGImageDestinationFinalize(destination)
        }
    }
    print("Exported aligned frame strips to \(directory.path)")
}

func selfTest() {
    machineSelfTest()
    // Unplugging falls back to the next most recent monitor; replugging doesn't change the order.
    var settings = Preferences()
    let frame = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    let positions = ["A": CGRect(x: 1020, y: 10, width: 180, height: 40),
                     "B": CGRect(x: 1400, y: 20, width: 200, height: 50),
                     "C": CGRect(x: 1720, y: 30, width: 260, height: 60)]
    for id in ["A", "B", "C"] {
        settings.selectScreen(id, placement: ScreenArea(positions[id]!, in: frame))
    }
    for (connected, expected) in [(["A", "B", "C"], "C"), (["A", "B"], "B"), (["A"], "A"), (["C", "A", "B"], "C")] {
        let id = settings.preferredScreen(in: connected)!
        precondition(id == expected && settings.screenAreas[id]!.rect(in: frame) == positions[id]!)
    }
    settings.selectScreen("B", placement: settings.screenAreas["B"]!)
    precondition(settings.screenOrder == ["B", "C", "A"])
    let saved = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
    precondition(saved.screenOrder == settings.screenOrder && saved.screenAreas["C"]!.rect(in: frame) == positions["C"]!)

    for kind in PetKind.allCases {
        for (pose, frames) in Sprites.frames(kind) {
            precondition(frames.count == 1 || frames.count == pose.frameCount, "\(kind)-\(pose): 프레임 \(frames.count)장")
        }
    }

    precondition(petKind(ofType: "claude") == .claude && petKind(ofType: "Codex") == .codex)
    precondition(PetKind.generic.contains(petKind(ofType: "opencode")))
    preferences.allCharacters = true
    let assigned = (0..<200).map { petKind(for: Agent(terminal_id: "term-\($0)", agent_status: "idle", agent: "claude")) }
    precondition(Set(assigned).count > 8)
    preferences.allCharacters = false

    for size: CGFloat in [16, 24, 48, 72] {
        let scale = size / baseSize
        let band = crowdBand(CGRect(x: 1200, y: 20, width: 260, height: 80), scale: scale)
        let path = Perimeter(r: CGRect(x: 0, y: 12, width: 1512, height: 920).insetBy(dx: footOffset * scale + 2, dy: footOffset * scale + 2))
        let pet = Pet(id: "sim", kind: .blob, spot: CGPoint(x: 0.5, y: 0.5), in: band)
        var cursor = CGPoint(x: 300, y: 900)
        var t = ProcessInfo.processInfo.systemUptime
        func run(seconds: Double) {
            for _ in 0..<Int(seconds * 15) {
                t += 1.0 / 15
                _ = pet.step(t: t, dt: 1.0 / 15, world: World(band: band, path: path, cursor: cursor, scale: scale, still: false))
            }
        }
        pet.setStatus("working")
        for _ in 0..<40 { run(seconds: 1); precondition(band.insetBy(dx: -2, dy: -2).contains(pet.position)) }
        pet.setStatus("blocked"); run(seconds: 12)
        precondition(abs(pet.position.y - path.r.maxY) < 1 && abs(pet.position.x - cursor.x) < 60)   // cursor at top left → top edge
        precondition(abs(abs(pet.zRotation) - .pi) < 0.01)                                            // hanging upside down
        cursor = CGPoint(x: 1490, y: 500); run(seconds: 12)
        precondition(abs(pet.position.x - path.r.maxX) < 1 && abs(pet.zRotation - .pi / 2) < 0.01)    // right edge
        pet.setStatus("idle"); run(seconds: 12)
        precondition(band.insetBy(dx: -2, dy: -2).contains(pet.position) && pet.zRotation == 0)       // back to the crowd
        let resting = pet.position; run(seconds: 5)
        precondition(pet.position == resting)                                                          // idle stays put
        pet.setStatus("working"); run(seconds: 5)
        precondition(pet.position != resting)                                                          // working wanders
    }

    // Moving the area sends idle pets to their own spots in the new one instead of piling up at the nearest corner.
    let from = crowdBand(CGRect(x: 1200, y: 20, width: 260, height: 80), scale: 1)
    let to = crowdBand(CGRect(x: 100, y: 600, width: 260, height: 80), scale: 1)
    let path = Perimeter(r: CGRect(x: 0, y: 12, width: 1512, height: 920))
    let spots = [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.9, y: 0.5)]
    let crowd = spots.map { Pet(id: "sim", kind: .blob, spot: $0, in: from) }
    var t = ProcessInfo.processInfo.systemUptime
    for band in [from, to] {
        for _ in 0..<(20 * 15) {
            t += 1.0 / 15
            for pet in crowd { _ = pet.step(t: t, dt: 1.0 / 15, world: World(band: band, path: path, cursor: .zero, scale: 1, still: false)) }
        }
    }
    for (pet, spot) in zip(crowd, spots) { precondition(hypot(pet.position.x - point(spot, in: to).x, pet.position.y - point(spot, in: to).y) < 2) }

    // In a small area, working pets wander through the middle instead of sticking to the side walls.
    let small = crowdBand(CGRect(x: 1300, y: 0, width: 189, height: 60), scale: 1)
    let walker = Pet(id: "sim", kind: .blob, spot: CGPoint(x: 0.5, y: 0.5), in: small)
    walker.setStatus("working")
    var atWall = 0
    for _ in 0..<(120 * 15) {
        t += 1.0 / 15
        _ = walker.step(t: t, dt: 1.0 / 15, world: World(band: small, path: path, cursor: .zero, scale: 1, still: false))
        if walker.position.x < small.minX + 1 || walker.position.x > small.maxX - 1 { atWall += 1 }
    }
    precondition(atWall < 120 * 15 / 5)
    print("PASS: assets, character assignment, working moves / idle rests / blocked edge run / return at 4 sizes, area move keeps spread")
}

// Fetchers queue replies until the test releases them. The clock never waits.
private final class PollerFixture {
    var now = 100.0
    var agentReads: [String: Int] = [:]
    var listReads = 0
    var pending: [String: ([Agent]?) -> Void] = [:]
    var pendingList: (([Machine]?) -> Void)?
    var agents: [Agent] = []
    var connected = true
    var shouldExit = false
    var poller: AgentPoller!

    init(plugin: Bool = true) {
        poller = AgentPoller(launchedByPlugin: plugin, clock: { self.now }, readAgents: { machine, complete in
            let id = machine ?? "local"
            precondition(self.pending[id] == nil, "overlapping poll: \(id)")
            self.agentReads[id, default: 0] += 1
            self.pending[id] = complete
        }, readMachines: { complete in
            precondition(self.pendingList == nil, "overlapping machine list")
            self.listReads += 1
            self.pendingList = complete
        }) { agents, connected, shouldExit in
            self.agents = agents
            self.connected = connected
            self.shouldExit = shouldExit
        }
    }

    func tick(_ seconds: Double = 0, others: Bool = true) {
        now += seconds
        poller.tick(otherMachines: others)
    }

    func reply(_ machine: String, _ agents: [Agent]?) {
        let complete = pending.removeValue(forKey: machine)!
        complete(agents)
    }

    func machines(_ machines: [Machine]?) {
        let complete = pendingList!
        pendingList = nil
        complete(machines)
    }
}

private func machineSelfTest() {
    let agent = Agent(terminal_id: "term-1", agent_status: "idle", agent: "codex")
    let profiles = [Machine(id: "mac-a", enabled: true), Machine(id: "mac-b", enabled: true), Machine(id: "off", enabled: false)]

    // Merge identical terminal IDs without a collision. Only enabled profiles are read.
    let f = PollerFixture()
    f.tick()
    f.reply("local", [agent])
    f.machines(profiles)
    f.reply("mac-a", [agent])
    f.reply("mac-b", [agent])
    precondition(f.agents.map(\.machine) == ["local", "mac-a", "mac-b"])
    precondition(Set(f.agents.map(\.id)).count == 3 && f.pending["off"] == nil)
    precondition(f.agents[0].terminal_id == f.agents[1].terminal_id)
    precondition(Agent(terminal_id: "b:c", agent_status: "idle", machine: "a").id != Agent(terminal_id: "c", agent_status: "idle", machine: "a:b").id)
    print("PASS: machines 1/8 merge, enabled profiles, collision-free keys")

    // Local reads each 2 seconds, remotes each 6, and profiles each 60.
    f.tick(2)
    precondition(f.agentReads["local"] == 2 && f.agentReads["mac-a"] == 1 && f.listReads == 1)
    f.tick(4)   // Keep Local pending to prove that another source can still start.
    precondition(f.agentReads["local"] == 2 && f.agentReads["mac-a"] == 2)
    f.tick(6)
    precondition(f.agentReads["mac-a"] == 2 && f.agentReads["mac-b"] == 2)
    f.reply("local", [])
    f.reply("mac-a", [agent])
    f.reply("mac-b", [agent])
    f.tick(47)
    precondition(f.listReads == 1)
    f.tick(1)
    precondition(f.listReads == 2)
    f.tick(60)
    precondition(f.listReads == 2)   // One discovery call can stay pending too.
    print("PASS: machines 2/8 poll intervals and one in-flight call per source")

    // Labels never enter the pet key or character choice, and the scene keeps its pet.
    let before = f.agents.first { $0.machine == "mac-a" }!
    let oldVisible = preferences.visible, oldCharacters = preferences.allCharacters
    preferences.visible = false
    preferences.allCharacters = true
    let character = petKind(for: before)
    let testScene = PetScene(root: CALayer())
    testScene.apply(f.agents)
    let pet = testScene.pets[before.id]!
    let position = pet.position
    let renamed = try! JSONDecoder().decode([Machine].self, from: Data("[{\"id\":\"mac-a\",\"label\":\"New label 99\",\"enabled\":true},{\"id\":\"mac-b\",\"enabled\":true}]".utf8))
    f.machines(renamed)
    testScene.apply(f.agents)
    precondition(testScene.pets[before.id] === pet && pet.position == position)
    precondition(petKind(for: f.agents.first { $0.machine == "mac-a" }!) == character)
    preferences.visible = oldVisible
    preferences.allCharacters = oldCharacters
    print("PASS: machines 3/8 label changes keep character, pet, and position")

    // Start the hold at the first failed reply. Repeated failures never extend it.
    let hold = PollerFixture()
    hold.tick()
    hold.reply("local", [agent])
    hold.machines([profiles[0]])
    hold.reply("mac-a", [agent])
    hold.tick(6)
    hold.reply("mac-a", nil)
    hold.tick(59.9)
    hold.reply("mac-a", nil)
    precondition(hold.agents.count == 2 && hold.connected && !hold.shouldExit)
    precondition(!hold.agents.contains(where: \.asleep))
    hold.tick(0.1)
    precondition(hold.agents.map(\.machine) == ["local", "mac-a"] && hold.agents.map(\.asleep) == [false, true])
    for _ in 0..<100 {   // Asleep pets stay while the machine keeps failing.
        hold.tick(6)
        hold.reply("mac-a", nil)
    }
    precondition(hold.agents.map(\.asleep) == [false, true] && hold.agents[1].id == before.id)
    hold.tick(6)
    hold.reply("mac-a", [agent])
    precondition(hold.agents.count == 2 && hold.agents[1].id == before.id && !hold.agents[1].asleep)
    hold.tick(6)
    hold.reply("mac-a", [])
    precondition(hold.agents.count == 1)   // An empty success removes old pets at once.
    let asleep = PollerFixture()   // Disabling an asleep machine removes its pets.
    asleep.tick()
    asleep.reply("local", [])
    asleep.machines([profiles[0]])
    asleep.reply("mac-a", [agent])
    asleep.tick(6)
    asleep.reply("mac-a", nil)
    asleep.tick(60)
    precondition(asleep.agents.map(\.asleep) == [true])
    asleep.machines([Machine(id: "mac-a", enabled: false)])
    precondition(asleep.agents.isEmpty)
    let scene = PetScene(root: CALayer())
    let live = (0..<maxPets).map { Agent(terminal_id: "live-\($0)", agent_status: "idle") }
    var sleeper = Agent(terminal_id: "blocked", agent_status: "blocked", machine: "mac-a")
    sleeper.asleep = true
    scene.apply([sleeper] + live)
    precondition(scene.pets[sleeper.id] == nil && scene.pets.count == maxPets)   // Asleep pets go last when the screen is full.
    scene.apply([sleeper])
    precondition(scene.pets[sleeper.id]?.status == "asleep")
    sleeper.asleep = false
    scene.apply([sleeper])
    precondition(scene.pets[sleeper.id]?.status == "blocked")
    print("PASS: machines 4/8 60-second hold, sleep, recovery, empty success, disabled while asleep")

    // Off starts no discovery or remote call, even after an old reply arrives.
    let toggle = PollerFixture()
    toggle.tick(others: false)
    toggle.reply("local", [agent])
    precondition(toggle.listReads == 0 && toggle.agentReads == ["local": 1])
    toggle.tick(others: true)
    toggle.machines([profiles[0]])
    toggle.tick(others: false)
    toggle.reply("mac-a", [agent])
    precondition(toggle.agents.map(\.machine) == ["local"])
    toggle.tick(60, others: false)
    precondition(toggle.listReads == 1 && toggle.agentReads["mac-a"] == 1)
    toggle.tick(others: true)
    toggle.tick(others: false)
    toggle.machines(profiles)   // Ignore a discovery reply started before Off.
    precondition(toggle.agentReads["mac-b"] == nil)
    toggle.tick(others: true)
    toggle.machines([profiles[0]])
    toggle.reply("mac-a", [agent])
    precondition(toggle.agents.count == 2)
    print("PASS: machines 5/8 Local-only setting and late replies")

    // A removed and re-added profile cannot accept its earlier pending reply.
    let removal = PollerFixture()
    removal.tick()
    removal.reply("local", [])
    removal.machines([profiles[0]])
    removal.tick(60)
    removal.machines([])
    removal.tick(60)
    removal.machines([profiles[0]])
    precondition(removal.agentReads["mac-a"] == 1)
    removal.reply("mac-a", [agent])
    precondition(removal.agents.isEmpty)
    removal.tick()
    removal.reply("mac-a", [agent])
    precondition(removal.agents.count == 1)
    removal.tick(60)
    removal.machines(nil)
    precondition(removal.agents.count == 1)   // A discovery failure keeps known profiles.
    removal.tick(60)
    removal.machines([Machine(id: "mac-a", enabled: false)])
    precondition(removal.agents.isEmpty)
    print("PASS: machines 6/8 removal, re-addition, discovery failure, disabled profile")

    // Only completed Local failures count toward plugin exit. Success resets the count.
    for plugin in [false, true] {
        let exit = PollerFixture(plugin: plugin)
        exit.tick()
        exit.machines([profiles[0]])
        exit.reply("local", [agent])
        exit.reply("mac-a", nil)
        for _ in 0..<15 {
            exit.tick(6)
            exit.reply("local", [])
            exit.reply("mac-a", nil)
            precondition(exit.poller.localFailures == 0 && !exit.shouldExit)
        }
        for count in 1...14 {
            exit.tick(2)
            exit.reply("local", nil)
            precondition(exit.poller.localFailures == count && !exit.shouldExit && !exit.connected)
        }
        exit.tick(2)
        exit.reply("local", nil)
        precondition(exit.shouldExit == plugin)
        exit.tick(2)
        exit.reply("local", [agent])
        precondition(exit.poller.localFailures == 0 && !exit.shouldExit && exit.connected)
    }
    print("PASS: machines 7/8 remote failures never exit, 15 Local failures, reset, direct run")

    var settings = try! JSONDecoder().decode(Preferences.self, from: Data("{\"size\":32}".utf8))
    precondition(settings.otherMachines && settings.size == 32)
    settings.otherMachines = false
    let saved = try! JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(settings))
    precondition(!saved.otherMachines && saved.size == 32)
    print("PASS: machines 8/8 preference default and persistence")
}
