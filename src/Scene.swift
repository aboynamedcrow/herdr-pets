import AppKit
import SpriteKit

// Scene coordinates = the whole screen the overlay covers.
final class PetScene: SKScene {
    private(set) var pets: [String: Pet] = [:]    // terminal_id → pet
    private(set) var agents: [Agent] = []
    var area = CGRect.zero          // Crowd area
    var walls = CGRect.zero         // Screen below the menu bar and above the Dock
    var screenOrigin = CGPoint.zero // Converts the cursor to scene coordinates
    private var lastTime: Double?

    // If there are too many, show blocked first.
    // Pets that disappeared or whose character changed (agent kind or character option) leave and come back new.
    func apply(_ agents: [Agent]) {
        self.agents = agents
        let shown = (agents.filter { $0.agent_status == "blocked" } + agents.filter { $0.agent_status != "blocked" }).prefix(maxPets)
        var changed = false
        for (id, pet) in pets where !shown.contains(where: { $0.terminal_id == id && petKind(for: $0) == pet.kind }) {
            changed = true
            pets[id] = nil
            pet.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        let band = crowdBand(area, scale: petScale)
        for agent in shown {
            let pet = pets[agent.terminal_id] ?? {
                let pet = Pet(id: agent.terminal_id, kind: petKind(for: agent), at: randomPoint(in: band))
                pet.alpha = 0
                pet.run(.fadeIn(withDuration: 0.25))
                addChild(pet)
                pets[agent.terminal_id] = pet
                return pet
            }()
            if pet.status != agent.agent_status {
                pet.setStatus(agent.agent_status)
                changed = true
            }
        }
        // Don't wake if nothing changed. Each wake reallocates a screen-sized draw buffer, which is costly.
        if changed { wake() }
    }

    func wake() {
        if preferences.visible { view?.isPaused = false }
    }

    override func update(_ currentTime: TimeInterval) {
        let t = ProcessInfo.processInfo.systemUptime   // Same clock as Pet's rest timer
        let dt = CGFloat(min(t - (lastTime ?? t), 0.1))
        lastTime = t
        let mouse = NSEvent.mouseLocation
        let world = World(band: crowdBand(area, scale: petScale),
                          path: Perimeter(r: walls.insetBy(dx: footOffset * petScale + 2, dy: footOffset * petScale + 2)),
                          cursor: CGPoint(x: mouse.x - screenOrigin.x, y: mouse.y - screenOrigin.y),
                          scale: petScale,
                          still: motionReduced)
        var moving = false
        for pet in pets.values {
            if pet.step(t: t, dt: dt, world: world) { moving = true }
        }
        view?.preferredFramesPerSecond = pets.values.contains { $0.isDashing } ? 30 : 15
        if !moving && !children.contains(where: { $0.hasActions() }) { view?.isPaused = true }
    }
}
