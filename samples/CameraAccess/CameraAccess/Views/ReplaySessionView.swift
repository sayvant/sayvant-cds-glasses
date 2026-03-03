import SwiftUI

/// Replays a saved encounter by streaming the transcript progressively
/// and calling /comprehensive_analysis at intervals to populate cards.
struct ReplaySessionView: View {
  let encounter: SavedEncounter
  @Environment(\.dismiss) private var dismiss
  @StateObject private var bridge = PABackendBridge()

  @State private var replayProgress: Double = 0
  @State private var displayedTranscript = ""
  @State private var isReplaying = false
  @State private var replayTask: Task<Void, Never>?

  private var prediction: PredictResponse? { bridge.predictionResult }
  private var comprehensive: ComprehensiveResponse? { bridge.comprehensiveResult }

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Button { stopAndDismiss() } label: {
          Image(systemName: "xmark")
            .foregroundColor(.white)
            .font(.system(size: 18))
        }
        Spacer()
        Text("REPLAY")
          .font(.system(size: 12, weight: .bold))
          .tracking(2)
          .foregroundColor(.cyan)
        Spacer()
        // Share replayed results
        if comprehensive != nil {
          ShareLink(item: buildReplayShareText()) {
            Image(systemName: "square.and.arrow.up")
              .foregroundColor(.white)
              .font(.system(size: 16))
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color.cyan.opacity(0.08))

      // Progress bar
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(Color(white: 0.15))
          Rectangle()
            .fill(Color.cyan.opacity(0.6))
            .frame(width: geo.size.width * replayProgress)
        }
      }
      .frame(height: 3)

      // Card stack (same as main session)
      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 12) {
          if prediction == nil && isReplaying {
            HStack(spacing: 12) {
              ProgressView().tint(.white)
              Text("Replaying encounter...")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(white: 0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .cdsCard()
          }

          if let pred = prediction {
            RiskScoreCard(prediction: pred, uncertainty: comprehensive?.uncertainty)
          }

          if let diff = comprehensive?.differential {
            DifferentialCard(differential: diff)
          }

          if let workup = comprehensive?.recommended_workup, !workup.isEmpty {
            WorkupCard(recommendations: workup)
          }

          RedFlagCard(flags: bridge.redFlags)
          AskNextCard(questions: bridge.askNextQuestions)

          CompletenessCard(
            completeness: comprehensive?.guidance.completeness,
            score: bridge.completenessScore
          )

          if let trop = prediction?.troponin_prediction {
            TroponinCard(troponin: trop)
          }

          if let disp = prediction?.disposition_prediction {
            DispositionCard(disposition: disp)
          }

          if let pred = prediction {
            FeatureAttributionCard(contributions: pred.feature_contributions)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
      }

      // Transcript pane
      VStack(alignment: .leading, spacing: 4) {
        Text("TRANSCRIPT")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(Color(white: 0.4))
          .tracking(1)
        ScrollView {
          Text(displayedTranscript)
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 80)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(Color(white: 0.06))

      // Control buttons
      HStack(spacing: 16) {
        if isReplaying {
          Button {
            replayTask?.cancel()
            isReplaying = false
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "pause.fill")
              Text("Pause")
                .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.orange.opacity(0.8))
            .cornerRadius(14)
          }
        } else if replayProgress > 0 && replayProgress < 1 {
          Button { startReplay(fromProgress: replayProgress) } label: {
            HStack(spacing: 6) {
              Image(systemName: "play.fill")
              Text("Resume")
                .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue.opacity(0.8))
            .cornerRadius(14)
          }
        } else {
          Button { startReplay(fromProgress: 0) } label: {
            HStack(spacing: 6) {
              Image(systemName: "play.fill")
              Text(replayProgress >= 1 ? "Replay Again" : "Start Replay")
                .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.blue.opacity(0.8))
            .cornerRadius(14)
          }
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
    }
    .background(Color.black.ignoresSafeArea())
    .preferredColorScheme(.dark)
    .onAppear { startReplay(fromProgress: 0) }
    .onDisappear { replayTask?.cancel() }
  }

  private func startReplay(fromProgress: Double) {
    replayTask?.cancel()
    let transcript = encounter.transcript
    guard !transcript.isEmpty else { return }

    if fromProgress == 0 {
      bridge.resetSession()
      displayedTranscript = ""
    }

    isReplaying = true

    // Split transcript into sentences
    let sentences = transcript.components(separatedBy: ". ")
      .flatMap { $0.components(separatedBy: "\n") }
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

    let startIdx = Int(fromProgress * Double(sentences.count))

    replayTask = Task {
      for i in startIdx..<sentences.count {
        guard !Task.isCancelled else { break }

        let sentence = sentences[i]
        displayedTranscript += (displayedTranscript.isEmpty ? "" : " ") + sentence + "."
        replayProgress = Double(i + 1) / Double(sentences.count)

        // Call backend every 3 sentences or on last sentence
        if (i - startIdx) % 3 == 2 || i == sentences.count - 1 {
          bridge.fullTranscript = displayedTranscript
          await bridge.runAutoAnalysis()
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s per sentence
      }

      isReplaying = false
      replayProgress = 1.0
    }
  }

  private func stopAndDismiss() {
    replayTask?.cancel()
    dismiss()
  }

  private func buildReplayShareText() -> String {
    var text = "CDS Replay Analysis\n"
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    text += "Original: \(df.string(from: encounter.date))\n\n"

    if let pred = prediction {
      text += "ACS Risk: \(Int(pred.probabilityPct))% (\(pred.band))\n"
    }

    if let diffs = comprehensive?.differential.ranked_diagnoses.prefix(5) {
      text += "Top Dx: \(diffs.map { "\($0.diagnosis) (\(Int($0.probabilityPct))%)" }.joined(separator: ", "))\n"
    }

    if let disp = prediction?.disposition_prediction {
      text += "Disposition: \(disp.recommendation) (\(Int(disp.probabilityValue))%)\n"
    }

    return text
  }
}
