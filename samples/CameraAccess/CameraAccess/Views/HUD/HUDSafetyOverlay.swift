import SwiftUI

struct HUDSafetyOverlay: View {
    let safetyApplied: Bool
    let overridesFired: [SafetyOverride]
    let activeRedFlag: String?
    let redFlags: [FullRedFlag]
    let scale: CGFloat

    @State private var redFlagPulse = false
    @State private var redFlagVisible = true
    @State private var flashWhite = false

    private var hasSafety: Bool { safetyApplied && !overridesFired.isEmpty }
    private var hasRedFlag: Bool { activeRedFlag != nil || !redFlags.isEmpty }
    private var isVisible: Bool { hasSafety || (hasRedFlag && redFlagVisible) }

    var body: some View {
        if isVisible {
            HStack(spacing: 6 * scale) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14 * scale))

                Text(bannerText)
                    .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if redFlags.count > 1 && !hasSafety {
                    Text("+\(redFlags.count - 1)")
                        .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4 * scale)
                        .padding(.vertical, 2 * scale)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4 * scale)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8 * scale)
            .padding(.horizontal, 12 * scale)
            .background(
                Color.red
                    .opacity(hasSafety ? 0.9 : (redFlagPulse ? 1.0 : 0.8))
            )
            .overlay(
                Color.white
                    .opacity(flashWhite ? 0.4 : 0)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                if hasRedFlag && !hasSafety {
                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                        redFlagPulse = true
                    }
                    // Auto-fade after 10s
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        withAnimation(.easeOut(duration: 0.5)) {
                            redFlagVisible = false
                        }
                    }
                }
            }
            .onChange(of: activeRedFlag) { _ in
                // Flash on new red flag
                flashWhite = true
                redFlagVisible = true
                withAnimation(.easeOut(duration: 0.3)) {
                    flashWhite = false
                }
                // Reset auto-fade
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        redFlagVisible = false
                    }
                }
            }
        }
    }

    private var bannerText: String {
        if hasSafety {
            let name = overridesFired.first?.name ?? "SAFETY OVERRIDE"
            return "\(name) -- SAFETY"
        }
        if let active = activeRedFlag {
            return active
        }
        if let first = redFlags.first {
            return first.message
        }
        return ""
    }
}
