import Foundation
import SwiftUI
import Observation

struct ChatLine: Identifiable, Hashable, Codable {
    enum Speaker: String, Codable { case user, assistant }
    var id = UUID()
    let speaker: Speaker
    let text: String
    var date = Date()
}

/// Keeps the conversation on the device so it survives closing the app.
enum HistoryStore {
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mimo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    static func load() -> [ChatLine] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ChatLine].self, from: data)) ?? []
    }

    static func save(_ lines: [ChatLine]) {
        let recent = Array(lines.suffix(200))
        if let data = try? JSONEncoder().encode(recent) { try? data.write(to: url, options: .atomic) }
    }
}

/// Runs a conversation turn: sends the message to the brain, then makes the character act and speak the reply.
@MainActor
@Observable
final class Conversation {
    private(set) var caption = ""
    private(set) var history: [ChatLine] = HistoryStore.load() {
        didSet { HistoryStore.save(history) }
    }
    private(set) var isThinking = false
    var errorMessage: String?

    let listener = SpeechInput()
    @ObservationIgnored let voice = SpeechOutput()
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private var brain: AssistantBrain
    @ObservationIgnored private var brainSignature = ""
    @ObservationIgnored private var turn: Task<Void, Never>?
    @ObservationIgnored private var voiceTask: Task<Void, Never>?
    /// A character the assistant asked to switch to; applied once the current reply finishes.
    @ObservationIgnored private var pendingSwitch: CharacterKind?

    init(app: AppState) {
        self.app = app
        brain = OfflineBrain(name: app.character.displayName)
        let voice = voice
        app.controller.voiceLevel = { MainActor.assumeIsolated { voice.level() } }
        refreshBrain()
    }

    /// Rebuilds the brain when the key, model or character changes.
    func refreshBrain() {
        let signature = "\(app.apiKey)|\(app.model)|\(app.character.rawValue)"
        guard signature != brainSignature else { return }
        brainSignature = signature
        if app.hasAPIKey {
            let app = app
            let tools = ToolBox(memory: app.memory) { [weak self] kind in self?.pendingSwitch = kind }
            brain = OpenAIBrain(apiKey: app.apiKey, model: app.model, tools: tools) {
                makeInstructions(character: app.character, userName: app.userName, memory: app.memory)
            }
        } else {
            brain = OfflineBrain(name: app.character.displayName)
        }
    }

