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
  Meeting-/Datei-Transkription, Agent-Modus, Signierung/App Store,
  **STT-Sprach-Auto-Erkennung** (aktuell fester Sprachschalter in den Einstellungen —
  Auto-Erkennung DE/EN ist geplant, Hinweis dazu steht im Settings-UI).

## ⛔ Pille — eingefroren (Onur, 18.08.2026)
Design, Größe, Animation und Positionslogik der Pille sind final und dürfen **nicht** mehr
angefasst werden — außer Onur spricht es ausdrücklich an.
**Positionsregel (Onurs Vorgabe, wie Wispr Flow):** Die Pille sitzt unten mittig auf dem
Bildschirm, auf dem sich der **Mauszeiger** befindet — NICHT dem fokussierten Fenster,
NICHT dem Aufnahmestart. Wechsel erst, wenn die Maus ≥ 1 s auf einem anderen Bildschirm
ist; niemals während Aufnahme/Verarbeitung; Zentrierung auf screen.frame.midX (nicht
visibleFrame). Hintergrund: Fokus-Verfolgung und Aufnahmestart-Sprünge hatten wiederholt
Wandern/Rutschen verursacht (im Log nachgewiesen).

## Veröffentlichung
- GitHub: öffentliches Repo `avila-voice` unter Account `oyavuz-evo27` (gh-CLI angemeldet)
- Lizenz: MIT · Releases: GitHub Actions baut unsignierte `.app` als Download
  (README erklärt Systemeinstellungen → Datenschutz & Sicherheit → „Dennoch öffnen";
  Rechtsklick → Öffnen reicht seit macOS 15 nicht mehr)

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
  Scaffold komplett und **buildfähig** (swift build + make app erfolgreich): Menüleiste,
  Pille (Panel + Waveform + Hover), AudioRecorder (AVAudioEngine → 16-kHz-WAV),
  HotkeyManager (CGEventTap, PTT/Toggle, Maustasten), SpeechAnalyzer-Engine,
  Foundation-Models-Engine, 3 Modi, Texteinfügung (AX + Paste/Clipboard-Restore),
  Verlauf (5), Statistik, Wörterbuch, Settings-Fenster, Release-Workflow.
  Repo öffentlich: https://github.com/oyavuz-evo27/avila-voice
  **Ungetestet zur Laufzeit** — erster interaktiver Test durch User steht aus
  (Berechtigungen: Mikrofon, Bedienungshilfen, Eingabemonitoring).
  Nächste Schritte: Laufzeit-Test + Fehlerbehebung, Hotkey-Recorder-UI, Custom-Modes-UI,
  Parakeet-Engine (FluidAudio), Screenshot-OCR-Kontext, deutsche Lokalisierung,
  MLX-/Qwen-Stufe, erster Release (v0.1.0-Tag).
- **2026-08-13 (Nachmittag)** — App-Icon aus Onurs Amosia-Logo (Waveform) erzeugt:
  Silber/Graphit, macOS-26-Stil (`Scripts/make_icon.swift` → AppIcon.icns +
  Menüleisten-Template-Icon). Diagnose-Skript (`Scripts/diagnose.swift`) bestätigt auf
  dem Mini: Foundation Models VERFÜGBAR, SpeechAnalyzer de/en installiert. App gestartet.
  Hinweis: Ad-hoc-Signatur ⇒ nach jedem Rebuild können Bedienungshilfen/
  Eingabemonitoring-Freigaben neu zu setzen sein (später: eigenes Signatur-Zertifikat).
- **2026-08-13 (Abend)** — Laufzeit-Feedback-Runde mit Onur: Pille sichtbar gemacht
  (Layout-Bug), Multi-Monitor-Folgen, Mikrofonwahl (CoreAudio), deutsche Lokalisierung,
  Pillen-Redesign (Kreis-Buttons links Kopieren/rechts Modi, Sprechblase, Klick auf
  Pille = Aufnahme, Live-Waveform mit Mitten-Gewichtung, langsam driftende
  Schimmer-Segmente 12/17 s, atmende Idle-Umrandung). Hotkey-System ausgebaut:
  Push-to-talk UND Hands-free getrennt konfigurierbar per Hotkey-Recorder
  (Tastatur/Modifier/Maustasten, Esc bricht ab). Modi-Editor: eigene Modi mit
  KI-Anweisung + Kontext-Schaltern pro Modus (aktive App, markierter Text,
  Zwischenablage, Screenshot-OCR via ScreenCaptureKit+Vision — jetzt implementiert).
