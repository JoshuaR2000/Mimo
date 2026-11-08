import SwiftUI

/// Lets the user pick which OpenAI model powers the assistant.
struct ModelPickerView: View {
    @Bindable var app: AppState
    @State private var accountModels: [String] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var custom = ""

    /// Hand-picked choices with plain-language tradeoffs.
    private static let recommended: [(id: String, title: String, detail: String)] = [
        ("gpt-5-mini", "GPT-5 mini", "Fast and inexpensive. The best fit for quick spoken replies."),
        ("gpt-5", "GPT-5", "Smartest answers, but slower and costs more per message."),
        ("gpt-5-nano", "GPT-5 nano", "Fastest and cheapest, best for simple requests."),
        ("gpt-4.1-mini", "GPT-4.1 mini", "Quick, without step-by-step reasoning. Some tools may be limited."),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(Self.recommended, id: \.id) { option in
                    row(id: option.id, title: option.title, detail: option.detail)
                }
            } header: {
                Text("Recommended")
            } footer: {
                Text("Smarter models give better answers but take longer and cost more. You can switch at any time.")
            }

            Section {
                if loading {
                    HStack { ProgressView(); Text("Loading your models…").foregroundStyle(.secondary) }
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Try again") { Task { await load() } }
                } else if !app.hasAPIKey {
                    Text("Add an API key to see every model your account can use.").foregroundStyle(.secondary)
                } else {
                    ForEach(accountModels.filter { id in !Self.recommended.contains { $0.id == id } }, id: \.self) { id in
                        row(id: id, title: id, detail: nil)
                    }
                }
            } header: {
                Text("All models on your account")
            }

            Section {
                HStack {
                    TextField("Model name, e.g. gpt-5", text: $custom)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .onSubmit(useCustom)
                    Button("Use", action: useCustom).disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Other")
            } footer: {
                Text("Currently using \(app.model).")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Model")
        .task { await load() }
    }

    private func row(id: String, title: String, detail: String?) -> some View {
        Button {
            app.model = id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                if app.model == id { Image(systemName: "checkmark").foregroundStyle(.tint).fontWeight(.semibold) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(app.model == id ? .isSelected : [])
    }

    private func useCustom() {
        let id = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        app.model = id
        custom = ""
    }

    private func load() async {
        guard app.hasAPIKey, accountModels.isEmpty else { return }
        loading = true
        loadError = nil
        do { accountModels = try await OpenAIBrain.availableModels(apiKey: app.apiKey) }
        catch { loadError = error.localizedDescription }
        loading = false
    }
}
