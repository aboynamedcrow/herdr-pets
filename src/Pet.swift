import SpriteKit

let maxPets = 20
let dashSpeed: CGFloat = 320      // pt/s
let returnSpeed: CGFloat = 200
let acceleration: CGFloat = 700   // pt/s²
let celebrationTime = 1.8

struct World {
    let band: CGRect      // Floor strip the crowd lives on (range for the pet's anchor)
    let path: Perimeter   // Screen-edge path a blocked pet runs along
    let cursor: CGPoint
    let scale: CGFloat
    let still: Bool       // Reduce Motion
}

func crowdBand(_ area: CGRect, scale: CGFloat) -> CGRect {
    let side = 14 * scale + 2
    let depth = min(14, max(0, area.height - baseSize * scale - 4))   // A little front-to-back depth
    return CGRect(x: area.minX + side, y: area.minY + footOffset * scale + 2, width: max(0, area.width - 2 * side), height: depth)
}

func clamped(_ p: CGPoint, to r: CGRect) -> CGPoint {
    CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
}

func randomPoint(in r: CGRect) -> CGPoint {
    CGPoint(x: .random(in: r.minX...max(r.minX, r.maxX)), y: .random(in: r.minY...max(r.minY, r.maxY)))
}

// Height of a single hop between 0 and length seconds.
func hop(_ time: Double, length: Double, height: CGFloat) -> CGFloat {
    time >= 0 && time < length ? CGFloat(sin(.pi * time / length)) * height : 0
}

// Treats the four screen edges as one closed path. s is the distance counterclockwise from the bottom-left corner.
// r is inset from the walls by the pet's foot height, so walking on it keeps feet on the wall.
struct Perimeter {
    let r: CGRect
    var length: CGFloat { 2 * (r.width + r.height) }

    func wrap(_ s: CGFloat) -> CGFloat {
        let m = s.truncatingRemainder(dividingBy: length)
        return m < 0 ? m + length : m
    }

    // Signed distance from a to b, in the shorter direction
    func delta(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let d = wrap(b - a)
        return d > length / 2 ? d - length : d
    }

    func point(_ s: CGFloat) -> CGPoint {
        let s = wrap(s), w = r.width, h = r.height
        if s < w { return CGPoint(x: r.minX + s, y: r.minY) }                     // bottom
        if s < w + h { return CGPoint(x: r.maxX, y: r.minY + s - w) }             // right
        if s < 2 * w + h { return CGPoint(x: r.maxX - (s - w - h), y: r.maxY) }   // top
        return CGPoint(x: r.minX, y: r.maxY - (s - 2 * w - h))                    // left
    }

    // Angle with feet toward the wall. Within 14pt of a corner the angle blends so the body rolls around it.
    func angle(_ s: CGFloat) -> CGFloat {
        let s = wrap(s), w = r.width, h = r.height, k: CGFloat = 14
        for (corner, before) in [(0, -CGFloat.pi / 2), (w, 0), (w + h, .pi / 2), (2 * w + h, .pi)] as [(CGFloat, CGFloat)] {
            let d = delta(corner, s)
            if abs(d) < k { return before + (d + k) / (2 * k) * .pi / 2 }
        }
        if s < w { return 0 }
        if s < w + h { return .pi / 2 }
        if s < 2 * w + h { return .pi }
        return -.pi / 2
    }

    func nearest(_ p: CGPoint) -> CGFloat {
        let c = clamped(p, to: r), w = r.width, h = r.height
        let sides: [(distance: CGFloat, s: CGFloat)] = [
            (abs(p.y - r.minY), c.x - r.minX),               // bottom
            (abs(r.maxX - p.x), w + c.y - r.minY),           // right
            (abs(r.maxY - p.y), w + h + r.maxX - c.x),       // top
            (abs(p.x - r.minX), 2 * w + h + r.maxY - c.y),   // left
        ]
        return sides.min { $0.distance < $1.distance }!.s
    }
}

