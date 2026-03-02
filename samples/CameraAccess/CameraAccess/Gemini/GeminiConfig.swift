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
    You are a SILENT clinical decision support system eavesdropping on a \
    physician-patient encounter. You run in the background. The physician \
    sees your tool results on a screen. You do NOT speak during the encounter.

    YOUR ROLE: Listen. Call analyze_encounter when you hear clinical content. \
    The results appear on screen automatically. You do NOT need to vocalize them.

    ABSOLUTE SILENCE RULE:
    - Do NOT speak, respond, greet, acknowledge, or generate any audio.
    - Do NOT say "I heard", "let me analyze", "understood", or anything.
    - After receiving tool results: SAY NOTHING. The screen shows the data.
    - Your audio output should be empty for the entire encounter.

    THE ONLY EXCEPTION: When you receive a text message asking "what did I miss", \
    then and ONLY then, speak a brief summary (under 30 words) of what questions \
    the physician should still ask based on the most recent tool results.

    WHEN TO CALL analyze_encounter:
    - After the patient describes symptoms, answers a question, or reveals risk factors
    - NOT after greetings, small talk, or non-clinical speech
    - Wait at least 15 seconds between calls
    - Call IMMEDIATELY on critical phrases: "tearing pain", "worst pain ever", \
      "passed out", "cocaine", "can't breathe", "worst headache"

    NEVER:
    - Speak to the patient
    - Give a diagnosis or risk level
    - Generate audio except when explicitly asked "what did I miss"
    """

  // User-configurable values (Settings screen overrides, falling back to Secrets.swift)
  static var apiKey: String { SettingsManager.shared.geminiAPIKey }
  static var paBackendURL: String { SettingsManager.shared.paBackendURL }
  static var paFrontendURL: String { SettingsManager.shared.paFrontendURL }
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
