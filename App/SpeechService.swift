import AVFoundation
import Speech
import SwiftUI

@MainActor final class SpeechService: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var isFinishing = false
    @Published private(set) var seconds = 0
    @Published var error: String?
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timer: Task<Void, Never>?
    private var finalizer: Task<Void, Never>?
    private var token = UUID()

    func start() async {
        guard !isRecording && !isPreparing && !isFinishing else { return }
        error = nil; isPreparing = true
        let sessionToken = UUID(); token = sessionToken
        defer { if token == sessionToken { isPreparing = false } }
        let auth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
        }
        guard token == sessionToken else { return }
        guard auth == .authorized else { error = "Speech permission unavailable. You can type your fact instead."; return }
        let microphone = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in continuation.resume(returning: granted) }
        }
        guard token == sessionToken else { return }
        guard microphone else { error = "Microphone permission unavailable. You can type your fact instead."; return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-CA")), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            error = "On-device speech recognition is unavailable. Please type your fact."; return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            let node = engine.inputNode; let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw AlterEgoError.invalid("Microphone is unavailable.") }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            self.engine = engine; self.request = request; self.recognizer = recognizer
            transcript = ""; seconds = 0
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let isFinal = result?.isFinal ?? false
                let failureMessage = failure?.localizedDescription
                Task { @MainActor in
                    guard let self, self.token == sessionToken else { return }
                    if let text { self.transcript = String(text.prefix(600)) }
                    if isFinal || failureMessage != nil {
                        if self.transcript.isEmpty, failureMessage != nil { self.error = "Couldn't hear that clearly. Try again or type your fact." }
                        self.finish()
                    }
                }
            }
            engine.prepare(); try engine.start(); isRecording = true
            timer = Task { @MainActor [weak self] in
                for t in 1...15 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, !Task.isCancelled, self.token == sessionToken, self.isRecording else { return }
                    self.seconds = t
                }
                self?.stop()
            }
        } catch {
            finish(); self.error = "Recording unavailable: \(error.localizedDescription). You can type your fact."
        }
    }
    private func stopAudio() {
        if let engine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func stop() {
        guard isRecording else { return }
        isRecording = false; isFinishing = true; timer?.cancel(); timer = nil
        stopAudio(); request?.endAudio()
        let current = token
        finalizer = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self, !Task.isCancelled, self.token == current else { return }
            self.finish()
        }
    }
    private func finish() {
        token = UUID(); timer?.cancel(); timer = nil; finalizer?.cancel(); finalizer = nil
        stopAudio(); recognition?.cancel(); recognition = nil; request = nil; recognizer = nil
        isRecording = false; isPreparing = false; isFinishing = false
    }
    func reset() { finish(); transcript = ""; error = nil; seconds = 0 }
}
