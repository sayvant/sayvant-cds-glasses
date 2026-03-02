import Foundation

/// Snapshot of all session state for persistence across app restarts.
struct SessionState: Codable {
  let savedAt: Date
  let fullTranscript: String
  let completenessScore: Double
  let previouslyAsked: [String]
  let previouslyFlagged: [String]

  // Simplified prediction state (not full PredictResponse — just what we need to display)
  let acsProb: Double?
  let riskBand: String?
  let safetyApplied: Bool

  /// Whether the session state is still fresh enough to resume.
  var isResumable: Bool {
    Date().timeIntervalSince(savedAt) < 2 * 3600 // 2 hours
  }

  static let fileURL: URL = {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("cds_session_state.json")
  }()

  static func save(_ state: SessionState) {
    do {
      let data = try JSONEncoder().encode(state)
      try data.write(to: fileURL, options: .atomic)
      NSLog("[SessionState] Saved (transcript: %d chars)", state.fullTranscript.count)
    } catch {
      NSLog("[SessionState] Save error: %@", error.localizedDescription)
    }
  }

  static func load() -> SessionState? {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    do {
      let data = try Data(contentsOf: fileURL)
      let state = try JSONDecoder().decode(SessionState.self, from: data)
      guard state.isResumable else {
        clear()
        return nil
      }
      return state
    } catch {
      NSLog("[SessionState] Load error: %@", error.localizedDescription)
      return nil
    }
  }

  static func clear() {
    try? FileManager.default.removeItem(at: fileURL)
    NSLog("[SessionState] Cleared")
  }
}
