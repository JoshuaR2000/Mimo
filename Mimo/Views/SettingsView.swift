import SwiftUI

/// Everyday settings. Developer options (API key, model, playground) live under Advanced.
struct SettingsView: View {
    @Bindable var app: AppState
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @State private var confirmNewChat = false

    var body: some View {
        NavigationStack {
            Form {
                if !app.hasAPIKey {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline mode").font(.headline)
                                Text("\(app.character.displayName) can only give simple replies until an OpenAI key is added in Advanced.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "wifi.slash").foregroundStyle(.orange)
                        }
                    }
                }

                Section("Character") {
                    Picker("Assistant", selection: $app.character) {
                        ForEach(CharacterKind.allCases) { Text("\($0.displayName) · \($0.title)").tag($0) }
                    }
                    HStack {
                        Text("Colors")
                        Spacer()
                        ForEach(app.character.palettes) { p in
                            Button { app.setPalette(p) } label: {
                                Circle().fill(Color(PlatformColor(hex: p.primary)))
                                    .frame(width: 28, height: 28)
                                    .overlay(Circle().stroke(app.controller.paletteID == p.id ? Color.accentColor : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(p.name)
                            .accessibilityAddTraits(app.controller.paletteID == p.id ? .isSelected : [])
                        }
                    }
                }

                Section {
                    TextField("Your name", text: $app.userName)
                        .textContentType(.givenName)
                    Toggle("Speak replies out loud", isOn: $app.voiceEnabled)
                } header: {
                    Text("You")
                }

                Section {
                    if app.memory.facts.isEmpty {
                        Text("Nothing remembered yet.").foregroundStyle(.secondary)
                    }
                    ForEach(app.memory.facts, id: \.self) { fact in
                        Text(fact)
                    }
                    .onDelete { idx in idx.map { app.memory.facts[$0] }.forEach(app.memory.forget) }
                } header: {
                    Text("What \(app.character.displayName) remembers")
                } footer: {
                    Text("Swipe left on an item to forget it.")
                }

                Section("Notes") {
                    if app.memory.notes.isEmpty {
                        Text("No notes yet. Ask your assistant to save one.").foregroundStyle(.secondary)
                    }
                    ForEach(app.memory.notes) { note in
                        VStack(alignment: .leading) {
                            Text(note.text)
                            Text(note.created.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { idx in idx.map { app.memory.notes[$0] }.forEach(app.memory.deleteNote) }
                }

                Section {
                    Button("Start a new conversation") { confirmNewChat = true }
                    NavigationLink("Advanced") { AdvancedSettingsView(app: app) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Start a new conversation? The current one will be cleared. Memories and notes stay.", isPresented: $confirmNewChat, titleVisibility: .visible) {
                Button("Start new conversation", role: .destructive) { conversation.clearConversation() }
            }
        }
    }
}

/// Developer options: OpenAI key and model, the expression playground, and erasing data.
struct AdvancedSettingsView: View {
    @Bindable var app: AppState
    @State private var keyDraft = ""
    @State private var confirmErase = false

    var body: some View {
        Form {
            Section {
                SecureField(app.hasAPIKey ? "Key saved. Paste to replace." : "Paste API key (sk-…)", text: $keyDraft)
                    .autocorrectionDisabled()
                    .onSubmit(saveKey)
                    .onChange(of: keyDraft) { _, new in
                        // Pasting a full key saves it right away.
                        if new.trimmingCharacters(in: .whitespacesAndNewlines).count > 30 { saveKey() }
                    }
                if app.hasAPIKey {
                    Label("Key saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Button("Remove key", role: .destructive) { app.apiKey = "" }
                }
                TextField("Model", text: $app.model)
                    .autocorrectionDisabled()
            } header: {
                Text("OpenAI")
            } footer: {
                Text("Your key is stored in this device's keychain and is only sent to OpenAI. Get one at platform.openai.com.")
            }

            Section {
                Toggle("Show expression playground", isOn: $app.showPlayground)
            } footer: {
                Text("Adds buttons on the main screen to try every mood and gesture, handy for demos.")
            }

            Section {
                Button("Erase memory and notes", role: .destructive) { confirmErase = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Advanced")
        .onDisappear(perform: saveKey)
        .confirmationDialog("Erase everything your assistant remembers and all notes? This can't be undone.", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { app.memory.clearAll() }
        }
    }

    private func saveKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        app.apiKey = key
        keyDraft = ""
    }
}
