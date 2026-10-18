import AppKit

struct Preferences: Codable {
    var size: Double = 24              // pt, sizeRange
    var visible = true
    var reducedMotion = false
    var allCharacters = false          // false: character by agent kind, true: one of 14 per agent
    var area: CGRect? = nil            // Crowd area (screen coordinates). nil: default area
    var language = Locale.preferredLanguages.first?.hasPrefix("ko") == true ? "ko" : "en"   // "ko" or "en". Defaults to the system language

    static let sizeRange = 16.0...72.0

    // Herdr replaces the plugin folder on update, so a plugin keeps settings in its config folder.
    static let file = (ProcessInfo.processInfo.environment["HERDR_PLUGIN_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? projectRoot)
        .appendingPathComponent("pets-preferences.json")

    init() {}

    // Older files missing newer keys still keep their other values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? visible
        reducedMotion = try c.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? reducedMotion
        allCharacters = try c.decodeIfPresent(Bool.self, forKey: .allCharacters) ?? allCharacters
        area = try c.decodeIfPresent(CGRect.self, forKey: .area)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? language
    }

    static func read() -> Preferences {
        guard let data = try? Data(contentsOf: file), var value = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        value.size = min(sizeRange.upperBound, max(sizeRange.lowerBound, value.size))
        return value
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
