import Foundation

/// Full response from the /comprehensive_analysis endpoint.
/// Single API call returns prediction, differential, guidance, workup, and uncertainty.
struct ComprehensiveResponse: Decodable {
  let prediction: ComprehensivePrediction
  let uncertainty: UncertaintyData?
  let differential: DifferentialData
  let guidance: GuidanceData
  let recommended_workup: [String]
  let diagnostic_confidence: String
}

// MARK: - Prediction Block

struct ComprehensivePrediction: Decodable {
  let acs_probability: Double?
  let acs_probability_pct: String?
  let risk_band: String?
  let mode: String?
  let model_version: String?
  let confidence_interval: ConfidenceInterval?
  let safety_applied: Bool?
  let overrides_fired: [SafetyOverride]?
  let feature_contributions: [FeatureContribution]?
  let troponin_prediction: TroponinPrediction?
  let disposition_prediction: DispositionPrediction?

  /// Convert to the PredictResponse format used by existing card views.
  func toPredictResponse() -> PredictResponse? {
    guard let prob = acs_probability,
          let band = risk_band,
          let ci = confidence_interval,
          let mv = model_version else { return nil }
    return PredictResponse(
      prob: prob,
      band: band,
      confidence_interval: ci,
      safety_applied: safety_applied ?? false,
      overrides_fired: overrides_fired ?? [],
      feature_contributions: feature_contributions ?? [],
      troponin_prediction: troponin_prediction,
      disposition_prediction: disposition_prediction,
      model_version: mv
    )
  }
}

// MARK: - Uncertainty

struct UncertaintyData: Decodable {
  let confidence_interval: ConfidenceInterval?
  let calibrated_probability: Double?
  let uncertainty_level: String?
  let prediction_stability: Double?
  let feature_importance: [String: Double]?
  let uncertainty_sources: [UncertaintySource]?

  /// Stability as a display string.
  var stabilityLabel: String {
    guard let s = prediction_stability else { return "Unknown" }
    if s > 0.7 { return "Stable" }
    if s > 0.4 { return "Moderate" }
    return "Unstable"
  }

  /// Feature importance as sorted display items.
  var sortedFeatures: [(feature: String, importance: Double)] {
    (feature_importance ?? [:])
      .sorted { $0.value > $1.value }
      .map { (feature: $0.key, importance: $0.value) }
  }
}

/// Uncertainty source — backend returns either plain strings or objects.
struct UncertaintySource: Decodable, Identifiable {
  let source: String
  let description: String

  var id: String { source }

  init(from decoder: Decoder) throws {
    // Try plain string first (backend returns ["Limited clinical features..."])
    if let singleValue = try? decoder.singleValueContainer(),
       let text = try? singleValue.decode(String.self) {
      self.source = text
      self.description = text
      return
    }
    // Fall back to keyed object
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.source = try container.decode(String.self, forKey: .source)
    self.description = try container.decode(String.self, forKey: .description)
  }

  private enum CodingKeys: String, CodingKey {
    case source, description
  }
}

// MARK: - Differential

struct DifferentialData: Decodable {
  let ranked_diagnoses: [RankedDiagnosis]
  let cant_miss_alerts: [CantMissAlert]
  let most_likely: RankedDiagnosis?
  let risk_category: String
}

struct RankedDiagnosis: Decodable, Identifiable {
  let diagnosis: String
  let probability: Double
  let posterior: Double?
  let features_contributing: [String]?
  let clinical_pearl: String?
  let next_best_test: String?
  let supporting_features: [String]?
  let opposing_features: [String]?

  var id: String { diagnosis }
  var probabilityPct: Double { probability * 100 }
}

struct CantMissAlert: Decodable, Identifiable {
  let diagnosis: String
  let probability: Double
  let next_best_test: String?
  let clinical_pearl: String?

  var id: String { diagnosis }
  var probabilityPct: Double { probability * 100 }
}

// MARK: - Guidance

struct GuidanceData: Decodable {
  let red_flags: [FullRedFlag]
  let ask_next: [FullAskNext]
  let completeness: CompletenessData
  let risk_summary: String?
}

struct FullRedFlag: Decodable, Identifiable {
  let id: String
  let message: String
  let urgency: String
  let detected_features: [String]?
  let recommended_action: String?
  let clinical_reasoning: String?
}

struct FullAskNext: Decodable, Identifiable {
  let id: String
  let label: String
  let priority: Int
  let example_phrasing: String
  let reasoning: String?
  let clinical_relevance: String?
}

struct CompletenessData: Decodable {
  let overall_score: Double
  let captured_elements: [String]?
  let missing_elements: [String]?
  let category_scores: [String: CategoryScore]?
}

struct CategoryScore: Decodable {
  let score: Double?
  let captured: [String]?
  let missing: [String]?
  let total: Int?

  // The backend returns category_scores as a dict with varying shapes.
  // Handle both {score, captured, missing, total} objects AND plain numeric values like 40.0.
  init(from decoder: Decoder) throws {
    // Try plain Double first (backend returns "Pain Characteristics": 40.0)
    if let singleValue = try? decoder.singleValueContainer(),
       let numericScore = try? singleValue.decode(Double.self) {
      self.score = numericScore
      self.captured = nil
      self.missing = nil
      self.total = nil
      return
    }

    // Fall back to keyed object
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.score = try container.decodeIfPresent(Double.self, forKey: .score)
    self.captured = try container.decodeIfPresent([String].self, forKey: .captured)
    self.missing = try container.decodeIfPresent([String].self, forKey: .missing)
    self.total = try container.decodeIfPresent(Int.self, forKey: .total)
  }

  private enum CodingKeys: String, CodingKey {
    case score, captured, missing, total
  }
}
