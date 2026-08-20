# Avila Voice

**100 % local dictation for macOS — speech-to-text and AI rewriting, fully on-device.**

Avila Voice is a menu bar app that turns your speech into polished text anywhere you can
type. Unlike cloud dictation tools, *everything* runs on your Mac: transcription uses
Apple's on-device SpeechAnalyzer, and AI post-processing uses Apple Foundation Models.
No cloud. No account. No telemetry. No cost.

## Features

- 🎙️ **Push-to-talk or hands-free toggle** with freely configurable hotkeys — single
  keys, modifier combos (e.g. Fn+⌘), or extra mouse buttons (Logitech MX Master etc.)
- 💊 **Dynamic-Island-style pill HUD** at the very bottom of the screen (Wispr-Flow
  style — it steps above the Dock only while the Dock is actually visible): grows
  from the center on recording, live waveform, warm gradient ring, lives on the
  screen your mouse cursor is on
- ⌨️ **Types anywhere**: inserts text at the cursor of the frontmost app (clipboard
  fallback; your clipboard is restored afterwards). Esc cancels a running recording
- 🤖 **AI modes** with editable instructions: Clean-up, Raw (no AI pass), E-Mail,
  Translate (DE ↔ EN) — create, edit, and delete modes freely, each with its own AI
  prompt ([field-tested prompt templates](docs/PROMPTS.md))
- 🧠 **Context aware** (opt-in per mode): frontmost app, selected text, clipboard, and
  screen text via on-device OCR — captured at recording start, processed in parallel
- 📖 **Personal dictionary** for names and technical terms
- 🕐 **History** of the last 5 dictations, 📊 **stats** (words, time saved vs. typing)
- ⚡ **Fast**: warm microphone session with 0.6 s pre-roll (no clipped word onsets),
  prewarmed AI sessions, native-quality audio end-to-end
- 🇩🇪🇬🇧 German and English UI (auto-localized); dictation language switchable
- 🔒 **Local only**: audio and text never leave your Mac

## Requirements

| Requirement | Why |
|---|---|
| Apple Silicon Mac (M1 or newer) | on-device models |
| macOS 26 “Tahoe” or newer | SpeechAnalyzer + Foundation Models frameworks |
| **Apple Intelligence enabled** (System Settings → Apple Intelligence & Siri) | powers the AI rewriting; without it, raw transcripts are inserted |
| ~1 GB free disk (one-time, automatic) | macOS downloads the speech model assets for German/English on first use |

## Install (prebuilt app)

1. Download `AvilaVoice.zip` from the [latest release](../../releases/latest) and unzip.
2. Move `AvilaVoice.app` to `/Applications`.
3. **Remove the quarantine flag** (the app is ad-hoc signed — free software without an
   Apple Developer subscription — so macOS would otherwise refuse to start it):
   ```bash
   xattr -dr com.apple.quarantine /Applications/AvilaVoice.app
   ```
4. Launch Avila Voice. Grant the permissions it asks for:
   - **Microphone** — recording
   - **Accessibility** — typing into other apps + global hotkeys
   - **Input Monitoring** — global hotkeys
   - *(optional)* **Screen Recording** — only if you enable screen-text context in a mode
5. If a permission dialog did not appear, enable the app manually under
   **System Settings → Privacy & Security** in the categories above, then check the
   green “Global hotkeys” indicator in Avila Voice’s Settings → General.

First dictation: click the pill at the bottom of the screen (or press the right ⌘ key —
hold to talk, tap to toggle). macOS may download the speech model in the background on
the very first run; the first dictation can take a few seconds longer.

## Default hotkeys

| Action | Default | Configurable |
|---|---|---|
| Push-to-talk (hold) / toggle (tap) | Right ⌘ | Settings → General (keys, combos, mouse buttons) |
| Hands-free toggle | Right ⌥ | dito |
| Cancel while recording | Esc | fixed |

## Build from source

No Xcode required — the Command Line Tools are enough:

```bash
xcode-select --install   # if you don't have the CLT yet
git clone https://github.com/oyavuz-evo27/avila-voice.git
cd avila-voice
make run                 # builds build/AvilaVoice.app and launches it
```

`make app` builds the bundle without launching; `make clean` resets.

