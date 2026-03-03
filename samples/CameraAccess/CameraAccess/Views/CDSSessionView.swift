import SwiftUI

/// Outer shell — owns the GeminiSessionViewModel via @StateObject.
/// Passes both the VM and the bridge to the inner content view so
/// SwiftUI can subscribe to @Published changes on both objects.
struct CDSSessionView: View {
  @StateObject private var geminiVM = GeminiSessionViewModel()
  @State private var showSettings = false
  @State private var showOnboarding = false

  var body: some View {
    CDSSessionContent(
      geminiVM: geminiVM,
      bridge: geminiVM.paBackendBridge,
      showSettings: $showSettings,
      showOnboarding: $showOnboarding
    )
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .sheet(isPresented: $showOnboarding) {
      OnboardingView()
    }
    .onAppear {
      // Run pre-flight check on launch
      Task { await geminiVM.paBackendBridge.runPreFlightCheck() }

      // Show onboarding if first launch and no keys configured
      if !SettingsManager.shared.hasCompletedOnboarding
          && !GeminiConfig.isConfigured
          && !GeminiConfig.isPABackendConfigured {
        showOnboarding = true
      }
    }
  }
}

/// Inner content view — observes both the VM and the bridge.
/// Without @ObservedObject on the bridge, SwiftUI never learns that
/// predictionResult / redFlags / askNextQuestions changed.
private struct CDSSessionContent: View {
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @ObservedObject var bridge: PABackendBridge
  @Binding var showSettings: Bool
  @Binding var showOnboarding: Bool

  @State private var showPastEncounters = false
  @State private var showEncounterSummary: SavedEncounter?
  @State private var manualText = ""
  @State private var isManualAnalyzing = false
  @State private var isDemoMode = false

