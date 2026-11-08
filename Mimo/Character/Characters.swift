import SwiftUI

/// A color scheme for one character: what each value colors depends on the character.
struct Palette: Identifiable, Hashable {
    let id: String
    let name: String
    /// Alien: skin. Robot: body paint. Human: skin.
    let primary: UInt32
    /// Robot: joints. Human: shirt.
    let secondary: UInt32
    /// Robot: glow. Human: hair.
    let tertiary: UInt32
}

/// The characters a user can choose as their assistant.
enum CharacterKind: String, CaseIterable, Identifiable, Codable {
    case alien, robot, human

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .alien: "Zuri"
        case .robot: "Bolt"
        case .human: "Ava"
        }
    }

    var title: String {
        switch self {
        case .alien: "Alien"
        case .robot: "Robot"
        case .human: "Human"
        }
    }

    var tagline: String {
        switch self {
        case .alien: "Curious, upbeat, loves Earth facts"
        case .robot: "Precise, calm, quietly funny"
        case .human: "Warm, friendly, encouraging"
        }
    }

    /// Used in the system prompt so each character has its own voice.
    var personality: String {
        switch self {
        case .alien:
            "a curious, upbeat alien visiting Earth. You find everyday human things fascinating and make a light space joke now and then, but you are genuinely helpful and accurate."
        case .robot:
            "a precise, warm-hearted robot. You speak efficiently, with a dry sense of humor, and sometimes mention your circuits or processors."
        case .human:
            "a friendly, calm, encouraging person who sounds like a thoughtful friend."
        }
    }

    /// OpenAI text-to-speech voice and speaking style.
    var voice: String {
        switch self {
        case .alien: "fable"
        case .robot: "onyx"
        case .human: "coral"
        }
    }

    var voiceStyle: String {
        switch self {
        case .alien: "Playful, curious and bright, with a hint of wonder."
        case .robot: "Calm, precise and even, with a slightly mechanical cadence and dry humor."
        case .human: "Warm, natural and friendly, like talking to a close friend."
        }
    }

    var palettes: [Palette] {
        switch self {
        case .alien: [
            Palette(id: "lime", name: "Lime", primary: 0xA9C23F, secondary: 0, tertiary: 0),
            Palette(id: "sky", name: "Sky", primary: 0x4FA3E3, secondary: 0, tertiary: 0),
            Palette(id: "pearl", name: "Pearl", primary: 0xD7E6DE, secondary: 0, tertiary: 0),
        ]
        case .robot: [
            Palette(id: "white", name: "White", primary: 0xE6EAF0, secondary: 0x2B3442, tertiary: 0x5EF2FF),
            Palette(id: "orange", name: "Orange", primary: 0xF28C38, secondary: 0x2B3442, tertiary: 0x7DFF9A),
            Palette(id: "graphite", name: "Graphite", primary: 0x5B6472, secondary: 0x1B2028, tertiary: 0xFF5FD2),
        ]
        case .human: [
            Palette(id: "light", name: "Light", primary: 0xF2C6A5, secondary: 0x4B6CDB, tertiary: 0x4A2E1F),
            Palette(id: "medium", name: "Medium", primary: 0xC98E62, secondary: 0xE0644B, tertiary: 0x2A1A12),
            Palette(id: "deep", name: "Deep", primary: 0x8A5638, secondary: 0x2FA58A, tertiary: 0x151012),
        ]
        }
    }

    /// Background gradient for this character's world.
    var backgroundColors: [Color] {
        switch self {
        case .alien: [Color(red: 0.10, green: 0.12, blue: 0.32), Color(red: 0.03, green: 0.03, blue: 0.10)]
        case .robot: [Color(red: 0.08, green: 0.22, blue: 0.27), Color(red: 0.02, green: 0.06, blue: 0.08)]
        case .human: [Color(red: 0.36, green: 0.20, blue: 0.36), Color(red: 0.08, green: 0.05, blue: 0.12)]
        }
    }

    /// Glow color of the floor ring.
    var accent: UInt32 {
        switch self {
        case .alien: 0xB5D33D
        case .robot: 0x4FE3F0
        case .human: 0xFF8A6B
        }
    }
}
