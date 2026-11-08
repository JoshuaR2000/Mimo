import Foundation
import Observation

/// App-wide settings and shared objects. Settings persist in UserDefaults; the API key lives in the keychain.
@MainActor
@Observable
final class AppState {
    private let defaults = UserDefaults.standard

    let controller = CharacterController()
    let memory = MemoryStore()

    var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    var voiceEnabled: Bool { didSet { defaults.set(voiceEnabled, forKey: "voiceEnabled") } }
    var showPlayground: Bool { didSet { defaults.set(showPlayground, forKey: "showPlayground") } }
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    var character: CharacterKind {
        didSet {
            defaults.set(character.rawValue, forKey: "character")
            controller.kind = character
            controller.paletteID = paletteID(for: character)
        }
    }
    var apiKey: String { didSet { Keychain.write(apiKey, for: "openai") } }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    static let defaultModel = "gpt-5-mini"

    init() {
        onboarded = defaults.bool(forKey: "onboarded")
        userName = defaults.string(forKey: "userName") ?? ""
        voiceEnabled = defaults.object(forKey: "voiceEnabled") as? Bool ?? true
        showPlayground = defaults.bool(forKey: "showPlayground")
        model = defaults.string(forKey: "model") ?? Self.defaultModel
        character = CharacterKind(rawValue: defaults.string(forKey: "character") ?? "") ?? .alien
        apiKey = Keychain.read("openai") ?? ""
        controller.kind = character
        controller.paletteID = paletteID(for: character)
    }

    func paletteID(for kind: CharacterKind) -> String {
        defaults.string(forKey: "palette.\(kind.rawValue)") ?? kind.palettes[0].id
    }

    func setPalette(_ palette: Palette) {
        defaults.set(palette.id, forKey: "palette.\(character.rawValue)")
        controller.paletteID = palette.id
    }
}

/// Questions handed over from Siri / Shortcuts before the main screen picks them up.
@MainActor
@Observable
final class PendingRequests {
    static let shared = PendingRequests()
    var question: String?
}
