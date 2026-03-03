import SwiftUI

/// First-launch onboarding wizard. 3 steps: Gemini key, CDS key, verify backend.
struct OnboardingView: View {
  @Environment(\.dismiss) private var dismiss
  private let settings = SettingsManager.shared

  @State private var step = 0
  @State private var geminiKey = ""
  @State private var cdsKey = ""
  @State private var backendURL = ""
  @State private var isVerifying = false
  @State private var verifyResult: String?
  @State private var verifySuccess = false

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Progress dots
        HStack(spacing: 8) {
          ForEach(0..<3, id: \.self) { i in
            Circle()
              .fill(i <= step ? Color.blue : Color(white: 0.3))
              .frame(width: 8, height: 8)
          }
        }
        .padding(.top, 16)

        Spacer()

        switch step {
        case 0: geminiStep
        case 1: cdsStep
        default: verifyStep
        }

        Spacer()

        // Navigation buttons
        HStack(spacing: 16) {
          if step > 0 {
            Button("Back") {
              withAnimation { step -= 1 }
            }
            .foregroundColor(Color(white: 0.5))
          }

          Spacer()

          if step < 2 {
            Button(action: { withAnimation { step += 1 } }) {
              Text("Next")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(12)
            }
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)

        // Skip option
        Button {
          settings.hasCompletedOnboarding = true
          dismiss()
        } label: {
          Text("Skip for now \u{2014} use Demo Mode")
            .font(.system(size: 14))
            .foregroundColor(Color.cyan.opacity(0.8))
        }
        .padding(.bottom, 24)
      }
      .background(Color.black)
      .navigationTitle("Setup")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Cancel") { dismiss() }
        }
      }
      .preferredColorScheme(.dark)
      .onAppear {
        geminiKey = settings.geminiAPIKey
        cdsKey = settings.cdsAPIKey
        backendURL = settings.paBackendURL
      }
    }
  }

  // MARK: - Step 1: Gemini API Key

  private var geminiStep: some View {
    VStack(spacing: 16) {
      Image(systemName: "brain.filled.head.profile")
        .font(.system(size: 48))
        .foregroundColor(.blue)

      Text("Gemini API Key")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)

      Text("Powers the live audio AI assistant.\nGet your key at aistudio.google.com/apikey")
        .font(.system(size: 14))
        .foregroundColor(Color(white: 0.5))
        .multilineTextAlignment(.center)

      TextField("AIza...", text: $geminiKey)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .font(.system(.body, design: .monospaced))
        .padding(12)
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .padding(.horizontal, 24)
        .onChange(of: geminiKey) {
          settings.geminiAPIKey = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

      if GeminiConfig.isConfigured {
        Label("Key configured", systemImage: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(.green)
      }
    }
  }

  // MARK: - Step 2: CDS API Key

  private var cdsStep: some View {
    VStack(spacing: 16) {
      Image(systemName: "stethoscope")
        .font(.system(size: 48))
        .foregroundColor(.blue)

      Text("CDS API Key")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)

      Text("Authenticates with the Predictive Analytics backend.\nProvided by your admin.")
        .font(.system(size: 14))
        .foregroundColor(Color(white: 0.5))
        .multilineTextAlignment(.center)

      TextField("CDS key", text: $cdsKey)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .font(.system(.body, design: .monospaced))
        .padding(12)
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .padding(.horizontal, 24)
        .onChange(of: cdsKey) {
          settings.cdsAPIKey = cdsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

      TextField("Backend URL", text: $backendURL)
        .textInputAutocapitalization(.never)
        .disableAutocorrection(true)
        .keyboardType(.URL)
        .font(.system(.body, design: .monospaced))
        .padding(12)
        .background(Color(white: 0.1))
        .cornerRadius(10)
        .padding(.horizontal, 24)
        .onChange(of: backendURL) {
          settings.paBackendURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }

      if GeminiConfig.isPABackendConfigured {
        Label("Key configured", systemImage: "checkmark.circle.fill")
          .font(.system(size: 13, weight: .medium))
          .foregroundColor(.green)
      }
    }
  }

  // MARK: - Step 3: Verify

  private var verifyStep: some View {
    VStack(spacing: 16) {
      Image(systemName: "checkmark.shield")
        .font(.system(size: 48))
        .foregroundColor(verifySuccess ? .green : .blue)

      Text("Verify Connection")
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)

      Text("Test that the backend is reachable\nand your keys are valid.")
        .font(.system(size: 14))
        .foregroundColor(Color(white: 0.5))
        .multilineTextAlignment(.center)

      Button {
        isVerifying = true
        verifyResult = nil
        Task {
          let bridge = PABackendBridge()
          await bridge.runPreFlightCheck()
          let status = bridge.preFlightStatus
          verifySuccess = status.overallState == .ready
          verifyResult = status.statusMessage
          isVerifying = false
        }
      } label: {
        HStack(spacing: 8) {
          if isVerifying {
            ProgressView().tint(.white)
          }
          Text(isVerifying ? "Checking..." : "Verify Now")
            .font(.system(size: 16, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.blue.opacity(0.8))
        .cornerRadius(12)
      }
      .disabled(isVerifying)
      .padding(.horizontal, 24)

      if let result = verifyResult {
        HStack(spacing: 6) {
          Image(systemName: verifySuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .foregroundColor(verifySuccess ? .green : .orange)
          Text(result)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(verifySuccess ? .green : .orange)
        }
      }

      if verifySuccess {
        Button {
          settings.hasCompletedOnboarding = true
          dismiss()
        } label: {
          Text("Done")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.green)
            .cornerRadius(12)
        }
        .padding(.horizontal, 24)
      }
    }
  }
}
