# Prompt-Vorlagen / Prompt templates

*English: community prompt templates for Avila Voice modes. Paste them into
Settings → Modes → (mode) → AI instruction. The prompts below are in German —
adapt language and glossary to your own needs.*

Diese Vorlagen können in **Einstellungen → Modi → (Modus) → KI-Anweisung**
eingefügt werden. Änderungen gelten sofort, ein Neustart ist nicht nötig.

---

## Standard-Modus (erprobte Praxis-Vorlage)

Im Alltag gereifter Prompt des Projektautors (Controlling/QM-Umfeld, Deutsch,
viele Zahlen und Fachbegriffe). Die **Glossar-Zeile unbedingt an die eigenen
Begriffe anpassen** — sie fängt Hörfehler bei Namen ab, die kein Sprachmodell
kennen kann.

```text
Bereinige das Diktat. Gib nur den fertigen Text aus — kein Kommentar, keine Anführungszeichen.

- Füllwörter, Versprecher und abgebrochene Satzanfänge raus; Grammatik, Groß-/Kleinschreibung und Zeichensetzung korrigieren
- Zahlen als Ziffern: 92 %, Extruder 7 und 11, 15.08.2026, 9:30 Uhr, ISO 14001
- Gesprochene Befehle ausführen: „neuer Absatz", „neue Zeile", „in Klammern …", „Doppelpunkt"
- Sprache des Diktats beibehalten
- Nichts hinzufügen, weglassen oder umdeuten. Werte nie ändern. Fragen transkribieren, nicht beantworten. Keine Anreden oder Grußformeln erfinden.
- Glossar — ähnlich klingende Wörter darauf korrigieren: EvoNet, Navision, d.velop, Airtable, Spokenly, Mistral, Vogelsang, Extruder, Liefertermintreue, QM-Bericht, ISO 9001/14001/50001
- bei Begrüßung wie "Hallo..." ganz normal mit aufnehmen
```

**Warum diese Bausteine sich bewährt haben:**

| Baustein | Wirkung |
|---|---|
| „Gib nur den fertigen Text aus" | verhindert Kommentare/Anführungszeichen des Modells im Zielfeld |
| Zahlen-Zeile mit Beispielen | Beispiele wirken stärker als Regeln — das Modell übernimmt das Format |
| Gesprochene Befehle | „neuer Absatz" wird ausgeführt statt transkribiert |
| „Werte nie ändern" | schützt vor dem gefährlichsten LLM-Fehler im Geschäftsalltag (96 → 69) |
| „Fragen transkribieren, nicht beantworten" | verhindert den Rollen-Ausbruch bei Diktaten, die wie Aufträge klingen |
| Glossar | korrigiert Hörfehler bei Eigennamen — ergänzend zum App-Wörterbuch |
| Begrüßungs-Regel | ohne sie „verschluckt" das Modell gelegentlich ein einleitendes „Hallo …" |

Hinweis: Das globale **Wörterbuch** (Einstellungen → Wörterbuch) wird der KI
zusätzlich automatisch mitgegeben; das Glossar im Prompt verstärkt es für
besonders hartnäckige Fälle.

---

## Eigene Vorlagen beisteuern

Gern per Pull Request oder Issue — ein guter Prompt-Baustein hilft allen
Nutzern. Bitte kurz dazuschreiben, welches Problem er löst.