    func greet() {
        let name = app.userName.isEmpty ? "" : ", \(app.userName)"
        let returning = history.contains { $0.speaker == .user }
        let line = returning
            ? "Welcome back\(name)! What's next?"
            : "Hi\(name)! I'm \(app.character.displayName). What can I help you with?"
        perform(AssistantReply(text: line, mood: .happy, gesture: .wave), speakAloud: false, record: false)
    }

    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        interrupt()
        refreshBrain()
        // Recent turns give the brain context after a relaunch or a character switch.
        let context = Array(history.suffix(12))
        history.append(ChatLine(speaker: .user, text: message))
        errorMessage = nil
        turn = Task {
            isThinking = true
            app.controller.mood = .thinking
            caption = "…"
            do {
                let reply = try await brain.reply(to: message, context: context)
                isThinking = false
                guard !Task.isCancelled else { return }
                await act(reply, speakAloud: app.voiceEnabled && app.hasAPIKey)
                if let kind = pendingSwitch, !Task.isCancelled {
                    pendingSwitch = nil
                    app.character = kind // the main screen greets with the new character
                }
            } catch {
                isThinking = false
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                await act(AssistantReply(text: "Hmm, I couldn't get an answer just now. The details are above.", mood: .concerned, gesture: .shrug), speakAloud: false, record: false)
            }
        }
    }

    /// Shows a reply without asking the brain (greetings, demos).
    func perform(_ reply: AssistantReply, speakAloud: Bool, record: Bool = true) {
        interrupt()
        turn = Task { await act(reply, speakAloud: speakAloud, record: record) }
    }

    /// Stops talking immediately, e.g. when the user starts speaking.
    func interrupt() {
        turn?.cancel()
        voiceTask?.cancel()
        voice.stop()
        app.controller.speaking = false
        isThinking = false
    }

    func toggleListening() {
        if listener.isStarting {
            listener.stop()
        } else if listener.isListening {
            let heard = listener.stop().trimmingCharacters(in: .whitespacesAndNewlines)
            if !heard.isEmpty {
                send(heard)
            } else if app.hasAPIKey, let recording = listener.recordingURL {
                // Apple's recognizer gave nothing (common in the simulator): let OpenAI transcribe the recording.
                transcribeThenSend(recording)
            } else {
                didNotCatchThat()
            }
        } else {
            interrupt()
            Task {
                do { try await listener.start() } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private func transcribeThenSend(_ recording: URL) {
        interrupt()
        let key = app.apiKey
        turn = Task {
            isThinking = true
            app.controller.mood = .thinking
            do {
                let text = try await Transcriber.transcribe(recording, apiKey: key)
                isThinking = false
                guard !Task.isCancelled else { return }
                if text.isEmpty { didNotCatchThat() } else { send(text) }
            } catch {
                isThinking = false
                errorMessage = error.localizedDescription
                didNotCatchThat()
            }
        }
    }

    private func didNotCatchThat() {
        perform(AssistantReply(text: "Sorry, I didn't catch that. Tap the mic and try again.", mood: .concerned, gesture: nil), speakAloud: false, record: false)
    }

    func clearConversation() {
        interrupt()
        history = []
        caption = ""
        brain.reset()
    }

    private func act(_ reply: AssistantReply, speakAloud: Bool, record: Bool = true) async {
        let controller = app.controller
        if record { history.append(ChatLine(speaker: .assistant, text: reply.text)) }
        controller.mood = reply.mood
        if let g = reply.gesture { controller.perform(g) }
        // VoiceOver users hear the reply read out.
        AccessibilityNotification.Announcement("\(app.character.displayName): \(reply.text)").post()

        // Start downloading the voice right away, but don't wait for it: the caption
        // starts immediately and the audio joins in as soon as it arrives.
        voiceTask?.cancel()
        if speakAloud {
            let voice = voice, app = app
            voiceTask = Task {
                do {
                    // Speak the first sentence as soon as it's ready while the rest is still being made.
                    let parts = Self.splitForSpeech(reply.text)
                    let synth = { (text: String) in
                        try await voice.synthesize(text, voice: app.character.voice, style: app.character.voiceStyle, apiKey: app.apiKey)
                    }
                    let rest = parts.count > 1 ? Task { try await synth(parts[1]) } : nil
                    let first = try await synth(parts[0])
                    guard !Task.isCancelled else { rest?.cancel(); return }
                    _ = try voice.play(first)
                    controller.speaking = false // the real audio drives the mouth from here
                    if let rest {
                        let data = try await rest.value
                        await voice.waitUntilFinished()
                        guard !Task.isCancelled else { return }
                        _ = try voice.play(data)
                    }
                } catch is CancellationError {
                } catch {
                    if !Task.isCancelled { self.errorMessage = error.localizedDescription }
                }
            }
        }

        // Reveal the caption at about the pace people speak; the mouth flaps until audio takes over.
        controller.speaking = true
        caption = ""
        for ch in reply.text {
            if Task.isCancelled { controller.speaking = false; return }
            caption.append(ch)
            try? await Task.sleep(for: .seconds(0.05))
        }
        await voiceTask?.value
        controller.speaking = false
        await voice.waitUntilFinished()
        try? await Task.sleep(for: .seconds(2.5))
        if !Task.isCancelled { controller.mood = .neutral }
    }

    /// Splits a reply into its first sentence and the rest, so speech can start sooner.
    static func splitForSpeech(_ text: String) -> [String] {
        let enders: Set<Character> = [".", "!", "?"]
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if enders.contains(text[index]), next < text.endIndex, text[next] == " ",
               text.distance(from: text.startIndex, to: index) >= 20 {
                let first = String(text[...index]).trimmingCharacters(in: .whitespaces)
                let rest = String(text[next...]).trimmingCharacters(in: .whitespaces)
                return rest.count >= 12 ? [first, rest] : [text]
            }
            index = next
        }
        return [text]
    }

    /// Lets the character speak up on its own, e.g. when a timer ends.
    func announce(_ text: String, mood: Mood = .surprised, gesture: CharacterGesture? = .jump) {
        let reply = AssistantReply(text: text, mood: mood, gesture: gesture)
        let speak = app.voiceEnabled && app.hasAPIKey
        // Never cut off a request that's still being answered: wait for it, then speak up.
        guard isThinking || turn != nil, let current = turn else {
            perform(reply, speakAloud: speak)
            return
        }
        Task {
            await current.value
            if self.turn == current { self.perform(reply, speakAloud: speak) }
            else { self.history.append(ChatLine(speaker: .assistant, text: text)) }
        }
    }
}
