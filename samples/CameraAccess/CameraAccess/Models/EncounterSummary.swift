import Foundation

// MARK: - /full_summary Response

struct EncounterSummaryResponse: Decodable {
  let format: String
  let summary: EncounterSummaryData?
}

struct EncounterSummaryData: Decodable {
  let encounter_id: String?
  let prediction: SummaryPrediction?
  let differential: SummaryDifferential?
  let guidance: SummaryGuidance?
  let uncertainty: SummaryUncertainty?
  let recommendations: [String]?
}

struct SummaryPrediction: Decodable {
  let acs_probability: Double?
  let risk_band: String?
  let safety_applied: Bool?
}

struct SummaryDifferential: Decodable {
  let ranked_diagnoses: [SummaryDiagnosis]?
  let risk_category: String?
}

struct SummaryDiagnosis: Decodable, Identifiable {
  let diagnosis: String
  let probability: Double

  var id: String { diagnosis }
  var probabilityPct: Double { probability * 100 }
}

struct SummaryGuidance: Decodable {
  let completeness: SummaryCompleteness?
  let red_flags_count: Int?
  let questions_remaining: Int?
}

struct SummaryCompleteness: Decodable {
  let overall_score: Double?
}

struct SummaryUncertainty: Decodable {
  let uncertainty_level: String?
  let prediction_stability: String?
}

// MARK: - Local Encounter Storage

struct SavedEncounter: Codable, Identifiable {
  let id: String
  let date: Date
  let transcript: String
  let acsRiskPct: Double?
  let riskBand: String?
  let topDiagnosis: String?
  let disposition: String?
  let completenessScore: Double?

  // Summary sections
  let differentialSummary: [DiagnosisSummaryItem]?
  let workupItems: [String]?
  let redFlagCount: Int
  let questionsAsked: Int
}

struct DiagnosisSummaryItem: Codable, Identifiable {
  let diagnosis: String
  let probabilityPct: Double

  var id: String { diagnosis }
}

// MARK: - Encounter Store

class EncounterStore {
  static let shared = EncounterStore()

  private let fileManager = FileManager.default

  private var documentsURL: URL {
    fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  private var storeURL: URL {
    documentsURL.appendingPathComponent("encounters.json")
  }

  func save(_ encounter: SavedEncounter) {
    var encounters = loadAll()
    encounters.insert(encounter, at: 0)
    // Keep last 50 encounters
    if encounters.count > 50 {
      encounters = Array(encounters.prefix(50))
    }
    do {
      let data = try JSONEncoder().encode(encounters)
      try data.write(to: storeURL, options: .atomic)
    } catch {
      NSLog("[EncounterStore] Save error: %@", error.localizedDescription)
    }
  }

  func loadAll() -> [SavedEncounter] {
    guard fileManager.fileExists(atPath: storeURL.path) else { return [] }
    do {
      let data = try Data(contentsOf: storeURL)
      return try JSONDecoder().decode([SavedEncounter].self, from: data)
    } catch {
      NSLog("[EncounterStore] Load error: %@", error.localizedDescription)
      return []
    }
  }

  func delete(id: String) {
    var encounters = loadAll()
    encounters.removeAll { $0.id == id }
    do {
      let data = try JSONEncoder().encode(encounters)
      try data.write(to: storeURL, options: .atomic)
    } catch {
      NSLog("[EncounterStore] Delete error: %@", error.localizedDescription)
    }
  }
}
