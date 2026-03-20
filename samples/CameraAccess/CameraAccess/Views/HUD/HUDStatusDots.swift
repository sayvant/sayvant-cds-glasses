import SwiftUI

struct HUDStatusDots: View {
    let geminiState: GeminiConnectionState
    let paState: PABackendConnectionState
    let audioRoute: AudioRouteStatus
    let scale: CGFloat

    private var dotSize: CGFloat { 6 * scale }
    private var spacing: CGFloat { 8 * scale }

    private var labelFont: Font { .system(size: 7 * scale, weight: .medium, design: .monospaced) }
    private var labelColor: Color { .white.opacity(0.4) }

    var body: some View {
        HStack(spacing: spacing) {
            VStack(spacing: 2 * scale) {
                Circle()
                    .fill(geminiDotColor)
                    .frame(width: dotSize, height: dotSize)
                Text("AI")
                    .font(labelFont)
                    .foregroundColor(labelColor)
            }
            VStack(spacing: 2 * scale) {
                Circle()
                    .fill(paDotColor)
                    .frame(width: dotSize, height: dotSize)
                Text("CDS")
                    .font(labelFont)
                    .foregroundColor(labelColor)
            }
            VStack(spacing: 2 * scale) {
                Circle()
                    .fill(audioDotColor)
                    .frame(width: dotSize, height: dotSize)
                Text("Mic")
                    .font(labelFont)
                    .foregroundColor(labelColor)
            }
        }
    }

    private var geminiDotColor: Color {
        switch geminiState {
        case .ready: return .green
        case .connecting, .settingUp: return .yellow
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var paDotColor: Color {
        switch paState {
        case .connected: return .green
        case .checking: return .yellow
        case .unreachable: return .red
        case .notConfigured: return .gray
        }
    }

    private var audioDotColor: Color {
        switch audioRoute {
        case .bluetoothGlasses: return .green
        case .phoneMic: return .yellow
        case .unknown: return .gray
        }
    }
}