// One agent = one pet.
// working: busily wanders the crowd. idle/done: rests in place.
// blocked: startled hop, climbs the nearest screen edge, runs along it to near the cursor and waves.
final class Pet: SKNode {
    let kind: PetKind
    private let frames: [Pose: [Frame]]
    private let body = SKNode()   // Bounce and left/right facing
    private let sprite = SKSpriteNode()
    private let badge = SKShapeNode(rectOf: CGSize(width: 19, height: 19), cornerRadius: 9.5)
    private let badgeLabel = SKLabelNode(fontNamed: ".AppleSystemUIFont")
    private let phase: Double     // Offsets each pet's motion rhythm
    private let walkSpeed = CGFloat.random(in: 26...38)
    private let blockSide = CGFloat.random(in: 26...44)   // Stops beside the cursor so it doesn't cover it

    private(set) var status = ""
    private(set) var isDashing = false
    private var statusSince: Double?
    private var runSpeed: CGFloat = 0
    private var wanderTarget: CGPoint?
    private var restUntil = 0.0
    private var edgeS: CGFloat?   // Position on the edge path. nil when not on the edge
    private var goalS: CGFloat?

    init(id: String, kind: PetKind, at start: CGPoint) {
        self.kind = kind
        frames = Sprites.frames(kind)
        phase = Double(id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 1600) / 100
        super.init()
        position = start
        sprite.position.y = -footOffset
        body.addChild(sprite)
        addChild(body)
        // Attach the badge to the pet, not body, so its text doesn't flip with the body.
        badge.strokeColor = .clear
        badge.zPosition = 2
        badgeLabel.fontSize = 12
        badgeLabel.fontColor = .white
        badgeLabel.verticalAlignmentMode = .center
        badge.addChild(badgeLabel)
        addChild(badge)
        show(.resting)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setStatus(_ s: String) {
        guard s != status else { return }
        status = s
        statusSince = nil
        wanderTarget = nil
        goalS = nil
        badgeLabel.text = s == "blocked" ? "!" : "✓"
        badge.fillColor = s == "blocked" ? .systemOrange : .systemGreen
    }

    // true while still moving. When all return false, the scene stops drawing.
    func step(t: Double, dt: CGFloat, world w: World) -> Bool {
        if statusSince == nil { statusSince = t }
        let age = t - statusSince!
        let celebrating = status == "done" && age < celebrationTime
        updateLook(scale: w.scale)

        if w.still { stayStill(w); return false }
        if status == "blocked" { return stepBlocked(t: t, age: age, dt: dt, world: w) }
        if edgeS != nil || !w.band.insetBy(dx: -2, dy: -2).contains(position) { return stepReturning(t: t, dt: dt, world: w) }
        return stepInCrowd(t: t, age: age, celebrating: celebrating, dt: dt, world: w)
    }

    private func updateLook(scale: CGFloat) {
        setScale(scale)
        badge.setScale(0.8 / scale)   // Same on-screen size regardless of character size
        badge.position.y = 30 + 10 / scale
        badge.isHidden = status != "blocked" && status != "done"   // Keep done's ✓ until the user checks the pane
        body.position = .zero
        zPosition = status == "blocked" ? 10_000 : -position.y   // Pets in front (lower) draw on top
        isDashing = false
    }

    private func stayStill(_ w: World) {
        if status == "blocked" {
            edgeS = blockGoal(w)
            stand(on: w.path)
        } else {
            leaveEdge()
            position = clamped(position, to: w.band)
        }
        show(standingPose)
    }

    // Outside the crowd because blocked ended or the area moved. If on the edge, run back along it to near the crowd and step off.
    private func stepReturning(t: Double, dt: CGFloat, world w: World) -> Bool {
        isDashing = true
        if edgeS != nil {
            let home = w.path.nearest(CGPoint(x: w.band.midX, y: w.band.minY))
            if runAlongEdge(to: home, on: w.path, maxSpeed: returnSpeed, dt: dt) { leaveEdge() }
        } else {
            isDashing = !runToward(clamped(position, to: w.band), maxSpeed: returnSpeed, dt: dt)
        }
        showMoving(t, fps: 12, bob: 2)
        return true
    }

    private func stepInCrowd(t: Double, age: Double, celebrating: Bool, dt: CGFloat, world w: World) -> Bool {
        if celebrating {
            show(.celebrate, frame: Int(age / 0.2), loop: false)
            body.position.y = hop(age, length: 0.8, height: 6)
            return true
        }
        guard status == "working" else { show(.resting); return false }
        if t < restUntil {   // Fidgets in place even while pausing
            show(.working, frame: Int((t + phase) * 6))
            return true
        }
        let target = clamped(wanderTarget ?? randomPoint(in: w.band), to: w.band)   // If the area changed, pull the old target into the new one
        wanderTarget = target
        if runToward(target, maxSpeed: walkSpeed, dt: dt) {
            wanderTarget = nil
            restUntil = t + .random(in: 0.4...1.5)
        }
        showMoving(t, fps: 10, bob: 2)
        return true
    }

    private func stepBlocked(t: Double, age: Double, dt: CGFloat, world w: World) -> Bool {
        let goal = blockGoal(w)
        if edgeS == nil && age < 0.35 {   // Startled hop
            show(.blocked)
            body.position.y = hop(age, length: 0.35, height: 8)
            return true
        }
        isDashing = true
        if edgeS == nil {
            let entry = w.path.nearest(position)
            if runToward(w.path.point(entry), maxSpeed: dashSpeed, dt: dt) { edgeS = entry }
        } else if runAlongEdge(to: goal, on: w.path, maxSpeed: dashSpeed, dt: dt) {
            isDashing = false
            show(.blocked, frame: Int((t + phase) * 4))
            body.xScale = -1   // Goal is ahead of the cursor on the path, so turning back faces the cursor
            body.position.y = hop((t + phase).truncatingRemainder(dividingBy: 2.5), length: 0.3, height: 6)
            return true
        }
        showMoving(t, fps: 14, bob: 3)
        return true
    }

    // Only retarget when the cursor moves 50pt+, so small cursor moves don't make it chase.
    private func blockGoal(_ w: World) -> CGFloat {
        let wanted = w.path.wrap(w.path.nearest(w.cursor) + blockSide)
        if goalS.map({ abs(w.path.delta($0, wanted)) > 50 }) ?? true { goalS = wanted }
        return goalS!
    }

    private var standingPose: Pose {
        switch status {
        case "working": return .working
        case "blocked": return .blocked
        default: return .resting
        }
    }

    // Distance to move this frame. Accelerates from a stop and slows as the remaining distance shrinks.
    private func advance(remaining: CGFloat, maxSpeed: CGFloat, dt: CGFloat) -> CGFloat {
        runSpeed = min(runSpeed + acceleration * dt, maxSpeed, max(20, remaining * 3))
        return min(remaining, runSpeed * dt)
    }

    private func runToward(_ goal: CGPoint, maxSpeed: CGFloat, dt: CGFloat) -> Bool {
        let dx = goal.x - position.x, dy = goal.y - position.y, d = hypot(dx, dy)
        if d < 1.5 { position = goal; runSpeed = 0; return true }
        let step = advance(remaining: d, maxSpeed: maxSpeed, dt: dt)
        position.x += dx / d * step
        position.y += dy / d * step
        if abs(dx) > 0.5 { body.xScale = dx < 0 ? -1 : 1 }
        return false
    }

    private func runAlongEdge(to goal: CGFloat, on path: Perimeter, maxSpeed: CGFloat, dt: CGFloat) -> Bool {
        let d = path.delta(edgeS!, goal)
        if abs(d) < 1.5 {
            edgeS = path.wrap(goal); runSpeed = 0
        } else {
            edgeS = path.wrap(edgeS! + advance(remaining: abs(d), maxSpeed: maxSpeed, dt: dt) * (d < 0 ? -1 : 1))
            body.xScale = d < 0 ? -1 : 1
        }
        stand(on: path)
        return abs(d) < 1.5
    }

    private func stand(on path: Perimeter) {
        position = path.point(edgeS!)
        zRotation = path.angle(edgeS!)
        badge.zRotation = -zRotation   // Keep the badge upright when the body flips
    }

    private func leaveEdge() {
        edgeS = nil
        zRotation = 0
        badge.zRotation = 0
    }

    // When loop is false, stops on the last frame.
    private func show(_ pose: Pose, frame index: Int = 0, loop: Bool = true) {
        let list = frames[pose]!
        let f = list[loop ? index % list.count : min(index, list.count - 1)]
        guard sprite.texture !== f.texture else { return }
        sprite.texture = f.texture
        sprite.size = f.size
        sprite.anchorPoint = CGPoint(x: f.anchorX, y: 0)
    }

    private func showMoving(_ t: Double, fps: Double, bob: CGFloat) {
        show(.working, frame: Int((t + phase) * fps))
        body.position.y = abs(sin((t + phase) * fps * 1.15)) * bob
    }
}
