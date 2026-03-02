import SwiftUI

// MARK: - Card Background Modifier

struct CDSCardModifier: ViewModifier {
  var accentColor: Color = .clear

  func body(content: Content) -> some View {
    HStack(spacing: 0) {
      if accentColor != .clear {
        RoundedRectangle(cornerRadius: 2)
          .fill(accentColor)
          .frame(width: 4)
      }
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
    .background(Color(white: 0.12))
    .cornerRadius(16)
  }
}

extension View {
  func cdsCard(accent: Color = .clear) -> some View {
    modifier(CDSCardModifier(accentColor: accent))
  }
}

// MARK: - Section Header

struct SectionHeader: View {
  let title: String
  var trailing: String? = nil

  var body: some View {
    HStack {
      Text(title)
        .font(.system(size: 12, weight: .bold))
        .foregroundColor(Color(white: 0.5))
        .tracking(1)
      Spacer()
      if let trailing {
        Text(trailing)
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(Color(white: 0.5))
      }
    }
  }
}

// MARK: - Color Helpers

func bandColor(_ band: String) -> Color {
  switch band.uppercased() {
  case "HIGH": return .red
  case "MED": return .orange
  case "LOW": return .green
  default: return .gray
  }
}

func troponinColor(_ pct: Double) -> Color {
  if pct >= 50 { return .red }
  if pct >= 20 { return .orange }
  return .green
}

func dispositionColor(_ recommendation: String) -> Color {
  switch recommendation.lowercased() {
  case "admit": return .red
  case "observation": return .orange
  case "discharge", "discharge with follow-up": return .green
  default: return .gray
  }
}

func urgencyColor(_ urgency: String) -> Color {
  switch urgency.lowercased() {
  case "critical", "high": return .red
  default: return .orange
  }
}

// MARK: - Progress Bar

struct CDSProgressBar: View {
  let value: Double  // 0-1
  let color: Color

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color(white: 0.2))
        RoundedRectangle(cornerRadius: 4)
          .fill(color)
          .frame(width: geo.size.width * min(max(value, 0), 1))
      }
    }
    .frame(height: 8)
  }
}
