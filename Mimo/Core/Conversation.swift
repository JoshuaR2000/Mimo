import Foundation
import Observation

struct ChatLine: Identifiable, Hashable {
    enum Speaker { case user, assistant }
    let id = UUID()
    let speaker: Speaker
    let text: String
}

/// Runs a conversation turn: sends the message to the brain, then makes the character act and speak the reply.
@MainActor
@Observable
final class Conversation {
    private(set) var caption = ""
    private(set) var history: [ChatLine] = []
    private(set) var isThinking = false
    var errorMessage: String?

    let listener = SpeechInput()
    @ObservationIgnored let voice = SpeechOutput()
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private var brain: AssistantBrain
    @ObservationIgnored private var brainSignature = ""
    @ObservationIgnored private var turn: Task<Void, Never>?

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
            brain = OpenAIBrain(apiKey: app.apiKey, model: app.model, tools: ToolBox(memory: app.memory)) {
                makeInstructions(character: app.character, userName: app.userName, memory: app.memory)
            }
        } else {
            brain = OfflineBrain(name: app.character.displayName)
        }
    }

    func greet() {
        let name = app.userName.isEmpty ? "" : ", \(app.userName)"
        let line = "Hi\(name)! I'm \(app.character.displayName). What can I help you with?"
        perform(AssistantReply(text: line, mood: .happy, gesture: .wave), speakAloud: false)
    }

    func send(_ text: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        interrupt()
        refreshBrain()
        history.append(ChatLine(speaker: .user, text: message))
        errorMessage = nil
        turn = Task {
            isThinking = true
            app.controller.mood = .thinking
            caption = "…"
            do {
                let reply = try await brain.reply(to: message)
                isThinking = false
                guard !Task.isCancelled else { return }
                await act(reply, speakAloud: app.voiceEnabled && app.hasAPIKey)
            } catch {
                isThinking = false
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                await act(AssistantReply(text: "Sorry, something went wrong. \(error.localizedDescription)", mood: .concerned, gesture: .shrug), speakAloud: false)
            }
        }
    }

    /// Shows a reply without asking the brain (greetings, demos).
    func perform(_ reply: AssistantReply, speakAloud: Bool) {
        interrupt()
        turn = Task { await act(reply, speakAloud: speakAloud) }
    }

    /// Stops talking immediately, e.g. when the user starts speaking.
    func interrupt() {
        turn?.cancel()
        voice.stop()
        app.controller.speaking = false
        isThinking = false
    }

    func toggleListening() {
        if listener.isListening {
            let heard = listener.stop()
            send(heard)
        } else {
            interrupt()
            Task {
                do { try await listener.start() } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    func clearConversation() {
        interrupt()
        history = []
        caption = ""
        brain.reset()
    }

    private func act(_ reply: AssistantReply, speakAloud: Bool) async {
        let controller = app.controller
        history.append(ChatLine(speaker: .assistant, text: reply.text))
        controller.mood = reply.mood
        if let g = reply.gesture { controller.perform(g) }

        var duration = Double(reply.text.count) * 0.045
        var usingAudio = false
        if speakAloud {
            do {
                let data = try await voice.synthesize(reply.text, voice: app.character.voice, style: app.character.voiceStyle, apiKey: app.apiKey)
                guard !Task.isCancelled else { return }
                duration = try voice.play(data)
                usingAudio = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        // Reveal the caption in step with the voice (or at reading speed with no audio).
        controller.speaking = !usingAudio
        caption = ""
        let step = max(0.012, min(0.06, duration / Double(max(1, reply.text.count))))
        for ch in reply.text {
            if Task.isCancelled { controller.speaking = false; return }
            caption.append(ch)
            try? await Task.sleep(for: .seconds(step))
        }
        controller.speaking = false
        if usingAudio { await voice.waitUntilFinished() }
        try? await Task.sleep(for: .seconds(2.5))
        if !Task.isCancelled { controller.mood = .neutral }
    }
}
