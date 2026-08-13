# Avila Voice — 100 % lokales Diktier-Tool für macOS

## Ziel
Menüleisten-App für macOS, die Diktate vollständig **on-device** transkribiert (STT) und
per lokalem LLM nachbearbeitet (Modi wie Bereinigung, E-Mail, Übersetzung). Keine Cloud,
keine Telemetrie, keine Kosten. Open Source (MIT) auf GitHub.

Vorbilder: Wispr Flow (UX/Pille), Spokenly (lokale Modelle, Local-Only), VoiceInk (Custom
Modes, Power Mode, Kontext), Voicely (WhisperKit, MIT). Marktlücke: keine dieser Apps
kombiniert lokale STT **und** lokale LLM-Modi out-of-the-box.

## Zielgeräte
| Gerät | Chip/RAM | macOS | Standard-STT | Standard-LLM |
|---|---|---|---|---|
| Mac mini (geschäftlich) | M4 Pro, 48 GB | 26.5 | Parakeet v3 | Qwen3.5-4B (opt. Gemma 4 12B) |
| MacBook Air 2020 (privat) | M1, 8 GB | 27 Beta | Apple SpeechAnalyzer | Apple Foundation Models |

Minimum-Deployment-Target: **macOS 26**.

## Beschlossene Architektur (Grill-Session 13.08.2026)
- **Native Swift/SwiftUI-App**, gebaut **ohne Xcode**: Swift Package (SwiftPM) +
  `Scripts/make_app.sh` setzt das `.app`-Bundle zusammen. Nur Command Line Tools nötig.
- **STT zweigleisig, in Einstellungen wählbar:**
  - Apple **SpeechAnalyzer** (Speech.framework, macOS 26): bestes Deutsch bei sauberer
    Sprache, systemverwaltet ≈ 0 RAM. Default MacBook.
  - **NVIDIA Parakeet TDT 0.6B v3** via FluidAudio (SPM, Core ML/ANE): bestes Deutsch bei
    Spontansprache/Füllwörtern, ~0,3 s für 30 s Audio. Default Mac mini.
  - Deutsch + Englisch mit Auto-Erkennung. Modelle warm halten (Kaltstart vermeiden!).
- **LLM zweistufig:**
  - **Apple Foundation Models** (FoundationModels.framework): 0 RAM, sofort da. Default.
    Grenzen: 4.096 Token, Guardrails.
  - **Qwen3.5-4B 4-bit** als optionaler Download (~2,5 GB); auf dem Mini zusätzlich
    **Gemma 4 12B** (~7 GB) wählbar. Runtime: MLX bevorzugt; falls Metal-Toolchain ohne
    Xcode klemmt → llama.cpp mit embedded Metal-Source als Fallback. (Phase 2)
- **Modi v1:** Standard-Bereinigung · E-Mail · Übersetzen (DE↔EN, Zielsprache einstellbar)
  · eigene Modi (Name + System-Prompt) frei anlegbar.
- **Kontext pro Modus schaltbar:** aktive App, markierter Text, Zwischenablage,
  Screenshot→Text per Vision-OCR. Vision-LLM (echtes Bildverständnis) = spätere Ausbaustufe.
- **Pille:** dauerhaft sichtbar, unten mittig, ganz klein; wächst bei Aufnahme, zeigt
  Sprachbalken. Hover-Panel: Moduswechsel + letztes Transkript mit Kopier-Button (auch
  abgebrochene/nicht eingefügte). Während Aufnahme: Beenden/Abbrechen/Moduswechsel.
- **Einfügen:** fokussiertes Textfeld → automatisch an Cursor (AX-API, Paste-Fallback,
  Clipboard danach wiederherstellen); sonst wartet der Text in der Pille.
- **Hotkeys:** Push-to-talk (halten) + Toggle (kurz), frei belegbar inkl. Maustasten
  (CGEventTap; MX Master 4: von Logi Options+ belegte Tasten dort auf Tastenkombi legen).
  Keine Hotkeys pro Modus.
- **Wörterbuch:** global, eigener Einstellungsbereich; wird als Korrekturliste in den
  LLM-Schritt gegeben.
- **Verlauf:** letzte 5 Diktate (roh + Ergebnis), lokal, löschbar.
- **Statistik:** Wörter + Sprechzeit pro Tag/Woche/Monat; Ersparnis gegen einstellbare
  Tippgeschwindigkeit (Default 40 WPM).
- **Sounds** bei Start/Stopp (abschaltbar) · Mikrofonwahl · Login-Start (Default an) ·
  Updates: „Nach Updates suchen" → GitHub-Releases (kein Sparkle in v1).
- **UI:** natives Apple-Design, Liquid Glass, hell/dunkel automatisch. Basis Englisch,
  vollständige deutsche Lokalisierung.
- **Nicht in v1:** Live-Text beim Sprechen, Vision-LLM, Hotkeys pro Modus, Sparkle,
  Meeting-/Datei-Transkription, Agent-Modus, Signierung/App Store.

## Veröffentlichung
- GitHub: öffentliches Repo `avila-voice` unter Account `oyavuz-evo27` (gh-CLI angemeldet)
- Lizenz: MIT · Releases: GitHub Actions baut unsignierte `.app` als Download
  (README erklärt Rechtsklick → Öffnen)

## Benötigte Berechtigungen (beim ersten Start interaktiv erteilen)
Mikrofon · Bedienungshilfen (Texteinfügung) · Eingabemonitoring (globale Hotkeys) ·
Bildschirmaufnahme (nur wenn Screenshot-Kontext aktiviert)

## Build
```bash
make build   # swift build -c release
make app     # .app-Bundle nach build/AvilaVoice.app
make run     # bauen + starten
```

## Sync-Regel
Diese CLAUDE.md wird bei Änderungen gespiegelt nach:
`second_brain/03_Bereiche/Lokal/Avila Voice.md`

## Sync nach oben
Übergeordnete Datei: keine (eigenständiges privates Projekt außerhalb der
Abteilungsstruktur; bewusst kein Eintrag in Projects/CLAUDE.md nötig — bei Bedarf dort
unter „Lokal" ergänzen).

## Session-Log
- **2026-08-13** — Projektstart. Grill-Session (3 Runden, Q1–Q27) abgeschlossen; Recherche
  Konkurrenz-Features (Wispr Flow, Spokenly, VoiceInk, Voicely), lokale STT-Modelle
  (Parakeet v3, SpeechAnalyzer, Whisper, Nemotron) und lokale LLMs (Foundation Models,
  Qwen3.5, Gemma 4) durch Subagenten. Alle Architektur-Entscheidungen fixiert (s. o.).
  Scaffold: SwiftPM-Projekt ohne Xcode, App-Skelett begonnen.
