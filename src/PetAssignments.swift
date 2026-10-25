import Foundation

struct GridAssignment: Codable, Equatable {
    var repository: String
    var role: String
    var agentType: String
    var pet: String
}

struct AssignmentDocument: Codable, Equatable {
    var version = 1
    var repositories: [String] = []
    var roles: [String] = []
    var cells: [GridAssignment] = []

    mutating func set(_ pet: String?, repository: String, role: String, agentType: String) {
        cells.removeAll { $0.repository == repository && $0.role == role && $0.agentType == agentType }
        if let pet { cells.append(GridAssignment(repository: repository, role: role, agentType: agentType, pet: pet)) }
    }
}

enum AssignmentError: LocalizedError {
    case conflict, invalid
    var errorDescription: String? {
        switch self {
        case .conflict: return "Assignments changed outside Pet Studio. Reload before saving."
        case .invalid: return "Cannot read these assignments. The last valid choices remain active."
        }
    }
}

final class AssignmentStore {
    let file: URL
    private(set) var document = AssignmentDocument()
    private(set) var snapshot: Data?
    private(set) var lastError: String?

    init(file: URL) { self.file = file.resolvingSymlinksInPath() }

    @discardableResult
    func load() -> AssignmentDocument {
        let data = try? Data(contentsOf: file)
        if data == snapshot { return document }
        snapshot = data
        do {
            guard let data else { throw AssignmentError.invalid }
            let value = try JSONDecoder().decode(AssignmentDocument.self, from: data)
            try validate(value)
            document = value
            lastError = nil
        } catch { lastError = error.localizedDescription }
        return document
    }

    func save(_ value: AssignmentDocument, expected: Data?) throws {
        try validate(value)
        guard (try? Data(contentsOf: file)) == expected else { throw AssignmentError.conflict }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(value)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = try? Data(contentsOf: file) {
            let backup: Data
            do {
                let decoded = try JSONDecoder().decode(AssignmentDocument.self, from: previous)
                try validate(decoded)
                backup = previous
            } catch { backup = try encoder.encode(document) }
            try backup.write(to: file.appendingPathExtension("bak"), options: .atomic)
        }
        try bytes.write(to: file, options: .atomic)
        snapshot = bytes
        document = value
        lastError = nil
    }

    private func validate(_ value: AssignmentDocument) throws {
        guard value.version == 1 else { throw AssignmentError.invalid }
        var keys: Set<String> = []
        for cell in value.cells {
            let path = Self.prefix(cell.repository, home: NSHomeDirectory())
            let values = [path, cell.role.lowercased(), cell.agentType.lowercased()]
            let key = values.map { "\($0.utf8.count):\($0)" }.joined()
            guard keys.insert(key).inserted, !cell.pet.isEmpty,
                  cell.repository.isEmpty || cell.repository.hasPrefix("/") || cell.repository == "~" || cell.repository.hasPrefix("~/") else {
                throw AssignmentError.invalid
            }
        }
    }

    static func prefix(_ path: String, home: String) -> String {
        guard !path.isEmpty else { return "" }
        let expanded = path == "~" ? home : path.hasPrefix("~/") ? home + path.dropFirst() : path
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    static func winner(for pane: Agent, document: AssignmentDocument, home: String) -> GridAssignment? {
        let matches = document.cells.filter { cell in
            PetRule(role: cell.role.isEmpty ? nil : [cell.role],
                    agent: cell.agentType.isEmpty ? nil : [cell.agentType],
                    cwd: cell.repository.isEmpty ? nil : [cell.repository], pet: cell.pet).matches(pane, home: home)
        }
        return matches.max { a, b in
            let ar = (a.repository.isEmpty ? 0 : prefix(a.repository, home: home).count, a.role.isEmpty ? 0 : 1, a.agentType.isEmpty ? 0 : 1)
            let br = (b.repository.isEmpty ? 0 : prefix(b.repository, home: home).count, b.role.isEmpty ? 0 : 1, b.agentType.isEmpty ? 0 : 1)
            return ar < br
        }
    }
}
