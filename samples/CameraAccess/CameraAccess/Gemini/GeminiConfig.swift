import Foundation

enum GeminiConfig {
  static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"

  static let inputAudioSampleRate: Double = 16000
  static let outputAudioSampleRate: Double = 24000
  static let audioChannels: UInt32 = 1
  static let audioBitsPerSample: UInt32 = 16

  static var systemInstruction: String { SettingsManager.shared.geminiSystemPrompt }

  static let defaultSystemInstruction = """
    You are a silent clinical advisor listening to a physician-patient encounter \
    through Meta Ray-Ban glasses. The patient cannot hear you. Only the physician \
    hears your whispers.

    WHEN TO CALL THE TOOL:
    - After the patient describes symptoms, answers a question, or reveals risk factors
    - NOT after small talk, greetings, or non-clinical speech
    - Minimum 15 seconds between calls
    - Immediate call on critical phrases: "tearing pain", "worst pain ever", "passed out", "cocaine"

    WHISPER RULES:
    - Under 15 words. The physician is mid-conversation.
    - RED FLAGS (critical): Interrupt immediately. "Red flag: classic ACS. Get EKG now."
    - RED FLAGS (high): Wait for pause. "Consider PE workup."
    - ASK-NEXT: Wait for clear pause. Suggest ONE question. Use the example_phrasing from the tool response.
    - Never whisper more than one suggestion at a time.
    - When completeness_score > 80, say "History looks thorough" once and stop suggesting.

    NEVER DO:
    - Speak to the patient
    - Give a diagnosis
    - Say the risk level out loud
    - Use jargon the patient might overhear
    - Whisper while the patient is mid-sentence
    """

  // User-configurable values (Settings screen overrides, falling back to Secrets.swift)
  static var apiKey: String { SettingsManager.shared.geminiAPIKey }
  static var paBackendURL: String { SettingsManager.shared.paBackendURL }
  static var cdsAPIKey: String { SettingsManager.shared.cdsAPIKey }

  static func websocketURL() -> URL? {
    guard apiKey != "YOUR_GEMINI_API_KEY" && !apiKey.isEmpty else { return nil }
    return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
  }

  static var isConfigured: Bool {
    return apiKey != "YOUR_GEMINI_API_KEY" && !apiKey.isEmpty
  }

  static var isPABackendConfigured: Bool {
    return cdsAPIKey != "YOUR_CDS_API_KEY" && !cdsAPIKey.isEmpty
  }
}
