# Sayvant CDS Glasses — Claude Code Instructions

## What This Is

iOS app that delivers real-time clinical decision support to physicians wearing smart glasses during patient encounters. On-device speech recognition provides near-instant transcription. The PA backend (same model as the web app) scores risk, generates differential diagnoses, suggests next questions, and flags safety concerns. Results display on a heads-up display or full card view.

Gemini Live WebSocket provides clinical context detection and optional whispered summaries. It is NOT the primary transcription source — Apple's SFSpeechRecognizer handles that on-device.

## Architecture

```
Glasses mic → iPhone AudioManager
    ├── Raw Float32 buffer → LocalSpeechRecognizer (on-device, ~100ms)
    │       ├── onPartial → userTranscript (display)
    │       ├── flush timer (2s) → PABackendBridge.appendTranscript()
    │       └── onFinal → commit remaining delta + transcript entries
    │
    └── Resampled 16kHz Int16 → Gemini Live WebSocket (if connected)
            └── onToolCall(analyze_encounter) → PABackendBridge.analyzeEncounter()

Auto-analysis loop (3s cycle, 2s initial delay):
    PABackendBridge.fullTranscript → POST /comprehensive_analysis → update all @Published state

Both paths → same callComprehensiveAnalysis() core → applyComprehensiveResult()
    → predictionResult, askNextQuestions, redFlags, completenessScore, differentials, workup
```

## Project Structure

```
samples/CameraAccess/CameraAccess/
├── CameraAccessApp.swift              # App entry point → MainAppView
├── Secrets.swift                      # API keys (DO NOT COMMIT real keys)
│
├── Gemini/
│   ├── LocalSpeechRecognizer.swift    # On-device Apple STT, ~100ms latency
│   ├── GeminiLiveService.swift        # WebSocket to Gemini Live API
│   ├── AudioManager.swift             # Mic capture, Bluetooth routing, dual buffer output
│   ├── GeminiConfig.swift             # Model config, system prompt (silence-enforced), URLs
│   └── GeminiSessionViewModel.swift   # Session lifecycle, partial flush, auto-analysis, audio gate
│
├── OpenClaw/
│   ├── PABackendBridge.swift          # HTTP client for /comprehensive_analysis, all @Published clinical state
│   ├── ToolCallModels.swift           # Gemini tool call parsing (analyze_encounter)
│   └── ToolCallRouter.swift           # Routes tool calls → bridge
│
├── Models/
│   ├── ComprehensiveResponse.swift    # Full PA response decode (prediction, differential, guidance, workup, uncertainty)
│   ├── PredictResponse.swift          # ACS risk + troponin + disposition prediction structs
│   ├── EncounterSummary.swift         # SavedEncounter + EncounterStore (local JSON persistence)
│   ├── EncounterTimeline.swift        # TimelineEntry for risk trend chart
│   ├── TranscriptEntry.swift          # Speaker-labeled transcript entries
│   └── SessionState.swift             # Auto-save/resume across app restarts
│
├── Settings/
│   ├── SettingsManager.swift          # UserDefaults wrapper
│   └── SettingsView.swift             # Settings UI (API keys, backend URL, system prompt override)
│
├── DemoFixtures/                      # Pre-baked JSON for demo mode (classic ACS, low risk, safety)
│
└── Views/
    ├── CDSSessionView.swift           # Master view (pre-session, active session, card stack, manual text)
    ├── MainAppView.swift              # Top-level navigation
    ├── EncounterSummaryView.swift     # Post-encounter summary + past encounters list
    ├── HUD/
    │   ├── HUDViewport.swift          # Glasses-mode HUD: risk strip, ask-next hero, live transcript
    │   ├── HUDSafetyOverlay.swift     # Red flag / safety override banner
    │   └── HUDStatusDots.swift        # Connection status indicators
    ├── Components/
    │   ├── TranscriptPane.swift       # Live scrollable transcript with full-screen modal
    │   ├── HUDModeToggle.swift        # Glasses icon toggle
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
| `LocalSpeechRecognizer.swift` | On-device STT via SFSpeechRecognizer, nonisolated buffer append | Changing transcription behavior, latency tuning |
| `PABackendBridge.swift` | All HTTP calls to PA backend, owns all @Published clinical state | Adding endpoints, changing response handling |
| `GeminiSessionViewModel.swift` | Session lifecycle, audio wiring, partial flush, auto-analysis loop, audio gate | Changing session behavior, transcript flow |
| `CDSSessionView.swift` | Master UI — card stack layout, feature-gated display | Adding/reordering cards, changing session flow |
| `HUDViewport.swift` | Glasses-mode HUD with ask-next hero, live transcript indicator | Changing HUD layout, adding HUD elements |
| `ComprehensiveResponse.swift` | Decodable models matching `/comprehensive_analysis` JSON | When backend response schema changes |
| `GeminiConfig.swift` | System prompt, model selection, API URLs | Changing Gemini behavior |

## Critical Design Decisions

### Local STT first, Gemini second
Audio + local STT start immediately in `startSession()`. Gemini connects asynchronously in the background via `connectGemini()`. If Gemini fails, the session continues — local STT feeds the PA backend independently. The `geminiConnected` bool gates audio send to Gemini.

### Partial transcript flush
SFSpeechRecognizer's `onFinal` only fires after a pause in speech. During continuous talking, only `onPartial` fires. A 2-second flush timer (`partialFlushTask`) periodically commits partial text to `PABackendBridge.appendTranscript()`. Tracks `lastFlushedPartial` to send only deltas. Resets tracking when STT recognition restarts (detects prefix mismatch). `onFinal` commits any remaining delta beyond what was already flushed.

### Audio gate (silence by default)
Gemini's system prompt enforces absolute silence. The audio gate (`audioGateOpen`) is closed by default and does NOT open on tool responses. It only opens when the physician taps "What did I miss?" via `requestSummary()`. This prevents Gemini from speaking filler phrases like "Let me check."

### Feature-gated display
Risk score is hidden until the model detects at least one clinical feature AND probability exceeds 10% (above the 7.4% base-rate intercept). Applies to both the HUD risk strip and the card view's RiskScoreCard. "History complete" only shows when completeness > 80%.

### Ask-next dedup
`previouslyAsked` is sent in all `/comprehensive_analysis` calls. Auto-analysis does NOT accumulate to `previouslyAsked` — only Gemini tool calls do. This means the HUD always shows current relevant questions (backend filters based on extracted features), while Gemini's whispered suggestions don't repeat.

### Session state ownership
- `GeminiSessionViewModel` owns: `isGeminiActive`, `transcriptEntries`, `userTranscript`, `audioGateOpen`, `geminiConnected`
- `PABackendBridge` owns: `predictionResult`, `comprehensiveResult`, `redFlags`, `askNextQuestions`, `completenessScore`, `fullTranscript`, `previouslyAsked`
- `CDSSessionContent` observes BOTH via `@ObservedObject`

### Encounter summary sheet
The `.sheet(item: $showEncounterSummary)` lives at the TOP-LEVEL body of `CDSSessionContent`, not inside `activeSessionView`. When `stopSession()` flips `isGeminiActive` to false, `activeSessionView` unmounts. Any sheet inside it would die.

## Common Gotchas

- **Swift model must match backend JSON exactly.** If a field type doesn't match, JSONDecoder throws and the entire response fails silently. Test with `curl` first.
- **`ConfidenceInterval.display` is optional.** Prediction CI has it; uncertainty CI does not.
- **`CategoryScore` has dual decode paths.** Backend returns plain numbers not objects. Custom decoder handles both.
- **`stopSession()` clears VM state but NOT `transcriptEntries`.** They persist for encounter summary. Cleared on next `startSession()`.
- **SourceKit cross-file errors are noise.** "Cannot find type X in scope" warnings appear during editing. They resolve at build time.
- **`nonisolated(unsafe)` on `_requestRef`**: Required because `appendAudioBuffer()` is called from the audio thread but `LocalSpeechRecognizer` is `@MainActor`. The `SFSpeechAudioBufferRecognitionRequest.append()` method is thread-safe per Apple docs.
- **Audio gate must stay closed on tool responses.** Opening it causes Gemini filler speech ("Let me check") to play through the glasses.
- **Partial flush resets on STT restart.** When recognition restarts after an error, `userTranscript` resets to shorter text. The flush timer detects prefix mismatch and resets `lastFlushedPartial`.

## Build & Run

```bash
# Build for simulator
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project samples/CameraAccess/CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build

