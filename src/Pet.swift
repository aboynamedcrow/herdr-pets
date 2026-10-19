import AppKit

let dashSpeed: CGFloat = 320      // pt/s
let returnSpeed: CGFloat = 200
let acceleration: CGFloat = 700   // pt/s²
let celebrationTime = 1.8

struct World {
    let band: CGRect      // Floor the crowd lives on (range for the pet's anchor)
    let path: Perimeter   // Screen-edge path a blocked pet runs along
    let cursor: CGPoint
    let scale: CGFloat
    let still: Bool       // Reduce Motion
}

func crowdBand(_ area: CGRect, scale: CGFloat) -> CGRect {
    let side = 14 * scale + 2
    let depth = max(0, area.height - baseSize * scale - 4)   // Higher is farther back
    return CGRect(x: area.minX + side, y: area.minY + footOffset * scale + 2, width: max(0, area.width - 2 * side), height: depth)
}

func clamped(_ p: CGPoint, to r: CGRect) -> CGPoint {
    CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
}

// A spot is a position relative to the band (0...1 on each axis), so it follows the band when the area moves or resizes.
func point(_ spot: CGPoint, in r: CGRect) -> CGPoint {
    CGPoint(x: r.minX + spot.x * r.width, y: r.minY + spot.y * r.height)
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
// working: short quick trips around the area, tapping in place in between. idle/done: rests in place.
// When the area changes, each pet runs to its own spot in the new one, so the crowd keeps its spread.
// blocked: startled hop, climbs the nearest screen edge, runs along it to near the cursor and waves.
final class Pet {
    let kind: PetKind
    let spot: CGPoint
    let layer = CALayer()         // Position, rotation, scale, and order among pets
    let badge = CALayer()         // ! or ✓. Added to the scene root above the pets, so another pet's body never covers it
    private let body = CALayer()  // Bounce and left/right facing
    private let sprite = CALayer()
    private let frames: [Pose: [Frame]]
    private let phase: Double     // Offsets each pet's motion rhythm
    private let walkSpeed = CGFloat.random(in: 48...66)
    private let blockSide = CGFloat.random(in: 26...44)   // Stops beside the cursor so it doesn't cover it

    private(set) var status = ""
    private(set) var isDashing = false
    private(set) var position: CGPoint
    private(set) var zRotation: CGFloat = 0
    private var scale = petScale
    private var bounce: CGFloat = 0
    private var facing: CGFloat = 1   // -1 faces left
    private var statusSince: Double?
    private var runSpeed: CGFloat = 0
    private var wanderTarget: CGPoint?
    private var restUntil = 0.0
    private var edgeS: CGFloat?   // Position on the edge path. nil when not on the edge
    private var goalS: CGFloat?
    private var lastBand: CGRect?
    private var homing = false    // Heading to its spot because the area changed

    init(id: String, kind: PetKind, spot: CGPoint, in band: CGRect) {
        self.kind = kind
        self.spot = spot
        frames = Sprites.frames(kind)
        phase = Double(id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 1600) / 100
        position = point(spot, in: band)
        sprite.position.y = -footOffset
        let filter: CALayerContentsFilter = kind == .pixel || kind == .claude ? .nearest : .linear
        sprite.magnificationFilter = filter
        sprite.minificationFilter = filter
        body.addSublayer(sprite)
        layer.addSublayer(body)
        badge.bounds.size = CGSize(width: 19, height: 19)
        show(.resting)
        render()
    }

    // Returns false if the status is unchanged.
    @discardableResult
    func setStatus(_ s: String) -> Bool {
        guard s != status else { return false }
        status = s
        statusSince = nil
        wanderTarget = nil
        goalS = nil
        badge.contents = s == "blocked" ? Pet.blockedBadge : Pet.doneBadge
        return true
    }

    // true while still moving. When all return false, the scene stops drawing.
    func step(t: Double, dt: CGFloat, world w: World) -> Bool {
        defer { render() }
        if statusSince == nil { statusSince = t }
        let age = t - statusSince!
        scale = w.scale
        bounce = 0
        isDashing = false
        if w.band != lastBand {
            if lastBand != nil { homing = true }
            lastBand = w.band
        }

        if w.still { stayStill(w); return false }
        if status == "blocked" { return stepBlocked(t: t, age: age, dt: dt, world: w) }
        if edgeS != nil || homing || !w.band.insetBy(dx: -2, dy: -2).contains(position) { return stepReturning(t: t, dt: dt, world: w) }
        return stepInCrowd(t: t, age: age, dt: dt, world: w)
    }

    // Writes the state to the layers. Call inside a transaction with actions disabled.
    private func render() {
        layer.position = position
        layer.zPosition = status == "blocked" ? 10_000 : -position.y   // Pets in front (lower) draw on top
        layer.setAffineTransform(CGAffineTransform(rotationAngle: zRotation).scaledBy(x: scale, y: scale))
        body.position.y = bounce
        body.setAffineTransform(CGAffineTransform(scaleX: facing, y: 1))
        // Above the head, upright, and the same on-screen size regardless of character size.
        let head = CGPoint(x: 0, y: 30 * scale + 10).applying(CGAffineTransform(rotationAngle: zRotation))
        badge.position = CGPoint(x: position.x + head.x, y: position.y + head.y)
        badge.zPosition = layer.zPosition + 2
        badge.setAffineTransform(CGAffineTransform(scaleX: 0.8, y: 0.8))
        badge.isHidden = status != "blocked" && status != "done"   // Keep done's ✓ until the user checks the pane
    }

    // Fades in, or fades out and then removes the layers. A fade-out starts from the current opacity, so it doesn't flash.
    func fade(out: Bool) {
        CATransaction.begin()
        if out {
            let (layer, badge) = (layer, badge)
            CATransaction.setCompletionBlock { layer.removeFromSuperlayer(); badge.removeFromSuperlayer() }
        }
        for l in [layer, badge] {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = out ? l.presentation()?.opacity ?? l.opacity : 0
            animation.duration = 0.25
            l.opacity = out ? 0 : 1
            l.add(animation, forKey: "fade")
        }
        CATransaction.commit()
    }

    private func stayStill(_ w: World) {
        if status == "blocked" {
            edgeS = blockGoal(w)
            stand(on: w.path)
        } else {
            leaveEdge()
            if homing || !w.band.contains(position) { position = point(spot, in: w.band); homing = false }
        }
        show(standingPose)
    }

    // Blocked ended or the area changed. If on the edge, run along it to the point nearest its spot and step off, then run to the spot.
    private func stepReturning(t: Double, dt: CGFloat, world w: World) -> Bool {
        isDashing = true
        let home = point(spot, in: w.band)
        if edgeS != nil {
            if runAlongEdge(to: w.path.nearest(home), on: w.path, maxSpeed: returnSpeed, dt: dt) { leaveEdge() }
        } else if runToward(home, maxSpeed: returnSpeed, dt: dt) {
            isDashing = false
            homing = false
            wanderTarget = nil
        }
        showMoving(t, fps: 12, bob: 2)
        return true
    }

    private func stepInCrowd(t: Double, age: Double, dt: CGFloat, world w: World) -> Bool {
        if status == "done" && age < celebrationTime {
            show(.celebrate, frame: Int(age / 0.2), loop: false)
            bounce = hop(age, length: 0.8, height: 6)
            return true
        }
        guard status == "working" else { show(.resting); return false }
        // Rhythm: a short trip, then quick taps in place, then another trip.
        if t < restUntil {
            show(.working, frame: Int((t + phase) * 8))
            bounce = hop((t + phase).truncatingRemainder(dividingBy: 0.45), length: 0.27, height: 2)
            return true
        }
        let target = clamped(wanderTarget ?? nearbyPoint(in: w.band, scale: w.scale), to: w.band)   // If the area changed, pull the old target into the new one
        wanderTarget = target
        if runToward(target, maxSpeed: walkSpeed, dt: dt) {
            wanderTarget = nil
            restUntil = t + .random(in: 0.8...2.0)
        }
        showMoving(t, fps: 14, bob: 2)
        return true
    }

    // A trip that turns back at the band's walls instead of stopping against them, so pets don't pile up at the sides of a small area.
    private func nearbyPoint(in band: CGRect, scale: CGFloat) -> CGPoint {
        func turn(_ from: CGFloat, by d: CGFloat, within lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            let d = min(abs(d), (hi - lo) / 2) * (d < 0 ? -1 : 1)
            return lo...hi ~= from + d ? from + d : from - d
        }
        return CGPoint(x: turn(position.x, by: .random(in: 20...50) * scale * (Bool.random() ? 1 : -1), within: band.minX, band.maxX),
                       y: turn(position.y, by: .random(in: -12...12) * scale, within: band.minY, band.maxY))
    }

    private func stepBlocked(t: Double, age: Double, dt: CGFloat, world w: World) -> Bool {
        let goal = blockGoal(w)
        if edgeS == nil && age < 0.35 {   // Startled hop
            show(.blocked)
            bounce = hop(age, length: 0.35, height: 8)
            return true
        }
        isDashing = true
        if edgeS == nil {
            let entry = w.path.nearest(position)
            if runToward(w.path.point(entry), maxSpeed: dashSpeed, dt: dt) { edgeS = entry }
        } else if runAlongEdge(to: goal, on: w.path, maxSpeed: dashSpeed, dt: dt) {
            isDashing = false
            show(.blocked, frame: Int((t + phase) * 4))
            facing = -1   // Goal is ahead of the cursor on the path, so turning back faces the cursor
            bounce = hop((t + phase).truncatingRemainder(dividingBy: 2.5), length: 0.3, height: 6)
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
        if abs(dx) > 0.5 { facing = dx < 0 ? -1 : 1 }
        return false
    }

    private func runAlongEdge(to goal: CGFloat, on path: Perimeter, maxSpeed: CGFloat, dt: CGFloat) -> Bool {
        let d = path.delta(edgeS!, goal)
        if abs(d) < 1.5 {
            edgeS = path.wrap(goal); runSpeed = 0
        } else {
            edgeS = path.wrap(edgeS! + advance(remaining: abs(d), maxSpeed: maxSpeed, dt: dt) * (d < 0 ? -1 : 1))
            facing = d < 0 ? -1 : 1
        }
        stand(on: path)
        return abs(d) < 1.5
    }

    private func stand(on path: Perimeter) {
        position = path.point(edgeS!)
        zRotation = path.angle(edgeS!)
    }

    private func leaveEdge() {
        edgeS = nil
        zRotation = 0
    }

    // When loop is false, stops on the last frame.
    private func show(_ pose: Pose, frame index: Int = 0, loop: Bool = true) {
        let list = frames[pose]!
        let f = list[loop ? index % list.count : min(index, list.count - 1)]
        guard sprite.contents as AnyObject? !== f.image else { return }
        sprite.contents = f.image
        sprite.bounds.size = f.size
        sprite.anchorPoint = CGPoint(x: f.anchorX, y: 0)
    }

    private func showMoving(_ t: Double, fps: Double, bob: CGFloat) {
        show(.working, frame: Int((t + phase) * fps))
        bounce = abs(sin((t + phase) * fps * 1.15)) * bob
    }

    private static let blockedBadge = badgeImage("!", .systemOrange)
    private static let doneBadge = badgeImage("✓", .systemGreen)

    // A 19 pt circle with a white mark, drawn at 2x.
    private static func badgeImage(_ mark: String, _ color: NSColor) -> CGImage {
        let context = bitmap(width: 38, height: 38)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: 38, height: 38))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = NSAttributedString(string: mark, attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.white])
        text.draw(at: CGPoint(x: (38 - text.size().width) / 2, y: (38 - text.size().height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}
