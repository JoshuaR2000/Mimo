import Foundation
import Testing
@testable import Mimo

@MainActor
struct ReplyCleanupTests {
    @Test func removesCitationLinks() {
        let raw = "Bills at Vikings, 8:15 PM ET on ESPN/ABC. ([nfl.com](https://www.nfl.com/schedules/2026/by-week/week-9?utm_source=openai))"
        #expect(OpenAIBrain.speakable(raw) == "Bills at Vikings, 8:15 PM ET on ESPN/ABC.")
    }

    @Test func keepsLinkLabels() {
        #expect(OpenAIBrain.speakable("See [Apple's site](https://apple.com) for details.") == "See Apple's site for details.")
    }

    @Test func removesBareURLs() {
        #expect(OpenAIBrain.speakable("More at https://example.com today.") == "More at today.")
    }

    @Test func leavesPlainTextAlone() {
        #expect(OpenAIBrain.speakable("It's 72°F and sunny.") == "It's 72°F and sunny.")
    }
}

@MainActor
struct DateParsingTests {
    @Test("Accepts the date formats the model sends", arguments: [
        "2026-11-09T09:00:00", "2026-11-09T09:00", "2026-11-09 09:00", "2026-11-09", "2026-11-09T09:00:00Z",
    ])
    func parses(_ text: String) {
        #expect(ToolBox.parseDate(text) != nil)
    }

    @Test func readsLocalTime() throws {
        let date = try #require(ToolBox.parseDate("2026-11-09T14:30:00"))
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        #expect(parts.year == 2026 && parts.month == 11 && parts.day == 9)
        #expect(parts.hour == 14 && parts.minute == 30)
    }

    @Test func rejectsNaturalLanguage() {
        #expect(ToolBox.parseDate("next tuesday") == nil)
    }
}

@MainActor
struct CharacterTests {
    @Test func everyCharacterIsComplete() {
        for kind in CharacterKind.allCases {
            #expect(!kind.palettes.isEmpty)
            #expect(!kind.displayName.isEmpty)
            #expect(!kind.voice.isEmpty)
            #expect(Set(kind.palettes.map(\.id)).count == kind.palettes.count, "Palette ids must be unique for \(kind)")
        }
    }

    @Test func moodsLookDifferent() {
        #expect(Face.target(.happy).mouthCurve > Face.target(.neutral).mouthCurve)
        #expect(Face.target(.sad).mouthCurve < 0)
        #expect(Face.target(.surprised).eyeOpen > Face.target(.neutral).eyeOpen)
    }

    @Test func controllerFallsBackToFirstPalette() {
        let controller = CharacterController()
        controller.kind = .robot
        controller.paletteID = "does-not-exist"
        #expect(controller.palette == CharacterKind.robot.palettes[0])
    }

    @Test func gesturesBumpTheToken() {
        let controller = CharacterController()
        controller.perform(.wave)
        controller.perform(.wave)
        #expect(controller.gestureToken == 2)
        #expect(controller.gesture == .wave)
    }
}

@MainActor
struct OfflineBrainTests {
    @Test func greetsWithAWave() async throws {
        let reply = try await OfflineBrain(name: "Zuri").reply(to: "hello there")
        #expect(reply.gesture == .wave)
        #expect(reply.text.contains("Zuri"))
    }

    @Test func pointsToSettingsWhenUnsure() async throws {
        let reply = try await OfflineBrain(name: "Bolt").reply(to: "what's the capital of France?")
        #expect(reply.text.contains("API key"))
    }
}
