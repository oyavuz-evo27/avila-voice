# Engine-Benchmark — 17.08.2026 (Mac mini M4 Pro 48 GB, macOS 26.5.2, Alltagslast)

Gemessen von einem Benchmark-Agenten mit echten Skripten (Apple SpeechAnalyzer, FluidAudio/Parakeet,
Ollama /api/chat, Apple Foundation Models). Rohdaten lagen im Session-Scratchpad; hier die Essenz.

## A — Spracherkennung (6 deutsche TTS-Diktate mit Fachbegriffen, je 3 Läufe)

| Engine | Latenz Ø warm | WER Ø | Notizen |
|---|---|---|---|
| Apple SpeechAnalyzer | 124 ms | 11,9 % | bessere Satzzeichen, unterdrückt Füller selbst; „PA00", „Cash", „Decloyment" |
| **NVIDIA Parakeet v3** | **88 ms** | **7,5 %** | trifft PE100, Cache, Deployment, Liefertermintreue; Kommaketten statt Punkte; 15 s Kaltladen |

Beide verfehlen EvoNet, Supabase, ClimatePartner → Wörterbuch + LLM fangen das ab.
Echtes 9-s-Diktat: Apple inhaltlich richtig („was"), Parakeet 1 Wortfehler („dass") — kein Modell ist überall vorn.

## B — KI-Bereinigung (4 Rohdiktate, App-Prompt, Qualität 0–40)

| Modell | RAM | Latenz kurz / mittel / lang | Tok/s | Qualität |
|---|---|---|---|---|
| **gemma4:26b-mlx** | 17,5 GB | **0,3 / 1,6 / 5,9 s** | 48 | **40/40** |
| gemma4:12b | 8,1 GB | 1,0–2,6 / 5,4 / 16,9 s | 21 | **40/40** |
| gemma3:12b | 7,8 GB | 1,2–2,6 / 5,8 / 17,2 s | 20 | 33 (Zahlenfehler 96→69) |
| qwen3.6:27b | 17,5 GB | 2,2–5,0 / 11,6 / 32,8 s | 10 | 36 (formuliert zu stark um) |
| gemma4:e4b | 9,6 GB | 0,6–1,1 / 2,5 / 9,1 s | 42 | 35 (Zahlen instabil) |
| gemma3:4b | 3,8 GB | 0,6–0,9 / 2,0 / 5,9 s | 55 | 17 (unbrauchbar) |
| Apple Foundation Models | 0 | 0,6 / 1,3 / 4,9 s | – | 13,5 (Rollen-Ausbrüche, Zahlen 96→69, 2025→„25.000") |

## Empfehlung

- **Mac mini (48 GB):** STT **Parakeet v3** · LLM **gemma4:26b-mlx** (beste Qualität UND schnellstes brauchbares
  Modell dank MoE+MLX; 17,5 GB RAM). Bei RAM-Druck: gemma4:12b (gleiche Qualität, 3× langsamer).
- **8-GB-MacBook Air:** STT Apple SpeechAnalyzer · LLM Apple Foundation Models (kein Ollama-Modell passt;
  gemma3:4b qualitativ unbrauchbar, gemma4:e4b belegt 9,6 GB). Vorbehalt bei Zahlen/Fachbegriffen.
- Apple FM taugt nur als Notfall-Fallback ohne Ollama.
