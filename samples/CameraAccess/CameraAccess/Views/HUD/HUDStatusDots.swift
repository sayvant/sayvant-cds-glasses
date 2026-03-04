import SwiftUI

struct HUDStatusDots: View {
    let geminiState: GeminiConnectionState
    let paState: PABackendConnectionState
    let audioRoute: AudioRouteStatus
    let scale: CGFloat

    private var dotSize: CGFloat { 6 * scale }
    private var spacing: CGFloat { 8 * scale }

    var body: some View {
        HStack(spacing: spacing) {
            Circle()
                .fill(geminiDotColor)
                .frame(width: dotSize, height: dotSize)
            Circle()
                .fill(paDotColor)
                .frame(width: dotSize, height: dotSize)
            Circle()
                .fill(audioDotColor)
                .frame(width: dotSize, height: dotSize)
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
