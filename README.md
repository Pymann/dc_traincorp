# dc_traincorp — Trainingskorpora und Trainingskette

Alles, was das Training der `prophecy`-Modelle von DataCreatures braucht, in
einem Paket, das für sich allein läuft: Korpora, Namens- und Markenlisten,
Cluster, die Trainings-Apps und ein GitHub-Workflow, der die Kette ausführt.

**Keine Spieldaten.** Das Training liest ausschließlich Korpusdateien und
`prophecy/data`; es öffnet ausschließlich `prophecy_*`-KV-Stores. Kreaturen,
Konten, Inventare sind nicht enthalten und nicht nötig.

## Was hier liegt

| Pfad | Inhalt |
|---|---|
| `itemgen/data/items_augmented.txt` | Rezepte + Eingabezeilen (259 Rezepte, 5.696 Samples) |
| `discovergen/data/discoveries_augmented.txt` | Fund- und Entdeckungsbeispiele (25.000) |
| `data/skill_corpus.txt` | 253 Fertigkeiten × 60 Beispiele |
| `data/combat_skill_corpus.txt` | 166 Kampffertigkeiten × 60 Beispiele |
| `data/combat.txt` | Handbestand + erzeugte Chance/Wucht-Beispiele |
| `prophecy/data/` | Namen, Marken, Cluster, Domänen, Regellisten |
| `prophecy/sources/` | Modell, Trainer, Köpfe, Inferenz |
| `korpusgen/` | der Korpus-Erzeuger (aiml, JIT) |
| `sources/shared/` | die Modelldefinitionen, die der Abschluss braucht (nur Datenformen) |
| `exodus-*.json` | je ein Build-Ziel; keine absoluten Pfade |

Die Verzeichnisstruktur entspricht der im Spiel-Repo, weil die Apps ihre
Datenpfade fest verdrahtet tragen (`prophecy/data/...`,
`itemgen/data/items_augmented.txt`). Wer hier umbenennt, bricht sie.

## Die Kette

Die Reihenfolge ist nicht beliebig — jede Stufe sitzt auf der vorigen.

| # | Ziel | Binary | Artefakt |
|---|---|---|---|
| 1 | `exodus-prophecy.json` | `prophecy_build` | `prophecy_atlas`, `prophecy_vocab` |
| 2 | `exodus-prophecy-pretrain.json` | `prophecy_pretrain` | `prophecy_embedding_weights` |
| 3 | `exodus-prophecy-item-head.json` u. a. | `prophecy_train_*_head` | die fünf Köpfe |
| 4 | `exodus-prophecy-train-transformer.json` | `prophecy_train_transformer` | `prophecy_transformer_weights` |
| 5 | `exodus-prophecy-chance-kopf.json` | `prophecy_train_chance_kopf` | `prophecy_chance_head` |

Dazu zwei Prüfungen, die keine Gewichte brauchen:

* `rezept_probe` — Datenregeln: jede Rezeptzutat ist ein echter Stoffname,
  liegt in einem Welt-Cluster, `kern` ⊆ `materials`, die Regellisten unter
  `prophecy/data/rules/` nennen echte Stoffnamen. 2.497 Prüfungen.
* `prophecy_gate_korpus` — zählt Korpuswörter ohne Atlas-Token und lässt jede
  echte Trainingsfolge durch die Regel laufen. Braucht einen Atlas, läuft also
  **nach** Schritt 1.

## Der Workflow

`.github/workflows/training.yml`, nur von Hand auslösbar
(`workflow_dispatch`). Eingaben: welcher Teil der Kette, Epochen, Lernrate,
Stapelgröße, und die Run-ID eines früheren Laufes, dessen `aiondb` fortgesetzt
wird.

Ergebnis jedes Laufes: zwei Artefakte — `aiondb` (die KV-Stores) und
`berichte` (alle Logs). Ein Folgelauf nimmt die `aiondb` des Vorlaufs über
seine Run-ID entgegen; so lässt sich die Kette über mehrere Läufe verteilen.

