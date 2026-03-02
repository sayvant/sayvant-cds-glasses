import Foundation

/// A single transcript entry with timestamp and speaker attribution.
struct TranscriptEntry: Identifiable, Codable {
  let id: String
  let timestamp: Date
  let text: String
  let speaker: Speaker

  enum Speaker: String, Codable {
    case patient = "patient"
    case ai = "ai"
  }

  init(text: String, speaker: Speaker) {
    self.id = UUID().uuidString
    self.timestamp = Date()
    self.text = text
    self.speaker = speaker
  }
}
