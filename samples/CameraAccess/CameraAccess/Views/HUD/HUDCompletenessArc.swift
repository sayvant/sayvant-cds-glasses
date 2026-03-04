import SwiftUI

struct HUDCompletenessArc: View {
    let score: Double // 0-100
    let scale: CGFloat

    private var normalized: Double { min(max(score / 100.0, 0), 1) }

    private var fillColor: Color {
        if score > 80 { return .green }
        if score > 50 { return .orange }
        return .red
    }

    private var arcSize: CGFloat { 44 * scale }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Fill
            Circle()
                .trim(from: 0, to: 0.75 * normalized)
                .stroke(fillColor, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.easeInOut(duration: 0.6), value: normalized)

            // Center text
            Text("\(Int(score))")
                .font(.system(size: 14 * scale, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(width: arcSize, height: arcSize)
    }
}
