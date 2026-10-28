import AppKit
import ImageIO

var maxPets: Int { min(60, max(10, preferences.maxPets)) }

// Scene coordinates = the whole screen the overlay covers.
final class PetScene {
    private(set) var pets: [String: Pet] = [:]    // machine + terminal_id → pet
    private(set) var agents: [Agent] = []
    var area = CGRect.zero          // Crowd area
    var walls = CGRect.zero         // Screen below the menu bar and above the Dock
    var screenOrigin = CGPoint.zero // Converts the cursor to scene coordinates
    private let roles: RolePets?
    private let root: CALayer
    private var timer: Timer?       // nil while every pet rests
    private var lastTime: Double?
    private var bubbleManager: SpeechBubbles?
    var machineNames: [String: String] = [:]
    private var blockedTexts: [String: String] = [:]
    private var groups: [String: String] = [:]   // Pet id → cluster key. One empty key when clustering is off
    private lazy var blockedReader = BlockedTextPoller { [weak self] texts in
        self?.blockedTexts = texts
        self?.syncBubbles()
    }

    init(root: CALayer, roles: RolePets? = nil) { self.root = root; self.roles = roles }

    // If there are too many, show blocked first and asleep last.
    // Art changes keep the same pet and its position.
    func apply(_ agents: [Agent]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        roles?.refresh()
        let agents = agents.map { observed -> Agent in
            guard observed.agent == "attention" else { return observed }
            var agent = observed
            let previous = self.agents.first { $0.id == observed.id && observed.sessionKey != nil && $0.sessionKey == observed.sessionKey }
            // Keep art and assignment rules tied to the native agent during the hold.
            agent.agent = observed.agent_session?.agent ?? previous?.agent ?? observed.agent
            return agent
        }
        self.agents = agents
        let active = Set(agents.compactMap(\.sessionKey))
        if let roles { roles.agentOverrides = roles.agentOverrides.filter { active.contains($0.key) } }
        let awake = agents.filter { !$0.asleep }
        let shown = (awake.filter(\.needsAttention) + awake.filter { !$0.needsAttention } + agents.filter(\.asleep)).prefix(maxPets)
        var changed = false
        for (id, pet) in pets where !shown.contains(where: { $0.id == id }) {
            changed = true
            pets[id] = nil
            pet.fade(out: true)
        }
        groups = Dictionary(shown.map { ($0.id, clusterKey($0, mode: preferences.clusterMode)) }, uniquingKeysWith: { first, _ in first })
        let floors = layout()
        for (index, agent) in shown.enumerated() {
            let pet = pets[agent.id] ?? {
                let band = floors.bands[groups[agent.id] ?? ""] ?? floors.whole
                let pet = Pet(id: agent.id, kind: petKind(for: agent), spot: freeSpot(in: band, floor: floors.floor), in: band, floor: floors.floor)
                root.addSublayer(pet.layer)
                root.addSublayer(pet.badge)
                pet.fade(out: false)
                pets[agent.id] = pet
                return pet
            }()
            let character = roles?.character(for: agent, mode: demo ? .agent : preferences.characterMode) ?? .builtin(petKind(for: agent))
            let displayed: PetCharacter
            if demo && arguments.contains("--custom-demo"), let roles, !roles.customIDs.isEmpty { displayed = roles.resolve("custom:" + roles.customIDs[index % roles.customIDs.count], for: agent) }
            else { displayed = character }
            if pet.setCharacter(displayed, frames: roles?.frames(for: displayed)) { changed = true }
            if pet.setStatus(agent.asleep ? "asleep" : agent.needsAttention ? "blocked" : agent.agent_status) { changed = true }
        }
        let eligible = preferences.visible && preferences.showQuestionBubbles
        if demo {
            blockedTexts = Dictionary(uniqueKeysWithValues: agents.filter(\.needsAttention).compactMap { agent -> (String, String)? in
                if arguments.contains("--stage-preview") && arguments.contains("--bubble-fixtures") {
                    if agent.terminal_id == "bubble-empty" { return nil }
                    if agent.terminal_id == "bubble-wrapped" {
                        return (agent.id, """
                        The sample garden has a row of blue flowers beside a small stone path.
                        A display choice: the next preview can show every flower beside the winding
                        path or keep the smaller view with a single row and a short legend. Which view should appear
                        in the next preview?

                        ❯ 1. Show every flower
                        Use the wider view with all flowers and the complete path.
                        keep the legend below the picture so the colors remain easy to compare.
                        2. Keep the small view
                        """)
                    }
                }
                return (agent.id, "Preview question: Should I apply these changes?\n1. Apply\n2. Keep the current version")
            })
        } else { blockedReader.update(eligible ? agents.filter { pets[$0.id] != nil } : []) }
        syncBubbles()
        if changed && preferences.visible { update() }   // Show the new status in this same commit, not one tick later
    }

    // The floor and each group's part of the band. Groups follow cluster key order: Local first, unknown projects last.
    private func layout() -> (floor: Floor, whole: CGRect, bands: [String: CGRect]) {
        let floor = floorEdge(of: area, in: walls)
        let whole = preferences.movementMode == .broadway ? broadwayBand(walls, area: area, floor: floor, scale: petScale) : crowdBand(area, scale: petScale, floor: floor)
        let counts = Dictionary(groups.values.map { ($0, 1) }, uniquingKeysWith: +)
        let keys = counts.keys.sorted { clusterRank($0) != clusterRank($1) ? clusterRank($0) < clusterRank($1) : $0.localizedStandardCompare($1) == .orderedAscending }
        let parts = segments(of: whole, floor: floor, weights: keys.map { counts[$0]! }, gap: 24 * petScale)
        return (floor, whole, Dictionary(uniqueKeysWithValues: zip(keys, parts)))
    }

