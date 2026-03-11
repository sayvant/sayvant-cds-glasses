import Foundation
import SwiftUI

@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var transcriptEntries: [TranscriptEntry] = []
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var paBackendConnectionState: PABackendConnectionState = .notConfigured
  @Published var audioRoute: AudioRouteStatus = .unknown

  private let geminiService = GeminiLiveService()
  let paBackendBridge = PABackendBridge()
  private var toolCallRouter: ToolCallRouter?
  private let audioManager = AudioManager()
  let localSTT = LocalSpeechRecognizer()
  private var stateObservation: Task<Void, Never>?
  private var autoAnalysisTask: Task<Void, Never>?
  private var lastAutoAnalyzedLength = 0

  /// Audio gate: only play Gemini audio that arrives after we send a tool response.
  /// Prevents Gemini's conversational/acknowledgment audio from playing.
  private var audioGateOpen = false

  func startSession() async {
    guard !isGeminiActive else { return }

    guard GeminiConfig.isConfigured else {
      errorMessage = "Gemini API key not configured. Go to Settings and enter your key from https://aistudio.google.com/apikey"
      return
    }

    isGeminiActive = true

    // Wire audio callbacks
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        self.geminiService.sendAudio(data: data)
      }
    }

    geminiService.onAudioReceived = { [weak self] data in
      guard let self, self.audioGateOpen else { return }
      self.audioManager.playAudio(data: data)
    }

    geminiService.onInterrupted = { [weak self] in
      self?.audioGateOpen = false
      self?.audioManager.stopPlayback()
    }

    geminiService.onTurnComplete = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        self.audioGateOpen = false
        // Don't clear userTranscript here — keep it visible in the transcript pane
        // until new input arrives. It will be cleared when onInputTranscription fires.
      }
    }

    // Gemini input transcription — still listen but DON'T use for display.
    // Local STT handles the real-time transcript. Gemini transcription is a
    // backup and feeds into Gemini's context so its tool calls stay informed.
    geminiService.onInputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        // No-op for display — local STT handles userTranscript + transcriptEntries.
        // Gemini still sees this internally for its conversation context.
      }
    }

    geminiService.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.aiTranscript += text
        // Append AI response to transcript log
        self.transcriptEntries.append(TranscriptEntry(text: text, speaker: .ai))
      }
    }

    // Handle unexpected disconnection
    geminiService.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }
        self.stopSession()
        self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
      }
    }

    // Check PA backend connectivity and start fresh session
    await paBackendBridge.checkConnection()
    paBackendBridge.resetSession()
    paBackendBridge.startAutoSave()
    transcriptEntries = []

    // Wire tool call handling
    toolCallRouter = ToolCallRouter(bridge: paBackendBridge)

    geminiService.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        for call in toolCall.functionCalls {
          // analyzeEncounter now calls /comprehensive_analysis (single call)
          // which returns prediction + differential + guidance + workup
          self.toolCallRouter?.handleToolCall(call) { [weak self] response in
            guard let self else { return }
            // Open the audio gate: next audio from Gemini is the whisper
            self.audioGateOpen = true
            NSLog("[AudioGate] Opened — tool response sent, ready for whisper audio")
            self.geminiService.sendToolResponse(response)
          }
        }
      }
    }

    geminiService.onToolCallCancellation = { [weak self] cancellation in
      guard let self else { return }
      Task { @MainActor in
        self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
      }
    }

    // Observe service state
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled else { break }
        self.connectionState = self.geminiService.connectionState
        self.isModelSpeaking = self.geminiService.isModelSpeaking
        self.toolCallStatus = self.paBackendBridge.lastToolCallStatus
        self.paBackendConnectionState = self.paBackendBridge.connectionState
        self.audioRoute = self.audioManager.audioRoute
      }
    }

    // Setup audio — Bluetooth routing for glasses speaker
    do {
      try audioManager.setupAudioSession(useBluetoothGlasses: true)
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      isGeminiActive = false
      return
    }

    // Connect to Gemini and wait for setupComplete
    let setupOk = await geminiService.connect()

    if !setupOk {
      let msg: String
      if case .error(let err) = geminiService.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to Gemini"
      }
      errorMessage = msg
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }

    // Wire local STT to AudioManager's raw buffer callback
    audioManager.onRawBufferCaptured = { [weak self] buffer in
      guard let self else { return }
      self.localSTT.appendAudioBuffer(buffer)
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      geminiService.disconnect()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }

    // Start local on-device speech recognition — near-instant transcription
    localSTT.requestAuthorization()
    localSTT.startRecognizing(
      onPartial: { [weak self] text in
        guard let self else { return }
        // Update display with partial (real-time) text
        self.userTranscript = text
      },
      onFinal: { [weak self] text in
        guard let self else { return }
        // Finalized segment — append to transcript entries + PA bridge
        self.userTranscript = ""
        if !text.isEmpty {
          if let lastIdx = self.transcriptEntries.indices.last,
             self.transcriptEntries[lastIdx].speaker == .patient,
             Date().timeIntervalSince(self.transcriptEntries[lastIdx].timestamp) < 3.0 {
            let existing = self.transcriptEntries[lastIdx]
            self.transcriptEntries[lastIdx] = TranscriptEntry(
              merging: existing.text + " " + text,
              from: existing
            )
          } else {
            self.transcriptEntries.append(TranscriptEntry(text: text, speaker: .patient))
          }
          self.paBackendBridge.appendTranscript(text)
        }
      }
    )

    // Start auto-analysis loop: every 10 seconds, if new transcript text has
    // accumulated, send to /comprehensive_analysis for real-time card updates.
    // This runs independently of Gemini tool calls — cards update even if
    // Gemini hasn't decided to call analyze_encounter yet.
    lastAutoAnalyzedLength = 0
    autoAnalysisTask = Task { [weak self] in
      // Wait 4 seconds before first analysis to accumulate initial speech
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      while !Task.isCancelled {
        guard let self else { break }
        let currentLength = self.paBackendBridge.fullTranscript.count
        let hasNewText = currentLength > self.lastAutoAnalyzedLength + 10 // ~2 words
        if hasNewText {
          NSLog("[AutoAnalysis] Triggering (transcript: %d chars)", currentLength)
          let didRun = await self.paBackendBridge.runAutoAnalysis()
          if didRun {
            self.lastAutoAnalyzedLength = currentLength
          }
        }
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
      }
    }
  }

  /// Physician taps "What did I miss?" — open audio gate and ask Gemini to summarize.
  func requestSummary() {
    guard isGeminiActive else { return }

    // Build summary from accumulated PA data
    let questions = paBackendBridge.askNextQuestions
    let flags = paBackendBridge.redFlags
    let score = paBackendBridge.completenessScore

    var prompt: String

    if score > 0 || !questions.isEmpty || !flags.isEmpty {
      // We have CDS data — build a targeted summary
      prompt = "The physician is asking: what did I miss? Summarize what they should still ask. "

      if !flags.isEmpty {
        let flagTexts = flags.map { $0.message }
        prompt += "Red flags: \(flagTexts.joined(separator: "; ")). "
      }

      if !questions.isEmpty {
        let qTexts = questions.map { $0.example_phrasing }
        prompt += "Questions still needed: \(qTexts.joined(separator: "; ")). "
      }

      prompt += "Completeness: \(Int(score))%. "
      prompt += "Speak a brief summary of what questions they should still ask. Under 30 words. Do not list scores."
    } else {
      // No CDS data yet — ask Gemini to summarize from conversation context
      prompt = "The physician is asking: what did I miss? Based on what you've heard so far in this encounter, briefly summarize what key questions still need to be asked for a thorough chest pain workup. Under 30 words."
    }

    NSLog("[Summary] Requesting: %@", prompt)

    // Open the audio gate — this is the ONE time we want to hear Gemini
    audioGateOpen = true
    geminiService.sendTextMessage(prompt)
  }

  func stopSession() {
    localSTT.stopRecognizing()
    paBackendBridge.stopAutoSave()
    autoAnalysisTask?.cancel()
    autoAnalysisTask = nil
    toolCallRouter?.cancelAll()
    toolCallRouter = nil
    audioManager.onRawBufferCaptured = nil
    audioManager.stopCapture()
    geminiService.disconnect()
    stateObservation?.cancel()
    stateObservation = nil
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    audioGateOpen = false
    userTranscript = ""
    aiTranscript = ""
    // Don't clear transcriptEntries here — they're needed for encounter summary.
    // They'll be cleared on next startSession() via resetSession().
    toolCallStatus = .idle
  }
}
