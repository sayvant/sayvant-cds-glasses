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
      Text("95% CI: \(troponin.confidence_interval.displayText)")
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .foregroundColor(Color(white: 0.4))
    }
    .cdsCard(accent: color)
  }
}

// MARK: - Disposition Card (with threshold visualization)

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

      // Threshold visualization
      dispositionThresholdBar

      // Threshold labels
      HStack(spacing: 0) {
        Text("Discharge")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.green.opacity(0.7))
        Spacer()
        Text("Observe")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.orange.opacity(0.7))
        Spacer()
        Text("Admit")
          .font(.system(size: 9, weight: .medium))
          .foregroundColor(.red.opacity(0.7))
      }
    }
    .cdsCard(accent: color)
  }

  /// Bar showing current probability plotted against admit/observe thresholds.
  private var dispositionThresholdBar: some View {
    GeometryReader { geo in
      let width = geo.size.width
      let admitX = width * CGFloat(disposition.thresholds.admit)
      let observeX = width * CGFloat(disposition.thresholds.observe)
      let currentX = width * CGFloat(min(max(disposition.probability, 0), 1))

      ZStack(alignment: .leading) {
        // Background zones
        HStack(spacing: 0) {
          Rectangle()
            .fill(Color.green.opacity(0.15))
            .frame(width: observeX)
          Rectangle()
            .fill(Color.orange.opacity(0.15))
            .frame(width: admitX - observeX)
          Rectangle()
            .fill(Color.red.opacity(0.15))
        }

        // Threshold lines
        Rectangle()
          .fill(Color.orange.opacity(0.6))
          .frame(width: 1.5)
          .offset(x: observeX)
        Rectangle()
          .fill(Color.red.opacity(0.6))
          .frame(width: 1.5)
          .offset(x: admitX)

        // Current probability marker
        Circle()
          .fill(color)
          .frame(width: 10, height: 10)
          .shadow(color: color.opacity(0.6), radius: 4)
          .offset(x: currentX - 5)
      }
    }
    .frame(height: 12)
    .cornerRadius(6)
    .clipped()
  }
}

// MARK: - Feature Attribution Card (improved with summary line)

struct FeatureAttributionCard: View {
  let contributions: [FeatureContribution]

  private var topFeatures: [FeatureContribution] {
    Array(contributions.sorted { abs($0.weight) > abs($1.weight) }.prefix(5))
  }

  private var top3: [FeatureContribution] {
    Array(topFeatures.prefix(3))
  }

  private var maxWeight: Double {
    topFeatures.map { abs($0.weight) }.max() ?? 1
  }

  var body: some View {
    if !contributions.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "TOP CONTRIBUTORS")

        // One-line summary of top 3 drivers
        if !top3.isEmpty {
          Text("Driven by: \(top3.map { formatFeatureName($0.feature) }.joined(separator: ", "))")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(white: 0.7))
            .padding(.bottom, 2)
        }

        ForEach(Array(topFeatures.enumerated()), id: \.element.id) { index, fc in
          let isTop3 = index < 3

          HStack(spacing: 8) {
            Text(fc.direction == "positive" ? "+" : "-")
              .font(.system(size: isTop3 ? 16 : 14, weight: .bold, design: .monospaced))
              .foregroundColor(fc.direction == "positive" ? .red : .green)
              .frame(width: 16)
            Text(formatFeatureName(fc.feature))
              .font(.system(size: isTop3 ? 15 : 14, weight: isTop3 ? .semibold : .medium))
              .foregroundColor(isTop3 ? .white : Color(white: 0.5))
              .lineLimit(1)
            Spacer()
            // Weight bar
            GeometryReader { geo in
              let barWidth = geo.size.width * (abs(fc.weight) / maxWeight)
              HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                  .fill((fc.direction == "positive" ? Color.red : Color.green).opacity(isTop3 ? 0.6 : 0.25))
                  .frame(width: barWidth, height: 14)
              }
            }
            .frame(width: 60, height: 14)
            Text(String(format: "%+.2f", fc.weight))
              .font(.system(size: 12, weight: .medium, design: .monospaced))
              .foregroundColor(isTop3 ? Color(white: 0.6) : Color(white: 0.35))
              .frame(width: 50, alignment: .trailing)
          }
        }
      }
      .cdsCard(accent: .gray)
    }
  }

  private func formatFeatureName(_ name: String) -> String {
    name.replacingOccurrences(of: "has_", with: "")
        .replacingOccurrences(of: "_", with: " ")
  }
}
