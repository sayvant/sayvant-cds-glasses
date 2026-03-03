import Foundation

/// Full response from the /predict endpoint.
struct PredictResponse: Decodable {
  let prob: Double
  let band: String
  let confidence_interval: ConfidenceInterval
  let safety_applied: Bool
  let overrides_fired: [SafetyOverride]
  let feature_contributions: [FeatureContribution]
  let troponin_prediction: TroponinPrediction?
  let disposition_prediction: DispositionPrediction?
  let model_version: String

  var probabilityPct: Double { prob * 100 }
}

struct SafetyOverride: Decodable, Identifiable {
  let name: String
  let description: String?
  let enforced_min: Double?

  var id: String { name }
}

struct ConfidenceInterval: Decodable {
  let lower: Double
  let upper: Double
  let display: String?

  /// Formatted display string, falling back to computed if backend omits it.
  var displayText: String {
    display ?? "\(Int(lower * 100))%-\(Int(upper * 100))%"
  }
}

struct FeatureContribution: Decodable, Identifiable {
  let feature: String
  let weight: Double
  let direction: String
  let description: String

  var id: String { feature }
}

struct TroponinPrediction: Decodable {
  let probability: Double
  let probability_pct: String
  let confidence_interval: ConfidenceInterval

  var probabilityValue: Double {
    probability * 100
  }
}

struct DispositionPrediction: Decodable {
  let probability: Double
  let probability_pct: String
  let recommendation: String
  let thresholds: DispositionThresholds

  var probabilityValue: Double {
    probability * 100
  }
}

struct DispositionThresholds: Decodable {
  let admit: Double
  let observe: Double
}
