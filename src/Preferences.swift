import AppKit

struct Preferences: Codable {
    var size: Double = 24              // pt, 16~72
    var visible = true
    var reducedMotion = false
    var allCharacters = false          // false: character by agent kind, true: one of 14 per agent

    static let file = configDir.appendingPathComponent("pets-preferences.json")

    init() {}

    // Older files missing newer keys still keep their other values.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? size
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? visible
        reducedMotion = try c.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? reducedMotion
        allCharacters = try c.decodeIfPresent(Bool.self, forKey: .allCharacters) ?? allCharacters
    }

    static func read() -> Preferences {
        guard let data = try? Data(contentsOf: file), var value = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        value.size = min(72, max(16, value.size))
        return value
    }

    func save() {
        try? JSONEncoder().encode(self).write(to: Preferences.file, options: .atomic)
    }
}

var preferences = Preferences.read()
var petScale: CGFloat { CGFloat(preferences.size) / baseSize }
var motionReduced: Bool { preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
