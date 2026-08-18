# Ideen-Backlog — Wettbewerbsanalyse 18.08.2026

Quellen: Wispr Flow, Spokenly, VoiceInk, Superwhisper, Aqua Voice, MacWhisper, Voicely, Apple-Diktat
macOS 26 (Websites, Changelogs bis 17.08.2026). Alle Punkte sind LOKAL umsetzbar.
Aufwand: S = 1–2 Sessions · M = 3–5 · L = mehrwöchig. Sortiert nach Nutzen für Onurs Alltag
(Controlling/QM, viel E-Mail, DE/EN).

| # | Idee | Vorbild | Aufwand |
|---|---|---|---|
| 1 | **Edit-Modus auf markiertem Text** — Auswahl + Hotkey + sprechen („kürzer", „auf Englisch", oder direkt die korrigierte Fassung); Undo-Stack | Aqua Edit Mode, Wispr Command Mode | M |
| 2 | **Editier-Sprachbefehle + Backtrack + „abschicken"** — „neuer Absatz", „lösche den letzten Satz", „äh nein …" auflösen, ⌘↩ per Wort | Wispr Smart Formatting, Aqua „send it" | S–M |
| 3 | **Snippets mit Trigger-Phrase** — „meine Signatur", „QM-Hinweis Revision" → Textbaustein (vor dem LLM ersetzt) | Wispr Snippets | S |
| 4 | **Auto-Modus je App/URL + Trigger-Wort am Diktatanfang** — Outlook→E-Mail, Teams→locker, Excel→Zahlen; „Mail: …" überschreibt | Spokenly, VoiceInk Power Mode | S–M |
| 5 | **Wörterbuch lernt aus Korrekturen** + Ersetzungsregeln + Priorität | Wispr Dictionary Auto-Learn | M |
| 6 | **DE/EN sauber**: Sprach-Picker im Hover, Auto-Detect pro Session, „Englisch:"-Trigger; Parakeet ohne Locale lässt Mischsätze zu | Wispr, Aqua | S–M |
| 7 | **Zahlen/Datum/Währung DE normalisieren** — „zwölftausendfünfhundert Euro"→„12.500,00 €", „KW 34", Formatbefehle „als Aufzählung" | Aqua „abbreviate" | S |
| 8 | **Ton je App-Kategorie** (formal/neutral/locker als Regler) | Wispr Personalized Style, Superwhisper Tone | S |
| 9 | **Cursor-naher Text + Bildschirm-Namen als STT-Vokabular** | Wispr Variable Recognition, Aqua Deep Context | M |
| 10 | **Verlauf-Upgrade**: Audio-Playback, Suche, „mit anderem Modus neu verarbeiten", Roh-vs-KI-Diff, „KI rückgängig" | Superwhisper, Spokenly | M |
| 11 | **Insertion-Panel** (kein Textfeld → schwebendes Panel) + Scratchpad ⌥S | Spokenly, Wispr | S–M |
| 12 | **Assistant-Modus** — Frage → Antwort im Panel mit Bildschirm-Kontext („fasse den Mail-Thread zusammen") | VoiceInk | M |
| 13 | **Statistik & Streaks** — Heatmap, App-Aufschlüsselung, meistkorrigiertes Wort, Share-Card | Wispr Insights | S–M |
| 14 | **Datei-/Meeting-Transkription lokal** mit Sprechertrennung (FluidAudio Diarizer), Teams via ScreenCaptureKit, Zusammenfassung per Ollama | Wispr Notetaker, Voicely | L |
| 15 | **Aktionen & Integrationen** — Apple-Shortcut/Shell nach Diktat, Deep-Links `avila://`, MCP-Tool `ask_user_dictation` für Claude Code | Spokenly Agentic Actions/MCP | M |

Eigene Ideen (nicht bei der Konkurrenz): **Tagesnotiz-Modus** fürs Second Brain (Task-IDs `[T35]`,
Projektzuordnung, Prioritäts-Emojis) · **QM-Modus** (Anweisungs-Formulierungen im Vogelsang-Stil).

Bonus (S): Flüster-Modus (Auto-Gain), „buchstabiere B-M-W"-Parser, Medien pausieren bei Aufnahme,
kurze stille Clips verwerfen, Cleanup-Stufe None/Light/Medium/High als globaler Regler.

Beobachtung: Echten Sprachwechsel **pro Wort** kann keine der Apps — Wispr detektiert pro Session.
