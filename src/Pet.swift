import AppKit

let dashSpeed: CGFloat = 320      // pt/s
let returnSpeed: CGFloat = 200
let acceleration: CGFloat = 700   // pt/s²
let celebrationTime = 1.8

struct World {
    var band: CGRect      // Floor the crowd lives on (range for the pet's anchor). One group's part of it when pets cluster
    let path: Perimeter   // Screen-edge path a blocked pet runs along
    let cursor: CGPoint
    let scale: CGFloat
    let still: Bool       // Reduce Motion
    var broadway = false
    var usableBounds: CGRect? = nil
    var floor = Floor.bottom
}

// The screen edge the crowd stands on. Pets keep their feet toward it.
enum Floor: CaseIterable {
    case bottom, top, left, right
    var angle: CGFloat {
        switch self {
        case .bottom: return 0
        case .right: return .pi / 2
        case .top: return .pi
        case .left: return -.pi / 2
        }
    }
    var horizontal: Bool { self == .bottom || self == .top }
}

// Edges the area touches. A gap of one point or more counts as not touching.
func flushEdges(_ area: CGRect, in walls: CGRect) -> [Floor] {
    Floor.allCases.filter {
        switch $0 {
        case .bottom: return abs(area.minY - walls.minY) < 1
        case .top: return abs(area.maxY - walls.maxY) < 1
        case .left: return abs(area.minX - walls.minX) < 1
        case .right: return abs(area.maxX - walls.maxX) < 1
        }
    }
}

// Pets stand upright unless the area is flush with an edge. In a corner, the edge along the area's longer side wins.
func floorEdge(of area: CGRect, in walls: CGRect) -> Floor {
    let edges = flushEdges(area, in: walls)
    return edges.first { $0.horizontal == (area.width >= area.height) } ?? edges.first ?? .bottom
}

// Broadway pets walk the line of the area's floor across the whole screen.
func broadwayBand(_ walls: CGRect, area: CGRect, floor: Floor, scale: CGFloat) -> CGRect {
    let foot = footOffset * scale + 2
    switch floor {
    case .bottom: return CGRect(x: walls.minX, y: area.minY + foot, width: walls.width, height: 0)
    case .top: return CGRect(x: walls.minX, y: area.maxY - foot, width: walls.width, height: 0)
    case .left: return CGRect(x: area.minX + foot, y: walls.minY, width: 0, height: walls.height)
    case .right: return CGRect(x: area.maxX - foot, y: walls.minY, width: 0, height: walls.height)
    }
}

func crowdBand(_ area: CGRect, scale: CGFloat, floor: Floor = .bottom) -> CGRect {
    let side = 14 * scale + 2, foot = footOffset * scale + 2
    if floor.horizontal {
        let depth = max(0, area.height - baseSize * scale - 4)   // Farther from the floor is farther back
        return CGRect(x: area.minX + side, y: floor == .bottom ? area.minY + foot : area.maxY - foot - depth, width: max(0, area.width - 2 * side), height: depth)
    }
    let depth = max(0, area.width - baseSize * scale - 4)
    return CGRect(x: floor == .left ? area.minX + foot : area.maxX - foot - depth, y: area.minY + side, width: depth, height: max(0, area.height - 2 * side))
}

// Splits a band along its floor into one part per group, sized by member count, left to right or top to bottom.
func segments(of band: CGRect, floor: Floor, weights: [Int], gap: CGFloat) -> [CGRect] {
    let length = floor.horizontal ? band.width : band.height
    let gap = weights.count > 1 ? min(gap, length / CGFloat(2 * (weights.count - 1))) : 0
    let usable = max(0, length - gap * CGFloat(weights.count - 1))
    let total = CGFloat(max(1, weights.reduce(0, +)))
    var offset: CGFloat = 0
    return weights.map { weight in
        let size = usable * CGFloat(weight) / total
        defer { offset += size + gap }
        return floor.horizontal ? CGRect(x: band.minX + offset, y: band.minY, width: size, height: band.height)
            : CGRect(x: band.minX, y: band.maxY - offset - size, width: band.width, height: size)
    }
}

func clamped(_ p: CGPoint, to r: CGRect) -> CGPoint {
    CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY))
}

