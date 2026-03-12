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
  private var partialFlushTask: Task<Void, Never>?
  private var lastAutoAnalyzedLength = 0
  private var lastFlushedPartial: String = ""

  /// Audio gate: only play Gemini audio that arrives after we send a tool response.
  /// Prevents Gemini's conversational/acknowledgment audio from playing.
  private var audioGateOpen = false

  /// Whether Gemini WebSocket is connected (separate from isGeminiActive which means session is running)
  private var geminiConnected = false

  func startSession() async {
    guard !isGeminiActive else { return }

    isGeminiActive = true

    // ── STEP 1: Start audio + local STT immediately (no Gemini dependency) ──

    // Check PA backend connectivity and start fresh session
    await paBackendBridge.checkConnection()
    paBackendBridge.resetSession()
    paBackendBridge.startAutoSave()
    transcriptEntries = []

    // Setup audio session
    do {
      try audioManager.setupAudioSession(useBluetoothGlasses: true)
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      isGeminiActive = false
      return
    }

    // Wire local STT to AudioManager's raw buffer callback
    audioManager.onRawBufferCaptured = { [weak self] buffer in
      guard let self else { return }
      self.localSTT.appendAudioBuffer(buffer)
    }

    // Wire Gemini audio send — only if connected
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self, self.geminiConnected else { return }
      Task { @MainActor in
        self.geminiService.sendAudio(data: data)
      }
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      isGeminiActive = false
      return
    }

    // Start local on-device speech recognition — near-instant transcription
    // Uses combined auth+start to avoid race condition where startRecognizing
    // runs before authorization callback fires.
    lastFlushedPartial = ""
    localSTT.requestAuthorizationAndStart(
      onPartial: { [weak self] text in
        guard let self else { return }
        self.userTranscript = text
      },
      onFinal: { [weak self] text in
        guard let self else { return }
        self.userTranscript = ""
        if !text.isEmpty {
          // Only commit the delta beyond what periodic flushes already sent
          let remaining: String
          if !self.lastFlushedPartial.isEmpty, text.hasPrefix(self.lastFlushedPartial) {
            remaining = String(text.dropFirst(self.lastFlushedPartial.count))
              .trimmingCharacters(in: .whitespaces)
          } else if self.lastFlushedPartial.isEmpty {
            remaining = text
          } else {
            remaining = "" // Partials already covered this text
          }
          self.lastFlushedPartial = "" // Reset for next utterance

          if !remaining.isEmpty {
            self.paBackendBridge.appendTranscript(remaining)
            if let lastIdx = self.transcriptEntries.indices.last,
               self.transcriptEntries[lastIdx].speaker == .patient,
               Date().timeIntervalSince(self.transcriptEntries[lastIdx].timestamp) < 5.0 {
              let existing = self.transcriptEntries[lastIdx]
              self.transcriptEntries[lastIdx] = TranscriptEntry(
                merging: existing.text + " " + remaining,
                from: existing
              )
            } else {
              self.transcriptEntries.append(TranscriptEntry(text: remaining, speaker: .patient))
            }
          }
        }
      }
    )

    // Flush partial STT text to backend every 2 seconds so auto-analysis
    // doesn't wait for onFinal (which only fires after speech pauses).
    partialFlushTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !Task.isCancelled, let self else { break }
        self.flushPartialToBackend()
      }
    }

    // Start auto-analysis loop (reduced delays: 2s initial, 3s cycle)
    lastAutoAnalyzedLength = 0
    autoAnalysisTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      while !Task.isCancelled {
        guard let self else { break }
        let currentLength = self.paBackendBridge.fullTranscript.count
        let hasNewText = currentLength > self.lastAutoAnalyzedLength + 10
        if hasNewText {
          NSLog("[AutoAnalysis] Triggering (transcript: %d chars)", currentLength)
          let didRun = await self.paBackendBridge.runAutoAnalysis()
          if didRun {
            self.lastAutoAnalyzedLength = currentLength
          }
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
      }
    }

    // Observe service state
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard !Task.isCancelled else { break }
        self.connectionState = self.geminiService.connectionState
        self.isModelSpeaking = self.geminiService.isModelSpeaking
        self.toolCallStatus = self.paBackendBridge.lastToolCallStatus
        self.paBackendConnectionState = self.paBackendBridge.connectionState
        self.audioRoute = self.audioManager.audioRoute
      }
    }

    // ── STEP 2: Connect Gemini in background (non-blocking) ──

    if GeminiConfig.isConfigured {
      Task { [weak self] in
        guard let self else { return }
        await self.connectGemini()
      }
    } else {
      NSLog("[Session] Gemini not configured — running with local STT only")
    }
  }

  /// Connect Gemini WebSocket and wire callbacks. Runs in background.
  private func connectGemini() async {
    // Wire Gemini callbacks
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
      }
    }

    // Gemini transcription — no-op for display, local STT handles it
    geminiService.onInputTranscription = { [weak self] _ in
      // No-op: local STT is primary transcription source
    }

    geminiService.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.aiTranscript += text
        self.transcriptEntries.append(TranscriptEntry(text: text, speaker: .ai))
      }
    }

    geminiService.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        self.geminiConnected = false
        if self.isGeminiActive {
          NSLog("[Gemini] Disconnected: %@ — local STT continues", reason ?? "unknown")
        }
      }
    }

    // Wire tool call handling
    toolCallRouter = ToolCallRouter(bridge: paBackendBridge)

    geminiService.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        for call in toolCall.functionCalls {
          self.toolCallRouter?.handleToolCall(call) { [weak self] response in
            guard let self else { return }
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

    // Connect
    let setupOk = await geminiService.connect()

    if setupOk {
      geminiConnected = true
      NSLog("[Gemini] Connected successfully")
    } else {
      let msg: String
      if case .error(let err) = geminiService.connectionState {
        msg = err
      } else {
        msg = "Gemini connection failed"
      }
      NSLog("[Gemini] %@ — continuing with local STT only", msg)
      geminiService.disconnect()
      // Don't set isGeminiActive = false — session continues without Gemini
    }
  }

  /// Physician taps "What did I miss?" — open audio gate and ask Gemini to summarize.
  func requestSummary() {
    guard isGeminiActive else { return }

    let questions = paBackendBridge.askNextQuestions
    let flags = paBackendBridge.redFlags
    let score = paBackendBridge.completenessScore

    var prompt: String

    if score > 0 || !questions.isEmpty || !flags.isEmpty {
      prompt = "The physician is asking: what did I miss? Summarize what they should still ask. "
      if !flags.isEmpty {
        prompt += "Red flags: \(flags.map { $0.message }.joined(separator: "; ")). "
      }
      if !questions.isEmpty {
        prompt += "Questions still needed: \(questions.map { $0.example_phrasing }.joined(separator: "; ")). "
      }
      prompt += "Completeness: \(Int(score))%. "
      prompt += "Speak a brief summary of what questions they should still ask. Under 30 words. Do not list scores."
    } else {
      prompt = "The physician is asking: what did I miss? Based on what you've heard so far in this encounter, briefly summarize what key questions still need to be asked for a thorough chest pain workup. Under 30 words."
    }

    NSLog("[Summary] Requesting: %@", prompt)

    if geminiConnected {
      audioGateOpen = true
      geminiService.sendTextMessage(prompt)
    } else {
      NSLog("[Summary] Gemini not connected — cannot generate whisper summary")
    }
  }

  // MARK: - Partial Flush

  /// Commit accumulated partial STT text to the PA backend transcript.
  /// Called every 2 seconds so auto-analysis has data without waiting for onFinal.
  private func flushPartialToBackend() {
    let current = userTranscript
    guard !current.isEmpty else { return }

    // If STT recognition restarted, the partial text resets to a shorter/different
    // string. Detect this and reset tracking so new speech gets flushed.
    if !lastFlushedPartial.isEmpty && !current.hasPrefix(lastFlushedPartial) {
      lastFlushedPartial = ""
    }
    guard current.count > lastFlushedPartial.count else { return }

    let delta: String
    if !lastFlushedPartial.isEmpty, current.hasPrefix(lastFlushedPartial) {
      delta = String(current.dropFirst(lastFlushedPartial.count))
        .trimmingCharacters(in: .whitespaces)
    } else {
      delta = current
    }
    guard !delta.isEmpty else { return }

    NSLog("[PartialFlush] +%d chars → backend (total partial: %d)", delta.count, current.count)
    paBackendBridge.appendTranscript(delta)

    // Update transcript entries for live display
    if let lastIdx = transcriptEntries.indices.last,
       transcriptEntries[lastIdx].speaker == .patient,
       Date().timeIntervalSince(transcriptEntries[lastIdx].timestamp) < 5.0 {
      let existing = transcriptEntries[lastIdx]
      transcriptEntries[lastIdx] = TranscriptEntry(
        merging: existing.text + " " + delta,
        from: existing
      )
    } else {
      transcriptEntries.append(TranscriptEntry(text: delta, speaker: .patient))
    }

    lastFlushedPartial = current
  }

  func stopSession() {
    localSTT.stopRecognizing()
    paBackendBridge.stopAutoSave()
    partialFlushTask?.cancel()
    partialFlushTask = nil
    autoAnalysisTask?.cancel()
    autoAnalysisTask = nil
    toolCallRouter?.cancelAll()
    toolCallRouter = nil
    audioManager.onRawBufferCaptured = nil
    audioManager.stopCapture()
    geminiService.disconnect()
    geminiConnected = false
    stateObservation?.cancel()
    stateObservation = nil
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    audioGateOpen = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
  }
}
