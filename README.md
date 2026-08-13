# Avila Voice

**100 % local dictation for macOS — speech-to-text and AI rewriting, fully on-device.**

Avila Voice is a menu bar app that turns your speech into polished text anywhere you can
type. Unlike cloud dictation tools, *everything* runs on your Mac: transcription uses
Apple SpeechAnalyzer or NVIDIA Parakeet v3 (Core ML), and AI post-processing uses Apple
Foundation Models or a local open-weights LLM. No cloud. No account. No telemetry. Free.

## Features

- 🎙️ **Push-to-talk or toggle** recording with a customizable hotkey — including extra
  mouse buttons (e.g. Logitech MX Master)
- 💊 **Minimal pill HUD** at the bottom of your screen with live waveform; hover to switch
  modes or copy the last transcript
- ⌨️ **Types anywhere**: inserts text at the cursor in any app (clipboard fallback)
- 🤖 **AI modes**, each with its own instructions: Clean-up (default), E-Mail,
  Translate (DE ↔ EN) — plus unlimited **custom modes** with your own prompts
- 🧠 **Context aware** (per mode, opt-in): frontmost app, selected text, clipboard, and
  screen text via on-device OCR
- 📖 **Personal dictionary** for names and technical terms
- 🕐 **History** of your last 5 dictations, 📊 **stats** (words, time saved vs. typing)
- 🇩🇪🇬🇧 German + English with automatic language detection
- 🔒 **Local only**: audio and text never leave your Mac

## Requirements

- Apple Silicon Mac (M1 or newer)
- macOS 26 (Tahoe) or newer

## Install

Download the latest `AvilaVoice.app` from
[Releases](../../releases) and move it to `/Applications`. The app is not notarized
(free software without an Apple Developer subscription), so macOS blocks the first
launch: open it once, then go to **System Settings → Privacy & Security** and click
**"Open Anyway"**.

On first launch, grant the requested permissions: Microphone, Accessibility (to type for
you), Input Monitoring (global hotkeys), and — only if you enable screen context —
Screen Recording.

## Build from source

No Xcode required — the Command Line Tools are enough:

```bash
xcode-select --install   # if you don't have the CLT yet
git clone https://github.com/oyavuz-evo27/avila-voice.git
cd avila-voice
make run
```

## Speech-to-text engines

| Engine | Best for | RAM |
|---|---|---|
| Apple SpeechAnalyzer (default) | clean speech, low-memory Macs | ~0 (system-managed) |
| NVIDIA Parakeet TDT 0.6B v3 (Core ML) | spontaneous speech with filler words | ~1–2 GB |

## AI engines

| Engine | Best for | RAM |
|---|---|---|
| Apple Foundation Models (default) | instant availability, low-memory Macs | ~0 (system-managed) |
| Qwen3.5-4B (optional download) | higher quality rewriting | ~2.5 GB |
| Gemma 4 12B (optional download) | best German quality (32 GB+ Macs) | ~7 GB |

## License

[MIT](LICENSE)
