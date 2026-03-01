# Sayvant CDS Glasses

Real-time clinical decision support whispered to physicians through Meta Ray-Ban glasses during patient encounters. Hands-free, eyes-free, zero workflow disruption.

Forked from [VisionClaw](https://github.com/sseanliu/VisionClaw). Video stripped. Audio pipeline preserved. OpenClaw replaced with Sayvant PA backend.

## How it works

```
Ray-Ban Glasses (mic)
    | Bluetooth audio
iPhone (in pocket)
    | AudioManager: 16kHz PCM -> base64
Gemini Live API (WebSocket)
    | STT + clinical content detection
    | Calls analyze_encounter tool
iPhone: PABackendBridge
    | HTTP POST /cds_whisper
PA Backend (Railway)
    | preprocess() -> guidance_engine -> dedup filter
    | Returns: ask_next + red_flags + completeness_score
Gemini (generates whisper audio)
    | 24kHz PCM -> Bluetooth
Ray-Ban Glasses (speaker)
    -> Physician hears: "Ask about radiation to arm or jaw"
```

## Setup

1. Copy `samples/CameraAccess/CameraAccess/Secrets.swift.example` to `Secrets.swift`
2. Add your Gemini API key from [AI Studio](https://aistudio.google.com/apikey)
3. Add your CDS API key (set as `CDS_API_KEY` in Railway env vars)
4. Open `samples/CameraAccess/CameraAccess.xcodeproj` in Xcode
5. Build and run on iPhone (iOS 17+)

## Key files

| File | What it does |
|------|-------------|
| `Gemini/GeminiLiveService.swift` | WebSocket to Gemini Live API (kept from VisionClaw) |
| `Gemini/AudioManager.swift` | Mic capture + speaker playback with Bluetooth routing |
| `Gemini/GeminiConfig.swift` | Clinical system prompt + PA backend config |
| `Gemini/GeminiSessionViewModel.swift` | Session lifecycle, tool routing |
| `OpenClaw/PABackendBridge.swift` | HTTP client for /cds_whisper endpoint |
| `OpenClaw/ToolCallModels.swift` | analyze_encounter tool declaration |
| `OpenClaw/ToolCallRouter.swift` | Routes Gemini tool calls to PA bridge |
| `Views/CDSSessionView.swift` | Session UI: start/stop, red flags, transcript |

## What was stripped from VisionClaw

- All video/camera code (IPhoneCameraManager, WebRTC, photo capture)
- OpenClaw bridge and execute tool
- Meta DAT SDK wearables registration flow
- Android project
- WebRTC signaling

## Gemini behavior

The system prompt makes Gemini a silent clinical advisor:
- Listens to physician-patient conversation via glasses mic
- Calls `analyze_encounter` after hearing clinical content
- Whispers guidance through glasses speaker (under 15 words)
- Red flags interrupt immediately. Questions wait for pauses.
- Stops suggesting when completeness > 80%

## HIPAA

**Prototype only.** Patient audio goes to Google (Gemini). Text goes to Railway. Neither has a BAA.

Use with simulated patients only.

Production path: on-device STT (`SFSpeechRecognizer`, offline iOS 17+) + text-only to HIPAA-compliant LLM (Claude API with Anthropic BAA). Audio never leaves device.

## Backend

The PA backend lives in a separate repo: [sayvant/predictive-analytics](https://github.com/sayvant/predictive-analytics)

The only coupling is the `/cds_whisper` endpoint:

```bash
curl -X POST https://predictive-analytics.up.railway.app/cds_whisper \
  -H "X-CDS-Key: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text": "chest pain for 2 hours radiating to left arm"}'
```

## License

Original VisionClaw code: Meta Platforms license (see LICENSE file).
Sayvant modifications: proprietary.
