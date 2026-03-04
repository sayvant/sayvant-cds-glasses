import SwiftUI
import Combine

struct HUDAskNextRotator: View {
    let questions: [FullAskNext]
    let scale: CGFloat

    @State private var currentIndex = 0
    @State private var isVisible = true
    @State private var timer: AnyCancellable?

    var body: some View {
        if !questions.isEmpty {
            VStack(spacing: 6 * scale) {
                Text(questions[safe: currentIndex]?.example_phrasing ?? "")
                    .font(.system(size: 16 * scale, design: .monospaced))
                    .italic()
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.5), value: isVisible)
                    .frame(maxWidth: .infinity)

                // Dot indicators
                if questions.count > 1 {
                    HStack(spacing: 6 * scale) {
                        ForEach(0..<min(questions.count, 5), id: \.self) { idx in
                            Circle()
                                .fill(Color.white.opacity(idx == currentIndex ? 0.9 : 0.3))
                                .frame(width: 5 * scale, height: 5 * scale)
                        }
                    }
                }
            }
            .onAppear { startTimer() }
            .onDisappear { timer?.cancel() }
            .onChange(of: questions.count) { _ in
                currentIndex = 0
                startTimer()
            }
        }
    }

    private func startTimer() {
        timer?.cancel()
        guard questions.count > 1 else { return }

        timer = Timer.publish(every: 8, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                // Fade out
                withAnimation { isVisible = false }
                // After fade-out, advance and fade in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    currentIndex = (currentIndex + 1) % questions.count
                    withAnimation { isVisible = true }
                }
            }
    }
}

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
