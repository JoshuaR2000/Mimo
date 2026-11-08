import Foundation

/// Talks to the OpenAI Responses API. Each turn returns structured JSON (reply, mood, gesture),
/// and the model may call the app's tools or web search before answering.
@MainActor
final class OpenAIBrain: AssistantBrain {
    private let apiKey: String
    private let model: String
    private let tools: ToolBox
    private let instructions: () -> String
    private var previousResponseID: String?

    init(apiKey: String, model: String, tools: ToolBox, instructions: @escaping () -> String) {
        self.apiKey = apiKey
        self.model = model
        self.tools = tools
        self.instructions = instructions
    }

    func reset() { previousResponseID = nil }

    func reply(to message: String) async throws -> AssistantReply {
        var input: [[String: Any]] = [["role": "user", "content": message]]
        for _ in 0..<6 {
            var body: [String: Any] = [
                "model": model,
                "instructions": instructions(),
                "input": input,
                "tools": [["type": "web_search"]] + tools.definitions,
                "text": ["format": Self.replyFormat],
            ]
            if let previousResponseID { body["previous_response_id"] = previousResponseID }

            let response = try await post(body)
            previousResponseID = response["id"] as? String
            let output = response["output"] as? [[String: Any]] ?? []

            let calls = output.filter { $0["type"] as? String == "function_call" }
            if !calls.isEmpty {
                input = []
                for call in calls {
                    let name = call["name"] as? String ?? ""
                    let args = call["arguments"] as? String ?? "{}"
                    let result = await tools.run(name, arguments: args)
                    input.append(["type": "function_call_output", "call_id": call["call_id"] as? String ?? "", "output": result])
                }
                continue
            }
            return try parseReply(output)
        }
        throw BrainError(message: "I got stuck using my tools. Try asking again.")
    }

    // MARK: - Networking

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            if status == 401 { throw BrainError(message: "OpenAI rejected the API key. Check it in Settings.") }
            if status == 429 {
                let code = (json["error"] as? [String: Any])?["code"] as? String
                if code == "insufficient_quota" {
                    throw BrainError(message: "OpenAI says the account has no usable credit. If you just added some, it can take a few minutes to activate. If it keeps happening, create a new API key and paste it in Settings.")
                }
                throw BrainError(message: "OpenAI is getting too many requests right now. Wait a moment and try again.")
            }
            throw BrainError(message: "OpenAI error: \(detail)")
        }
        return json
    }

    private func parseReply(_ output: [[String: Any]]) throws -> AssistantReply {
        var text = ""
        for item in output where item["type"] as? String == "message" {
            for part in item["content"] as? [[String: Any]] ?? [] {
                if part["type"] as? String == "output_text" { text += part["text"] as? String ?? "" }
                if part["type"] as? String == "refusal" { return AssistantReply(text: part["refusal"] as? String ?? "I can't help with that.", mood: .concerned, gesture: nil) }
            }
        }
        struct Raw: Decodable { let reply: String; let mood: String; let gesture: String }
        guard let data = text.data(using: .utf8), let raw = try? JSONDecoder().decode(Raw.self, from: data) else {
            if text.isEmpty { throw BrainError(message: "OpenAI sent an empty reply.") }
            return AssistantReply(text: text, mood: .neutral, gesture: nil)
        }
        return AssistantReply(text: Self.speakable(raw.reply), mood: Mood(rawValue: raw.mood) ?? .neutral, gesture: CharacterGesture(rawValue: raw.gesture))
    }

    /// Removes links and citation markup, which look messy in captions and sound wrong when spoken.
    static func speakable(_ text: String) -> String {
        var t = text
        // "([site](https://…))" citations → removed entirely
        t = t.replacingOccurrences(of: #"\s*\(\[[^\]]*\]\([^)]*\)\)"#, with: "", options: .regularExpression)
        // "[label](https://…)" → "label"
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        // bare URLs → removed
        t = t.replacingOccurrences(of: #"\s*\(?https?://\S+\)?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([.,!?])"#, with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let replyFormat: [String: Any] = [
        "type": "json_schema",
        "name": "character_reply",
        "strict": true,
        "schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["reply", "mood", "gesture"],
            "properties": [
                "reply": ["type": "string", "description": "What the character says out loud."],
                "mood": ["type": "string", "enum": Mood.allCases.map(\.rawValue), "description": "Facial expression that fits the reply."],
                "gesture": ["type": "string", "enum": CharacterGesture.allCases.map(\.rawValue) + ["none"], "description": "Optional body movement; use none most of the time."],
            ],
        ] as [String: Any],
    ]
}

/// Builds the system instructions from the character, the user and what the app remembers.
@MainActor
func makeInstructions(character: CharacterKind, userName: String, memory: MemoryStore) -> String {
    let now = Date()
    let date = now.formatted(date: .complete, time: .shortened)
    let facts = memory.facts.isEmpty ? "Nothing yet." : memory.facts.map { "- \($0)" }.joined(separator: "\n")
    let who = userName.isEmpty ? "the user" : userName
    return """
    You are \(character.displayName), \(character.personality)
    You live inside the Mimo app as an animated 3D character on \(who)'s device, and you talk with them out loud.

    How to reply:
    - Your reply is spoken aloud, so keep it short and natural: usually one to three sentences. No markdown, lists, emoji, links, URLs or source citations. If a source matters, name it in words ("according to Reuters").
    - Pick the mood that matches what you say, and a gesture only when it fits (wave for greetings, nod for agreeing, shrug when unsure, jump for excitement). Otherwise use "none".
    - Use the tools when \(who) asks you to do something (reminders, calendar, notes, timers, weather, maps), and web search for anything current or that you're unsure of.
    - Only say an action is done after the tool result confirms it. If a tool fails, say what went wrong plainly.
    - When \(who) shares a lasting personal detail (name, preferences, important people or dates), save it with remember_fact.
    - Dates and times you pass to tools use the user's local time, written like 2026-11-09T09:00:00.

    Current local date and time: \(date) (time zone \(TimeZone.current.identifier)).

    What you remember about \(who):
    \(facts)
    """
}
