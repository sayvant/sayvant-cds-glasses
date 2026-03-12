# Sayvant CDS Glasses

Real-time clinical decision support displayed on a heads-up display for physicians wearing smart glasses during patient encounters. Hands-free, eyes-free, zero workflow disruption.

Forked from [VisionClaw](https://github.com/sseanliu/VisionClaw). Video stripped. Audio pipeline preserved. OpenClaw replaced with Sayvant PA backend.

## How it works

```
Ray-Ban Glasses (mic)
    | Bluetooth audio
iPhone (in pocket)
    | AudioManager: dual output
    |   1. Raw Float32 buffer → LocalSpeechRecognizer (on-device STT, ~100ms)
    |   2. Resampled 16kHz Int16 → Gemini Live WebSocket (clinical context)
    |
    ├── Local STT partials → flush every 2s → PABackendBridge.fullTranscript
    ├── Auto-analysis loop (every 3s) → POST /comprehensive_analysis
    └── Gemini tool calls (analyze_encounter) → POST /comprehensive_analysis
                              ↓
              PA Backend (Railway) — same model as web app
              360-chart LogReg + Bayesian differential + safety engine
                              ↓
              HUD renders: risk score, ask-next questions, completeness
              Physician hears whisper ONLY on "What did I miss?" tap
```

## Two display modes

**Card View** (default): Full scrollable cards — risk score, differential diagnosis, workup, feature attribution, troponin/disposition predictions, timeline, transcript.

**Glasses Mode** (HUD): Compact heads-up display optimized for ambient glanceable use:
- Risk strip (percentage + band + disposition)
- Ask-next hero (rotating questions with example phrasing)
- Live transcript indicator (waveform + last few words)
- Completeness bar
- End session button + status dots
- No risk shown until features actually detected (no misleading base rate)

## Setup

1. Copy `samples/CameraAccess/CameraAccess/Secrets.swift.example` to `Secrets.swift`
2. Add your Gemini API key from [AI Studio](https://aistudio.google.com/apikey)
3. Add your CDS API key (set as `CDS_API_KEY` in Railway env vars)
4. Open `samples/CameraAccess/CameraAccess.xcodeproj` in Xcode
5. Build and run on iPhone (iOS 17+)

## Key files

| File | What it does |
|------|-------------|
| `Gemini/LocalSpeechRecognizer.swift` | On-device Apple STT (~100ms latency, primary transcription) |
| `Gemini/AudioManager.swift` | Mic capture + Bluetooth speaker playback, dual buffer output |
| `Gemini/GeminiSessionViewModel.swift` | Session lifecycle, partial flush, auto-analysis, audio gate |
| `Gemini/GeminiConfig.swift` | System prompt (silence-enforced), model config, URLs |
| `Gemini/GeminiLiveService.swift` | WebSocket to Gemini Live API |
| `OpenClaw/PABackendBridge.swift` | HTTP client for /comprehensive_analysis, owns all clinical state |
| `OpenClaw/ToolCallRouter.swift` | Routes Gemini tool calls to PA bridge |
| `Views/CDSSessionView.swift` | Master view: pre-session, active session, card stack |
| `Views/HUD/HUDViewport.swift` | Glasses-mode HUD with ask-next hero + live transcript |

## Architecture highlights

**Local STT first, Gemini second**: Audio capture and on-device speech recognition start immediately. Gemini connects in the background. If Gemini fails, the session continues with local STT only.

**Partial transcript flush**: SFSpeechRecognizer's `onFinal` only fires after speech pauses. A 2-second flush timer periodically commits partial text to the backend so auto-analysis doesn't wait for silence.

**Audio gate**: Gemini is instructed to stay completely silent. The audio gate is closed by default. Only opens when the physician taps "What did I miss?" for a whispered summary.

**Feature-gated display**: Risk score and differential hidden until the model detects actual clinical features (not just the 7.4% base rate intercept with zero features).

## HIPAA

**Prototype only.** Patient audio goes to Google (Gemini) and Apple (SFSpeechRecognizer server fallback). Text goes to Railway. None have a BAA.

Use with simulated patients only.

Production path: on-device STT only (no server fallback) + text-only to HIPAA-compliant API (Claude with Anthropic BAA). Audio never leaves device.

## Backend

The PA backend lives in a separate repo: [sayvant/predictive-analytics](https://github.com/sayvant/predictive-analytics)

Primary endpoint: `/comprehensive_analysis` — returns prediction, differential, guidance, workup, uncertainty in one call.

```bash
curl -X POST https://predictive-analytics.up.railway.app/comprehensive_analysis \
  -H "X-CDS-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "chest pain for 2 hours radiating to left arm"}'
```

## License

Original VisionClaw code: Meta Platforms license (see LICENSE file).
Sayvant modifications: proprietary.
