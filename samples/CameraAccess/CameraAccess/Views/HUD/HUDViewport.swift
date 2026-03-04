import SwiftUI

struct HUDViewport: View {
    @ObservedObject var bridge: PABackendBridge
    @ObservedObject var geminiVM: GeminiSessionViewModel

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
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
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

    @ViewBuilder
    private func hudContent(scale: CGFloat) -> some View {
        VStack(spacing: 12 * scale) {
            // Safety / Red Flag banner
            HUDSafetyOverlay(
                safetyApplied: prediction?.safety_applied ?? false,
                overridesFired: prediction?.overrides_fired ?? [],
                activeRedFlag: bridge.activeRedFlag,
                redFlags: bridge.redFlags,
                scale: scale
            )

            Spacer().frame(height: 8 * scale)

            // Risk score
            riskSection(scale: scale)

            Spacer().frame(height: 4 * scale)

            // Ask-next question
            HUDAskNextRotator(
                questions: bridge.askNextQuestions,
                scale: scale
            )

            Spacer().frame(height: 8 * scale)

            // Disposition
            dispositionLabel(scale: scale)

            Spacer()

            // Bottom row: completeness arc + status dots
            HStack {
                HUDCompletenessArc(
                    score: bridge.completenessScore,
                    scale: scale
                )

                Spacer()

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
        .padding(.top, 0)
    }

    // MARK: - Risk Score

    @ViewBuilder
    private func riskSection(scale: CGFloat) -> some View {
        if let pred = prediction {
            let pct = Int(pred.prob * 100)
            let band = pred.band.uppercased()

            VStack(spacing: 8 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    Text("\(pct)%")
                        .font(.system(size: 72 * scale, weight: .bold, design: .monospaced))
                        .foregroundColor(bandColor(pred.band))
                        .animation(.spring(response: 0.4), value: pct)

                    Text(band)
                        .font(.system(size: 16 * scale, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8 * scale)
                        .padding(.vertical, 4 * scale)
                        .background(bandColor(pred.band).opacity(0.3))
                        .cornerRadius(4 * scale)
                }

                // Progress bar
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3 * scale)
                            .fill(Color.white.opacity(0.1))
                        RoundedRectangle(cornerRadius: 3 * scale)
                            .fill(bandColor(pred.band))
                            .frame(width: barGeo.size.width * pred.prob)
                            .animation(.spring(response: 0.4), value: pred.prob)
                    }
                }
                .frame(height: 6 * scale)
                .padding(.horizontal, 60 * scale)
            }
        } else {
            Text("--")
                .font(.system(size: 48 * scale, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - Disposition

    @ViewBuilder
    private func dispositionLabel(scale: CGFloat) -> some View {
        if let disp = prediction?.disposition_prediction {
            Text(disp.recommendation.uppercased())
                .font(.system(size: 24 * scale, weight: .bold, design: .monospaced))
                .foregroundColor(dispositionColor(disp.recommendation))
                .animation(.spring(response: 0.4), value: disp.recommendation)
        }
    }

    // MARK: - Helpers

    private var prediction: PredictResponse? {
        bridge.predictionResult
    }
}
