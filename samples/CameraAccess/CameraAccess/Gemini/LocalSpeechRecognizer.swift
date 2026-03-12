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

    /// Request speech recognition permission and start recognizing once authorized.
    func requestAuthorizationAndStart(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) {
        NSLog("[LocalSTT] Requesting authorization...")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthorized = (status == .authorized)
                NSLog("[LocalSTT] Authorization status: %d (authorized=%@)",
                      status.rawValue, status == .authorized ? "YES" : "NO")
                if status == .authorized {
                    self.startRecognizing(onPartial: onPartial, onFinal: onFinal)
                } else {
                    NSLog("[LocalSTT] NOT AUTHORIZED — speech recognition will not work")
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
        NSLog("[LocalSTT] startRecognizing called. recognizer=%@, available=%@, onDevice=%@",
              recognizer != nil ? "YES" : "NIL",
              recognizer?.isAvailable == true ? "YES" : "NO",
              recognizer?.supportsOnDeviceRecognition == true ? "YES" : "NO")

        guard recognizer?.isAvailable == true else {
            NSLog("[LocalSTT] *** Recognizer not available — NO TRANSCRIPTION ***")
            return
        }

        // Cancel any previous task
        stopRecognizing()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device but don't require it — falls back to server if model not downloaded
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
            NSLog("[LocalSTT] Using on-device recognition")
        } else {
            NSLog("[LocalSTT] On-device not available, using server recognition")
        }
        if #available(iOS 16, *) {
            request.addsPunctuation = false // Skip punctuation for lowest latency
        }
        // Smaller task hint for faster partial results
        request.taskHint = .dictation
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
                        NSLog("[LocalSTT] FINAL: \"%@\"", newText)
                        if !newText.isEmpty {
                            onFinal(newText)
                        }
                        self.lastFinalText = text
                        self.currentUtterance = ""
                    } else {
                        let newText = self.extractNewText(from: text)
                        NSLog("[LocalSTT] partial: \"%@\"", newText)
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
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        if #available(iOS 16, *) {
            request.addsPunctuation = false
        }
        request.taskHint = .dictation
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
