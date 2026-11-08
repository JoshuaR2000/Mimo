import Foundation
import AVFoundation
import Speech
import Observation

/// Listens to the microphone and turns speech into text on the device.
@MainActor
@Observable
final class SpeechInput {
    private(set) var transcript = ""
    private(set) var isListening = false
    /// True while permissions and audio are being set up, before listening begins.
    private(set) var isStarting = false
    /// Listening or about to be: what the mic button should show.
    var isActive: Bool { isListening || isStarting }
    @ObservationIgnored private var cancelPending = false

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer()

    func start() async throws {
        guard !isActive else { return }
        isStarting = true
        cancelPending = false
        defer { isStarting = false }
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { throw BrainError(message: "Speech recognition is turned off for Mimo. You can allow it in Settings.") }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw BrainError(message: "Mimo doesn't have microphone access. You can allow it in Settings.")
        }
        guard let recognizer, recognizer.isAvailable else { throw BrainError(message: "Speech recognition isn't available right now.") }
        if cancelPending { cancelPending = false; return }

        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on the device whenever the device can recognize speech by itself.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in self?.transcript = text }
        }
    }

    /// Stops listening and returns what was heard.
    @discardableResult
    func stop() -> String {
        if isStarting { cancelPending = true; return "" }
        guard isListening else { return transcript }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        return transcript
    }
}
