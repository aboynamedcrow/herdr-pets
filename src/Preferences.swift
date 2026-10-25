import AppKit

// Offsets are relative to the usable screen, independent of desktop arrangement.
struct ScreenArea: Codable {
    var right: CGFloat
    var bottom: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let standard = ScreenArea(right: 20, bottom: 8, width: 260, height: 60)

    // Shrinks and pushes the area inside a screen smaller than the one it was saved on.
    func rect(in frame: CGRect) -> CGRect {
        let w = min(max(width, minAreaSize.width), frame.width)
        let h = min(max(height, minAreaSize.height), frame.height)
        let x = min(max(frame.maxX - right - w, frame.minX), frame.maxX - w)
        let y = min(max(frame.minY + bottom, frame.minY), frame.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// In an extension so the memberwise init stays available.
extension ScreenArea {
    init(_ rect: CGRect, in frame: CGRect) {
        self.init(right: frame.maxX - rect.maxX, bottom: rect.minY - frame.minY, width: rect.width, height: rect.height)
    }
}

enum CharacterMode: String, Codable, CaseIterable {
    case agent, random, village, custom
    var title: String {
        switch self {
        case .agent: return t("에이전트별", "By agent type")
        case .random: return t("무작위", "Random")
        case .village: return t("마을", "Village")
        case .custom: return t("직접 설정", "Custom")
        }
    }
    var note: String {
        switch self {
        case .agent: return t("에이전트 종류별 캐릭터를 사용해요", "Characters follow the agent type")
        case .random: return t("펫마다 내장 14종 중 하나가 정해져요", "Each pet keeps one of 14 built-in characters")
        case .village: return t("내장 캐릭터와 커스텀 펫을 함께 골라요", "Pick from built-in and custom pets")
        case .custom: return t("규칙으로 펫을 골라요", "Rules choose each pet")
        }
    }
}

enum MovementMode: String, Codable, CaseIterable {
    case home, broadway
    var title: String { self == .home ? "Home Area" : "Broadway Mode" }
}

struct Preferences: Codable {
    var size: Double = 24              // pt, sizeRange
    var visible = true
    var otherMachines = true
    var characterMode: CharacterMode = .custom
    var customPetSize = 130
    var customSizeShares: [String: Double] = [:]
    var movementMode: MovementMode = .home
    var maxPets = 20
    var reducedMotion = false
    var screenAreas: [String: ScreenArea] = [:]   // Crowd area per monitor, keyed by NSScreen.placementID
    var screenOrder: [String] = []     // Most recently selected first; automatic moves never change this
    var language = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en"   // "ko" or "en". Defaults to the system language

    static let sizeRange = 16.0...72.0

    // Herdr replaces the plugin folder on update, so a plugin keeps settings in its config folder.
    static let file = (ProcessInfo.processInfo.environment["HERDR_PLUGIN_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? projectRoot)
        .appendingPathComponent("pets-preferences.json")

    init() {}

    private enum CodingKeys: String, CodingKey {
        case size, visible, otherMachines, characterMode, customPetSize, customSizeShares, movementMode, maxPets, reducedMotion, screenAreas, screenOrder, language
    }
    private enum LegacyKeys: String, CodingKey { case rolePets, allCharacters }

    // Older files missing newer keys still keep their other values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? visible
        otherMachines = try c.decodeIfPresent(Bool.self, forKey: .otherMachines) ?? otherMachines
        if c.contains(.characterMode) {
            characterMode = (try? c.decode(CharacterMode.self, forKey: .characterMode)) ?? .custom
        } else {
            let old = try decoder.container(keyedBy: LegacyKeys.self)
            let roles = try old.decodeIfPresent(Bool.self, forKey: .rolePets) ?? true
            let all = try old.decodeIfPresent(Bool.self, forKey: .allCharacters) ?? false
            characterMode = roles ? .custom : all ? .random : .agent
        }
        customPetSize = min(200, max(100, try c.decodeIfPresent(Int.self, forKey: .customPetSize) ?? customPetSize))
        customSizeShares = ((try? c.decode([String: Double].self, forKey: .customSizeShares)) ?? [:]).mapValues { $0.isFinite ? min(1, max(0, $0)) : 1 }
        movementMode = (try? c.decode(MovementMode.self, forKey: .movementMode)) ?? .home
        maxPets = min(60, max(10, try c.decodeIfPresent(Int.self, forKey: .maxPets) ?? maxPets))
        reducedMotion = try c.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? reducedMotion
        screenAreas = try c.decodeIfPresent([String: ScreenArea].self, forKey: .screenAreas) ?? [:]
        screenOrder = try c.decodeIfPresent([String].self, forKey: .screenOrder) ?? []
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? language
    }

    static func read() -> Preferences {
        guard let data = try? Data(contentsOf: file), var value = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        value.size = min(sizeRange.upperBound, max(sizeRange.lowerBound, value.size))
        return value
    }

    func preferredScreen(in connected: [String]) -> String? {
        screenOrder.first { connected.contains($0) }
    }

    mutating func selectScreen(_ id: String, placement: ScreenArea) {
        screenAreas[id] = placement
        screenOrder.removeAll { $0 == id }
        screenOrder.insert(id, at: 0)
    }

    func save() {
        try? JSONEncoder().encode(self).write(to: Preferences.file, options: .atomic)
    }
}

var preferences = Preferences.read()

// UI text in the chosen language.
func t(_ ko: String, _ en: String) -> String { preferences.language == "ko" ? ko : en }
var petScale: CGFloat { CGFloat(preferences.size) / baseSize }
var motionReduced: Bool { preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
