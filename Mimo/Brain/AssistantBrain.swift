import Foundation

/// What the character says and how it acts while saying it.
struct AssistantReply {
    var text: String
    var mood: Mood
    var gesture: CharacterGesture?
}

/// Anything that can produce replies. The rest of the app only talks to this, so providers can be swapped.
@MainActor
protocol AssistantBrain: AnyObject {
    func reply(to message: String) async throws -> AssistantReply
    func reset()
}

struct BrainError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Used when no API key is set: keyword replies so the character still reacts.
@MainActor
final class OfflineBrain: AssistantBrain {
    let name: String
    init(name: String) { self.name = name }

    func reset() {}

    func reply(to message: String) async throws -> AssistantReply {
        let lower = message.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { lower.range(of: "\\b\($0)\\b", options: .regularExpression) != nil } }
        if has(["joke"]) { return .init(text: "Why did the computer go to the doctor? It had a virus!", mood: .laughing, gesture: .jump) }
        if has(["sad", "sorry", "failed", "lost", "bad", "tired", "sick"]) { return .init(text: "Oh no, I'm sorry. That sounds hard.", mood: .sad, gesture: nil) }
        if has(["great", "awesome", "love", "thanks", "passed", "won", "amazing"]) { return .init(text: "That's great to hear!", mood: .happy, gesture: .jump) }
        if has(["hi", "hello", "hey"]) { return .init(text: "Hi! I'm \(name). Nice to meet you!", mood: .happy, gesture: .wave) }
        return .init(text: "I'm in offline mode right now. Add an OpenAI API key in Settings and I can really talk.", mood: .concerned, gesture: .shrug)
    }
}
