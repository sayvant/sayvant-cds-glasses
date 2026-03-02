import SwiftUI

/// Live transcript area — shows real-time dictation scrolling upward.
/// Tap to open full-screen timestamped transcript modal.
struct TranscriptPane: View {
  let currentText: String
  let entries: [TranscriptEntry]
  @State private var showFullTranscript = false

  var body: some View {
    VStack(spacing: 0) {
      // Live transcript area — scrollable, shows recent entries + current text
      Button {
        showFullTranscript = true
      } label: {
        ScrollViewReader { proxy in
          ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
              // Show last few transcript entries for context
              ForEach(entries.suffix(6)) { entry in
                HStack(alignment: .top, spacing: 6) {
                  Circle()
                    .fill(entry.speaker == .patient ? Color.blue.opacity(0.6) : Color.green.opacity(0.6))
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                  Text(entry.text)
                    .font(.system(size: 13))
                    .foregroundColor(entry.speaker == .patient ? .white.opacity(0.7) : .green.opacity(0.6))
                    .multilineTextAlignment(.leading)
                }
                .id(entry.id)
              }

              // Current live transcription (what's being said right now)
              if !currentText.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                  Image(systemName: "waveform")
                    .foregroundColor(.blue)
                    .font(.system(size: 10))
                    .padding(.top, 3)
                  Text(currentText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                }
                .id("live")
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .onChange(of: currentText) {
              withAnimation {
                proxy.scrollTo("live", anchor: .bottom)
              }
            }
            .onChange(of: entries.count) {
              if let last = entries.last {
                withAnimation {
                  proxy.scrollTo(last.id, anchor: .bottom)
                }
              }
            }
          }
        }
        .frame(height: 120)
        .background(Color(white: 0.08))
        .cornerRadius(10)
        .overlay(
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color(white: 0.2), lineWidth: 0.5)
        )
        .overlay(
          // Entry count badge + expand hint
          HStack(spacing: 4) {
            if !entries.isEmpty {
              Text("\(entries.count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
            }
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.system(size: 8))
              .foregroundColor(.white.opacity(0.3))
          }
          .padding(4)
          .background(Color.black.opacity(0.6))
          .cornerRadius(4),
          alignment: .topTrailing
        )
      }
      .buttonStyle(.plain)
      .sheet(isPresented: $showFullTranscript) {
        FullTranscriptView(entries: entries)
      }
    }
  }
}

// MARK: - Full Transcript Modal

struct FullTranscriptView: View {
  let entries: [TranscriptEntry]
  @Environment(\.dismiss) private var dismiss

  private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
  }()

  var body: some View {
    NavigationView {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(entries) { entry in
              HStack(alignment: .top, spacing: 10) {
                Text(timeFormatter.string(from: entry.timestamp))
                  .font(.system(size: 10, weight: .medium, design: .monospaced))
                  .foregroundColor(Color(white: 0.4))
                  .frame(width: 60, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.speaker == .patient ? "Patient" : "CDS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(entry.speaker == .patient ? .blue : .green)
                  Text(entry.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                }
              }
              .id(entry.id)
            }
          }
          .padding()
        }
        .background(Color.black)
        .onAppear {
          if let last = entries.last {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
      .navigationTitle("Transcript")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .preferredColorScheme(.dark)
    }
  }
}
