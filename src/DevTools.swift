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
