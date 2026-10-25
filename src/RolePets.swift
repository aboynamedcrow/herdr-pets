import AppKit
import ImageIO

// Rules select art without changing the stable machine/terminal key.
enum PetCharacter: Equatable {
    case builtin(PetKind)
    case custom(String, Int)
}

func roleWord(_ label: String?) -> String? {
    guard var words = label?.split(whereSeparator: { $0.isWhitespace }), !words.isEmpty else { return nil }
    // A dispatch label can have one marker before its role.
    if words[0].unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 127) }) {
        words.removeFirst()
    }
    guard let first = words.first, first.unicodeScalars.allSatisfy({ CharacterSet.letters.contains($0) }) else { return nil }
    return first.lowercased()
}

struct PetRule: Decodable {
    let role: [String]?
    let agent: [String]?
    let cwd: [String]?
    let pet: String

    init(role: [String]? = nil, agent: [String]? = nil, cwd: [String]? = nil, pet: String) {
        self.role = role; self.agent = agent; self.cwd = cwd; self.pet = pet
    }

    private enum CodingKeys: String, CodingKey { case role, agent, cwd, pet }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func strings(_ key: CodingKeys) throws -> [String]? {
            guard c.contains(key) else { return nil }
            if let value = try? c.decode(String.self, forKey: key) { return [value] }
            return try c.decode([String].self, forKey: key)
        }
        role = try strings(.role); agent = try strings(.agent); cwd = try strings(.cwd)
        pet = try c.decode(String.self, forKey: .pet)
    }

    func matches(_ pane: Agent, home: String) -> Bool {
        if let role, !role.contains(where: { $0.lowercased() == roleWord(pane.label) }) { return false }
        if let agent, !agent.contains(where: { $0 == pane.agent }) { return false }
        if let cwd {
            guard let path = pane.cwd, cwd.contains(where: { prefix in
                let expanded = prefix == "~" ? home : prefix.hasPrefix("~/") ? home + prefix.dropFirst() : prefix
                let base = expanded == "/" ? expanded : expanded.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
                return base == "/" ? path.hasPrefix("/") : path == base || path.hasPrefix(base + "/")
            }) else { return false }
        }
        return true
    }
}

func chooseCharacter(_ pane: Agent, rules: [PetRule], home: String, fallback: PetKind,
                     custom: (String) -> PetCharacter?) -> PetCharacter {
    guard let rule = rules.first(where: { $0.matches(pane, home: home) }) else { return .builtin(fallback) }
    if rule.pet == "agent" { return .builtin(fallback) }
    if rule.pet == "generic" { return .builtin(pick(PetKind.generic, by: pane.id)) }
    if let value = custom(rule.pet) { return value }
    return .builtin(PetKind(rawValue: rule.pet) ?? fallback)
}

struct CustomPet {
    static let rowLimits = [6, 8, 8, 4, 5, 8, 6, 6, 6]
    let counts: [Int]
    let crop: CGRect
    let frames: [Pose: [Frame]]

    init(sheet: CGImage) throws {
        guard sheet.width == 1536 && sheet.height == 2288 else { throw PetLoadError.invalidSheet }
        // One box across every used cell keeps feet and scale steady between poses.
        var rgba = [UInt8](repeating: 0, count: sheet.width * sheet.height * 4)
        rgba.withUnsafeMutableBytes { bitmap(width: sheet.width, height: sheet.height, data: $0.baseAddress).draw(sheet, in: CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height)) }
        var cells: [[CGRect]] = []
        var bounds = CGRect.null
        for (row, limit) in Self.rowLimits.enumerated() {
            var used: [CGRect] = []
            for column in 0..<limit {
                var cellBounds = CGRect.null
                for y in 0..<208 {
                    for x in 0..<192 where rgba[((row * 208 + y) * sheet.width + column * 192 + x) * 4 + 3] > 0 {
                        cellBounds = cellBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                if !cellBounds.isNull {
                    used.append(CGRect(x: column * 192, y: row * 208, width: 192, height: 208))
                    bounds = bounds.union(cellBounds)
                }
            }
            cells.append(used)
        }
        guard !bounds.isNull, [0, 4, 6, 7].allSatisfy({ !cells[$0].isEmpty }) else { throw PetLoadError.emptyPose }
        counts = cells.map(\.count)
        crop = bounds
        let scale = min(baseSize / bounds.height, 60 / bounds.width)
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        var result: [Pose: [Frame]] = [:]
        for (pose, row) in [(Pose.working, 7), (.blocked, 6), (.celebrate, 4), (.resting, 0)] {
            result[pose] = try cells[row].map { cell in
                guard let image = sheet.cropping(to: bounds.offsetBy(dx: cell.minX, dy: cell.minY)) else { throw PetLoadError.invalidSheet }
                // Decode once, then retain only display-sized frames.
                let context = bitmap(width: max(1, Int(ceil(size.width * 3))), height: max(1, Int(ceil(size.height * 3))))
                context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
                guard let scaled = context.makeImage() else { throw PetLoadError.invalidSheet }
                return Frame(image: scaled, size: size, anchorX: 0.5)
            }
        }
        frames = result
    }
}

enum PetLoadError: Error { case invalidMetadata, invalidSheet, emptyPose }

final class RolePets {
    private struct Metadata: Decodable {
        let id: String
        let displayName: String
        let spriteVersionNumber: Int
        let spritesheetPath: String
    }
    private struct Stamp: Equatable {
        let date: Date?
        let size: UInt64?
        init(_ url: URL) {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            date = attributes?[.modificationDate] as? Date
            size = attributes?[.size] as? UInt64
        }
    }
    private struct Cached {
        let folder: Stamp
        let metadata: Stamp
        let sheetURL: URL?
        let sheet: Stamp?
        let pet: CustomPet?
        let revision: Int
    }
    static var directory: URL {
        let env = ProcessInfo.processInfo.environment
        return URL(fileURLWithPath: env["HERDR_PETS_DIR"] ?? (env["XDG_CONFIG_HOME"] ?? NSHomeDirectory() + "/.config") + "/herdr/pets")
    }
    private let directory: URL
    private let home: String
    private let clock: () -> Double
    private let log: (String) -> Void
    private var nextRead = -Double.infinity
    private var rulesStamp: Stamp?
    private var rules: [PetRule] = []
    private var cache: [String: Cached] = [:]
    private var logged: Set<String> = []
    private var revision = 0

