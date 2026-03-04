import SwiftUI

/// Live transcript area — shows real-time dictation scrolling upward.
/// Tap to open full-screen timestamped transcript modal.
struct TranscriptPane: View {
  let currentText: String
  let entries: [TranscriptEntry]
  @State private var showFullTranscript = false
  @State private var isPaused = false

  var body: some View {
    VStack(spacing: 0) {
      // Live transcript area — scrollable, shows recent entries + current text
      ZStack(alignment: .topTrailing) {
        Button {
          showFullTranscript = true
        } label: {
          ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
              VStack(alignment: .leading, spacing: 4) {
                // Show last few transcript entries for context
                ForEach(entries.suffix(6)) { entry in
                  HStack(alignment: .top, spacing: 6) {
                    // Prominent speaker label
                    Text(entry.speaker == .patient ? "PT" : "AI")
                      .font(.system(size: 9, weight: .bold, design: .monospaced))
                      .foregroundColor(entry.speaker == .patient ? .blue : .green)
                      .frame(width: 20)
                      .padding(.top, 2)
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
                if !isPaused {
                  withAnimation {
                    proxy.scrollTo("live", anchor: .bottom)
                  }
                }
              }
              .onChange(of: entries.count) {
                if !isPaused, let last = entries.last {
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
        }
        .buttonStyle(.plain)

        // Top-right controls: pause + count + expand
        HStack(spacing: 6) {
          // Pause/resume auto-scroll
          Button {
            isPaused.toggle()
          } label: {
            Image(systemName: isPaused ? "play.fill" : "pause.fill")
              .font(.system(size: 9))
              .foregroundColor(isPaused ? .orange : .white.opacity(0.4))
          }
          .buttonStyle(.plain)

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
        .cornerRadius(4)
        .padding(4)
      }
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
  @State private var searchText = ""
  @State private var filterSpeaker: TranscriptEntry.Speaker?

  private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
  }()

  private var filteredEntries: [TranscriptEntry] {
    entries.filter { entry in
      let matchesSpeaker = filterSpeaker == nil || entry.speaker == filterSpeaker
      let matchesSearch = searchText.isEmpty || entry.text.localizedCaseInsensitiveContains(searchText)
      return matchesSpeaker && matchesSearch
    }
  }

  var body: some View {
    NavigationView {
      VStack(spacing: 0) {
        // Search + filter bar
        HStack(spacing: 8) {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
              .foregroundColor(Color(white: 0.4))
              .font(.system(size: 13))
            TextField("Search transcript...", text: $searchText)
              .font(.system(size: 14))
              .foregroundColor(.white)
          }
          .padding(8)
          .background(Color(white: 0.12))
          .cornerRadius(8)

          // Speaker filter
          Menu {
            Button("All") { filterSpeaker = nil }
            Button("Patient") { filterSpeaker = .patient }
            Button("CDS") { filterSpeaker = .ai }
          } label: {
            HStack(spacing: 4) {
              Text(filterLabel)
                .font(.system(size: 12, weight: .medium))
              Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11))
            }
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))
            .cornerRadius(8)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(filteredEntries) { entry in
                HStack(alignment: .top, spacing: 10) {
                  Text(timeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                    .frame(width: 60, alignment: .leading)

                  VStack(alignment: .leading, spacing: 2) {
                    Text(entry.speaker == .patient ? "Patient" : "CDS")
                      .font(.system(size: 11, weight: .bold))
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
            if let last = filteredEntries.last {
              proxy.scrollTo(last.id, anchor: .bottom)
            }
          }
        }
      }
      .background(Color.black)
      .navigationTitle("Transcript (\(filteredEntries.count))")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .preferredColorScheme(.dark)
    }
  }

  private var filterLabel: String {
    switch filterSpeaker {
    case nil: return "All"
    case .patient: return "Patient"
    case .ai: return "CDS"
    }
  }
}
