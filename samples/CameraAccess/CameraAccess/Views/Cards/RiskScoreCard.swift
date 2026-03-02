import SwiftUI

/// Hero card showing ACS risk probability, band, and confidence interval.
struct RiskScoreCard: View {
  let prediction: PredictResponse
  var uncertainty: UncertaintyData?
  @State private var showUncertaintyDetail = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        SectionHeader(title: "ACS RISK")
        Spacer()

        // Uncertainty badge
        if let unc = uncertainty {
          Button {
            showUncertaintyDetail.toggle()
          } label: {
            HStack(spacing: 4) {
              Image(systemName: stabilityIcon(unc.prediction_stability))
                .font(.system(size: 11, weight: .bold))
              Text(unc.prediction_stability?.capitalized ?? "")
                .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(stabilityColor(unc.prediction_stability))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(stabilityColor(unc.prediction_stability).opacity(0.15))
            .cornerRadius(6)
          }
          .buttonStyle(.plain)
        }

        Text(prediction.band)
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(bandColor(prediction.band))
          .cornerRadius(8)
      }

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(Int(prediction.probabilityPct))")
          .font(.system(size: 56, weight: .bold, design: .rounded))
          .foregroundColor(bandColor(prediction.band))
        Text("%")
          .font(.system(size: 24, weight: .bold, design: .rounded))
          .foregroundColor(bandColor(prediction.band).opacity(0.7))

        Spacer()

        if prediction.safety_applied {
          Image(systemName: "shield.checkered")
            .font(.system(size: 24))
            .foregroundColor(.red)
        }
      }

      CDSProgressBar(value: prediction.prob, color: bandColor(prediction.band))

      Text("95% CI: \(prediction.confidence_interval.display)")
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundColor(Color(white: 0.5))

      // Uncertainty detail (expanded)
      if showUncertaintyDetail, let unc = uncertainty {
        VStack(alignment: .leading, spacing: 6) {
          if let level = unc.uncertainty_level {
            HStack {
              Text("Uncertainty:")
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.5))
              Text(level.uppercased())
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(stabilityColor(unc.prediction_stability))
            }
          }

          if let sources = unc.uncertainty_sources, !sources.isEmpty {
            ForEach(sources) { source in
              HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                  .font(.system(size: 10))
                  .foregroundColor(.orange)
                  .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                  Text(source.source.replacingOccurrences(of: "_", with: " "))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                  Text(source.description)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
                }
              }
            }
          }
        }
        .padding(.top, 4)
      }
    }
    .cdsCard(accent: bandColor(prediction.band))
  }

  private func stabilityIcon(_ stability: String?) -> String {
    switch stability?.lowercased() {
    case "stable": return "checkmark.circle.fill"
    case "moderate": return "questionmark.circle"
    case "unstable": return "exclamationmark.triangle.fill"
    default: return "questionmark.circle"
    }
  }

  private func stabilityColor(_ stability: String?) -> Color {
    switch stability?.lowercased() {
    case "stable": return .green
    case "moderate": return .orange
    case "unstable": return .red
    default: return .gray
    }
  }
}
