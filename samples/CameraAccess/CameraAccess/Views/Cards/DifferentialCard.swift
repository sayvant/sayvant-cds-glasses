import SwiftUI

/// Differential diagnosis card showing can't-miss alerts and ranked diagnoses.
struct DifferentialCard: View {
  let differential: DifferentialData
  @State private var expandedDiagnosis: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeader(title: "DIFFERENTIAL DIAGNOSIS",
                    trailing: "\(differential.ranked_diagnoses.count)")

      // CAN'T MISS — pinned red alerts
      if !differential.cant_miss_alerts.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill")
              .font(.system(size: 12, weight: .bold))
              .foregroundColor(.red)
            Text("CAN'T MISS")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(.red)
              .tracking(1)
          }

          ForEach(differential.cant_miss_alerts) { alert in
            HStack(spacing: 8) {
              Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
              Text(alert.diagnosis)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
              Spacer()
              Text("\(Int(alert.probabilityPct))%")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
            }

            if let test = alert.next_best_test, !test.isEmpty {
              HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                  .font(.system(size: 10))
                  .foregroundColor(.orange)
                Text(test)
                  .font(.system(size: 12, weight: .medium))
                  .foregroundColor(.orange)
              }
              .padding(.leading, 16)
            }
          }
        }
        .padding(10)
        .background(Color.red.opacity(0.12))
        .cornerRadius(10)
      }

      // Ranked diagnoses (top 5)
      let topDiagnoses = Array(differential.ranked_diagnoses.prefix(5))
      ForEach(topDiagnoses) { dx in
        VStack(alignment: .leading, spacing: 4) {
          Button {
            withAnimation {
              expandedDiagnosis = expandedDiagnosis == dx.id ? nil : dx.id
            }
          } label: {
            HStack(spacing: 8) {
              Text(dx.diagnosis)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
              Spacer()
              Text("\(Int(dx.probabilityPct))%")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(diagnosisColor(dx.probabilityPct))
              Image(systemName: expandedDiagnosis == dx.id ? "chevron.up" : "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.4))
            }
          }
          .buttonStyle(.plain)

          // Probability bar
          CDSProgressBar(value: dx.probability, color: diagnosisColor(dx.probabilityPct))
            .frame(height: 4)

          // Expanded detail
          if expandedDiagnosis == dx.id {
            VStack(alignment: .leading, spacing: 6) {
              // Supporting features
              if let supporting = dx.supporting_features, !supporting.isEmpty {
                FeatureList(label: "Supporting", features: supporting, color: .green)
              } else if let contributing = dx.features_contributing, !contributing.isEmpty {
                FeatureList(label: "Contributing", features: contributing, color: .green)
              }

              // Opposing features
              if let opposing = dx.opposing_features, !opposing.isEmpty {
                FeatureList(label: "Opposing", features: opposing, color: .red)
              }

              // Clinical pearl
              if let pearl = dx.clinical_pearl, !pearl.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                  Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.yellow)
                  Text(pearl)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.6))
                    .italic()
                }
              }

              // Next best test
              if let test = dx.next_best_test, !test.isEmpty {
                HStack(spacing: 6) {
                  Image(systemName: "stethoscope")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                  Text(test)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                }
              }
            }
            .padding(.leading, 8)
            .padding(.top, 4)
          }
        }
      }
    }
    .cdsCard(accent: .purple)
  }

  private func diagnosisColor(_ pct: Double) -> Color {
    if pct >= 30 { return .red }
    if pct >= 10 { return .orange }
    return Color(white: 0.5)
  }
}

// MARK: - Feature List Helper

private struct FeatureList: View {
  let label: String
  let features: [String]
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(features, id: \.self) { feature in
        HStack(spacing: 6) {
          Circle()
            .fill(color)
            .frame(width: 5, height: 5)
          Text(feature.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 12))
            .foregroundColor(Color(white: 0.6))
        }
      }
    }
  }
}
