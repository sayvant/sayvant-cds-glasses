import SwiftUI

struct HUDViewport: View {
    @ObservedObject var bridge: PABackendBridge
    @ObservedObject var geminiVM: GeminiSessionViewModel
    var onEndSession: (() -> Void)?

    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - 32
            let scale = side / 600.0

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    hudContent(scale: scale)
                }
                .frame(width: side, height: side)
                .overlay(
                    RoundedRectangle(cornerRadius: 8 * scale)
                        .stroke(hudBorderColor.opacity(0.25), lineWidth: 1)
                )
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(hasAppeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Border color reflects risk state

    private var hudBorderColor: Color {
        guard let pred = prediction else { return .green }
        return bandColor(pred.band)
    }

    // MARK: - Main HUD Layout

    @ViewBuilder
    private func hudContent(scale: CGFloat) -> some View {
        VStack(spacing: 0) {

            // ── TOP: Safety / Red Flag alert ──
            HUDSafetyOverlay(
                safetyApplied: prediction?.safety_applied ?? false,
                overridesFired: prediction?.overrides_fired ?? [],
                activeRedFlag: bridge.activeRedFlag,
                redFlags: bridge.redFlags,
                scale: scale
            )

            // ── AMBIENT STRIP: Risk + Disposition ──
            riskStrip(scale: scale)
                .padding(.top, 8 * scale)

            // ── HERO: Ask-next questions ──
            Spacer()

            askNextHero(scale: scale)

            Spacer()

            // ── COMPLETENESS + END SESSION ──
            bottomSection(scale: scale)
        }
        .padding(.top, 0)
    }

    // MARK: - Risk Strip (compact horizontal bar)

    /// True when the model has detected at least one clinical feature
    /// (not just returning the base-rate intercept with zero features).
    private var hasMeaningfulPrediction: Bool {
        guard let pred = prediction else { return false }
        // Must have at least one detected feature AND probability above base rate (7.4%)
        return !pred.feature_contributions.isEmpty && pred.prob > 0.10
    }

    @ViewBuilder
    private func riskStrip(scale: CGFloat) -> some View {
        if let pred = prediction, hasMeaningfulPrediction {
            let pct = Int(pred.prob * 100)
            let color = bandColor(pred.band)

            HStack(spacing: 0) {
                // Risk percentage + band
                HStack(spacing: 6 * scale) {
                    Text("\(pct)%")
                        .font(.system(size: 28 * scale, weight: .bold, design: .monospaced))
                        .foregroundColor(color)
                        .animation(.spring(response: 0.4), value: pct)

                    Text(pred.band.uppercased())
                        .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 6 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(color.opacity(0.25))
                        .cornerRadius(3 * scale)
                }

                Spacer()

                // Disposition recommendation
                if let disp = pred.disposition_prediction {
                    let dispColor = dispositionColor(disp.recommendation)
                    HStack(spacing: 4 * scale) {
                        Circle()
                            .fill(dispColor)
                            .frame(width: 6 * scale, height: 6 * scale)
                        Text(disp.recommendation.uppercased())
                            .font(.system(size: 13 * scale, weight: .bold, design: .monospaced))
                            .foregroundColor(dispColor)
                    }
                }
            }
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 10 * scale)
            .background(Color.white.opacity(0.04))

            // Thin risk bar
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                    Rectangle()
                        .fill(color)
                        .frame(width: barGeo.size.width * pred.prob)
                        .animation(.spring(response: 0.4), value: pred.prob)
                }
            }
            .frame(height: 3 * scale)
            .padding(.horizontal, 24 * scale)
        } else {
            // Pre-prediction state
            HStack {
                Text("ANALYZING")
                    .font(.system(size: 12 * scale, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(2)
                Spacer()
            }
            .padding(.horizontal, 24 * scale)
            .padding(.vertical, 10 * scale)
        }
    }

    // MARK: - Ask-Next Hero (center stage)

    @ViewBuilder
    private func askNextHero(scale: CGFloat) -> some View {
        if !bridge.askNextQuestions.isEmpty {
            VStack(spacing: 16 * scale) {
                // Section label
                HStack(spacing: 6 * scale) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 12 * scale))
                        .foregroundColor(.cyan.opacity(0.6))
                    Text("ASK NEXT")
                        .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan.opacity(0.6))
                        .tracking(2)
                }

                // Rotating question
                HUDAskNextHero(
                    questions: bridge.askNextQuestions,
                    scale: scale
                )
            }
            .padding(.horizontal, 24 * scale)
        } else if !hasMeaningfulPrediction {
            // No features detected yet — still listening
            VStack(spacing: 12 * scale) {
                Image(systemName: "waveform")
                    .font(.system(size: 32 * scale))
                    .foregroundColor(.white.opacity(0.15))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("Listening...")
                    .font(.system(size: 14 * scale, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        } else if bridge.completenessScore > 80 {
            // Genuinely complete history
            VStack(spacing: 10 * scale) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 36 * scale))
                    .foregroundColor(.green.opacity(0.6))
                Text("History complete")
                    .font(.system(size: 14 * scale, weight: .medium, design: .monospaced))
                    .foregroundColor(.green.opacity(0.5))
            }
        } else {
            // Prediction exists, low completeness, but no questions returned
            // (shouldn't normally happen — fallback)
            VStack(spacing: 12 * scale) {
                Image(systemName: "waveform")
                    .font(.system(size: 32 * scale))
                    .foregroundColor(.white.opacity(0.15))
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("Analyzing...")
                    .font(.system(size: 14 * scale, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    // MARK: - Live Transcript Indicator

    @ViewBuilder
    private func liveTranscriptIndicator(scale: CGFloat) -> some View {
        let liveText = geminiVM.userTranscript
        let lastWords: String = {
            let words = liveText.split(separator: " ")
            let tail = words.suffix(6).joined(separator: " ")
            return tail.isEmpty ? "" : tail
        }()

        HStack(spacing: 8 * scale) {
            // Waveform icon — animates when speech is active
            Image(systemName: liveText.isEmpty ? "waveform" : "waveform")
                .font(.system(size: 14 * scale))
                .foregroundColor(liveText.isEmpty ? .white.opacity(0.1) : .cyan.opacity(0.6))
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !liveText.isEmpty)

            if !lastWords.isEmpty {
                Text(lastWords)
                    .font(.system(size: 11 * scale, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.head)
            } else {
                Text("waiting for speech...")
                    .font(.system(size: 10 * scale, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.12))
            }
            Spacer()
        }
        .padding(.horizontal, 24 * scale)
        .frame(height: 20 * scale)
    }

    // MARK: - Bottom Section (completeness + end session + status)

    @ViewBuilder
    private func bottomSection(scale: CGFloat) -> some View {
        VStack(spacing: 8 * scale) {

            // Live transcript indicator (waveform + last words)
            liveTranscriptIndicator(scale: scale)

            // Completeness bar
            if bridge.completenessScore > 0 {
                completenessBar(scale: scale)
            }

            // Bottom row: end session + status dots
            HStack(alignment: .bottom) {
                // End encounter button
                if let endAction = onEndSession {
                    Button {
                        endAction()
                    } label: {
                        HStack(spacing: 6 * scale) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10 * scale))
                            Text("END")
                                .font(.system(size: 11 * scale, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 14 * scale)
                        .padding(.vertical, 8 * scale)
                        .background(Color.red.opacity(0.3))
                        .cornerRadius(6 * scale)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6 * scale)
                                .stroke(Color.red.opacity(0.4), lineWidth: 1)
                        )
                    }
                }

                Spacer()

                // Status dots
                HUDStatusDots(
                    geminiState: geminiVM.connectionState,
                    paState: bridge.connectionState,
                    audioRoute: geminiVM.audioRoute,
                    scale: scale
                )
            }
            .padding(.horizontal, 24 * scale)
            .padding(.bottom, 16 * scale)
        }
    }

    // MARK: - Completeness Bar

    @ViewBuilder
    private func completenessBar(scale: CGFloat) -> some View {
        let score = bridge.completenessScore
        let normalized = min(max(score / 100.0, 0), 1)
        let color: Color = score > 80 ? .green : score > 50 ? .orange : .red

        VStack(spacing: 4 * scale) {
            HStack {
                Text("COMPLETENESS")
                    .font(.system(size: 9 * scale, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)
                Spacer()
                Text("\(Int(score))%")
                    .font(.system(size: 12 * scale, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
            }

            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(color)
                        .frame(width: barGeo.size.width * normalized)
                        .animation(.easeInOut(duration: 0.6), value: normalized)
                }
            }
            .frame(height: 4 * scale)
        }
        .padding(.horizontal, 24 * scale)
    }

    // MARK: - Helpers

    private var prediction: PredictResponse? {
        bridge.predictionResult
    }
}

// MARK: - Ask-Next Hero (large, readable, auto-rotating)

struct HUDAskNextHero: View {
    let questions: [FullAskNext]
    let scale: CGFloat

    @State private var currentIndex = 0
    @State private var isVisible = true
    @State private var timer: AnyCancellable?

    var body: some View {
        if let question = questions[safe: currentIndex] {
            VStack(spacing: 12 * scale) {
                // Priority indicator
                priorityDots(for: question, scale: scale)

                // Question label (what to ask about)
                Text(question.label)
                    .font(.system(size: 22 * scale, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: isVisible)
                    .frame(maxWidth: .infinity)

                // Example phrasing (how to ask it)
                Text("\"\(question.example_phrasing)\"")
                    .font(.system(size: 15 * scale, weight: .regular, design: .monospaced))
                    .italic()
                    .foregroundColor(.cyan.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(isVisible ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4).delay(0.05), value: isVisible)
                    .frame(maxWidth: .infinity)

                // Page indicators
                if questions.count > 1 {
                    HStack(spacing: 8 * scale) {
                        ForEach(0..<min(questions.count, 6), id: \.self) { idx in
                            RoundedRectangle(cornerRadius: 2 * scale)
                                .fill(Color.white.opacity(idx == currentIndex ? 0.8 : 0.15))
                                .frame(width: idx == currentIndex ? 16 * scale : 6 * scale, height: 3 * scale)
                                .animation(.easeInOut(duration: 0.3), value: currentIndex)
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

    @ViewBuilder
    private func priorityDots(for question: FullAskNext, scale: CGFloat) -> some View {
        let color: Color = question.priority == 1 ? .red : question.priority == 2 ? .orange : .green
        HStack(spacing: 4 * scale) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < (4 - question.priority) ? color : Color.white.opacity(0.1))
                    .frame(width: 5 * scale, height: 5 * scale)
            }
        }
    }

    private func startTimer() {
        timer?.cancel()
        guard questions.count > 1 else { return }

        timer = Timer.publish(every: 6, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                withAnimation { isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    currentIndex = (currentIndex + 1) % questions.count
                    withAnimation { isVisible = true }
                }
            }
    }
}

import Combine

// Safe array subscript
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
