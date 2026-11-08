import Foundation
import AVFoundation

/// Turns text into speech with OpenAI's voices and exposes the live loudness for lip sync.
@MainActor
final class SpeechOutput {
    private var player: AVAudioPlayer?
    private var smoothed: Float = 0

    var isPlaying: Bool { player?.isPlaying ?? false }

    /// Loudness of the current audio, 0...1, smoothed so the mouth doesn't jitter.
    func level() -> Float {
        guard let player, player.isPlaying else { smoothed *= 0.8; return smoothed }
        player.updateMeters()
        let db = player.averagePower(forChannel: 0)
        let target = max(0, min(1, (db + 42) / 34))
        smoothed += (target - smoothed) * 0.5
        return smoothed
    }

    /// Downloads speech audio. Returns the audio data so playback can start in sync with the caption.
    func synthesize(_ text: String, voice: String, style: String, apiKey: String) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
            "instructions": style,
            "response_format": "mp3",
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String }
            throw BrainError(message: "Voice error: \(detail ?? "the speech request failed")")
        }
        return data
    }

    /// Plays audio and returns its duration in seconds.
    func play(_ data: Data) throws -> TimeInterval {
        stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let p = try AVAudioPlayer(data: data)
        p.isMeteringEnabled = true
        p.prepareToPlay()
        p.play()
        player = p
        return p.duration
    }

    /// Waits until playback finishes (or is stopped).
    func waitUntilFinished() async {
        while let player, player.isPlaying, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(80))
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
