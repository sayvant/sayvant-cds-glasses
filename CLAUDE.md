# Sayvant CDS Glasses — Claude Code Instructions

## What This Is

iOS app that delivers real-time clinical decision support to physicians wearing smart glasses during patient encounters. Audio flows from glasses mic to Gemini (transcription only) to the PA backend (all the clinical brains) and back as whispered guidance through the glasses speaker.

Gemini is a microphone + speaker. The PA backend (predictive-analytics on Railway) does all clinical analysis — same 360-chart-trained LogReg, Bayesian differential (18 diagnoses), safety engine, guidance engine, and auxiliary models that power the web frontend.

## Architecture

```
Glasses mic → iPhone → Gemini Live WebSocket (transcription)
                              ↓
              Auto-analysis loop (every 10s) + Gemini tool calls
                              ↓
                POST /comprehensive_analysis (Railway PA backend)
                              ↓
              Cards render on screen (risk, differential, workup, etc.)
              Gemini whispers summary through glasses speaker
```

## Project Structure

```
samples/CameraAccess/CameraAccess/
├── CameraAccessApp.swift              # App entry point → MainAppView
├── Secrets.swift                      # API keys (DO NOT COMMIT real keys)
│
├── Gemini/
│   ├── GeminiLiveService.swift        # WebSocket to Gemini Live API
│   ├── AudioManager.swift             # Mic capture + Bluetooth speaker playback
│   ├── GeminiConfig.swift             # Model config, system prompt, URLs
│   └── GeminiSessionViewModel.swift   # Session lifecycle, transcript, auto-analysis loop
│
├── OpenClaw/
│   ├── PABackendBridge.swift          # HTTP client for /comprehensive_analysis
│   ├── ToolCallModels.swift           # Gemini tool call parsing (analyze_encounter)
│   └── ToolCallRouter.swift           # Routes tool calls → bridge
│
├── Models/
│   ├── ComprehensiveResponse.swift    # Full PA response decode (prediction, differential, guidance, workup, uncertainty)
│   ├── PredictResponse.swift          # ACS risk + troponin + disposition prediction structs
│   ├── EncounterSummary.swift         # SavedEncounter + EncounterStore (local JSON persistence)
│   ├── EncounterTimeline.swift        # TimelineEntry for risk trend chart
│   ├── TranscriptEntry.swift          # Speaker-labeled transcript entries
│   └── SessionState.swift            # Auto-save/resume across app restarts
│
├── Settings/
│   ├── SettingsManager.swift          # UserDefaults wrapper
│   └── SettingsView.swift             # Settings UI (API keys, backend URL, system prompt)
│
└── Views/
    ├── CDSSessionView.swift           # Master view (pre-session, active session, manual results)
    ├── MainAppView.swift              # Top-level navigation
    ├── EncounterSummaryView.swift     # Post-encounter summary + past encounters list
    ├── Components/
    │   ├── TranscriptPane.swift       # Live scrollable transcript with full-screen modal
    │   └── ...                        # CardView, CircleButton, GeminiOverlayView, StatusText
    └── Cards/
        ├── RiskScoreCard.swift        # ACS probability hero card + uncertainty badge
        ├── DifferentialCard.swift     # 18 diagnoses ranked + can't-miss alerts
        ├── WorkupCard.swift           # Tiered workup recommendations
        ├── GuidanceCardsView.swift    # RedFlagCard + AskNextCard + CompletenessCard
        ├── PredictionCardsView.swift  # TroponinCard + DispositionCard + FeatureAttributionCard
        ├── TimelineCard.swift         # Risk trend sparkline (SwiftUI Charts)
        ├── SafetyBannerView.swift     # Safety override banner
        └── CDSCardStyle.swift         # Shared .cdsCard() modifier
```

## Key Files

