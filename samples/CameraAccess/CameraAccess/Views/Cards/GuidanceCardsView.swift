import SwiftUI

// MARK: - Red Flag Card

struct RedFlagCard: View {
  let flags: [FullRedFlag]
  @State private var expandedFlag: String?
  @State private var acknowledgedFlags: Set<String> = []

  private var activeFlags: [FullRedFlag] {
    flags.filter { !acknowledgedFlags.contains($0.id) }
  }

  private var reviewedFlags: [FullRedFlag] {
    flags.filter { acknowledgedFlags.contains($0.id) }
  }

  var body: some View {
    if !flags.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "RED FLAGS", trailing: "\(activeFlags.count)")

        ForEach(activeFlags) { flag in
          VStack(alignment: .leading, spacing: 4) {
            Button {
              withAnimation { expandedFlag = expandedFlag == flag.id ? nil : flag.id }
            } label: {
              HStack(alignment: .top, spacing: 8) {
                Circle()
                  .fill(urgencyColor(flag.urgency))
                  .frame(width: 8, height: 8)
                  .padding(.top, 5)
                Text(flag.message)
                  .font(.system(size: 15, weight: .medium))
                  .foregroundColor(.white)
                  .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: expandedFlag == flag.id ? "chevron.up" : "chevron.down")
                  .font(.system(size: 10))
                  .foregroundColor(Color(white: 0.4))
              }
            }
            .buttonStyle(.plain)

            if expandedFlag == flag.id {
              VStack(alignment: .leading, spacing: 6) {
                if let action = flag.recommended_action, !action.isEmpty {
                  HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                      .font(.system(size: 12))
                      .foregroundColor(.orange)
                    Text(action)
                      .font(.system(size: 13, weight: .medium))
                      .foregroundColor(Color(white: 0.8))
                  }
                }
                if let reasoning = flag.clinical_reasoning, !reasoning.isEmpty {
                  Text(reasoning)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.5))
                    .italic()
                }
                Button {
                  withAnimation {
                    acknowledgedFlags.insert(flag.id)
                    expandedFlag = nil
                  }
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                      .font(.system(size: 12))
                    Text("Reviewed")
                      .font(.system(size: 12, weight: .medium))
                  }
                  .foregroundColor(.green)
                  .padding(.top, 4)
                }
                .buttonStyle(.plain)
              }
              .padding(.leading, 16)
              .padding(.top, 2)
            }
          }
        }

        // Collapsed reviewed section
        if !reviewedFlags.isEmpty {
          DisclosureGroup {
            ForEach(reviewedFlags) { flag in
              HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.system(size: 12))
                  .foregroundColor(.green.opacity(0.6))
                Text(flag.message)
                  .font(.system(size: 13))
                  .foregroundColor(Color(white: 0.4))
                  .strikethrough()
              }
            }
          } label: {
            Text("Reviewed (\(reviewedFlags.count))")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(Color(white: 0.4))
          }
          .tint(Color(white: 0.4))
        }
      }
      .cdsCard(accent: .red)
    }
  }
}

// MARK: - Ask Next Card

struct AskNextCard: View {
  let questions: [FullAskNext]

  var body: some View {
    if !questions.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SectionHeader(title: "QUESTIONS TO ASK", trailing: "\(questions.count)")
        ForEach(Array(questions.enumerated()), id: \.element.id) { index, q in
          HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1).")
              .font(.system(size: 14, weight: .bold, design: .monospaced))
              .foregroundColor(Color(white: 0.4))
              .frame(width: 20, alignment: .trailing)
            Text("\"\(q.example_phrasing)\"")
              .font(.system(size: 15, weight: .medium))
              .foregroundColor(.white)
              .italic()
          }
        }
      }
      .cdsCard(accent: .blue)
    }
  }
}

// MARK: - Completeness Card

struct CompletenessCard: View {
  let completeness: CompletenessData?
  let score: Double

  init(completeness: CompletenessData?, score: Double) {
    self.completeness = completeness
    self.score = score
  }

  /// Simple initializer for backwards compatibility (score only).
  init(score: Double) {
    self.completeness = nil
    self.score = score
  }

  private var color: Color {
    if score > 80 { return .green }
    if score > 50 { return .orange }
    return .red
  }

  @State private var expandedCategory: String?

  var body: some View {
    if score > 0 {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          SectionHeader(title: "COMPLETENESS")
          Spacer()
          Text("\(Int(score))%")
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundColor(color)
        }
        CDSProgressBar(value: score / 100, color: color)

        // Category breakdown
        if let categories = completeness?.category_scores, !categories.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(categories.keys.sorted()), id: \.self) { category in
              if let catScore = categories[category] {
                let pct = catScore.score ?? 0
                let catColor = pct > 80 ? Color.green : pct > 50 ? Color.orange : Color.red

                VStack(alignment: .leading, spacing: 4) {
                  Button {
                    withAnimation {
                      expandedCategory = expandedCategory == category ? nil : category
                    }
                  } label: {
                    HStack {
                      Text(category.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                      Spacer()
                      Text("\(Int(pct))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(catColor)
                      if let total = catScore.total {
                        Text("\(catScore.captured?.count ?? 0)/\(total)")
                          .font(.system(size: 11, design: .monospaced))
                          .foregroundColor(Color(white: 0.4))
                      }
                    }
                  }
                  .buttonStyle(.plain)

                  CDSProgressBar(value: pct / 100, color: catColor)
                    .frame(height: 4)

                  // Expanded: show missing elements
                  if expandedCategory == category, let missing = catScore.missing, !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                      ForEach(missing, id: \.self) { element in
                        HStack(spacing: 6) {
                          Circle()
                            .fill(Color.orange.opacity(0.6))
                            .frame(width: 4, height: 4)
                          Text(element.replacingOccurrences(of: "_", with: " "))
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.5))
                        }
                      }
                    }
                    .padding(.leading, 8)
                  }
                }
              }
            }
          }
          .padding(.top, 4)
        }
      }
      .cdsCard(accent: color)
    }
  }
}
