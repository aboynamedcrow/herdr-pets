import AppKit

// Offsets are relative to the usable screen, independent of desktop arrangement.
struct ScreenArea: Codable {
    var right: CGFloat
    var bottom: CGFloat
    var width: CGFloat
    var height: CGFloat
    var top: Bool? = nil    // Flush with the top edge. Keeps it there on a taller screen
    var left: Bool? = nil   // Flush with the left edge. Keeps it there on a wider screen

    static let standard = ScreenArea(right: 20, bottom: 8, width: 260, height: 60)

    // Shrinks and pushes the area inside a screen smaller than the one it was saved on.
    func rect(in frame: CGRect) -> CGRect {
        let w = min(max(width, minAreaSize.width), frame.width)
        let h = min(max(height, minAreaSize.height), frame.height)
        let x = left == true ? frame.minX : min(max(frame.maxX - right - w, frame.minX), frame.maxX - w)
        let y = top == true ? frame.maxY - h : min(max(frame.minY + bottom, frame.minY), frame.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// In an extension so the memberwise init stays available.
extension ScreenArea {
    init(_ rect: CGRect, in frame: CGRect) {
        self.init(right: frame.maxX - rect.maxX, bottom: rect.minY - frame.minY, width: rect.width, height: rect.height,
                  top: rect.maxY > frame.maxY - 1 ? true : nil, left: rect.minX < frame.minX + 1 ? true : nil)
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
        case .village: return t("내장 캐릭터와 커스텀 펫을 함께 골라요", "Mixed pets; Studio assignments are off")
        case .custom: return t("규칙으로 펫을 골라요", "Studio assignments, then existing rules")
        }
    }
}

enum MovementMode: String, Codable, CaseIterable {
    case home, broadway
    var title: String { self == .home ? "Home Area" : "Broadway Mode" }
}

// Pets of one machine or one project stand together. In Broadway Mode each group walks its own part of the line.
enum ClusterMode: String, Codable, CaseIterable {
    case off, machine, project
    var title: String {
        switch self {
        case .off: return t("끄기", "Off")
        case .machine: return t("머신별", "Machine")
        case .project: return t("프로젝트별", "Project")
        }
    }
}

// A global key combination. Modifiers hold NSEvent.ModifierFlags raw values.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt
    var key: String   // Shown name of the key, for example "P" or "F5"

    var title: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        return [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
            .filter { flags.contains($0.0) }.map(\.1).joined() + key
    }
}

enum ShortcutAction: String, Codable, CaseIterable {
    case togglePets, toggleBubbles, toggleMovement, toggleHomeArea, nextMonitor, toggleMenu
    var title: String {
        switch self {
        case .togglePets: return t("펫 보이기/숨기기", "Show or hide pets")
        case .toggleBubbles: return t("말풍선/아이콘 전환", "Bubbles or icon only")
        case .toggleMovement: return t("모이는 곳/브로드웨이 전환", "Home area or Broadway")
        case .toggleHomeArea: return t("모이는 곳 창 열기/닫기", "Show or hide the home area window")
        case .nextMonitor: return t("다음 모니터로", "Move to the next monitor")
        case .toggleMenu: return t("메뉴 막대 패널 열기/닫기", "Show or hide the menu bar panel")
        }
    }
}

struct Preferences: Codable {
    var size: Double = 24              // pt, sizeRange
    var visible = true
    var otherMachines = true
    var characterMode: CharacterMode = .custom
    var customPetSize = 130
    var customSizeShares: [String: Double] = [:]
    var movementMode: MovementMode = .home
    var showQuestionBubbles = false
    var clusterMode: ClusterMode = .off
    var shortcuts: [String: Shortcut] = [:]   // ShortcutAction raw value → combination
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
        case size, visible, otherMachines, characterMode, customPetSize, customSizeShares, movementMode, showQuestionBubbles, clusterMode, shortcuts, maxPets, reducedMotion, screenAreas, screenOrder, language
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
        showQuestionBubbles = (try? c.decode(Bool.self, forKey: .showQuestionBubbles)) ?? (movementMode == .broadway)
        clusterMode = (try? c.decode(ClusterMode.self, forKey: .clusterMode)) ?? .off
        shortcuts = (try? c.decode([String: Shortcut].self, forKey: .shortcuts)) ?? [:]
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

    func saveChecked(to file: URL = Preferences.file) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    func save() { try? saveChecked() }
}

var preferences = Preferences.read()

// UI text in the chosen language.
func t(_ ko: String, _ en: String) -> String { preferences.language == "ko" ? ko : en }
var petScale: CGFloat { CGFloat(preferences.size) / baseSize }
var motionReduced: Bool { preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
