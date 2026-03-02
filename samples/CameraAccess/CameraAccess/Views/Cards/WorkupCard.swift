import SwiftUI

/// Workup recommendations card with tiered priority items.
struct WorkupCard: View {
  let recommendations: [String]

  var body: some View {
    if !recommendations.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "RECOMMENDED WORKUP", trailing: "\(recommendations.count)")

        ForEach(Array(recommendations.enumerated()), id: \.offset) { index, item in
          HStack(alignment: .top, spacing: 10) {
            Circle()
              .fill(tierColor(for: item, index: index))
              .frame(width: 8, height: 8)
              .padding(.top, 5)
            Text(highlightConditionSpecific(item))
              .font(.system(size: 14, weight: isConditionSpecific(item) ? .semibold : .medium))
              .foregroundColor(isConditionSpecific(item) ? .orange : .white)
          }
        }
      }
      .cdsCard(accent: .cyan)
    }
  }

  /// Determine tier color: first items = STAT (red), middle = Consider (amber), last = Follow-up (green).
  private func tierColor(for item: String, index: Int) -> Color {
    let lowered = item.lowercased()
    if lowered.contains("stat") || lowered.contains("immediate") || lowered.contains("emergent") {
      return .red
    }
    if lowered.contains("consider") || lowered.contains("if") {
      return .orange
    }
    if lowered.contains("follow") || lowered.contains("outpatient") {
      return .green
    }
    // Default by position
    if index < 3 { return .red }
    if index < 6 { return .orange }
    return .green
  }

  /// Detect condition-specific recommendations.
  private func isConditionSpecific(_ item: String) -> Bool {
    let lowered = item.lowercased()
    return lowered.contains("avoid") || lowered.contains("cocaine")
        || lowered.contains("contraindicated") || lowered.contains("d-dimer")
        || lowered.contains("ctpa") || lowered.contains("dissection")
  }

  /// Return text as-is (highlighting is handled via font weight/color).
  private func highlightConditionSpecific(_ item: String) -> String {
    item
  }
}
