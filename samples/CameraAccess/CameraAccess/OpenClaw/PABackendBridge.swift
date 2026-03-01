import Foundation

/// Connection state for the PA backend.
enum PABackendConnectionState: Equatable {
  case notConfigured
  case checking
  case connected
  case unreachable(String)
}

/// Bridges Gemini tool calls to the PA backend /cds_whisper endpoint.
@MainActor
class PABackendBridge: ObservableObject {
  @Published var lastToolCallStatus: ToolCallStatus = .idle
  @Published var connectionState: PABackendConnectionState = .notConfigured

  /// Latest completeness score from the backend.
  @Published var completenessScore: Double = 0

  /// Active red flag message for the banner.
  @Published var activeRedFlag: String?

  // Dedup state: IDs already whispered to the physician.
  private(set) var previouslyAsked: [String] = []
  private(set) var previouslyFlagged: [String] = []

  private let session: URLSession
  private let pingSession: URLSession

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    self.session = URLSession(configuration: config)

    let pingConfig = URLSessionConfiguration.default
    pingConfig.timeoutIntervalForRequest = 5
    self.pingSession = URLSession(configuration: pingConfig)
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
    lastToolCallStatus = .idle
    NSLog("[PABackend] Session reset")
  }

  // MARK: - CDS Whisper

  struct WhisperResponse: Decodable {
    let ask_next: [AskNextItem]
    let red_flags: [RedFlagItem]
    let completeness_score: Double
  }

  struct AskNextItem: Decodable {
    let id: String
    let label: String
    let priority: Int
    let example_phrasing: String
  }

  struct RedFlagItem: Decodable {
    let id: String
    let message: String
    let urgency: String
  }

  /// Call /cds_whisper with encounter transcript. Returns a tool result
  /// string for Gemini to vocalize.
  func analyzeEncounter(transcript: String) async -> ToolResult {
    let toolName = "analyze_encounter"
    lastToolCallStatus = .executing(toolName)

    guard let url = URL(string: "\(GeminiConfig.paBackendURL)/cds_whisper") else {
      lastToolCallStatus = .failed(toolName, "Invalid URL")
      return .failure("Invalid PA backend URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(GeminiConfig.cdsAPIKey, forHTTPHeaderField: "X-CDS-Key")

    let body: [String: Any] = [
      "text": transcript,
      "previously_asked": previouslyAsked,
      "previously_flagged": previouslyFlagged
    ]

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      let (data, response) = try await session.data(for: request)

      guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        NSLog("[PABackend] CDS whisper failed: HTTP %d", code)
        lastToolCallStatus = .failed(toolName, "HTTP \(code)")
        return .failure("PA backend returned HTTP \(code)")
      }

      let whisper = try JSONDecoder().decode(WhisperResponse.self, from: data)

      // Update dedup state
      for q in whisper.ask_next {
        previouslyAsked.append(q.id)
      }
      for rf in whisper.red_flags {
        previouslyFlagged.append(rf.id)
      }

      // Update published state for UI
      completenessScore = whisper.completeness_score
      if let firstFlag = whisper.red_flags.first {
        activeRedFlag = firstFlag.message
      }

      // Build response string for Gemini to vocalize
      let resultText = buildGeminiResponse(whisper)
      NSLog("[PABackend] CDS result: %@", String(resultText.prefix(200)))
      lastToolCallStatus = .completed(toolName)
      return .success(resultText)

    } catch {
      NSLog("[PABackend] CDS error: %@", error.localizedDescription)
      lastToolCallStatus = .failed(toolName, error.localizedDescription)
      return .failure("CDS error: \(error.localizedDescription)")
    }
  }

  /// Build a structured response string that Gemini will use to generate
  /// its whisper audio. Gemini sees this as the tool result.
  private func buildGeminiResponse(_ whisper: WhisperResponse) -> String {
    var parts: [String] = []

    // Red flags first (highest priority)
    for rf in whisper.red_flags {
      parts.append("RED FLAG (\(rf.urgency)): \(rf.message)")
    }

    // Ask-next suggestions
    for q in whisper.ask_next {
      parts.append("SUGGEST: \(q.example_phrasing)")
    }

    // Completeness
    parts.append("COMPLETENESS: \(Int(whisper.completeness_score))%")

    if whisper.completeness_score > 80 && whisper.red_flags.isEmpty && whisper.ask_next.isEmpty {
      parts.append("History looks thorough. No further suggestions.")
    }

    return parts.joined(separator: "\n")
  }
}
