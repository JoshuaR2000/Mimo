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
    /// Live microphone loudness (0...1), so the user can see sound is getting through.
    private(set) var level: Float = 0
    /// The most recent recognition problem, shown on screen instead of failing silently.
    private(set) var lastError: String?
    /// The last recording, kept until the next time listening starts.
    @ObservationIgnored private(set) var recordingURL: URL?
    @ObservationIgnored private var cancelPending = false
    @ObservationIgnored private var onDeviceFailed = false

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
        lastError = nil
        level = 0

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw BrainError(message: "No microphone was found. On a Mac running the simulator, check System Settings → Privacy & Security → Microphone, and the Simulator's I/O → Audio Input menu.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        #if !targetEnvironment(simulator)
        // On real devices, keep audio on the device when it can recognize speech by itself.
        // (Simulators usually lack the on-device speech models, so they use Apple's service.)
        if recognizer.supportsOnDeviceRecognition && !onDeviceFailed { request.requiresOnDeviceRecognition = true }
        #endif
        self.request = request

        // Also save the audio, so it can be transcribed by OpenAI if Apple's recognizer can't.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-voice.wav")
        try? FileManager.default.removeItem(at: url)
        let file = try? AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        recordingURL = file == nil ? nil : url

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            try? file?.write(from: buffer)
            let rms = Self.rms(buffer)
            Task { @MainActor in self?.level = rms }
        }
        engine.prepare()
        try engine.start()
        isListening = true

        let usedOnDevice = request.requiresOnDeviceRecognition
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let message = error.map { ($0 as NSError).localizedDescription }
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                // Errors after the user pressed stop are expected; only report ones while listening.
                if let message, self.isListening {
                    if usedOnDevice { self.onDeviceFailed = true }
                    self.lastError = "Speech recognition stopped: \(message)"
                }
            }
        }
    }

    /// Loudness of a microphone buffer, scaled to 0...1 for the level bar.
    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let db = 20 * log10(max(1e-7, sqrt(sum / Float(buffer.frameLength))))
        return max(0, min(1, (db + 55) / 45))
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
        level = 0
        return transcript
    }
}
