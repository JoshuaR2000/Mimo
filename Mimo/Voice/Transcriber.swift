import Foundation

/// Turns a voice recording into text with OpenAI. Used when Apple's on-device recognizer isn't available.
enum Transcriber {
    static func transcribe(_ fileURL: URL, apiKey: String) async throws -> String {
        let audio = try Data(contentsOf: fileURL)
        guard audio.count > 8_000 else { return "" } // Too short to contain speech.

        let boundary = "MimoBoundary\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "gpt-4o-mini-transcribe")
        field("response_format", "json")
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"voice.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String ?? "the transcription request failed"
            throw BrainError(message: "Couldn't understand the recording: \(detail)")
        }
        return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
