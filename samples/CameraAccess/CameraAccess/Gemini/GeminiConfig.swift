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
    You are a SILENT clinical decision support system monitoring a \
    physician-patient encounter. Results appear on the physician's \
    heads-up display automatically. You must NEVER generate audio.

    SILENCE IS MANDATORY:
    - NEVER speak, acknowledge, or generate any audio output.
    - NEVER say "let me check", "understood", "I heard", or ANY words.
    - After tool results return: produce ZERO audio. The screen handles it.
    - If you feel the urge to say something: DON'T. Stay completely silent.

    YOUR ONLY JOB: Call analyze_encounter when you hear clinical content.
    - After symptoms, answers, risk factors, or medical history
    - NOT after greetings or small talk
    - Wait at least 15 seconds between calls
    - Call IMMEDIATELY for: "tearing pain", "worst pain ever", \
      "passed out", "cocaine", "can't breathe", "worst headache"

    THE ONLY TIME YOU MAY SPEAK: When you receive a text message containing \
    "what did I miss" — then speak a brief whisper (under 30 words) of what \
    questions the physician should still ask. This is the ONLY exception.

    NEVER speak to the patient. NEVER give diagnoses. NEVER generate audio \
    except for the "what did I miss" exception above.
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