// A spot is a position relative to the band (0...1 on each axis), so it follows the band when the area moves or resizes.
// x runs along the floor in the pet's own left-to-right direction. y runs away from the floor.
func point(_ spot: CGPoint, in r: CGRect, floor: Floor = .bottom) -> CGPoint {
    switch floor {
    case .bottom: return CGPoint(x: r.minX + spot.x * r.width, y: r.minY + spot.y * r.height)
    case .top: return CGPoint(x: r.maxX - spot.x * r.width, y: r.maxY - spot.y * r.height)
    case .left: return CGPoint(x: r.minX + spot.y * r.width, y: r.maxY - spot.x * r.height)
    case .right: return CGPoint(x: r.maxX - spot.y * r.width, y: r.minY + spot.x * r.height)
    }
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
// asleep: its machine stopped answering. Rests in place, dimmed, with a z badge.
final class Pet {
    private(set) var kind: PetKind
    private(set) var character: PetCharacter
    let spot: CGPoint
    let layer = CALayer()         // Position, rotation, scale, and order among pets
    let badge = CALayer()         // !, ✓ or z. Added to the scene root above the pets, so another pet's body never covers it
    private let body = CALayer()  // Bounce and left/right facing
    private let sprite = CALayer()
    private var frames: [Pose: [Frame]]
    private var customSize = 0
    private var customSizeShares: [String: Double] = [:]
    var artSize: CGSize { sprite.bounds.size }
    private var attention = AttentionCycle(counts: [.blocked: 1], seed: 1)
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
    private var movementBounds: CGRect?
    private var wanderTarget: CGPoint?
    private var restUntil = 0.0
    private var pendingEntryS: CGFloat?
    private var edgeS: CGFloat?   // Position on the edge path. nil when not on the edge
    private var goalS: CGFloat?
    private var lastBand: CGRect?
    private var lastBroadway = false
    private var broadwayDirection: CGFloat = 1
    private var homing = false    // Heading to its spot because the area changed
    private var floor = Floor.bottom

    init(id: String, kind: PetKind, spot: CGPoint, in band: CGRect, floor: Floor = .bottom) {
        self.kind = kind
        self.character = .builtin(kind)
        self.spot = spot
        self.floor = floor
        frames = Sprites.frames(kind)
        phase = Double(id.unicodeScalars.reduce(0) { $0 + Int($1.value) } % 1600) / 100
        position = point(spot, in: band, floor: floor)
        zRotation = floor.angle
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

    @discardableResult
    func setCharacter(_ value: PetCharacter, frames custom: [Pose: [Frame]]? = nil) -> Bool {
        guard value != character || (custom != nil && (customSize != preferences.customPetSize || customSizeShares != preferences.customSizeShares)) else { return false }
        switch value {
        case .builtin(let kind): self.kind = kind; frames = Sprites.frames(kind)
        case .custom: guard let custom else { return false }; frames = custom
        }
        character = value
        attention = AttentionCycle(counts: frames.mapValues(\.count), seed: UInt64(phase * 100) + 1)
        customSize = preferences.customPetSize
        customSizeShares = preferences.customSizeShares
        let filter: CALayerContentsFilter = value == .builtin(.pixel) || value == .builtin(.claude) ? .nearest : .linear
        sprite.magnificationFilter = filter
        sprite.minificationFilter = filter
        show(standingPose)
        return true
    }

    // Returns false if the status is unchanged.
    @discardableResult
    func setStatus(_ s: String) -> Bool {
        guard s != status else { return false }
        status = s
        statusSince = nil
        wanderTarget = nil
        goalS = nil
        pendingEntryS = nil
        badge.contents = s == "blocked" ? Pet.blockedBadge : s == "asleep" ? Pet.asleepBadge : Pet.doneBadge
        return true
    }

    // true while still moving. When all return false, the scene stops drawing.
    func step(t: Double, dt: CGFloat, world w: World) -> Bool {
        defer { if let bounds = w.usableBounds { keepArt(in: bounds) }; render() }
        if statusSince == nil { statusSince = t }
        let age = t - statusSince!
        scale = w.scale
        movementBounds = w.usableBounds
        bounce = 0
        isDashing = false
        if w.band != lastBand {
            if lastBand != nil { homing = true }
            lastBand = w.band
        }
        floor = w.floor
        if edgeS == nil && pendingEntryS == nil { zRotation = floor.angle }

        if w.broadway != lastBroadway {
            leaveEdge(); wanderTarget = nil
            restUntil = 0; homing = true; lastBroadway = w.broadway
        }
        if w.still { stayStill(w); return false }
        if status == "blocked" { return stepBlocked(t: t, age: age, dt: dt, world: w) }
        if w.broadway {
            if edgeS != nil { return stepReturning(t: t, dt: dt, world: w) }
            return stepBroadway(t: t, age: age, dt: dt, world: w)
        }
        let home = point(spot, in: w.band, floor: w.floor)
        let containedHome = movementBounds.map { containedAnchor(home, in: $0) } ?? home
        let atHome = hypot(position.x - containedHome.x, position.y - containedHome.y) < 1.5
        if edgeS != nil || homing || (!w.band.insetBy(dx: -2, dy: -2).contains(position) && !atHome) { return stepReturning(t: t, dt: dt, world: w) }
        return stepInCrowd(t: t, age: age, dt: dt, world: w)
    }

    private func keepArt(in bounds: CGRect) { position = containedAnchor(position, in: bounds) }

    private func containedAnchor(_ proposed: CGPoint, in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0 && bounds.height > 0 else { return proposed }
        let art = frames.values.flatMap { $0 }
        let half = art.map { max($0.anchorX, 1 - $0.anchorX) * $0.size.width }.max() ?? baseSize / 2
        let height = art.map(\.size.height).max() ?? baseSize
        let rect = CGRect(x: -half, y: -footOffset + bounce, width: half * 2, height: height)
        func box() -> CGRect { rect.applying(CGAffineTransform(rotationAngle: zRotation).scaledBy(x: scale, y: scale)) }
        var extent = box()
        let fit = min(1, bounds.width / max(1, extent.width), bounds.height / max(1, extent.height))
        if fit < 1 { scale *= fit; extent = box() }
        return CGPoint(x: min(max(proposed.x, bounds.minX - extent.minX), bounds.maxX - extent.maxX),
                       y: min(max(proposed.y, bounds.minY - extent.minY), bounds.maxY - extent.maxY))
    }

    // Writes the state to the layers. Call inside a transaction with actions disabled.
    private func render() {
        layer.position = position
        layer.zPosition = status == "blocked" ? 10_000 : -depth   // Pets in front (nearer the floor) draw on top
        layer.setAffineTransform(CGAffineTransform(rotationAngle: zRotation).scaledBy(x: scale, y: scale))
        body.position.y = bounce
        let mirror: CGFloat = { if case .custom = character { return 1 }; return facing }()
        body.setAffineTransform(CGAffineTransform(scaleX: mirror, y: 1))
        // Above the head, upright, and the same on-screen size regardless of character size.
        let head = CGPoint(x: 0, y: badgeOffset).applying(CGAffineTransform(rotationAngle: zRotation))
        badge.position = CGPoint(x: position.x + head.x, y: position.y + head.y)
        badge.zPosition = layer.zPosition + 2
        badge.setAffineTransform(CGAffineTransform(scaleX: 0.8, y: 0.8))
        badge.isHidden = !["blocked", "done", "asleep"].contains(status)   // Keep done's ✓ until the user checks the pane
        sprite.opacity = status == "asleep" ? 0.4 : 1   // The sprite, so fade() keeps its own layer opacity
    }

    // Distance from the floor's side of the screen, the depth axis of the crowd.
    private var depth: CGFloat {
        switch floor {
        case .bottom: return position.y
        case .top: return -position.y
        case .left: return position.x
        case .right: return -position.x
        }
    }

    var badgeOffset: CGFloat {
        let height = frames.values.flatMap { $0 }.map(\.size.height).max() ?? baseSize
        let top: CGFloat = { if case .custom = character { return height - footOffset }; return 30 }()
        return (top + bounce) * scale + 10
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
            if homing || !w.band.contains(position) { position = point(spot, in: w.band, floor: w.floor); homing = false }
        }
        show(standingPose)
    }

    // Blocked ended or the area changed. If on the edge, run along it to the point nearest its spot and step off, then run to the spot.
    private func stepReturning(t: Double, dt: CGFloat, world w: World) -> Bool {
        isDashing = true
        let home = point(spot, in: w.band, floor: w.floor)
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

    // A trip along the floor that turns back at the band's walls instead of stopping against them, so pets don't pile up at the sides of a small area.
    private func nearbyPoint(in band: CGRect, scale: CGFloat) -> CGPoint {
        func turn(_ from: CGFloat, by d: CGFloat, within lo: CGFloat, _ hi: CGFloat) -> CGFloat {
            let d = min(abs(d), (hi - lo) / 2) * (d < 0 ? -1 : 1)
            return lo...hi ~= from + d ? from + d : from - d
        }
        let along = CGFloat.random(in: 70...110) * scale * (Bool.random() ? 1 : -1), across = CGFloat.random(in: -20...20) * scale
        let (dx, dy) = floor.horizontal ? (along, across) : (across, along)
        return CGPoint(x: turn(position.x, by: dx, within: band.minX, band.maxX), y: turn(position.y, by: dy, within: band.minY, band.maxY))
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
            let entry = pendingEntryS ?? w.path.nearest(position)
            pendingEntryS = entry
            zRotation = w.path.angle(entry)
            if let bounds = w.usableBounds { keepArt(in: bounds) }
            let goal = w.usableBounds.map { containedAnchor(w.path.point(entry), in: $0) } ?? w.path.point(entry)
            if runToward(goal, maxSpeed: dashSpeed, dt: dt) { edgeS = entry; pendingEntryS = nil }
        } else if runAlongEdge(to: goal, on: w.path, maxSpeed: dashSpeed, dt: dt) {
            isDashing = false
            showAttention(t + phase)
            facing = -1   // Goal is ahead of the cursor on the path, so turning back faces the cursor
            bounce = hop((t + phase).truncatingRemainder(dividingBy: 2.5), length: 0.3, height: 6)
            return true
        }
        showMoving(t, fps: 14, bob: 3)
        return true
    }

    // Walks the band's line from one end to the other. The band is the whole screen's width, or one group's part of it.
    private func stepBroadway(t: Double, age: Double, dt: CGFloat, world w: World) -> Bool {
        leaveEdge()
        let screen = w.usableBounds ?? w.path.r
        let art = frames.values.flatMap { $0 }
        let half = art.map { max($0.anchorX, 1 - $0.anchorX) * $0.size.width }.max() ?? baseSize / 2
        let height = art.map(\.size.height).max() ?? baseSize
        let (length, room) = w.floor.horizontal ? (screen.width, screen.height) : (screen.height, screen.width)
        scale = max(0.01, min(w.scale, max(1, length - 4) / (2 * half), max(1, room - 4) / (height + 8)))
        let side = half * scale + 2
        let lane = w.floor.horizontal ? w.band.insetBy(dx: min(side, w.band.width / 2), dy: 0) : w.band.insetBy(dx: 0, dy: min(side, w.band.height / 2))
        // Tall art near a wall cannot stand on the lane itself. Use the nearest line where the art fits.
        func reachable(_ along: CGFloat) -> CGPoint {
            let p = point(CGPoint(x: along, y: 0), in: lane, floor: w.floor)
            return w.usableBounds.map { containedAnchor(p, in: $0) } ?? p
        }
        let home = reachable(spot.x)
        let offLine = w.floor.horizontal
            ? abs(position.y - home.y) > 1.5 || position.x < lane.minX - 1.5 || position.x > lane.maxX + 1.5
            : abs(position.x - home.x) > 1.5 || position.y < lane.minY - 1.5 || position.y > lane.maxY + 1.5
        if w.still {
            position = home; show(standingPose); return false
        }
        if status == "done" && age < celebrationTime {
            show(.celebrate, frame: Int(age / 0.2), loop: false)
            bounce = hop(age, length: 0.8, height: 6)
            return true
        }
        if homing || offLine {
            homing = !runToward(home, maxSpeed: returnSpeed, dt: dt)
            showMoving(t, fps: 12, bob: 0)
            return true
        }
        guard status == "working" else { show(.resting); return false }
        if t < restUntil { show(.working, frame: Int((t + phase) * 8)); return true }
        let goal = reachable(broadwayDirection < 0 ? 0 : 1)
        if runToward(goal, maxSpeed: walkSpeed, dt: dt) {
            broadwayDirection *= -1
            restUntil = t + Double.random(in: 0.8...2)
        }
        showMoving(t, fps: 14, bob: 0)
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

    private func runToward(_ proposed: CGPoint, maxSpeed: CGFloat, dt: CGFloat) -> Bool {
        let goal = movementBounds.map { containedAnchor(proposed, in: $0) } ?? proposed
        let dx = goal.x - position.x, dy = goal.y - position.y, d = hypot(dx, dy)
        if d < 1.5 { position = goal; runSpeed = 0; return true }
        let step = advance(remaining: d, maxSpeed: maxSpeed, dt: dt)
        position.x += dx / d * step
        position.y += dy / d * step
        let along = dx * cos(zRotation) + dy * sin(zRotation)   // Movement in the pet's own left-to-right direction
        if abs(along) > 0.5 { facing = along < 0 ? -1 : 1 }
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
        pendingEntryS = nil
        edgeS = nil
        zRotation = floor.angle
    }

    // When loop is false, stops on the last frame.
    private func show(_ pose: Pose, frame index: Int = 0, loop: Bool = true) {
        let list = frames[pose]!
        let f = list[loop ? index % list.count : min(index, list.count - 1)]
        guard sprite.contents as AnyObject? !== f.image || sprite.bounds.size != f.size else { return }
        sprite.contents = f.image
        sprite.bounds.size = f.size
        sprite.anchorPoint = CGPoint(x: f.anchorX, y: 0)
    }

    private func showAttention(_ time: Double) {
        if case .custom = character {
            let sample = attention.sample(at: time)
            show(sample.pose, frame: sample.frame)
        } else { show(.blocked, frame: Int(time * 4)) }
    }

    private func showMoving(_ t: Double, fps: Double, bob: CGFloat) {
        let pose: Pose = facing < 0 ? .walkingLeft : .walkingRight
        show(frames[pose]?.isEmpty == false ? pose : .working, frame: Int((t + phase) * fps))
        bounce = abs(sin((t + phase) * fps * 1.15)) * bob
    }

    private static let blockedBadge = badgeImage("!", .systemOrange)
    private static let doneBadge = badgeImage("✓", .systemGreen)
    private static let asleepBadge = badgeImage("z", .systemGray)

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
