import AppKit

let maxPets = 20

// Scene coordinates = the whole screen the overlay covers.
final class PetScene {
    private(set) var pets: [String: Pet] = [:]    // terminal_id → pet
    private(set) var agents: [Agent] = []
    var area = CGRect.zero          // Crowd area
    var walls = CGRect.zero         // Screen below the menu bar and above the Dock
    var screenOrigin = CGPoint.zero // Converts the cursor to scene coordinates
    private let root: CALayer
    private var timer: Timer?       // nil while every pet rests
    private var lastTime: Double?

    init(root: CALayer) { self.root = root }

    // If there are too many, show blocked first.
    // Pets that disappeared or whose character changed (agent kind or character option) leave and come back new.
    func apply(_ agents: [Agent]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        self.agents = agents
        let shown = (agents.filter { $0.agent_status == "blocked" } + agents.filter { $0.agent_status != "blocked" }).prefix(maxPets)
        var changed = false
        for (id, pet) in pets where !shown.contains(where: { $0.terminal_id == id && petKind(for: $0) == pet.kind }) {
            changed = true
            pets[id] = nil
            pet.fade(out: true)
        }
        let band = crowdBand(area, scale: petScale)
        for agent in shown {
            let pet = pets[agent.terminal_id] ?? {
                let pet = Pet(id: agent.terminal_id, kind: petKind(for: agent), at: randomPoint(in: band))
                root.addSublayer(pet.layer)
                root.addSublayer(pet.badge)
                pet.fade(out: false)
                pets[agent.terminal_id] = pet
                return pet
            }()
            if pet.setStatus(agent.agent_status) { changed = true }
        }
        if changed && preferences.visible { update() }   // Show the new status in this same commit, not one tick later
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
