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
    var displayName = ""
    let customSizeShare: Double
    let counts: [Int]
    let crop: CGRect
    let frames: [Pose: [Frame]]

    init(sheet: CGImage, customSizeShare: Double = 1) throws {
        self.customSizeShare = min(1, max(0, customSizeShare))
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
        for (pose, row) in [(Pose.working, 7), (.blocked, 6), (.celebrate, 4), (.resting, 0), (.walkingRight, 1), (.walkingLeft, 2), (.jump, 3), (.thinking, 5), (.sleeping, 8)] where !cells[row].isEmpty {
            result[pose] = try cells[row].map { cell in
                guard let image = sheet.cropping(to: bounds.offsetBy(dx: cell.minX, dy: cell.minY)) else { throw PetLoadError.invalidSheet }
                // Decode once for 200%, 72 pt, Retina 2x.
                let context = bitmap(width: max(1, Int(ceil(size.width * 6))), height: max(1, Int(ceil(size.height * 6))))
                context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
                guard let scaled = context.makeImage() else { throw PetLoadError.invalidSheet }
                return Frame(image: scaled, size: size, anchorX: 0.5)
            }
        }
        frames = result
    }
    func frames(sizePercent: Int, share: Double? = nil) -> [Pose: [Frame]] {
        let scale = CGFloat(100 + Double(min(200, max(100, sizePercent)) - 100) * min(1, max(0, share ?? customSizeShare))) / 100
        return frames.mapValues { $0.map { Frame(image: $0.image, size: CGSize(width: $0.size.width * scale, height: $0.size.height * scale), anchorX: $0.anchorX) } }
    }
}

enum PetLoadError: Error { case invalidMetadata, invalidSheet, emptyPose }

final class RolePets {
    private struct Metadata: Decodable {
        let id: String
        let displayName: String
        let spriteVersionNumber: Int
        let spritesheetPath: String
        let customSizeShare: Double
        let invalidSizeShare: Bool

        private enum CodingKeys: String, CodingKey { case id, displayName, spriteVersionNumber, spritesheetPath, customSizeShare }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            displayName = try c.decode(String.self, forKey: .displayName)
            spriteVersionNumber = try c.decode(Int.self, forKey: .spriteVersionNumber)
            spritesheetPath = try c.decode(String.self, forKey: .spritesheetPath)
            let share = try? c.decode(Double.self, forKey: .customSizeShare)
            customSizeShare = share ?? 1
            invalidSizeShare = c.contains(.customSizeShare) && share == nil
        }
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
    private var nextRulesRead = -Double.infinity
    private var rulesStamp: Stamp?
    private var rules: [PetRule] = []
    var legacyRules: [PetRule] { rules }
    let assignments: AssignmentStore
    var agentOverrides: [String: String] = [:]
    private var cache: [String: Cached] = [:]
    private var logged: Set<String> = []
    private var revision = 0

