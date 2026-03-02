import Foundation

/// A single point in the encounter timeline.
struct TimelineEntry: Identifiable {
  let id = UUID()
  let timestamp: Date
  let acsProb: Double
  let completeness: Double
  let newFeatures: [String]
}