  private var prediction: PredictResponse? { bridge.predictionResult }
  private var comprehensive: ComprehensiveResponse? { bridge.comprehensiveResult }
  private var isActive: Bool { geminiVM.isGeminiActive }
  private var preflight: PreFlightStatus { bridge.preFlightStatus }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      if isActive {
        activeSessionView
      } else if isManualAnalyzing || comprehensive != nil {
        manualResultsView
      } else {
        preSessionView
      }
    }
    .sheet(item: $showEncounterSummary) { encounter in
      EncounterSummaryView(encounter: encounter)
    }
  }

  // MARK: - Pre-Session Splash

  private var preSessionView: some View {
    VStack(spacing: 0) {
      statusBar
      Spacer()

      VStack(spacing: 16) {
        Image(systemName: "waveform.badge.mic")
          .font(.system(size: 48))
          .foregroundColor(Color(white: 0.3))
        Text("Ready to listen")
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(Color(white: 0.4))

        // Pre-flight status indicator
        preFlightIndicator

        // Resume previous session
        if bridge.hasResumableState {
          Button {
            bridge.resumeFromSavedState()
            Task { await geminiVM.startSession() }
          } label: {
            HStack(spacing: 8) {
              Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14))
              Text("Resume Previous Session")
                .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(10)
          }
        }
      }

      Spacer()

      // Demo mode button
      Button {
        isDemoMode = true
        bridge.loadDemoData(.classicACS)
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 16))
          Text("Try Demo")
            .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.cyan)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.cyan.opacity(0.12))
        .cornerRadius(12)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 8)

      // Manual text input
      manualTextInput

      sessionButton

      // Past Encounters
      Button {
        showPastEncounters = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "clock.arrow.circlepath")
            .font(.system(size: 14))
          Text("Past Encounters")
            .font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(Color(white: 0.5))
      }
      .padding(.bottom, 12)

      errorView
    }
    .sheet(isPresented: $showPastEncounters) {
      PastEncountersView()
    }
  }

  // MARK: - Pre-Flight Indicator

  private var preFlightIndicator: some View {
    Button {
      Task { await bridge.runPreFlightCheck() }
    } label: {
      HStack(spacing: 8) {
        Circle()
          .fill(preflightDotColor)
          .frame(width: 10, height: 10)
        Text(preflight.statusMessage)
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(Color(white: 0.5))
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 16)
      .background(Color(white: 0.08))
      .cornerRadius(20)
    }
    .padding(.top, 8)
  }

  private var preflightDotColor: Color {
    switch preflight.overallState {
    case .ready: return .green
    case .partial: return .yellow
    case .error: return .red
    case .notConfigured: return .gray
    }
  }

  // MARK: - Manual Text Input

  private var manualTextInput: some View {
    VStack(spacing: 8) {
      HStack {
        Rectangle()
          .fill(Color(white: 0.25))
          .frame(height: 1)
        Text("or")
          .font(.system(size: 12))
          .foregroundColor(Color(white: 0.35))
        Rectangle()
          .fill(Color(white: 0.25))
          .frame(height: 1)
      }
      .padding(.horizontal, 40)

      TextEditor(text: $manualText)
        .font(.system(size: 14))
        .foregroundColor(.white)
        .scrollContentBackground(.hidden)
        .background(Color(white: 0.1))
        .cornerRadius(12)
        .frame(height: 100)
        .overlay(
          Group {
            if manualText.isEmpty {
              Text("Paste HPI text here...")
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.3))
                .padding(8)
            }
          },
          alignment: .topLeading
        )
        .padding(.horizontal, 24)

      Button {
        guard !manualText.isEmpty else { return }
        isManualAnalyzing = true
        isDemoMode = false
        Task {
          await bridge.analyzeText(manualText)
          isManualAnalyzing = false
        }
      } label: {
        HStack(spacing: 8) {
          if isManualAnalyzing {
            ProgressView()
              .tint(.white)
          }
          Image(systemName: "magnifyingglass")
            .font(.system(size: 16))
          Text("Analyze")
            .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(analyzeButtonDisabled ? Color.gray.opacity(0.3) : Color.blue.opacity(0.8))
        .cornerRadius(12)
      }
      .disabled(analyzeButtonDisabled)
      .padding(.horizontal, 24)

      // Show analysis error if decode/network fails
      if let error = bridge.analysisError {
        Text(error)
          .font(.system(size: 12))
          .foregroundColor(.red)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }

      Spacer().frame(height: 12)
    }
  }

  private var analyzeButtonDisabled: Bool {
    manualText.isEmpty || isManualAnalyzing
  }

  // MARK: - Manual Results View

  private var manualResultsView: some View {
    VStack(spacing: 0) {
      // Demo mode banner
      if isDemoMode {
        HStack(spacing: 6) {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 12))
          Text("DEMO MODE")
            .font(.system(size: 11, weight: .bold))
            .tracking(1)
          Text("using sample data")
            .font(.system(size: 11))
        }
        .foregroundColor(.cyan)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.cyan.opacity(0.1))
      }

      statusBar
      cardStack
      Spacer(minLength: 0)

      // Share + New Analysis buttons
      HStack(spacing: 12) {
        ShareLink(item: buildShareText()) {
          HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 14))
            Text("Share")
              .font(.system(size: 14, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(Color(white: 0.2))
          .cornerRadius(14)
        }

        Button {
          bridge.resetSession()
          manualText = ""
          isManualAnalyzing = false
          isDemoMode = false
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "arrow.left")
              .font(.system(size: 16))
            Text("New Analysis")
              .font(.system(size: 16, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(Color.blue.opacity(0.8))
          .cornerRadius(14)
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
    }
  }

  // MARK: - Active Session

  private var activeSessionView: some View {
    VStack(spacing: 0) {
      // Safety banner (pinned above scroll)
      if let pred = prediction, pred.safety_applied {
        SafetyBannerView(overrides: pred.overrides_fired)
      } else if let redFlag = bridge.activeRedFlag {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 16, weight: .bold))
          Text(redFlag)
            .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.red)
      }

      // Status bar
      statusBar

      // Scrollable card stack
      cardStack

      Spacer(minLength: 0)

      // Transcript pane
      TranscriptPane(
        currentText: geminiVM.userTranscript,
        entries: geminiVM.transcriptEntries
      )
      .padding(.horizontal, 16)
      .padding(.bottom, 8)

      // What did I miss?
      Button {
        geminiVM.requestSummary()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "text.bubble")
            .font(.system(size: 16))
          Text("What did I miss?")
            .font(.system(size: 16, weight: .medium))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.blue.opacity(0.8))
        .cornerRadius(14)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 8)

      sessionButton
      errorView
    }
  }

  // MARK: - Card Stack (shared between active session and manual results)

  private var cardStack: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 12) {
        // Listening indicator (before any data arrives)
        if prediction == nil && bridge.redFlags.isEmpty
            && bridge.askNextQuestions.isEmpty && bridge.completenessScore == 0 {
          listeningIndicator
        }

        // Risk score hero card
        if let pred = prediction {
          RiskScoreCard(prediction: pred, uncertainty: comprehensive?.uncertainty)
        } else if bridge.isPredicting {
          predictingPlaceholder
        }

        // Differential diagnosis
        if let diff = comprehensive?.differential {
          DifferentialCard(differential: diff)
        }

        // Workup recommendations
        if let workup = comprehensive?.recommended_workup, !workup.isEmpty {
          WorkupCard(recommendations: workup)
        }

        // Red flags from guidance
        RedFlagCard(flags: bridge.redFlags)

        // Ask-next questions
        AskNextCard(questions: bridge.askNextQuestions)

        // Completeness with category breakdown
        CompletenessCard(
          completeness: comprehensive?.guidance.completeness,
          score: bridge.completenessScore
        )

        // Troponin prediction
        if let trop = prediction?.troponin_prediction {
          TroponinCard(troponin: trop)
        }

        // Disposition prediction
        if let disp = prediction?.disposition_prediction {
          DispositionCard(disposition: disp)
        }

        // Risk trend timeline
        TimelineCard(entries: bridge.timelineEntries)

        // Feature attribution
        if let pred = prediction {
          FeatureAttributionCard(contributions: pred.feature_contributions)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
  }

  // MARK: - Shared Components

  private var statusBar: some View {
    HStack(spacing: 8) {
      if isActive {
        GeminiStatusBar(geminiVM: geminiVM)
      }
      Spacer()
      if bridge.completenessScore > 0 {
        let score = Int(bridge.completenessScore)
        Text("\(score)%")
          .font(.system(size: 13, weight: .bold, design: .monospaced))
          .foregroundColor(score > 80 ? .green : score > 50 ? .orange : .red)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(Color.black.opacity(0.6))
          .cornerRadius(12)
      }
      Button {
        showSettings = true
      } label: {
        Image(systemName: "gearshape")
          .foregroundColor(.white.opacity(0.7))
          .font(.system(size: 18))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.black.opacity(0.5))
  }

  private var sessionButton: some View {
    Button {
      if isActive {
        endSession()
      } else {
        Task { await geminiVM.startSession() }
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isActive ? "stop.fill" : "mic.fill")
          .font(.system(size: 20))
        Text(isActive ? "End Session" : "Start Session")
          .font(.system(size: 18, weight: .semibold))
      }
      .foregroundColor(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .background(isActive ? Color.red : Color.blue)
      .cornerRadius(16)
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
  }

  private func endSession() {
    // Capture all data BEFORE stopping (stopSession clears VM state)
    let transcript = bridge.fullTranscript
    let hasAnyData = !transcript.isEmpty
      || prediction != nil
      || !bridge.redFlags.isEmpty
      || bridge.completenessScore > 0
      || !geminiVM.transcriptEntries.isEmpty

    if hasAnyData {
      // Build transcript from entries if fullTranscript is empty
      let finalTranscript: String
      if transcript.isEmpty && !geminiVM.transcriptEntries.isEmpty {
        finalTranscript = geminiVM.transcriptEntries
          .map { ($0.speaker == .patient ? "Patient: " : "CDS: ") + $0.text }
          .joined(separator: "\n")
      } else {
        finalTranscript = transcript
      }

      var encounter = SavedEncounter(
        id: UUID().uuidString,
        date: Date(),
        transcript: finalTranscript,
        acsRiskPct: prediction?.probabilityPct,
        riskBand: prediction?.band,
        topDiagnosis: comprehensive?.differential.ranked_diagnoses.first?.diagnosis,
        disposition: prediction?.disposition_prediction?.recommendation,
        completenessScore: bridge.completenessScore,
        differentialSummary: comprehensive?.differential.ranked_diagnoses.prefix(5).map {
          DiagnosisSummaryItem(diagnosis: $0.diagnosis, probabilityPct: $0.probabilityPct)
        },
        workupItems: comprehensive?.recommended_workup,
        redFlagCount: bridge.redFlags.count,
        questionsAsked: bridge.previouslyAsked.count
      )
      EncounterStore.shared.save(encounter)
      showEncounterSummary = encounter

      // Fetch rich /full_summary in the background (updates encounter async)
      let capturedBridge = bridge
      Task {
        if let summaryResponse = await capturedBridge.fetchFullSummary(text: finalTranscript),
           let summaryData = summaryResponse.summary {
          encounter.fullSummary = summaryData
          EncounterStore.shared.update(encounter)
          NSLog("[EndSession] Rich summary saved for encounter %@", encounter.id)
        }
      }
    }

    geminiVM.stopSession()
  }

  // MARK: - Share Text Builder

  private func buildShareText() -> String {
    var text = "CDS Analysis\n"
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    text += "\(df.string(from: Date()))\n\n"

    if let pred = prediction {
      text += "ACS Risk: \(Int(pred.probabilityPct))% (\(pred.band))"
      text += " | 95% CI: \(pred.confidence_interval.displayText)"
      text += "\n"
    }

    if let diffs = comprehensive?.differential.ranked_diagnoses.prefix(5) {
      text += "\nTop Dx: "
      text += diffs.map { "\($0.diagnosis) (\(Int($0.probabilityPct))%)" }.joined(separator: ", ")
      text += "\n"
    }

    if let workup = comprehensive?.recommended_workup, !workup.isEmpty {
      text += "\nWorkup: \(workup.joined(separator: ", "))\n"
    }

    if let disp = prediction?.disposition_prediction {
      text += "\nDisposition: \(disp.recommendation) (\(Int(disp.probabilityValue))%)\n"
    }

    let score = bridge.completenessScore
    if score > 0 {
      text += "\nCompleteness: \(Int(score))%"
      if let missing = comprehensive?.guidance.completeness.missing_elements, !missing.isEmpty {
        text += " -- missing \(missing.prefix(3).joined(separator: ", "))"
      }
      text += "\n"
    }

    if !bridge.redFlags.isEmpty {
      text += "\nRed Flags: \(bridge.redFlags.count) (\(bridge.redFlags.map(\.message).joined(separator: "; ")))\n"
    }

    return text
  }

  @ViewBuilder
  private var errorView: some View {
    if let error = geminiVM.errorMessage {
      Text(error)
        .font(.system(size: 12))
        .foregroundColor(.red)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }
  }

  private var listeningIndicator: some View {
    VStack(spacing: 8) {
      ProgressView()
        .tint(Color(white: 0.4))
      Text("Listening...")
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(Color(white: 0.35))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 32)
  }

  private var predictingPlaceholder: some View {
    HStack(spacing: 12) {
      ProgressView()
        .tint(.white)
      Text("Analyzing...")
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(Color(white: 0.5))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .cdsCard()
  }
}
