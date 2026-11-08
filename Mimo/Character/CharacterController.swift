import Foundation
import Observation

/// The emotion the character's face and body show.
enum Mood: String, CaseIterable, Identifiable, Codable {
    case neutral, happy, laughing, sad, surprised, thinking, concerned
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A one-off body movement layered on top of the mood.
enum CharacterGesture: String, CaseIterable, Identifiable, Codable {
    case wave, nod, shake, jump, shrug
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var duration: Float {
        switch self {
        case .wave: 2.4
        case .nod, .shake: 1.3
        case .jump: 1.1
        case .shrug: 1.6
        }
    }
}

/// Shared state the app writes and the 3D rig reads every frame.
@Observable
final class CharacterController {
    var kind: CharacterKind = .alien
    var paletteID: String = "lime"
    var mood: Mood = .neutral
    /// True while a reply is being shown without audio (mouth flaps on its own).
    var speaking = false
    var yaw: Float = 0
    /// Mirrors the system Reduce Motion setting: no bouncing, swaying or glancing around.
    var reduceMotion = false
    private(set) var gesture: CharacterGesture?
    private(set) var gestureToken = 0

    /// Live loudness of the character's voice (0...1), used for lip sync.
    @ObservationIgnored var voiceLevel: () -> Float = { 0 }

    var palette: Palette {
        kind.palettes.first { $0.id == paletteID } ?? kind.palettes[0]
    }

    func perform(_ gesture: CharacterGesture) {
        self.gesture = gesture
        gestureToken += 1
    }
}
