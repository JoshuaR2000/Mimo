import SwiftUI

struct SettingsView: View {
    @Bindable var app: AppState
    let conversation: Conversation
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Form {
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
                        }
                    }
                }

                Section("You") {
                    TextField("Your name", text: $app.userName)
                }

                Section {
                    SecureField(app.hasAPIKey ? "Key saved. Paste to replace." : "Paste API key (sk-…)", text: $keyDraft)
                        .autocorrectionDisabled()
                    if !keyDraft.isEmpty {
                        Button("Save key") { app.apiKey = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines); keyDraft = "" }
                    }
                    if app.hasAPIKey {
                        Button("Remove key", role: .destructive) { app.apiKey = "" }
                    }
                    TextField("Model", text: $app.model)
                        .autocorrectionDisabled()
                    Toggle("Speak replies out loud", isOn: $app.voiceEnabled)
                } header: {
                    Text("OpenAI")
                } footer: {
                    Text("Your key is stored in this device's keychain and is only sent to OpenAI. Get one at platform.openai.com.")
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
                    Text("Swipe to forget something.")
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
                    }
                    .onDelete { idx in idx.map { app.memory.notes[$0] }.forEach(app.memory.deleteNote) }
                }

                Section("Extras") {
                    Toggle("Show expression playground", isOn: $app.showPlayground)
                    Button("Start a new conversation") { conversation.clearConversation() }
                    Button("Erase memory and notes", role: .destructive) { confirmClear = true }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Erase everything \(app.character.displayName) remembers and all notes?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Erase", role: .destructive) { app.memory.clearAll() }
            }
        }
    }
}
