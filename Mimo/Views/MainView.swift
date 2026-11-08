import SwiftUI

/// The main screen: the character, what it's saying, and ways to talk to it.
struct MainView: View {
    let app: AppState
    @State private var conversation: Conversation
    @State private var input = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool
    private let pending = PendingRequests.shared

    init(app: AppState) {
        self.app = app
        _conversation = State(initialValue: Conversation(app: app))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack(alignment: .bottom) {
                CharacterStage(controller: app.controller)
                captionView
            }
            if app.showPlayground { playground }
            inputBar
        }
        .background(LinearGradient(colors: app.character.backgroundColors, startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings, onDismiss: conversation.refreshBrain) { SettingsView(app: app, conversation: conversation) }
        .sheet(isPresented: $showHistory) { HistoryView(lines: conversation.history) }
        .onAppear {
            NotificationRelay.shared.onDeliver = { [conversation] text in
                conversation.announce("Time's up! \(text)")
            }
            conversation.greet()
            if let q = pending.question { pending.question = nil; conversation.send(q) }
        }
        .onChange(of: pending.question) { _, q in
            if let q { pending.question = nil; conversation.send(q) }
        }
        .onChange(of: app.character) { _, _ in
            conversation.refreshBrain()
            conversation.greet()
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(CharacterKind.allCases) { kind in
                    Button {
                        app.character = kind
                    } label: {
                        Label("\(kind.displayName) · \(kind.title)", systemImage: app.character == kind ? "checkmark" : "person.crop.circle")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(app.character.displayName).font(.title2.bold())
                    Image(systemName: "chevron.down").font(.caption.bold())
                }
                .foregroundStyle(.white)
            }
            .accessibilityLabel("Change character")
            if !app.hasAPIKey {
                Text("Offline").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.25), in: Capsule()).foregroundStyle(.orange)
            }
            Spacer()
            Button { showHistory = true } label: { Image(systemName: "text.bubble") }
                .accessibilityLabel("Conversation history")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Settings")
        }
        .font(.title3)
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Caption

    private var captionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = conversation.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if let error = conversation.listener.lastError, !app.hasAPIKey {
                Label(error, systemImage: "mic.slash.fill")
                    .font(.footnote).foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            if conversation.listener.isActive {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(conversation.listener.transcript.isEmpty ? "Listening… start talking" : conversation.listener.transcript)
                        .font(.subheadline).foregroundStyle(.secondary)
                    MicLevelBar(level: conversation.listener.level)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            if conversation.isThinking {
                HStack(spacing: 8) { ProgressView(); Text("Thinking…").foregroundStyle(.secondary) }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            } else if !conversation.caption.isEmpty && !conversation.listener.isActive {
                Text(conversation.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: conversation.isThinking)
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message \(app.character.displayName)…", text: $input)
                .submitLabel(.send)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                .onSubmit(send)
            if input.isEmpty {
                Button(action: conversation.toggleListening) {
                    Image(systemName: conversation.listener.isActive ? "stop.fill" : "mic.fill")
                        .font(.title3)
                        .frame(width: 46, height: 46)
                        .background(conversation.listener.isActive ? Color.red : Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(conversation.listener.isActive ? "Stop listening and send" : "Talk")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up").font(.title3.bold())
                        .frame(width: 46, height: 46)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func send() {
        let text = input
        input = ""
        inputFocused = false
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
                            .tint(app.controller.mood == mood ? .accentColor : .gray)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// The full conversation as text.
struct HistoryView: View {
    let lines: [ChatLine]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if lines.isEmpty {
                    ContentUnavailableView("No messages yet", systemImage: "text.bubble", description: Text("What you and your assistant say appears here."))
                } else {
                    List(lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.speaker == .user ? "You" : "Assistant").font(.caption).foregroundStyle(.secondary)
                            Text(line.text)
                        }
                    }
                }
            }
            .navigationTitle("Conversation")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A small bar that moves with microphone volume, so it's obvious whether sound is getting through.
struct MicLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(level > 0.05 ? Color.green : Color.gray)
                    .frame(width: max(6, geo.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
        .frame(width: 140, height: 6)
        .accessibilityLabel("Microphone level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}
