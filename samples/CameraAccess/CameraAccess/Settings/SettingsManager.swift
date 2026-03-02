import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  private let defaults = UserDefaults.standard

  private enum Key: String {
    case geminiAPIKey
    case geminiSystemPrompt_v2  // v2: stronger silence-first prompt
    case paBackendURL
    case cdsAPIKey
    case paFrontendURL
  }

  private init() {}

  // MARK: - Gemini

  var geminiAPIKey: String {
    get { defaults.string(forKey: Key.geminiAPIKey.rawValue) ?? Secrets.geminiAPIKey }
    set { defaults.set(newValue, forKey: Key.geminiAPIKey.rawValue) }
  }

  var geminiSystemPrompt: String {
    get { defaults.string(forKey: Key.geminiSystemPrompt_v2.rawValue) ?? GeminiConfig.defaultSystemInstruction }
    set { defaults.set(newValue, forKey: Key.geminiSystemPrompt_v2.rawValue) }
  }

  // MARK: - PA Backend

  var paBackendURL: String {
    get { defaults.string(forKey: Key.paBackendURL.rawValue) ?? Secrets.paBackendURL }
    set { defaults.set(newValue, forKey: Key.paBackendURL.rawValue) }
  }

  var cdsAPIKey: String {
    get { defaults.string(forKey: Key.cdsAPIKey.rawValue) ?? Secrets.cdsAPIKey }
    set { defaults.set(newValue, forKey: Key.cdsAPIKey.rawValue) }
  }

  var paFrontendURL: String {
    get { defaults.string(forKey: Key.paFrontendURL.rawValue) ?? Secrets.paFrontendURL }
    set { defaults.set(newValue, forKey: Key.paFrontendURL.rawValue) }
  }

  // MARK: - Reset

  func resetAll() {
    for key in [Key.geminiAPIKey, .geminiSystemPrompt_v2, .paBackendURL, .cdsAPIKey, .paFrontendURL] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