### Zwei Voraussetzungen

1. **Geheimnis `AIML_TOKEN`.** Der aiml-Übersetzer liegt im privaten Repo
   `Pymann/aiml`; der Workflow checkt es mit diesem Token aus. Ein
   Fine-grained-PAT mit Leserecht auf genau dieses Repo genügt.
2. **Ubuntu 24.04.** aiml bindet LLVM 18 ein und zieht rund 30 versions- und
   digest-gepinnte apt-Pakete in einen eigenen Cache (ohne root). Die
   gepinnten Versionen sind Noble-Versionen; auf einem anderen Runner-Image
   schlägt `apt-get download` fehl.

### Warum der aiml-Build gecacht wird

`out/aiml/aiml` und `libaiml.so` sind je rund 90 MB und binden LLVM ein. Der
Cache ist auf den aiml-Commit geschlüsselt: einmal bauen je Commit, danach
laden. Ohne das wäre die Übersetzung die teuerste Zeile des Workflows.

### Grenzen, die man kennen muss

* **6 Stunden je Job.** GitHub kappt dort; der Workflow steht auf 350 Minuten.
  Der letzte vollständige Kettenlauf auf einem Arbeitsplatzrechner lag
  zwischen 00:20 und 11:56 Uhr. Darum ist die Kette in Schritte zerlegt, die
  einzeln laufen und sich über die Run-ID verketten — `alles` ist für kurze
  Epochenzahlen gedacht, nicht für den vollen Lauf.
* **Kein Determinismus-Versprechen über Runner hinweg.** Gleicher Seed, andere
  CPU: die Korpora sind reproduzierbar, die Gewichte nicht bitgenau.
* **Ein Lauf zur Zeit** (`concurrency: training`). Zwei Läufe auf derselben
  Datenbank überschreiben sich die Gewichte.

## Lokal

```bash
# aiml-Venv: bin/aiml + lib/libaiml.so
export AIML_VENV=/pfad/zum/aimlvenv
export AIML="$AIML_VENV/bin/aiml"
export AIONDB_PATH="$PWD/aiondb"

exodus build -c exodus-rezept-probe.json && ./rezept_probe
exodus build -c exodus-prophecy.json     && ./prophecy_build
exodus build -c exodus-prophecy-gate-korpus.json && ./prophecy_gate_korpus
```

`$AIML` und `$AIML_VENV` löst exodus in den Configs auf (aiml spec/68
F68-23) — darum steht hier kein absoluter Pfad.

**Eine Falle:** wird `$AIML` auf einen anderen aiml-Stand umgestellt, ohne
`out/` zu löschen, übersetzt exodus nicht neu, solange die Compiler-Dateizeit
nicht jünger ist als die Objekte. Das Ergebnis sind Objekte des alten
Übersetzers an der neuen Bibliothek — das Binary baut sauber und stürzt beim
Start ab. Bei einem Werkzeugwechsel `rm -rf out`.

## Bekannte Befunde

* **45 der 259 Rezepte** tragen eine Prozessmarke (`iron_craft`,
  `fiber_craft`, `bone_craft` …) als Voraussetzung. Die Trainingsfolge steckt
  sie in einen Abschnitt, den die Regel gegen den *Fertigkeits*-Wortschatz
  prüft, und lehnt sie ab (`gate: 1 echte Trainingsfolgen abgelehnt` bei 300
  Stichproben). Entweder akzeptiert die Regel dort Prozessmarken, oder diese
  45 Rezepte brauchen eine echte Fertigkeit als Voraussetzung.
* Die Meldung **„9 Korpus-Wörter ohne Token"** (`rune_craft`, `iron_craft`, …)
  kam von einem veralteten Atlas und ist nach Schritt 1 verschwunden —
  nachgemessen am 25.11.2026.