    init(directory: URL = RolePets.directory, home: String = NSHomeDirectory(),
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("herdr-pets: \($0)\n".utf8)) }) {
        self.directory = directory; self.home = home; self.clock = clock; self.log = log
    }

    private func problem(_ url: URL) {
        if logged.insert(url.path).inserted { log("Cannot load \(url.path). Using agent art.") }
    }

    func refresh() {
        let now = clock()
        guard now >= nextRead else { return }
        nextRead = now + 60
        let url = directory.appendingPathComponent("rules.json")
        let stamp = Stamp(url)
        if stamp != rulesStamp {
            rulesStamp = stamp
            do { rules = try JSONDecoder().decode([PetRule].self, from: Data(contentsOf: url)) }
            catch { rules = []; problem(url) }
        }
        let ids = Set(rules.map(\.pet)).subtracting(["agent", "generic"])
        cache = cache.filter { ids.contains($0.key) }
        for id in ids {
            // IDs name a direct subfolder, never a path outside the pets folder.
            guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\") else { problem(url); continue }
            let folder = directory.appendingPathComponent(id)
            let metadataURL = folder.appendingPathComponent("pet.json")
            let folderStamp = Stamp(folder)
            let metadataStamp = Stamp(metadataURL)
            if let previous = cache[id], previous.folder == folderStamp, previous.metadata == metadataStamp,
               previous.sheetURL.map({ Stamp($0) }) == previous.sheet { continue }
            revision += 1
            var sheetURL: URL?
            var loaded: CustomPet?
            do {
                let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
                guard metadata.id == id, !metadata.displayName.isEmpty, metadata.spriteVersionNumber == 2,
                      !metadata.spritesheetPath.hasPrefix("/") else { throw PetLoadError.invalidMetadata }
                let target = folder.appendingPathComponent(metadata.spritesheetPath).standardizedFileURL
                guard target.path.hasPrefix(folder.standardizedFileURL.path + "/"),
                      ["png", "webp"].contains(target.pathExtension.lowercased()) else { throw PetLoadError.invalidMetadata }
                sheetURL = target
                guard let source = CGImageSourceCreateWithURL(target as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw PetLoadError.invalidSheet }
                loaded = try CustomPet(sheet: image)
            } catch {
                // A missing override folder for a built-in name is normal.
                if sheetURL != nil || folderStamp.date != nil || PetKind(rawValue: id) == nil { problem(sheetURL ?? metadataURL) }
            }
            cache[id] = Cached(folder: folderStamp, metadata: metadataStamp, sheetURL: sheetURL, sheet: sheetURL.map(Stamp.init), pet: loaded, revision: revision)
        }
    }

    func character(for pane: Agent, enabled: Bool) -> PetCharacter {
        let fallback = petKind(for: pane)
        guard enabled else { return .builtin(fallback) }
        return chooseCharacter(pane, rules: rules, home: home, fallback: fallback) { id in
            guard let cached = self.cache[id] else { return nil }
            if cached.pet != nil { return .custom(id, cached.revision) }
            return cached.folder.date != nil ? .builtin(fallback) : nil
        }
    }

    func frames(for character: PetCharacter) -> [Pose: [Frame]]? {
        guard case .custom(let id, _) = character else { return nil }
        return cache[id]?.pet?.frames
    }
}