- **2026-08-13 (Spätabend)** — Qualitätsrunde auf Onurs Wunsch: Design-Agent (15 Befunde)
  + QA-Agent (22 Befunde) → alle 37 behoben, u. a. kritischer Zustandsmaschinen-Crash,
  LLM-Fallback auf Rohtranskript, Kombi-Hotkeys im Recorder, Login-Start (SMAppService),
  Verlauf-Menü, abbrechbare Verarbeitung mit 60-s-Watchdog, Fehler-Bubble, Materialien,
  Dock-/Multi-Monitor-Verhalten, workflow-permissions. Abschließender /code-review
  (Stufe high, 10 Blickwinkel) fand 7 Befunde in der Statistik-Bereinigung → behoben
  (Cutoff relativ zum neuesten Eintrag statt Systemuhr, Prune bei jedem record(),
  Backup-Key für undecodierbare Blobs). Stand: gepusht, App läuft, Onurs
  End-to-End-Test (Hotkey-Freigaben) steht noch aus.
- **2026-08-14 — Debugging-Session mit Onur, Ende: ERSTES ERFOLGREICHES DIKTAT.**
  Behobene Feldprobleme in Reihenfolge: (1) SIGTRAP-Crash bei Screenshot-OCR
  (Vision-Callback auf Background-Queue war MainActor-gebunden → nonisolated ohne
  Completion-Closure). (2) Fehlalarm „Audiogerät geändert" bei jedem Start
  (AVAudioEngineConfigurationChange feuert auch beim Engine-Start). (3) Kombi-Hotkeys:
  erst gar nicht aufnehmbar, dann reihenfolgeabhängig → HotkeyBinding.modifierKey um
  extraFlags erweitert (handgeschriebenes Codable), Matching reihenfolgeunabhängig.
  (4) Kernproblem „Sprache nicht erkannt"/tote Waveform: AVAudioEngine lieferte auf
  macOS 26 trotz erfolgreicher AUHAL-Geräteumleitung (Status 0!) und erteilter
  Mikro-Berechtigung NULL Puffer → **AudioRecorder komplett auf AVCaptureSession
  umgeschrieben** (native Geräteauswahl per UID, 16-kHz-Format direkt, Konverter nur
  Fallback). AirPods bleiben dadurch unangetastet (kein HFP-Umschalten mehr).
  Dazu: DebugLog nach ~/Library/Logs/AvilaVoice.log, Stall-Watchdog mit
  Session-Rebuild, explizite Mikrofonanfrage beim Start, Leeraufnahme-Guard (0,3 s),
  Watchdog 30 s. Wichtige Debug-Lehren: `log` ist in zsh ein Builtin
  (→ /usr/bin/log), Onurs Setup: AIRHUG 21 (USB-Konferenzmikro) als Wunschgerät,
  „Microsoft Teams Audio"-Loopback existiert als Falle für Default-Input.
  Onurs Erstest erfolgreich; ausführlicher Test steht aus.
