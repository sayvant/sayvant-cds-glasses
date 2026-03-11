import Foundation
import Speech
import AVFoundation

/// On-device speech recognition using Apple's SFSpeechRecognizer.
/// Provides near-instant transcription (~100-200ms latency) vs Gemini's ~3s.
/// Feeds transcript directly to PABackendBridge for CDS updates.
@MainActor
class LocalSpeechRecognizer: ObservableObject {
    @Published var currentUtterance: String = ""
    @Published var isAuthorized: Bool = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastFinalText: String = ""

    /// Thread-safe reference for appending audio buffers from non-main threads.
    /// Set whenever recognitionRequest is created/cleared.
    nonisolated(unsafe) private var _requestRef: SFSpeechAudioBufferRecognitionRequest?

    /// Request speech recognition permission.
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.isAuthorized = (status == .authorized)
                if status != .authorized {
                    NSLog("[LocalSTT] Authorization denied: %d", status.rawValue)
                }
            }
        }
    }

    /// Start recognizing. Audio buffers are fed via appendAudioBuffer().
    /// Call this AFTER AudioManager.startCapture() so buffers flow in.
    func startRecognizing(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        guard recognizer?.isAvailable == true else {
            NSLog("[LocalSTT] Recognizer not available")
            return
        }

        // Cancel any previous task
        stopRecognizing()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // On-device = lowest latency
        // iOS 16+: add punctuation if available
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        self.recognitionRequest = request
        self._requestRef = request

        lastFinalText = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.currentUtterance = text

                    if result.isFinal {
                        // Extract only the new portion since last final
                        let newText = self.extractNewText(from: text)
                        if !newText.isEmpty {
                            onFinal(newText)
                        }
                        self.lastFinalText = text
                        self.currentUtterance = ""
                    } else {
                        // Partial — show what's new since last finalized
                        let newText = self.extractNewText(from: text)
                        if !newText.isEmpty {
                            onPartial(newText)
                        }
                    }
                }

                if let error {
                    NSLog("[LocalSTT] Recognition error: %@", error.localizedDescription)
                    // Auto-restart on transient errors (silence timeout, etc.)
                    if (error as NSError).code != 203 { // 203 = cancelled
                        self.restartRecognition(
                            onPartial: onPartial,
                            onFinal: onFinal
                        )
                    }
                }
            }
        }

        NSLog("[LocalSTT] Recognition started (on-device)")
    }

    /// Append an audio buffer from AudioManager's capture pipeline.
    /// Call this from AudioManager's tap callback with the NATIVE format buffer
    /// (before any resampling to Int16 for Gemini).
    /// Thread-safe: SFSpeechAudioBufferRecognitionRequest.append() can be called from any thread.
    nonisolated func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // recognitionRequest.append() is thread-safe per Apple docs.
        // Access via the nonisolated reference stored separately.
        _requestRef?.append(buffer)
    }

    func stopRecognizing() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        _requestRef = nil
        currentUtterance = ""
        lastFinalText = ""
    }

    // MARK: - Private

    private func extractNewText(from fullText: String) -> String {
        if lastFinalText.isEmpty { return fullText }
        // Strip the previously finalized prefix
        if fullText.hasPrefix(lastFinalText) {
            let suffix = String(fullText.dropFirst(lastFinalText.count))
                .trimmingCharacters(in: .whitespaces)
            return suffix
        }
        return fullText
    }

    private func restartRecognition(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        guard recognizer?.isAvailable == true else { return }

        NSLog("[LocalSTT] Restarting recognition...")

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        _requestRef = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }
        self.recognitionRequest = request
        self._requestRef = request
        lastFinalText = ""

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.currentUtterance = text
                    if result.isFinal {
                        let newText = self.extractNewText(from: text)
                        if !newText.isEmpty { onFinal(newText) }
                        self.lastFinalText = text
                        self.currentUtterance = ""
                    } else {
                        let newText = self.extractNewText(from: text)
                        if !newText.isEmpty { onPartial(newText) }
                    }
                }
                if let error {
                    NSLog("[LocalSTT] Restart recognition error: %@", error.localizedDescription)
                }
            }
        }
    }
}
