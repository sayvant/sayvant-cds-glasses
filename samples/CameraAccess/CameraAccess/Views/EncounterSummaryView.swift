import SwiftUI

/// Post-session encounter summary with collapsible sections, share, and copy buttons.
struct EncounterSummaryView: View {
  let encounter: SavedEncounter
  @Environment(\.dismiss) private var dismiss
  @State private var copiedToClipboard = false

  private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          // Date header
          Text(dateFormatter.string(from: encounter.date))
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color(white: 0.5))

          // Clinical Assessment
          if let risk = encounter.riskBand {
            SummarySection(title: "Clinical Assessment") {
              HStack {
                Text("ACS Risk")
                  .foregroundColor(Color(white: 0.6))
                Spacer()
                if let pct = encounter.acsRiskPct {
                  Text("\(Int(pct))%")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundColor(bandColor(risk))
                }
                Text(risk)
                  .font(.system(size: 12, weight: .bold))
                  .foregroundColor(.white)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 3)
                  .background(bandColor(risk))
                  .cornerRadius(6)
              }
            }
          }

          // Differential
          if let diffs = encounter.differentialSummary, !diffs.isEmpty {
            SummarySection(title: "Differential Diagnosis") {
              ForEach(diffs) { dx in
                HStack {
                  Text(dx.diagnosis)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                  Spacer()
                  Text("\(Int(dx.probabilityPct))%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.6))
                }
              }
            }
          }

          // Workup
          if let workup = encounter.workupItems, !workup.isEmpty {
            SummarySection(title: "Recommended Workup") {
              ForEach(workup, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                  Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
                    .padding(.top, 5)
                  Text(item)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                }
              }
            }
          }

          // Disposition
          if let disposition = encounter.disposition {
            SummarySection(title: "Disposition") {
              Text(disposition)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(dispositionColor(disposition))
            }
          }

          // Rich summary sections (from /full_summary if available)
          if let summary = encounter.fullSummary {
            if let recommendations = summary.recommendations, !recommendations.isEmpty {
              SummarySection(title: "Recommendations") {
                ForEach(recommendations, id: \.self) { rec in
                  HStack(alignment: .top, spacing: 8) {
                    Circle()
                      .fill(Color.blue)
                      .frame(width: 6, height: 6)
                      .padding(.top, 5)
                    Text(rec)
                      .font(.system(size: 14))
                      .foregroundColor(.white)
                  }
                }
              }
            }

            if let unc = summary.uncertainty {
              SummarySection(title: "Uncertainty") {
                VStack(spacing: 6) {
                  if let level = unc.uncertainty_level {
                    MetricRow(label: "Level", value: level.capitalized)
                  }
                  if let stability = unc.prediction_stability {
                    MetricRow(label: "Stability", value: stability.capitalized)
                  }
                }
              }
            }
          }

          // Quality Metrics
          SummarySection(title: "Quality Metrics") {
            VStack(spacing: 6) {
              MetricRow(label: "Completeness", value: encounter.completenessScore.map { "\(Int($0))%" } ?? "N/A")
              MetricRow(label: "Red Flags", value: "\(encounter.redFlagCount)")
              MetricRow(label: "Questions Asked", value: "\(encounter.questionsAsked)")
            }
          }

          // Transcript
          if !encounter.transcript.isEmpty {
            SummarySection(title: "Transcript") {
              Text(encounter.transcript)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
            }
          }
        }
        .padding()
      }
      .background(Color.black)
      .navigationTitle("Encounter Summary")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          HStack(spacing: 12) {
            // Copy to clipboard
            Button {
              UIPasteboard.general.string = buildShareText()
              copiedToClipboard = true
              DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedToClipboard = false
              }
            } label: {
              Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
            }

            // Share
            ShareLink(item: buildShareText()) {
              Image(systemName: "square.and.arrow.up")
            }
          }
        }
      }
      .preferredColorScheme(.dark)
    }
  }

  private func buildShareText() -> String {
    var text = "CDS Analysis \u{2014} \(dateFormatter.string(from: encounter.date))\n"

    if let pct = encounter.acsRiskPct, let band = encounter.riskBand {
      text += "ACS Risk: \(Int(pct))% (\(band))\n"
    }

    if let diffs = encounter.differentialSummary, !diffs.isEmpty {
      text += "Top Dx: \(diffs.map { "\($0.diagnosis) (\(Int($0.probabilityPct))%)" }.joined(separator: ", "))\n"
    }

    if let workup = encounter.workupItems, !workup.isEmpty {
      text += "Workup: \(workup.joined(separator: ", "))\n"
    }

    if let disposition = encounter.disposition {
      text += "Disposition: \(disposition)\n"
    }

    if let score = encounter.completenessScore {
      text += "Completeness: \(Int(score))%\n"
    }

    text += "Red Flags: \(encounter.redFlagCount)\n"

    if !encounter.transcript.isEmpty {
      text += "\n--- Transcript ---\n\(encounter.transcript)\n"
    }

    return text
  }
}