| File | What it does | When you'll touch it |
|------|-------------|---------------------|
| `PABackendBridge.swift` | All HTTP calls to PA backend, owns all @Published clinical state | Adding endpoints, changing response handling |
| `GeminiSessionViewModel.swift` | Session lifecycle, audio wiring, auto-analysis loop | Changing session behavior, transcript handling |
| `CDSSessionView.swift` | Master UI — three states (pre/active/manual), card stack layout | Adding/reordering cards, changing session flow |
| `ComprehensiveResponse.swift` | Decodable models matching `/comprehensive_analysis` JSON | When backend response schema changes |
| `GeminiConfig.swift` | System prompt, model selection, API URLs | Changing Gemini behavior |

## Critical Design Decisions

### Dual-path analysis
Cards update via two independent paths:
1. **Auto-analysis loop** (every 10s): `onInputTranscription` feeds text to `bridge.appendTranscript()`, periodic task calls `bridge.runAutoAnalysis()`. Cards render regardless of Gemini.
2. **Gemini tool calls**: Gemini calls `analyze_encounter` when it detects clinical content. Returns structured result for whisper audio.

Both paths use the same `callComprehensiveAnalysis()` core in PABackendBridge.

### Audio gate
Gemini generates audio constantly (acknowledgments, filler). The audio gate blocks ALL playback except:
- After a tool response is sent back (whispered guidance)
- When "What did I miss?" is tapped (summary request)

### Session state ownership
- `GeminiSessionViewModel` owns: `isGeminiActive`, `transcriptEntries`, `userTranscript`
- `PABackendBridge` owns: `predictionResult`, `comprehensiveResult`, `redFlags`, `askNextQuestions`, `completenessScore`, `fullTranscript`
- `CDSSessionContent` observes BOTH via `@ObservedObject` — without this, SwiftUI doesn't re-render when bridge state changes

### Encounter summary sheet
The `.sheet(item: $showEncounterSummary)` lives at the TOP-LEVEL body of `CDSSessionContent`, not inside `activeSessionView`. When `stopSession()` flips `isGeminiActive` to false, `activeSessionView` unmounts. Any sheet inside it would die.

## Common Gotchas

- **Swift model must match backend JSON exactly.** If a field type doesn't match (Double vs String, dict vs array), JSONDecoder throws and the entire response fails silently. Always test with `curl` against the live endpoint first.
- **`ConfidenceInterval.display` is optional.** The prediction block's CI has it; the uncertainty block's CI does not.
- **`CategoryScore` has dual decode paths.** Backend returns plain numbers (`"Pain Characteristics": 40.0`) not objects. Custom decoder handles both.
- **`stopSession()` clears VM state but NOT `transcriptEntries`.** They persist so encounter summary can use them. Cleared on next `startSession()`.
- **SourceKit cross-file errors are noise.** "Cannot find type X in scope" warnings appear constantly during editing. They resolve at build time. Always verify with `xcodebuild`.

## Build & Run

```bash
# Build for simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project samples/CameraAccess/CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build

# Build for device
# Open CameraAccess.xcodeproj in Xcode, select your device, Cmd+R
```

Requirements: Xcode 15+, iOS 17+, no external dependencies (pure native Swift).

## Backend Integration

The app talks to the PA backend at `https://predictive-analytics.up.railway.app`.

| Endpoint | Used by | Purpose |
|----------|---------|---------|
| `/health` | `checkConnection()` | Verify backend reachable |
| `/comprehensive_analysis` | `callComprehensiveAnalysis()` | All clinical analysis (prediction, differential, guidance, workup, uncertainty) |
| `/full_summary` | `fetchFullSummary()` | End-of-encounter structured summary |

Auth: `X-CDS-Key` header with value from `Secrets.swift` or Settings.

The PA backend repo is at `/Users/andrewn/Documents/Projects/PA`. See its `CLAUDE.md` for backend instructions. If you change the `/comprehensive_analysis` response schema there, you MUST update `ComprehensiveResponse.swift` here to match.

## HIPAA

Prototype only. Patient audio goes to Google (Gemini). Text goes to Railway (PA backend). Neither has a BAA. Production path: on-device STT + HIPAA-compliant inference.