    // Each pet gets the world of its own group.
    private func worlds(cursor: CGPoint, still: Bool, broadway: Bool) -> [String: World] {
        let floors = layout()
        let base = World(band: floors.whole, path: Perimeter(r: walls.insetBy(dx: footOffset * petScale + 2, dy: footOffset * petScale + 2)),
                         cursor: cursor, scale: petScale, still: still, broadway: broadway, usableBounds: walls, floor: floors.floor)
        var result: [String: World] = [:]
        for id in pets.keys {
            var world = base
            world.band = floors.bands[groups[id] ?? ""] ?? floors.whole
            result[id] = world
        }
        return result
    }

    // A random spot that leans toward the middle and skips the outer 15%, retried only when it lands right on top of another pet.
    private func freeSpot(in band: CGRect, floor: Floor) -> CGPoint {
        func centered() -> CGFloat { 0.5 + (.random(in: -0.35...0.35) + .random(in: -0.35...0.35)) / 2 }   // Sum of two: peaks at the middle
        let taken = pets.values.map { point($0.spot, in: band, floor: floor) }
        let near = baseSize * petScale * 0.15
        var spot = CGPoint.zero
        for _ in 0..<8 {
            spot = CGPoint(x: centered(), y: centered())
            let p = point(spot, in: band, floor: floor)
            if !taken.contains(where: { hypot($0.x - p.x, $0.y - p.y) < near }) { break }
        }
        return spot
    }

    // Updates now; update() keeps the timer running while any pet moves.
    func wake() {
        if preferences.visible && timer == nil { update() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // .common keeps the timer running while a window is dragged or a menu is open.
    private func schedule(fps: Double) {
        stop()
        let timer = Timer(timeInterval: 1 / fps, repeats: true) { [unowned self] _ in update() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func update() {
        let t = ProcessInfo.processInfo.systemUptime   // Same clock as Pet's rest timer
        let dt = CGFloat(min(t - (lastTime ?? t), 0.1))
        lastTime = t
        let mouse = NSEvent.mouseLocation
        if let screen = screenContaining(CGPoint(x: screenOrigin.x + walls.midX, y: screenOrigin.y + walls.midY)) {
            walls = screen.visibleFrame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
        }
        let worlds = worlds(cursor: CGPoint(x: mouse.x - screenOrigin.x, y: mouse.y - screenOrigin.y), still: motionReduced, broadway: preferences.movementMode == .broadway)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var moving = false
        for (id, pet) in pets {
            pet.holdsBubble = bubbleManager?.holdsPet(id, pointer: mouse) ?? false
            if pet.step(t: t, dt: dt, world: worlds[id]!) { moving = true }
        }
        CATransaction.commit()
        syncBubbles()
        if !moving { stop(); return }   // Fades run in the render server and finish without the timer
        let fps: Double = pets.values.contains { $0.isDashing } ? 30 : 15
        if timer?.timeInterval != 1 / fps { schedule(fps: fps) }
    }
    private func syncBubbles() {
        guard preferences.visible && preferences.showQuestionBubbles else { bubbleManager?.hideAll(); return }
        if bubbleManager == nil { bubbleManager = SpeechBubbles() }
        bubbleManager?.update(agents: agents, pets: pets, texts: blockedTexts, origin: screenOrigin, screen: walls.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y), machineNames: machineNames, expandPreview: demo && arguments.contains("--stage-preview") && arguments.contains("--expand-bubbles"))
    }

    func exportPreview(to directory: URL) throws {
        guard !pets.isEmpty else { throw CocoaError(.coderValueNotFound) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stop()
        let worlds = worlds(cursor: CGPoint(x: walls.midX, y: walls.midY), still: motionReduced, broadway: preferences.movementMode == .broadway)
        let time = ProcessInfo.processInfo.systemUptime
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for index in 0..<180 { for (id, pet) in pets { _ = pet.step(t: time + Double(index) / 30, dt: 1 / 30, world: worlds[id]!) } }
        CATransaction.commit()
        syncBubbles()
        let context = bitmap(width: max(1, Int(root.bounds.width)), height: max(1, Int(root.bounds.height)))
        context.setFillColor(CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        root.render(in: context)
        let url = directory.appendingPathComponent("broadway.png")
        if let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
        }
        try bubbleManager?.exportPreviews(to: directory)
    }

}

// Clustering reads only the agent's machine and working folder, so it works the same for other machines' agents.
func clusterKey(_ agent: Agent, mode: ClusterMode) -> String {
    switch mode {
    case .off: return ""
    case .machine: return agent.machine
    case .project: return projectName(agent.cwd) ?? ""
    }
}

private func clusterRank(_ key: String) -> Int { key == "local" ? 0 : key.isEmpty ? 2 : 1 }

// The repository a folder belongs to, read from the path alone: worktrees/<repo>/… or ~/<code folder>/<repo>/… names <repo>.
func projectName(_ cwd: String?) -> String? {
    var parts = (cwd ?? "").split(separator: "/").map(String.init)
    if let index = parts.firstIndex(of: "worktrees"), index + 1 < parts.count { return parts[index + 1] }
    if parts.first == "~" { parts.removeFirst() }
    else if parts.count >= 2 && ["Users", "home"].contains(parts[0]) { parts.removeFirst(2) }
    if parts.count >= 2 && ["r", "src", "code", "dev", "repos", "projects", "work", "git", "Developer", "workspace"].contains(parts[0]) { return parts[1] }
    return parts.first
}
