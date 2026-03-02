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
  let prediction_stability: String?
  let feature_importance: [UncertaintyFeature]?
  let uncertainty_sources: [UncertaintySource]?
}

struct UncertaintyFeature: Decodable, Identifiable {
  let feature: String
  let importance: Double

  var id: String { feature }
}

struct UncertaintySource: Decodable, Identifiable {
  let source: String
  let description: String

  var id: String { source }
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
  // Handle both {score, captured, missing, total} and simple numeric values.
  init(from decoder: Decoder) throws {
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
