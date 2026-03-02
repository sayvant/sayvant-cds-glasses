import SwiftUI
import Charts

/// Encounter timeline card showing risk probability trend over time.
struct TimelineCard: View {
  let entries: [TimelineEntry]
  @State private var showFullTimeline = false

  var body: some View {
    if entries.count >= 2 {
      VStack(alignment: .leading, spacing: 8) {
        Button {
          showFullTimeline = true
        } label: {
          VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "RISK TREND", trailing: "\(entries.count) updates")

            // Sparkline
            Chart(entries) { entry in
              LineMark(
                x: .value("Time", entry.timestamp),
                y: .value("ACS %", entry.acsProb * 100)
              )
              .foregroundStyle(Color.orange)
              .interpolationMethod(.catmullRom)

              PointMark(
                x: .value("Time", entry.timestamp),
                y: .value("ACS %", entry.acsProb * 100)
              )
              .foregroundStyle(Color.orange)
              .symbolSize(20)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
              AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisValueLabel {
                  if let v = value.as(Int.self) {
                    Text("\(v)%")
                      .font(.system(size: 9, design: .monospaced))
                      .foregroundColor(Color(white: 0.4))
                  }
                }
              }
            }
            .frame(height: 60)
          }
        }
        .buttonStyle(.plain)
      }
      .cdsCard(accent: .orange)
      .sheet(isPresented: $showFullTimeline) {
        FullTimelineView(entries: entries)
      }
    }
  }
}

// MARK: - Full Timeline Modal

struct FullTimelineView: View {
  let entries: [TimelineEntry]
  @Environment(\.dismiss) private var dismiss

  private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
  }()

  var body: some View {
    NavigationView {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          // Full chart
          Chart(entries) { entry in
            LineMark(
              x: .value("Time", entry.timestamp),
              y: .value("ACS %", entry.acsProb * 100)
            )
            .foregroundStyle(Color.orange)
            .interpolationMethod(.catmullRom)

            AreaMark(
              x: .value("Time", entry.timestamp),
              y: .value("ACS %", entry.acsProb * 100)
            )
            .foregroundStyle(
              LinearGradient(
                colors: [Color.orange.opacity(0.3), Color.orange.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
              )
            )

            PointMark(
              x: .value("Time", entry.timestamp),
              y: .value("ACS %", entry.acsProb * 100)
            )
            .foregroundStyle(Color.orange)
            .annotation(position: .top) {
              Text("\(Int(entry.acsProb * 100))%")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.orange)
            }
          }
          .chartYScale(domain: 0...100)
          .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
              AxisValueLabel {
                if let v = value.as(Int.self) {
                  Text("\(v)%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color(white: 0.4))
                }
              }
              AxisGridLine()
                .foregroundStyle(Color(white: 0.15))
            }
          }
          .frame(height: 200)
          .padding()

          // Event log
          VStack(alignment: .leading, spacing: 8) {
            Text("EVENT LOG")
              .font(.system(size: 11, weight: .bold))
              .foregroundColor(Color(white: 0.5))
              .tracking(1)

            ForEach(entries) { entry in
              HStack(alignment: .top, spacing: 12) {
                Text(timeFormatter.string(from: entry.timestamp))
                  .font(.system(size: 11, weight: .medium, design: .monospaced))
                  .foregroundColor(Color(white: 0.4))
                  .frame(width: 65, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                  Text("ACS: \(Int(entry.acsProb * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.orange)

                  if !entry.newFeatures.isEmpty {
                    ForEach(entry.newFeatures, id: \.self) { feature in
                      Text("+ \(feature.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    }
                  }
                }
              }
            }
          }
          .padding()
        }
      }
      .background(Color.black)
      .navigationTitle("Risk Timeline")
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
