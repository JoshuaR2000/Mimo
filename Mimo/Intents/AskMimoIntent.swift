import AppIntents

/// Lets people ask their assistant from Siri, Spotlight or the Shortcuts app.
struct AskMimoIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Mimo"
    static var description = IntentDescription("Opens Mimo and asks your assistant a question.")
    static var openAppWhenRun = true

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    var question: String

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRequests.shared.question = question
        return .result()
    }
}

struct MimoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskMimoIntent(),
            phrases: ["Ask \(.applicationName)", "Talk to \(.applicationName)"],
            shortTitle: "Ask Mimo",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
