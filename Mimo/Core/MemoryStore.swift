import Foundation
import Observation

struct Note: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var created = Date()
}

/// Long-term memory kept on the device: facts the assistant learned about the user, and notes.
@Observable
final class MemoryStore {
    private(set) var facts: [String] = []
    private(set) var notes: [Note] = []

    private struct Saved: Codable { var facts: [String]; var notes: [Note] }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mimo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("memory.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            facts = saved.facts
            notes = saved.notes
        }
    }

    func remember(_ fact: String) {
        let trimmed = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !facts.contains(trimmed) else { return }
        facts.append(trimmed)
        if facts.count > 50 { facts.removeFirst(facts.count - 50) }
        save()
    }

    func forget(_ fact: String) { facts.removeAll { $0 == fact }; save() }

    func addNote(_ text: String) -> Note {
        let note = Note(text: text)
        notes.insert(note, at: 0)
        save()
        return note
    }

    func deleteNote(_ note: Note) { notes.removeAll { $0.id == note.id }; save() }

    func clearAll() { facts = []; notes = []; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(Saved(facts: facts, notes: notes)) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