    init(directory: URL = RolePets.directory, home: String = NSHomeDirectory(),
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("herdr-pets: \($0)\n".utf8)) }) {
        self.directory = directory; self.home = home; self.clock = clock; self.log = log
        assignments = AssignmentStore(file: directory.appendingPathComponent("assignments.json"))
    }

    private func problem(_ url: URL) {
        if logged.insert(url.path).inserted { log("Cannot load \(url.path). Using agent art.") }
    }

    func refresh(mode: CharacterMode = preferences.characterMode) {
        let now = clock()
        assignments.load()
        let url = directory.appendingPathComponent("rules.json")
        if mode == .custom && now >= nextRulesRead {
            nextRulesRead = now + 60
            let stamp = Stamp(url)
            if stamp != rulesStamp {
                rulesStamp = stamp
                do { rules = try JSONDecoder().decode([PetRule].self, from: Data(contentsOf: url)) }
                catch { rules = []; problem(url) }
            }
        }
        guard now >= nextRead else { return }
        nextRead = now + 60
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory.resolvingSymlinksInPath(), includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let discovered = folders.filter { (try? $0.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.map(\.lastPathComponent)
        let ids = Set(rules.map(\.pet)).subtracting(["agent", "generic"]).union(discovered)
        cache = cache.filter { ids.contains($0.key) }
        for id in ids.sorted() {
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
                if metadata.invalidSizeShare && logged.insert(metadataURL.path + ":customSizeShare").inserted {
                    log("Invalid customSizeShare in \(metadataURL.path). Using 1.")
                }
                loaded = try CustomPet(sheet: image, customSizeShare: metadata.customSizeShare)
                loaded?.displayName = metadata.displayName
            } catch {
                // A missing override folder for a built-in name is normal.
                if sheetURL != nil || folderStamp.date != nil || PetKind(rawValue: id) == nil { problem(sheetURL ?? metadataURL) }
            }
            cache[id] = Cached(folder: folderStamp, metadata: metadataStamp, sheetURL: sheetURL, sheet: sheetURL.map(Stamp.init), pet: loaded, revision: revision)
        }
    }

    // In-memory fixtures keep self-tests independent of Herdr and private art.
    convenience init(rules: [PetRule], customPets: [String: CustomPet]) {
        self.init(directory: URL(fileURLWithPath: "/unused-pets-fixture"), home: "/fake/home", log: { _ in })
        self.rules = rules
        nextRead = .infinity
        nextRulesRead = .infinity
        let stamp = Stamp(directory)
        for (id, pet) in customPets {
            cache[id] = Cached(folder: stamp, metadata: stamp, sheetURL: nil, sheet: nil, pet: pet, revision: 1)
        }
    }

    func reload() { nextRead = -.infinity; nextRulesRead = -.infinity; refresh() }

    var customIDs: [String] { cache.keys.filter { cache[$0]?.pet != nil }.sorted() }

    func character(for pane: Agent, mode: CharacterMode) -> PetCharacter {
        let fallback = petKind(ofType: pane.agent)
        switch mode {
        case .agent: return .builtin(fallback)
        case .random: return .builtin(pick(PetKind.allCases, by: pane.id))
        case .village:
            // Rendezvous scores isolate each candidate. Only a new winner changes a pick.
            let candidates = PetKind.allCases.map { "builtin:" + $0.rawValue } + customIDs.map { "custom:" + $0 }
            let winner = candidates.max { score($0, key: pane.id) < score($1, key: pane.id) }!
            if winner.hasPrefix("custom:") {
                let id = String(winner.dropFirst(7))
                return .custom(id, cache[id]!.revision)
            }
            return .builtin(PetKind(rawValue: String(winner.dropFirst(8)))!)
        case .custom:
            if let key = pane.sessionKey, let pet = agentOverrides[key] { return resolve(pet, for: pane) }
            if let cell = AssignmentStore.winner(for: pane, document: assignments.document, home: home) {
                let available = cell.pets.filter { token in
                    if token == "agent" || token == "generic" { return true }
                    if token.hasPrefix("builtin:") { return PetKind(rawValue: String(token.dropFirst(8))) != nil }
                    let id = token.hasPrefix("custom:") ? String(token.dropFirst(7)) : token
                    return cache[id]?.pet != nil || PetKind(rawValue: id) != nil
                }
                guard let selected = available.max(by: { score($0, key: pane.id) < score($1, key: pane.id) }) else { return .builtin(fallback) }
                return resolve(selected, for: pane)
            }
            return chooseCharacter(pane, rules: rules, home: home, fallback: fallback) { id in
                guard let cached = self.cache[id] else { return nil }
                if cached.pet != nil { return .custom(id, cached.revision) }
                return cached.folder.date != nil ? .builtin(fallback) : nil
            }
        }
    }

    func resolve(_ token: String, for pane: Agent) -> PetCharacter {
        let fallback = petKind(ofType: pane.agent)
        if token.hasPrefix("builtin:") { return .builtin(PetKind(rawValue: String(token.dropFirst(8))) ?? fallback) }
        let id = token.hasPrefix("custom:") ? String(token.dropFirst(7)) : token
        if let cached = cache[id], cached.pet != nil { return .custom(id, cached.revision) }
        if token == "generic" { return .builtin(pick(PetKind.generic, by: pane.id)) }
        return .builtin(token == "agent" ? fallback : PetKind(rawValue: token) ?? fallback)
    }

    private func score(_ id: String, key: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        for byte in "\(key.utf8.count):\(key):\(id)".utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return hash
    }

    func possible(mode: CharacterMode, agents: [Agent]) -> (builtin: Set<PetKind>, custom: Set<String>) {
        let agentKinds = Set([PetKind.claude, .codex] + agents.map { petKind(ofType: $0.agent) })
        switch mode {
        case .agent: return (agentKinds, [])
        case .random: return (Set(PetKind.allCases), [])
        case .village: return (Set(PetKind.allCases), Set(customIDs))
        case .custom:
            var builtin = agentKinds, custom: Set<String> = []
            for rule in rules {
                if rule.pet == "agent" { continue }
                if rule.pet == "generic" { builtin.formUnion(PetKind.generic) }
                else if cache[rule.pet]?.pet != nil { custom.insert(rule.pet) }
                else if cache[rule.pet]?.folder.date == nil, let kind = PetKind(rawValue: rule.pet) { builtin.insert(kind) }
            }
            for token in assignments.document.cells.flatMap(\.pets) + Array(agentOverrides.values) {
                if token == "generic" { builtin.formUnion(PetKind.generic); continue }
                if token.hasPrefix("builtin:"), let kind = PetKind(rawValue: String(token.dropFirst(8))) { builtin.insert(kind); continue }
                let id = token.hasPrefix("custom:") ? String(token.dropFirst(7)) : token
                if cache[id]?.pet != nil { custom.insert(id) }
                else if let kind = PetKind(rawValue: id) { builtin.insert(kind) }
            }
            return (builtin, custom)
        }
    }

    func thumbnail(_ id: String) -> (image: NSImage, title: String)? {
        guard let pet = cache[id]?.pet, let frame = pet.frames[.resting]?.first else { return nil }
        return (NSImage(cgImage: frame.image, size: frame.size), pet.displayName)
    }

    func sizeShare(_ id: String) -> Double { cache[id]?.pet?.customSizeShare ?? 1 }

    func frames(for character: PetCharacter, sizePercent: Int = preferences.customPetSize) -> [Pose: [Frame]]? {
        guard case .custom(let id, _) = character else { return nil }
        return cache[id]?.pet?.frames(sizePercent: sizePercent, share: preferences.customSizeShares[id])
    }
}