// MARK: - Summary Helpers

private struct SummarySection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content
  @State private var isExpanded = true

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation { isExpanded.toggle() }
      } label: {
        HStack {
          Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(white: 0.5))
            .tracking(1)
          Spacer()
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 10))
            .foregroundColor(Color(white: 0.3))
        }
      }
      .buttonStyle(.plain)

      if isExpanded {
        content
      }
    }
    .padding(14)
    .background(Color(white: 0.1))
    .cornerRadius(12)
  }
}

private struct MetricRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack {
      Text(label)
        .font(.system(size: 13))
        .foregroundColor(Color(white: 0.5))
      Spacer()
      Text(value)
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .foregroundColor(.white)
    }
  }
}

// MARK: - Past Encounters List

struct PastEncountersView: View {
  @State private var encounters: [SavedEncounter] = []
  @State private var selectedEncounter: SavedEncounter?
  @State private var replayEncounter: SavedEncounter?
  @Environment(\.dismiss) private var dismiss

  private let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f
  }()

  var body: some View {
    NavigationView {
      Group {
        if encounters.isEmpty {
          VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
              .font(.system(size: 40))
              .foregroundColor(Color(white: 0.3))
            Text("No past encounters")
              .font(.system(size: 16, weight: .medium))
              .foregroundColor(Color(white: 0.4))
          }
        } else {
          List {
            ForEach(encounters) { enc in
              Button {
                selectedEncounter = enc
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(dateFormatter.string(from: enc.date))
                      .font(.system(size: 14, weight: .medium))
                      .foregroundColor(.white)
                    Spacer()
                    if let band = enc.riskBand {
                      Text(band)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(bandColor(band))
                        .cornerRadius(4)
                    }
                  }
                  HStack {
                    if let dx = enc.topDiagnosis {
                      Text(dx)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.5))
                    }
                    Spacer()
                    // Replay button
                    if !enc.transcript.isEmpty {
                      Button {
                        replayEncounter = enc
                      } label: {
                        HStack(spacing: 4) {
                          Image(systemName: "play.fill")
                            .font(.system(size: 9))
                          Text("Replay")
                            .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(6)
                      }
                      .buttonStyle(.plain)
                    }
                  }
                }
              }
            }
            .onDelete { offsets in
              let idsToDelete = offsets.map { encounters[$0].id }
              for id in idsToDelete {
                EncounterStore.shared.delete(id: id)
              }
              encounters.remove(atOffsets: offsets)
            }
          }
          .listStyle(.plain)
        }
      }
      .background(Color.black)
      .navigationTitle("Past Encounters")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .preferredColorScheme(.dark)
      .onAppear {
        encounters = EncounterStore.shared.loadAll()
      }
      .sheet(item: $selectedEncounter) { enc in
        EncounterSummaryView(encounter: enc)
      }
      .fullScreenCover(item: $replayEncounter) { enc in
        ReplaySessionView(encounter: enc)
      }
    }
  }
}
