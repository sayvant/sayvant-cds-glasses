import SwiftUI

/// Minimized transcript bubble that expands to full-screen modal on tap.
struct TranscriptPane: View {
  let currentText: String
  let entries: [TranscriptEntry]
  @State private var showFullTranscript = false

  var body: some View {
    if !currentText.isEmpty || !entries.isEmpty {
      Button {
        showFullTranscript = true
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "waveform")
            .foregroundColor(.white.opacity(0.3))
            .font(.system(size: 12))
          Text(currentText.isEmpty ? "View transcript" : currentText)
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.4))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
          Spacer()
          if !entries.isEmpty {
            Text("\(entries.count)")
              .font(.system(size: 10, weight: .bold, design: .monospaced))
              .foregroundColor(.white.opacity(0.3))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Color(white: 0.2))
              .cornerRadius(4)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.7))
        .cornerRadius(8)
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
