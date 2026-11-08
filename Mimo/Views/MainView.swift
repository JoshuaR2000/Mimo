import SwiftUI

/// The main screen: the character in its world, what it's saying, and the big mic button.
struct MainView: View {
    let app: AppState
    @State private var conversation: Conversation
    @State private var input = ""
    @State private var typing = false
    @State private var showSettings = false
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pending = PendingRequests.shared

    private static let suggestions = ["Plan my day", "What's the weather?", "Set a reminder", "Tell me a joke"]

    init(app: AppState) {
        self.app = app
        _conversation = State(initialValue: Conversation(app: app))
    }

    var body: some View {
        ZStack {
            WorldBackground(kind: app.character)
            VStack(spacing: 0) {
                topBar
                ZStack(alignment: .bottom) {
                    // The character steps back (smaller, toward the top) to make room for result cards.
                    CharacterStage(controller: app.controller)
                        .scaleEffect(showingCards ? 0.62 : 1, anchor: .top)
                        .animation(reduceMotion ? nil : .spring(duration: 0.45), value: showingCards)
                    conversationArea
                }
                if app.showPlayground { playground }
                dock
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings, onDismiss: conversation.refreshBrain) { SettingsView(app: app, conversation: conversation) }
        .sheet(isPresented: $showHistory) { HistoryView(lines: conversation.history, character: app.character) }
        .onAppear {
            app.controller.reduceMotion = reduceMotion
            NotificationRelay.shared.onDeliver = { [conversation] text in
                conversation.announce("Time's up! \(text)")
            }
            conversation.greet()
            if let q = pending.question { pending.question = nil; conversation.send(q) }
        }
        .onChange(of: pending.question) { _, q in
            if let q { pending.question = nil; conversation.send(q) }
        }
        .onChange(of: reduceMotion) { _, value in app.controller.reduceMotion = value }
        .onChange(of: app.character) { _, _ in
            conversation.refreshBrain()
            conversation.greet()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(CharacterKind.allCases) { kind in
                    Button {
                        app.character = kind
                    } label: {
                        Label("\(kind.displayName) · \(kind.title)", systemImage: app.character == kind ? "checkmark" : "person.crop.circle")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(app.character.accentColor).frame(width: 24, height: 24)
                    Text(app.character.displayName).font(Brand.display(.title3)).foregroundStyle(Brand.mist)
                    Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(Brand.lavender)
                }
                .padding(.leading, 8).padding(.trailing, 14).frame(height: 40)
                .background(Brand.deep, in: Capsule())
                .overlay(Capsule().stroke(Brand.outline, lineWidth: 1))
            }
            .accessibilityLabel("Character: \(app.character.displayName). Change character")
            if !app.hasAPIKey {
                Text("Offline").font(.caption.bold()).padding(.horizontal, 10).frame(height: 26)
                    .background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
            }
            Spacer()
            CircleIconButton(systemName: "bubble.left.and.text.bubble.right", label: "Conversation history") { showHistory = true }
            CircleIconButton(systemName: "gearshape", label: "Settings") { showSettings = true }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    // MARK: Conversation area: what you said, what it's doing, what it says, what it did

    private var conversationArea: some View {
        VStack(spacing: 12) {
            if let error = conversation.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Brand.deep, in: RoundedRectangle(cornerRadius: 14))
            }
            if let error = conversation.listener.lastError, !app.hasAPIKey {
                Label(error, systemImage: "mic.slash.fill").font(.footnote).foregroundStyle(.orange)
            }

            if conversation.listener.isActive {
                UserBubble(text: conversation.listener.transcript.isEmpty ? "Listening…" : conversation.listener.transcript)
            } else if conversation.isThinking {
                if let said = conversation.lastUserMessage { UserBubble(text: said) }
                StatusPill(text: conversation.activity ?? "Thinking", accent: app.character.accentColor)
            } else if !conversation.caption.isEmpty {
                SpeechBubble(name: app.character.displayName, accent: app.character.accentColor, text: conversation.caption)
                if !conversation.cards.isEmpty && !conversation.isSpeaking {
                    VStack(spacing: 12) {
                        ForEach(conversation.cards.suffix(2)) { card in
                            ResultCardView(card: card, accent: app.character.accentColor) { conversation.undo(card) }
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
            if showSuggestions {
                SuggestionChips(suggestions: Self.suggestions) { conversation.send($0) }
                    .padding(.horizontal, -20)
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: conversation.cards)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: conversation.isThinking)
    }

    private var showingCards: Bool {
        !conversation.cards.isEmpty && !conversation.isThinking && !conversation.listener.isActive
    }

    private var showSuggestions: Bool {
        conversation.lastUserMessage == nil && !conversation.isThinking && !conversation.listener.isActive && !typing
    }

    // MARK: Dock: keyboard, the hero mic, switch character

    private var micState: MicState {
        if conversation.listener.isActive { return .listening }
        if conversation.isThinking { return .thinking }
        if conversation.isSpeaking { return .speaking }
        return .idle
    }

    private var dock: some View {
        VStack(spacing: 12) {
            if typing {
                HStack(spacing: 10) {
                    TextField("Message \(app.character.displayName)…", text: $input)
                        .submitLabel(.send)
                        .focused($inputFocused)
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        .background(Brand.deep, in: Capsule())
                        .overlay(Capsule().stroke(Brand.outline, lineWidth: 1))
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.title3.bold()).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(Brand.violet, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack(spacing: 32) {
                CircleIconButton(systemName: typing ? "mic" : "keyboard", label: typing ? "Use voice" : "Type a message", size: 52) {
                    withAnimation(.spring(duration: 0.3)) { typing.toggle() }
                    inputFocused = typing
                }
                MicButton(state: micState, level: micLevel, accent: app.character.accentColor, action: micTapped)
                CircleIconButton(systemName: "arrow.left.arrow.right", label: "Switch to \(nextCharacter.displayName)", size: 52) {
                    app.character = nextCharacter
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var nextCharacter: CharacterKind {
        let all = CharacterKind.allCases
        return all[(all.firstIndex(of: app.character)! + 1) % all.count]
    }

    private var micLevel: Float {
        conversation.listener.isActive ? conversation.listener.level : 0
    }

    private func micTapped() {
        switch micState {
        case .thinking, .speaking: conversation.interrupt()
        case .idle, .listening: conversation.toggleListening()
        }
    }

    private func send() {
        let text = input
        input = ""
        conversation.send(text)
    }

    // MARK: Expression playground (for demos)

    private var playground: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Mood.allCases) { mood in
                        Button(mood.label) { app.controller.mood = mood }
                            .buttonStyle(.bordered).controlSize(.small)
                            .tint(app.controller.mood == mood ? Brand.violet : .gray)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CharacterGesture.allCases) { g in
                        Button(g.label) { app.controller.perform(g) }
                            .buttonStyle(.bordered).controlSize(.small).tint(.gray)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// The full conversation as chat bubbles.
struct HistoryView: View {
    let lines: [ChatLine]
    let character: CharacterKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if lines.isEmpty {
                    ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.text.bubble.right",
                                           description: Text("What you and your assistant say appears here."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(lines) { line in
                                if line.speaker == .user {
                                    UserBubble(text: line.text)
                                } else {
                                    Text(line.text)
                                        .font(.callout).foregroundStyle(Brand.mist)
                                        .padding(.horizontal, 16).padding(.vertical, 11)
                                        .background(Brand.dusk, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20))
                                        .frame(maxWidth: 300, alignment: .leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityLabel("Assistant said: \(line.text)")
                                }
                            }
                        }
                        .padding(20)
                    }
                    .defaultScrollAnchor(.bottom)
                }
            }
            .background(Brand.night)
            .navigationTitle("Conversation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