# Build for device: open .xcodeproj in Xcode, select device, Cmd+R
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

The PA backend repo is at `sayvant/predictive-analytics` (local: `/Users/andrewn/Documents/Projects/PA`). If the `/comprehensive_analysis` response schema changes, update `ComprehensiveResponse.swift` to match.

## Voice Transcript Preprocessing

The PA backend's preprocessor detects voice transcripts (continuous text, no newlines/em-dashes, >100 chars) and segments them into doctor questions vs patient responses. Key patterns in `_VOICE_PATIENT_RE`: `i'm`, `i have`, `i've`, `i got`, `well`, `i smoke`, etc. Segments with no patient pattern but containing symptom keywords are kept as a safety net. This is critical — missing patterns cause the feature extractor to miss risk factors.

## HIPAA

Prototype only. Patient audio goes to Google (Gemini) and Apple (SFSpeechRecognizer server fallback). Text goes to Railway. None have a BAA. Use with simulated patients only.

Production path: on-device STT only (no server fallback) + text-only to HIPAA-compliant API (Claude with Anthropic BAA). Audio never leaves device.

## Meta ARIA Gen 2 Considerations

This app currently targets Meta Ray-Ban smart glasses. For Meta ARIA Gen 2:
- ARIA has more sensors (eye tracking, SLAM cameras, IMU) but the CDS use case primarily needs mic + speaker
- ARIA Research SDK provides direct sensor access vs Ray-Ban's Bluetooth-only audio
- The audio pipeline (AudioManager) would need adaptation for ARIA's sensor API
- HUD rendering would move from iPhone screen to ARIA's in-lens display
- Latency requirements become even more critical with in-lens rendering