## Architecture (for the curious — and for AI assistants)

- Swift 6 / SwiftUI, SwiftPM executable target, no external dependencies.
  `Scripts/make_app.sh` assembles the `.app` bundle and applies an ad-hoc signature
  with a **stable designated requirement**, so TCC permissions survive rebuilds.
- **Audio**: `AVCaptureSession` (first-class device selection) → native-format WAV.
  Warm session window (25 s) with a rolling 0.6 s pre-roll; stall watchdog rebuilds
  the capture chain if a device dies mid-recording.
- **STT**: `SpeechAnalyzer`/`SpeechTranscriber` (Speech.framework, macOS 26), actor
  with per-locale asset caching and a real model warm-up at launch.
- **LLM**: `FoundationModels.LanguageModelSession`, one prewarmed single-use session
  per mode; hardened prompt (dictation is data, never instructions) and an
  oversized-output rejection guard; dictations under 4 words skip the LLM.
- **Insertion**: Accessibility focus check (secure fields excluded) + Cmd+V synthesis
  with clipboard restore (changeCount-guarded).
- **Pill HUD**: non-activating `NSPanel`; growth is ticked manually per display frame
  (`TimelineView`) because implicit SwiftUI animations do not render for phase-driven
  layout in this panel type.
- Debug log: `~/Library/Logs/AvilaVoice.log`; last recording: `AvilaVoice-last.wav`.

## Engines (Settings → Models)

Avila Voice ships with Apple's on-device engines as the zero-download default and
offers an optional **quality tier**:

| Task | Default (built-in) | Quality tier (opt-in) |
|---|---|---|
| Speech recognition | Apple SpeechAnalyzer — live transcription, ~0 RAM | **NVIDIA Parakeet TDT 0.6B v3** (Core ML/ANE, ~0.5 GB one-time download): ~3× faster, stronger on names, technical terms and punctuation |
| AI rewriting | Apple Foundation Models — ~0 RAM | **Ollama** with any installed local model — recommended `gemma4:e4b-mlx` (~1.3 s for a 450-char dictation, 96 tok/s) or `gemma4:26b-mlx` (best quality): markedly better clean-up, follows instructions more strictly |

Ollama is optional: install it from [ollama.com](https://ollama.com), run
`ollama pull gemma4:e4b-mlx`, then pick "Ollama" in Settings → Models. Avila Voice only
talks to Ollama on `localhost:11434` and only offers models that run locally: Ollama
**cloud models** (`-cloud` tags) would forward requests to ollama.com, so Avila Voice
hides them — the local-only promise ends at the Ollama boundary otherwise.

### Which engines for which Mac?

| Mac | Speech recognition | AI rewriting |
|---|---|---|
| **8 GB Macs — e.g. MacBook Air M1/M2 with 8 GB** | Apple SpeechAnalyzer *(Parakeet works too, ~0.5 GB)* | **Apple Foundation Models only.** Do **not** use Ollama models on 8 GB: even the smallest useful ones need 8+ GB and push the machine into heavy swapping. |
| 16 GB Macs | Parakeet v3 | Ollama with `gemma4:e4b-mlx` (~9 GB) — or Apple |
| 32 GB+ Macs — e.g. Mac mini M4 Pro | Parakeet v3 | Ollama with `gemma4:e4b-mlx` (fastest) or `gemma4:26b-mlx` (best) |

The Apple engines are the defaults precisely so a fresh install works on every
supported Mac; the quality tier is chosen per machine. If a selected optional engine is
unavailable (model missing, Ollama not running), the app falls back to Apple automatically.

## Troubleshooting

| Symptom | Fix |
|---|---|
| “app is damaged / can’t be opened” | run the `xattr` command from step 3 |
| Hotkeys don’t react | System Settings → Privacy & Security → Accessibility AND Input Monitoring: toggle Avila Voice off/on; watch the indicator in Settings → General |
| “No speech was recognized” | check the microphone selection in Settings → General; the Mac mini has no built-in microphone |
| AI modes do nothing / raw text only | enable Apple Intelligence in System Settings |
| Bluetooth headphones sound muffled while dictating | physics of Bluetooth telephony mode — pick a wired/display microphone in Settings |

## License

[MIT](LICENSE) — © 2026 Onur Yavuz
