import SwiftUI

/// Main view for the CDS glasses session.
/// Start/stop, connection status, red flag banner, transcript, completeness.
struct CDSSessionView: View {
  @StateObject private var geminiVM = GeminiSessionViewModel()
  @State private var showSettings = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        // Red flag banner
        if let redFlag = geminiVM.paBackendBridge.activeRedFlag {
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
        HStack(spacing: 8) {
          GeminiStatusBar(geminiVM: geminiVM)
          Spacer()
          if geminiVM.paBackendBridge.completenessScore > 0 {
            let score = Int(geminiVM.paBackendBridge.completenessScore)
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

        Spacer()

        // Transcript overlay
        VStack(spacing: 8) {
          if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
            TranscriptView(userText: geminiVM.userTranscript, aiText: geminiVM.aiTranscript)
              .padding(.horizontal, 16)
          }

          if geminiVM.toolCallStatus != .idle {
            ToolCallStatusView(status: geminiVM.toolCallStatus)
          }

          if geminiVM.isModelSpeaking {
            HStack(spacing: 8) {
              SpeakingIndicator()
              Text("Whispering...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            }
          }
        }

        Spacer()

        // Start/Stop button
        Button {
          if geminiVM.isGeminiActive {
            geminiVM.stopSession()
          } else {
            Task { await geminiVM.startSession() }
          }
        } label: {
          HStack(spacing: 10) {
            Image(systemName: geminiVM.isGeminiActive ? "stop.fill" : "mic.fill")
              .font(.system(size: 20))
            Text(geminiVM.isGeminiActive ? "End Session" : "Start Session")
              .font(.system(size: 18, weight: .semibold))
          }
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(geminiVM.isGeminiActive ? Color.red : Color.blue)
          .cornerRadius(16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)

        // Error message
        if let error = geminiVM.errorMessage {
          Text(error)
            .font(.system(size: 12))
            .foregroundColor(.red)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
      }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
  }
}
