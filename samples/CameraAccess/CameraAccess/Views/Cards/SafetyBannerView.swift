import SwiftUI

/// Full-width red safety banner. Hidden when no overrides are fired.
struct SafetyBannerView: View {
  let overrides: [SafetyOverride]
  @State private var expandedOverride: String?

  var body: some View {
    if !overrides.isEmpty {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(overrides) { override_ in
          VStack(alignment: .leading, spacing: 2) {
            Button {
              withAnimation {
                expandedOverride = expandedOverride == override_.id ? nil : override_.id
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .font(.system(size: 14, weight: .bold))
                Text(override_.name.replacingOccurrences(of: "_", with: " "))
                  .font(.system(size: 14, weight: .semibold))
                Spacer()
                if override_.description != nil {
                  Image(systemName: expandedOverride == override_.id ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                }
              }
            }
            .buttonStyle(.plain)

            if expandedOverride == override_.id {
              if let desc = override_.description, !desc.isEmpty {
                Text(desc)
                  .font(.system(size: 12, weight: .medium))
                  .opacity(0.85)
              }
              if let minVal = override_.enforced_min {
                Text("Minimum enforced: \(Int(minVal * 100))%")
                  .font(.system(size: 11, weight: .bold, design: .monospaced))
                  .opacity(0.75)
              }
            }
          }
        }
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(Color.red)
    }
  }
}
