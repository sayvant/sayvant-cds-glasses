import SwiftUI

// MARK: - Troponin Card

struct TroponinCard: View {
  let troponin: TroponinPrediction

  private var pct: Double { troponin.probabilityValue }
  private var color: Color { troponinColor(pct) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SectionHeader(title: "TROPONIN+")
        Spacer()
        Text(String(format: "%.1f%%", pct))
          .font(.system(size: 15, weight: .bold, design: .monospaced))
          .foregroundColor(color)
      }
      CDSProgressBar(value: troponin.probability, color: color)
      Text("95% CI: \(troponin.confidence_interval.display)")
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundColor(Color(white: 0.4))
    }
    .cdsCard(accent: color)
  }
}

// MARK: - Disposition Card

struct DispositionCard: View {
  let disposition: DispositionPrediction

  private var pct: Double { disposition.probabilityValue }
  private var color: Color { dispositionColor(disposition.recommendation) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        SectionHeader(title: "DISPOSITION")
        Spacer()
        Text(disposition.recommendation.uppercased())
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(color)
          .cornerRadius(8)
      }
      HStack {
        Text(String(format: "%.1f%%", pct))
          .font(.system(size: 20, weight: .bold, design: .monospaced))
          .foregroundColor(color)
        Spacer()
      }
      CDSProgressBar(value: disposition.probability, color: color)
    }
    .cdsCard(accent: color)
  }
}

// MARK: - Feature Attribution Card

struct FeatureAttributionCard: View {
  let contributions: [FeatureContribution]

  private var topFeatures: [FeatureContribution] {
    Array(contributions.sorted { abs($0.weight) > abs($1.weight) }.prefix(5))
  }

  private var maxWeight: Double {
    topFeatures.map { abs($0.weight) }.max() ?? 1
  }

  var body: some View {
    if !contributions.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "TOP CONTRIBUTORS")
        ForEach(topFeatures) { fc in
          HStack(spacing: 8) {
            Text(fc.direction == "positive" ? "+" : "-")
              .font(.system(size: 14, weight: .bold, design: .monospaced))
              .foregroundColor(fc.direction == "positive" ? .red : .green)
              .frame(width: 16)
            Text(fc.feature.replacingOccurrences(of: "_", with: " "))
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white)
              .lineLimit(1)
            Spacer()
            // Weight bar
            GeometryReader { geo in
              let barWidth = geo.size.width * (abs(fc.weight) / maxWeight)
              HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                  .fill(fc.direction == "positive" ? Color.red.opacity(0.6) : Color.green.opacity(0.6))
                  .frame(width: barWidth, height: 14)
              }
            }
            .frame(width: 60, height: 14)
            Text(String(format: "%+.2f", fc.weight))
              .font(.system(size: 12, weight: .medium, design: .monospaced))
              .foregroundColor(Color(white: 0.5))
              .frame(width: 50, alignment: .trailing)
          }
        }
      }
      .cdsCard(accent: .gray)
    }
  }
}
