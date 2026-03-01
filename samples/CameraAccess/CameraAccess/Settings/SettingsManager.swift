import Foundation

final class SettingsManager {
  static let shared = SettingsManager()

  private let defaults = UserDefaults.standard

  private enum Key: String {
    case geminiAPIKey
    case geminiSystemPrompt
    case paBackendURL
    case cdsAPIKey
  }

  private init() {}

  // MARK: - Gemini

  var geminiAPIKey: String {
    get { defaults.string(forKey: Key.geminiAPIKey.rawValue) ?? Secrets.geminiAPIKey }
    set { defaults.set(newValue, forKey: Key.geminiAPIKey.rawValue) }
  }

  var geminiSystemPrompt: String {
    get { defaults.string(forKey: Key.geminiSystemPrompt.rawValue) ?? GeminiConfig.defaultSystemInstruction }
    set { defaults.set(newValue, forKey: Key.geminiSystemPrompt.rawValue) }
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

  // MARK: - Reset

  func resetAll() {
    for key in [Key.geminiAPIKey, .geminiSystemPrompt, .paBackendURL, .cdsAPIKey] {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
