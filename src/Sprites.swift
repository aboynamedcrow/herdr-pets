import AppKit

// Parent folder of the executable (bin/pets). Assets are found here.
let projectRoot = Bundle.main.executableURL!.resolvingSymlinksInPath()
    .deletingLastPathComponent().deletingLastPathComponent()

let baseSize: CGFloat = 48    // Reference height of character art (pt)
let footOffset: CGFloat = 18  // Distance from the pet's anchor down to its feet (pt)

// rawValue = assets file name
enum PetKind: String, CaseIterable {
    case blob, robot, paper, cat, mushroom, ghost, stone, star, seed, cloud, octopus, pixel, claude, codex
    static let generic = allCases.filter { $0 != .claude && $0 != .codex }

    var title: String {
        switch self {
        case .blob: return t("말랑이", "Blob")
        case .robot: return t("로봇", "Robot")
        case .paper: return t("종이 정령", "Paper Sprite")
        case .cat: return t("고양이", "Cat")
        case .mushroom: return t("버섯 요정", "Mushroom Fairy")
        case .ghost: return t("유령", "Ghost")
        case .stone: return t("골렘", "Golem")
        case .star: return t("별", "Star")
        case .seed: return t("씨앗", "Seed")
        case .cloud: return t("구름", "Cloud")
        case .octopus: return t("문어", "Octopus")
        case .pixel: return t("픽셀 친구", "Pixel Buddy")
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

// Random keeps the original 14-kind assignment. Rules always fall back to agent type.
func petKind(for agent: Agent) -> PetKind {
    if preferences.characterMode == .random && !demo { return pick(PetKind.allCases, by: agent.id) }
    return petKind(ofType: agent.agent)
}

// claude and codex get their own characters. Other kinds map by name to a fixed one of the 12 generic ones.
func petKind(ofType type: String?) -> PetKind {
    let name = (type ?? "").lowercased()
    return PetKind(rawValue: name) ?? pick(PetKind.generic, by: name)
}

// Same result on every run (FNV-1a hash).
func pick<T>(_ items: [T], by key: String) -> T {
    var hash: UInt32 = 2166136261
    for byte in key.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
    return items[Int(hash % UInt32(items.count))]
}

enum Pose: String, CaseIterable {
    case working, blocked, celebrate, resting, walkingRight, walkingLeft, jump, thinking, sleeping
    var frameCount: Int { self == .blocked || self == .resting ? 2 : 4 }   // Frame count in animation files
}

struct Frame {
    let image: CGImage
    let size: CGSize       // pt
    let anchorX: CGFloat   // Centroid of opaque pixels (0–1). Keeps the body from shifting sideways on arm-reaching frames
}

// Character art. assets/sheets/<kind>.png has 4 poses side by side;
// if assets/frames/<kind>-<pose>.png exists, that pose becomes a multi-frame animation.
enum Sprites {
    static let builtinPoses: [Pose] = [.working, .blocked, .celebrate, .resting]
    private static var cache: [PetKind: [Pose: [Frame]]] = [:]

    static func frames(_ kind: PetKind) -> [Pose: [Frame]] {
        if let cached = cache[kind] { return cached }
        let sheet = slice("sheets/\(kind.rawValue)", into: builtinPoses.count)
        guard sheet.count == builtinPoses.count else { fatalError("캐릭터 이미지를 읽을 수 없습니다: assets/sheets/\(kind.rawValue).png") }
        // All four poses share one scale so a lying pose doesn't suddenly grow.
        let scale = min(baseSize / CGFloat(sheet.map(\.image.height).max()!), 60 / CGFloat(sheet.map(\.image.width).max()!))
        var result: [Pose: [Frame]] = [:]
        for (pose, still) in zip(builtinPoses, sheet) {
            let strip = slice("frames/\(kind.rawValue)-\(pose.rawValue)", into: pose.frameCount)
            if strip.isEmpty {
                result[pose] = [frame(still, scale: scale)]
            } else {   // Fit the tallest animation frame to the sheet pose height
                let stripScale = CGFloat(still.image.height) * scale / CGFloat(strip.map(\.image.height).max()!)
                result[pose] = strip.map { frame($0, scale: stripScale) }
            }
        }
        cache[kind] = result
        return result
    }

    static func thumbnail(_ kind: PetKind) -> NSImage {
        let f = frames(kind)[.working]![0]
        let context = bitmap(width: 128, height: 128)
        let size = CGSize(width: f.size.width * 1.65, height: f.size.height * 1.65)
        context.draw(f.image, in: CGRect(x: 64 - size.width * f.anchorX, y: 16, width: size.width, height: size.height))
        return NSImage(cgImage: context.makeImage()!, size: NSSize(width: 128, height: 128))
    }

    // Downscale images to the max display size (72pt, Retina 2x) to save memory.
    private static func frame(_ crop: (image: CGImage, centroidX: CGFloat), scale: CGFloat) -> Frame {
        let size = CGSize(width: CGFloat(crop.image.width) * scale, height: CGFloat(crop.image.height) * scale)
        let pixels = 2 * CGFloat(Preferences.sizeRange.upperBound) / baseSize
        var image = crop.image
        if CGFloat(image.width) > size.width * pixels {
            let context = bitmap(width: Int((size.width * pixels).rounded(.up)), height: Int((size.height * pixels).rounded(.up)))
            context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            image = context.makeImage()!
        }
        return Frame(image: image, size: size, anchorX: crop.centroidX)
    }

    // Slice a file with count images in equal-width cells. Empty array if the file is missing.
    static func slice(_ name: String, into count: Int) -> [(image: CGImage, centroidX: CGFloat)] {
        let url = projectRoot.appendingPathComponent("assets/\(name).png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let mask = AlphaMask(image)
        let cuts = [0] + (1..<count).map { mask.emptiestColumn(near: image.width * $0 / count, reach: image.width / (4 * count)) } + [image.width]
        return (0..<count).compactMap { i in
            guard let bounds = mask.drawingBounds(in: cuts[i]..<cuts[i + 1]), let crop = image.cropping(to: bounds) else { return nil }
            return (crop, mask.centroidX(in: bounds))
        }
    }
}

private struct AlphaMask {
    let width: Int, height: Int
    private let rgba: [UInt8]
    private let columnCounts: [Int]   // Opaque pixel count per column

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let (w, h) = (width, height)
        pixels.withUnsafeMutableBytes { bitmap(width: w, height: h, data: $0.baseAddress).draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        rgba = pixels
        columnCounts = (0..<w).map { x in (0..<h).reduce(0) { $0 + (pixels[($1 * w + x) * 4 + 3] > 32 ? 1 : 0) } }
    }

    func opaque(_ x: Int, _ y: Int) -> Bool { rgba[(y * width + x) * 4 + 3] > 32 }

    // Emptiest column near the expected boundary, so art slightly past a cell edge isn't clipped.
    func emptiestColumn(near expected: Int, reach: Int) -> Int {
        var best = expected
        for x in expected - reach...expected + reach
        where columnCounts[x] < columnCounts[best] || (columnCounts[x] == columnCounts[best] && abs(x - expected) < abs(best - expected)) {
            best = x
        }
        return best
    }

    // Drawing bounds in a cell, ignoring specks. A 3px margin keeps soft outlines.
    func drawingBounds(in cell: Range<Int>) -> CGRect? {
        let xs = cell.filter { columnCounts[$0] > max(3, height / 120) }
        let ys = (0..<height).filter { y in cell.reduce(0) { $0 + (opaque($1, y) ? 1 : 0) } > max(3, cell.count / 120) }
        guard let left = xs.first, let right = xs.last, let top = ys.first, let bottom = ys.last else { return nil }   // Image y=0 is the top
        let x0 = max(cell.lowerBound, left - 3), x1 = min(cell.upperBound, right + 4)
        let y0 = max(0, top - 3), y1 = min(height, bottom + 4)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // 0–1 relative to the range width
    func centroidX(in r: CGRect) -> CGFloat {
        var sum = 0, count = 0
        for y in Int(r.minY)..<Int(r.maxY) {
            for x in Int(r.minX)..<Int(r.maxX) where opaque(x, y) { sum += x - Int(r.minX); count += 1 }
        }
        return CGFloat(sum) / CGFloat(max(1, count)) / r.width
    }
}

func bitmap(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil) -> CGContext {
    let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: data == nil ? 0 : width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    return context
}
