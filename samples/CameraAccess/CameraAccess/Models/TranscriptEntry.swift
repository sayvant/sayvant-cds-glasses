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

  /// Merge new text into an existing entry, preserving original id and timestamp.
  init(merging text: String, from existing: TranscriptEntry) {
    self.id = existing.id
    self.timestamp = existing.timestamp
    self.text = text
    self.speaker = existing.speaker
  }
}