- **2026-08-14 (Nachmittag) — Dynamic-Island-Animation gelöst (Onur: „einfach perfekt").**
  Harte Lektionen: (1) In diesem NSPanel/NSHostingView-Setup rendert WEDER
  `.animation(value:)` NOCH `withAnimation` die phasengetriebene Größenänderung —
  die Pille wächst deshalb über einen **manuellen Ticker** (TimelineView(.animation),
  easeOutBack 0,38 s, pausiert wenn eingependelt); Beweis über Screenshot-Sonde
  (DebugHooks: avila.debug.animate/dictate + Pixel-Messung). (2) Sichtbarkeit zählt:
  Auf dunklen Bildschirmen trägt der FARBRING die Animation — beim Stopp bleibt er
  jetzt an der schrumpfenden Kapsel und blendet über 0,35 s aus (getickte Opacity)
  statt eingefroren entfernt zu werden. (3) AVCaptureSession.stopRunning blockierte
  den Main-Thread beim Stopp → läuft jetzt auf Background-Queue (Delegate vorher
  synchron abgehängt). (4) Übergänge richtungsabhängig (Aktivieren knackig, Beenden
  weich ausklingend); Ring = geschlossener Dreifarb-Verlauf (Orange/Rosé/Lila),
  14-s-Rotation, 1,5-s-Atmen; Idle-Balken pulst alle ~5 s komplett im Verlauf.
  Perf-Runde 1: Kontext parallel zur STT, vorgewärmte FM-Session pro Modus,
  Locale-Cache, Stufen-Timing im DebugLog. Performance-Agent zur Tiefenanalyse läuft.
- **2026-08-14 (Abend) — v0.1.0 VERÖFFENTLICHT, Projekt geht in Onurs Testphase.**
  Perf-Agent-Analyse (gemessen): LLM = ~80 % der Latenz (350–1160 ms), STT nur
  65–160 ms → Maßnahmen: LLM-Skip <4 Wörter (behebt auch Sprachflip-Bug bei
  Kurzdiktaten), echter STT-Modell-Warmlauf, Kontext-Erfassung beim Aufnahme-START,
  warme Capture-Session (25 s) + 0,6-s-Pre-Roll (Wortanfänge!), native
  Aufnahmequalität statt früher 16-kHz-Downsample. Sicherheits-Fix: LLM-Rollen-
  Ausbruch (Diktat klang wie Auftrag + Clipboard-Kontext → Modell echote Kontext
  und schrieb Korrekturliste) → PromptBuilder.policy engine-seitig an jede
  Modus-Anweisung angehängt + Notbremse (Ausgabe >3× Transkript verworfen).
  Modi voll verwaltbar (auch Builtins löschbar, persistiert). Accessories exakt
  zentriert/symmetrisch. README release-tauglich (xattr-Quarantäne-Schritt!),
  **Release v0.1.0 mit AvilaVoice.zip via GitHub Actions gebaut**:
  https://github.com/oyavuz-evo27/avila-voice/releases/tag/v0.1.0
  Onur testet jetzt 1–2 Wochen im Alltag (Ziel: Wispr-Flow-Abo ersetzt, „90 %
  genauso gut"); Wochenende: Installation auf privatem MacBook Air M1 nach README.
  Nächster großer Baustein auf Abruf: **Parakeet-v3-Engine** (Erkennungsqualität,
  Fall „Modell→Hotel"), danach MLX-LLM-Stufe (Qwen3.5-4B/Gemma 4).
- **2026-08-17 — Qualitätsstufe gebaut (Onur: „beide einrichten").** Perf-Runde 2
  (Messwerte der Testphase: LLM ~85 % der Latenz; Kontext = Kostentreiber →
  Standard-Modus ohne Kontext, Budget gekürzt), Live-Transkription im Hintergrund
  (LiveTranscriber, SpeechAnalyzer-Stream, volatile results; UI-Anzeige auf Onurs
  Wunsch entfernt), lebendigere Waveform bei fixer Pillengröße, LLM-Ausgabe-Streaming
  (unsichtbar). **Engines wählbar (Settings → Modelle):** STT Apple ↔ **Parakeet v3**
  (FluidAudio, ~470 MB int8, ModelStore mit Fortschritt; Direktvergleich auf echter
  32-s-Aufnahme: 166 ms vs. ~470 ms, besser bei Namen/Zeichensetzung, Apple teils
  besser bei Satzstruktur) · LLM Apple ↔ **Ollama** (lokal, jedes installierte Modell,
  Empfehlung gemma4:12b; getestet gemma4:12b + qwen3.6:27b: deutlich bessere
  Bereinigung, kein Rollen-Ausbruch, ~4 s warm). **Wichtige Lehre:** eingebettetes MLX
  scheitert ohne Xcode (SwiftPM kann Metal-Shader nicht kompilieren — offiziell
  dokumentiert); Ollama war auf Onurs Mini ohnehin installiert (gemma4:12b/26b,
  qwen3.6:27b, gemma3) → pragmatisch die bessere Wahl. RAM-Hinweis: Ollama-Modelle
  belegen 8–17 GB — für den 8-GB-MacBook Air bleibt Apple der Standard.
  Debug-Hook avila.debug.installParakeet. Alles gepusht; noch kein neuer Release-Tag.
- **2026-08-17 (Abend) — v0.2.0 veröffentlicht.** Benchmark-Agent (docs/BENCHMARK-2026-08.md):
  STT Parakeet 88 ms/7,5 % WER vs. Apple 124 ms/11,9 %; LLM gemma4 (12b/26b-mlx) 40/40
  Qualität, Apple FM 13,5/40 (Rollen-Ausbrüche, Zahlenfehler). Nachmessung auf Onurs
  echtem Text: **gemma4:e4b-mlx** 1,3 s / 96 t/s bei fast gleicher Qualität → neuer
  Standard auf dem Mini (26b-mlx 2,5 s als Qualitäts-Option). Erkenntnis: Zeit ist reine
  Generierung (Prompt-Cache 0 s), num_ctx wirkungslos → Tokens/s entscheiden. Wörterbuch
  mit Onurs Fachbegriffen vorbelegt. Bugs: Waveform ragte beim Schrumpfen heraus
  (Clip auf getickte Kapsel + Balken-Kollaps beim Stopp); Pille rutschte seitlich
  (Ursache: Zentrierung auf visibleFrame.midX + 1-s-Follow-Tick → jetzt screen.frame.midX
  und Neupositionierung NUR bei echtem Bildschirmwechsel, geloggt). make_app.sh kopiert
  jetzt alle SwiftPM-Bundles (Hub/Crypto für Parakeet-Download). Onur: „deutlich besser,
  Pille bewegt sich nicht" → Release für MacBook-Installation.
