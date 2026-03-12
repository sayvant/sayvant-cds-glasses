# Sayvant CDS Glasses — Agent Guide

## Overview

This document describes how AI agents (Claude Code, Cursor, etc.) should work with this codebase. The app delivers real-time clinical decision support to physicians wearing smart glasses during patient encounters.

## Agent Roles

### Code Agent (this repo)

Modifies the iOS app. Owns UI, audio pipeline, transcript flow, and backend integration.

**Can modify:** All Swift files in `samples/CameraAccess/CameraAccess/`
**Should not modify:** PA backend logic (lives in separate repo at `/Users/andrewn/Documents/Projects/PA`)

### Backend Agent (PA repo)

Modifies the prediction engine. Owns feature extraction, risk scoring, differential diagnosis, safety engine.

**Repo:** `sayvant/predictive-analytics` (local: `/Users/andrewn/Documents/Projects/PA`)
**Deploy:** `railway up` from clean temp dir or `railway redeploy --yes`

## Critical Constraints

1. **Never commit real API keys.** `Secrets.swift` is gitignored. Use `Secrets.swift.example` as template.
2. **Local STT is primary.** Apple SFSpeechRecognizer handles transcription (~100ms). Gemini is secondary (clinical context + whispered summaries). If Gemini fails, the session continues.
3. **Audio gate stays closed.** Gemini must produce zero audio unless the physician taps "What did I miss?" Opening the gate on tool responses causes filler speech ("Let me check").
4. **Feature-gated display.** Risk score hidden until model detects clinical features AND probability > 10%. Never show the 7.4% base-rate intercept.
5. **Dedup only on Gemini tool calls.** Auto-analysis does NOT accumulate to `previouslyAsked`. Only `analyzeEncounter()` (Gemini tool call path) adds question IDs. This prevents ask-next questions from being exhausted.
6. **Swift models must match backend JSON exactly.** If `ComprehensiveResponse.swift` doesn't match `/comprehensive_analysis` output, JSONDecoder throws silently. Test with `curl` first.
7. **HIPAA: prototype only.** Audio goes to Google (Gemini) and Apple (SFSpeechRecognizer). Text goes to Railway. No BAA. Simulated patients only.

## Data Flow

```
Glasses mic → iPhone AudioManager
    ├── Raw Float32 → LocalSpeechRecognizer (on-device, ~100ms)
    │       ├── onPartial → userTranscript (display)
    │       ├── flush timer (2s) → PABackendBridge.appendTranscript()
    │       └── onFinal → commit remaining delta
    │
    └── Resampled 16kHz Int16 → Gemini Live WebSocket
            └── onToolCall(analyze_encounter) → PABackendBridge.analyzeEncounter()

Auto-analysis loop (3s cycle, 2s initial delay):
    PABackendBridge.fullTranscript → POST /comprehensive_analysis → update @Published state
```

## State Ownership

| Owner | State |
|-------|-------|
| `GeminiSessionViewModel` | `isGeminiActive`, `transcriptEntries`, `userTranscript`, `audioGateOpen`, `geminiConnected` |
| `PABackendBridge` | `predictionResult`, `comprehensiveResult`, `redFlags`, `askNextQuestions`, `completenessScore`, `fullTranscript`, `previouslyAsked` |

Do not cross these boundaries. `CDSSessionContent` observes both via `@ObservedObject`.

## Common Tasks

### Adding a new card to the HUD
1. Add the view to `Views/HUD/` or `Views/Cards/`
2. Wire it into `HUDViewport.hudContent()` at the appropriate position
3. Gate visibility on data availability (don't show empty states)

### Adding a new backend endpoint
1. Add the HTTP method to `PABackendBridge.swift`
2. Add response model to `Models/ComprehensiveResponse.swift` or new file
3. Test with `curl` against `https://predictive-analytics.up.railway.app` first

### Changing transcript flow
1. Read `GeminiSessionViewModel.swift` thoroughly first
2. Understand partial flush timer, delta tracking, and STT restart detection
3. Never bypass `appendTranscript()` — it's the single path to `fullTranscript`

### Debugging risk scoring issues
1. Check PA backend preprocessor first (`server/preprocessor.py` in PA repo)
2. Voice transcripts get segmented — missing regex patterns silently drop patient history
3. Use `/comprehensive_analysis` curl with the exact transcript text to isolate iOS vs backend

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project samples/CameraAccess/CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -quiet build
```

Requirements: Xcode 15+, iOS 17+, no external dependencies.

## Git Workflow

Push to `main` on `sayvant/sayvant-cds-glasses`. No feature branches required for small changes. Use the `napiermd` GitHub account for push access to the sayvant org.
