import SwiftUI

/// First launch: pick a character, say your name, and optionally add an API key.
struct OnboardingView: View {
    let app: AppState
    @State private var step = 0
    @State private var name = ""
    @State private var key = ""

    var body: some View {
        VStack(spacing: 0) {
            CharacterStage(controller: app.controller)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                switch step {
                case 0: chooseCharacter
                case 1: askName
                default: askKey
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .padding(16)
        }
        .background(WorldBackground(kind: app.character))
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.25), value: step)
        .onAppear { app.controller.mood = .happy; app.controller.perform(.wave) }
    }

    private var chooseCharacter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meet your assistant").font(.title.bold())
            Text("Pick who you'd like to talk to. You can switch any time.").foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(CharacterKind.allCases) { kind in
                    Button {
                        app.character = kind
                        app.controller.perform(.wave)
                    } label: {
                        VStack(spacing: 4) {
                            Text(kind.displayName).font(.headline)
                            Text(kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(app.character == kind ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(app.character == kind ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(app.character.tagline).font(.callout).foregroundStyle(.secondary)
            Button { step = 1 } label: { Text("Continue").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var askName: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What should \(app.character.displayName) call you?").font(.title2.bold())
            TextField("Your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .textContentType(.givenName)
                .onSubmit { next() }
            HStack {
                Button("Back") { step = 0 }
                Spacer()
                Button("Continue", action: next).buttonStyle(.borderedProminent)
            }
        }
    }

    private var askKey: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect OpenAI").font(.title2.bold())
            Text("\(app.character.displayName) uses OpenAI to think and talk. Paste your API key from platform.openai.com. It's stored only in this device's keychain.")
                .foregroundStyle(.secondary)
            SecureField("sk-…", text: $key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            HStack {
                Button("Back") { step = 1 }
                Spacer()
                Button("Skip for now") { finish() }
                Button("Finish", action: finish).buttonStyle(.borderedProminent).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Without a key, the assistant runs in a limited offline mode.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func next() {
        app.userName = name.trimmingCharacters(in: .whitespaces)
        step = 2
    }

    private func finish() {
        app.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        app.onboarded = true
    }
}
