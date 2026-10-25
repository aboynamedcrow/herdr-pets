import AppKit

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

    init(root: CALayer, roles: RolePets? = nil) { self.root = root; self.roles = roles }

    // If there are too many, show blocked first and asleep last.
    // Art changes keep the same pet and its position.
    func apply(_ agents: [Agent]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        roles?.refresh()
        self.agents = agents
        let awake = agents.filter { !$0.asleep }
        let shown = (awake.filter { $0.agent_status == "blocked" } + awake.filter { $0.agent_status != "blocked" } + agents.filter(\.asleep)).prefix(maxPets)
        var changed = false
        for (id, pet) in pets where !shown.contains(where: { $0.id == id }) {
            changed = true
            pets[id] = nil
            pet.fade(out: true)
        }
        let band = crowdBand(area, scale: petScale)
        for agent in shown {
            let pet = pets[agent.id] ?? {
                let pet = Pet(id: agent.id, kind: petKind(for: agent), spot: freeSpot(in: band), in: band)
                root.addSublayer(pet.layer)
                root.addSublayer(pet.badge)
                pet.fade(out: false)
                pets[agent.id] = pet
                return pet
            }()
            let character = roles?.character(for: agent, mode: demo ? .agent : preferences.characterMode) ?? .builtin(petKind(for: agent))
            if pet.setCharacter(character, frames: roles?.frames(for: character)) { changed = true }
            if pet.setStatus(agent.asleep ? "asleep" : agent.agent_status) { changed = true }
        }
        if changed && preferences.visible { update() }   // Show the new status in this same commit, not one tick later
    }

    // A random spot that leans toward the middle and skips the outer 15%, retried only when it lands right on top of another pet.
    private func freeSpot(in band: CGRect) -> CGPoint {
        func centered() -> CGFloat { 0.5 + (.random(in: -0.35...0.35) + .random(in: -0.35...0.35)) / 2 }   // Sum of two: peaks at the middle
        let taken = pets.values.map { point($0.spot, in: band) }
        let near = baseSize * petScale * 0.15
        var spot = CGPoint.zero
        for _ in 0..<8 {
            spot = CGPoint(x: centered(), y: centered())
            let p = point(spot, in: band)
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
        let world = World(band: crowdBand(area, scale: petScale),
                          path: Perimeter(r: walls.insetBy(dx: footOffset * petScale + 2, dy: footOffset * petScale + 2)),
                          cursor: CGPoint(x: mouse.x - screenOrigin.x, y: mouse.y - screenOrigin.y),
                          scale: petScale,
                          still: motionReduced)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var moving = false
        for pet in pets.values {
            if pet.step(t: t, dt: dt, world: world) { moving = true }
        }
        CATransaction.commit()
        if !moving { stop(); return }   // Fades run in the render server and finish without the timer
        let fps: Double = pets.values.contains { $0.isDashing } ? 30 : 15
        if timer?.timeInterval != 1 / fps { schedule(fps: fps) }
    }
}
