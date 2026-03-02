import Foundation

/// Connection state for the PA backend.
enum PABackendConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

/// Bridges Gemini tool calls to the PA backend /comprehensive_analysis endpoint.
/// Single API call returns prediction, differential, guidance, workup, and uncertainty.
@MainActor
class PABackendBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: PABackendConnectionState = .notConfigured

  /// Latest completeness score from the backend.
  @Published var completenessScore: Double = 0

  /// Active red flag message for the banner.
  @Published var activeRedFlag: String?

  /// All red flags accumulated during the encounter (full objects with actions).
  @Published var redFlags: [FullRedFlag] = []

  /// Current ask-next questions from the latest analysis.
  @Published var askNextQuestions: [FullAskNext] = []

  /// Full prediction result for native cards.
  @Published var predictionResult: PredictResponse?

  /// Full comprehensive response (differential, workup, uncertainty, guidance).
  @Published var comprehensiveResult: ComprehensiveResponse?

  /// Whether an analysis call is in flight.
  @Published var isPredicting: Bool = false

  /// Full transcript accumulated across the encounter.
  @Published var fullTranscript: String = ""

  /// Timeline entries for risk trend visualization.
  @Published var timelineEntries: [TimelineEntry] = []

  // Dedup state: IDs already sent to the backend.
  private(set) var previouslyAsked: [String] = []
  private(set) var previouslyFlagged: [String] = []

  private let session: URLSession
  private let pingSession: URLSession
  private var autoSaveTask: Task<Void, Never>?

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)
  }

  /// Check if a resumable session state exists.
  var hasResumableState: Bool {
    SessionState.load() != nil
  }

  /// Resume from saved session state.
  func resumeFromSavedState() {
    guard let state = SessionState.load() else { return }
    fullTranscript = state.fullTranscript
    completenessScore = state.completenessScore
    previouslyAsked = state.previouslyAsked
    previouslyFlagged = state.previouslyFlagged
    NSLog("[PABackend] Resumed session (transcript: %d chars)", state.fullTranscript.count)
  }

  /// Start auto-saving session state every 5 seconds.
  func startAutoSave() {
    autoSaveTask?.cancel()
    autoSaveTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        guard !Task.isCancelled, let self else { break }
        await self.saveState()
      }
    }
  }

  /// Stop auto-saving.
  func stopAutoSave() {
    autoSaveTask?.cancel()
    autoSaveTask = nil
    SessionState.clear()
  }

  private func saveState() {
    guard !fullTranscript.isEmpty else { return }
    let state = SessionState(
      savedAt: Date(),
      fullTranscript: fullTranscript,
      completenessScore: completenessScore,
      previouslyAsked: previouslyAsked,
      previouslyFlagged: previouslyFlagged,
      acsProb: predictionResult?.prob,
      riskBand: predictionResult?.band,
      safetyApplied: predictionResult?.safety_applied ?? false
    )
    SessionState.save(state)
  }

  // MARK: - Connection check

  func checkConnection() async {
    guard GeminiConfig.isPABackendConfigured else {
      connectionState = .notConfigured
      return
    }
    connectionState = .checking
    guard let url = URL(string: "\(GeminiConfig.paBackendURL)/health") else {
      connectionState = .unreachable("Invalid URL")
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    do {
      let (_, response) = try await pingSession.data(for: request)
      if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
        connectionState = .connected
        NSLog("[PABackend] Reachable (HTTP %d)", http.statusCode)
      } else {
        connectionState = .unreachable("Unexpected response")
      }
    } catch {
      connectionState = .unreachable(error.localizedDescription)
      NSLog("[PABackend] Unreachable: %@", error.localizedDescription)
    }
  }

  func resetSession() {
    previouslyAsked = []
    previouslyFlagged = []
    completenessScore = 0
    activeRedFlag = nil
    redFlags = []
    askNextQuestions = []
    lastToolCallStatus = .idle
    predictionResult = nil
    comprehensiveResult = nil
    isPredicting = false
    fullTranscript = ""
    timelineEntries = []
    NSLog("[PABackend] Session reset")
  }

  // MARK: - Transcript Accumulation

  /// Append new speech text to the running transcript (called from onInputTranscription).
  func appendTranscript(_ text: String) {
    guard !text.isEmpty else { return }
    if !fullTranscript.isEmpty {
      fullTranscript += " "
    }
    fullTranscript += text
  }

  // MARK: - Comprehensive Analysis

  /// Shared core: call /comprehensive_analysis, update all published state.
  /// Returns the decoded response on success, nil on failure.
  private func callComprehensiveAnalysis(text: String) async -> ComprehensiveResponse? {
    guard !text.isEmpty else { return nil }
    guard let url = URL(string: "\(GeminiConfig.paBackendURL)/comprehensive_analysis") else {
      NSLog("[PABackend] Invalid PA backend URL")
      return nil
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(GeminiConfig.cdsAPIKey, forHTTPHeaderField: "X-CDS-Key")

    let body: [String: Any] = [
      "text": text,
      "previously_asked": previouslyAsked,
      "previously_flagged": previouslyFlagged,
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)

      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        NSLog("[PABackend] comprehensive_analysis failed: HTTP %d", code)
        return nil
      }

      let comprehensive = try JSONDecoder().decode(ComprehensiveResponse.self, from: data)
      applyComprehensiveResult(comprehensive)

      NSLog("[PABackend] comprehensive result: prob=%.3f diff=%d workup=%d",
            comprehensive.prediction.acs_probability ?? 0,
            comprehensive.differential.ranked_diagnoses.count,
            comprehensive.recommended_workup.count)

      return comprehensive
    } catch {
      NSLog("[PABackend] comprehensive error: %@", error.localizedDescription)
      return nil
    }
  }

  /// Apply a comprehensive response to all published state.
  private func applyComprehensiveResult(_ comprehensive: ComprehensiveResponse) {
    comprehensiveResult = comprehensive

    // Update prediction state for card views
    if let pred = comprehensive.prediction.toPredictResponse() {
      predictionResult = pred

      // Track timeline entry for risk trend chart
      let newFeatures = comprehensive.prediction.feature_contributions?
        .prefix(3).map { $0.feature } ?? []
      timelineEntries.append(TimelineEntry(
        timestamp: Date(),
        acsProb: pred.prob,
        completeness: comprehensive.guidance.completeness.overall_score,
        newFeatures: Array(newFeatures)
      ))
    }

    // Update dedup state for guidance
    for q in comprehensive.guidance.ask_next {
      if !previouslyAsked.contains(q.id) {
        previouslyAsked.append(q.id)
      }
    }
    for rf in comprehensive.guidance.red_flags {
      if !previouslyFlagged.contains(rf.id) {
        previouslyFlagged.append(rf.id)
      }
    }

    // Update published guidance state for UI
    completenessScore = comprehensive.guidance.completeness.overall_score
    askNextQuestions = comprehensive.guidance.ask_next

    for rf in comprehensive.guidance.red_flags {
      if !redFlags.contains(where: { $0.id == rf.id }) {
        redFlags.append(rf)
      }
    }
    if !comprehensive.guidance.red_flags.isEmpty {
      activeRedFlag = comprehensive.guidance.red_flags.first?.message
    }
  }

  /// Call /comprehensive_analysis via Gemini tool call.
  /// Updates all published state and returns a tool result string for Gemini to vocalize.
  func analyzeEncounter(transcript: String) async -> ToolResult {
    let toolName = "analyze_encounter"
    lastToolCallStatus = .executing(toolName)
    isPredicting = true

    // Accumulate transcript
    appendTranscript(transcript)

    guard let comprehensive = await callComprehensiveAnalysis(text: fullTranscript) else {
      lastToolCallStatus = .failed(toolName, "Analysis failed")
      isPredicting = false
      return .failure("PA backend analysis failed")
    }

    let resultText = buildGeminiResponse(comprehensive)
    lastToolCallStatus = .completed(toolName)
    isPredicting = false
    return .success(resultText)
  }

  /// Auto-triggered analysis from transcript accumulation (no Gemini tool call).
  /// Updates all published state for real-time card rendering.
  func runAutoAnalysis() async {
    guard !isPredicting else { return }
    guard !fullTranscript.isEmpty else { return }
    isPredicting = true
    _ = await callComprehensiveAnalysis(text: fullTranscript)
    isPredicting = false
  }

  /// Build a structured response string that Gemini will use to generate
  /// its whisper audio. Gemini sees this as the tool result.
  private func buildGeminiResponse(_ response: ComprehensiveResponse) -> String {
    var parts: [String] = []

    // Red flags first (highest priority)
    for rf in response.guidance.red_flags {
      parts.append("RED FLAG (\(rf.urgency)): \(rf.message)")
    }

    // Can't-miss alerts from differential
    for alert in response.differential.cant_miss_alerts {
      parts.append("CAN'T MISS: \(alert.diagnosis) (\(Int(alert.probabilityPct))%)")
    }

    // Ask-next suggestions
    for q in response.guidance.ask_next {
      parts.append("SUGGEST: \(q.example_phrasing)")
    }

    // Completeness
    let score = Int(response.guidance.completeness.overall_score)
    parts.append("COMPLETENESS: \(score)%")

    if score > 80 && response.guidance.red_flags.isEmpty && response.guidance.ask_next.isEmpty {
      parts.append("History looks thorough. No further suggestions.")
    }

    return parts.joined(separator: "\n")
  }

  // MARK: - Direct Analysis (no Gemini)

  /// Call /comprehensive_analysis directly with text input (for manual text mode).
  /// Updates all published state but does not return a Gemini tool result.
  func analyzeText(_ text: String) async {
    guard !text.isEmpty else { return }
    isPredicting = true
    _ = await callComprehensiveAnalysis(text: text)
    isPredicting = false
  }

  // MARK: - Full Summary

  /// Call /full_summary for end-of-encounter summary.
  func fetchFullSummary(text: String) async -> EncounterSummaryResponse? {
    guard let url = URL(string: "\(GeminiConfig.paBackendURL)/full_summary") else { return nil }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(GeminiConfig.cdsAPIKey, forHTTPHeaderField: "X-CDS-Key")

    let body: [String: Any] = ["text": text, "format": "json"]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)

      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        return nil
      }

      return try JSONDecoder().decode(EncounterSummaryResponse.self, from: data)
    } catch {
      NSLog("[PABackend] full_summary error: %@", error.localizedDescription)
      return nil
    }
  }
}
