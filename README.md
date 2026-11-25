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

### Voraussetzungen

1. **Ubuntu 24.04.** aiml bindet LLVM 18 ein und zieht rund 30 versions- und
   digest-gepinnte apt-Pakete in einen eigenen Cache (ohne root). Die
   gepinnten Versionen sind Noble-Versionen; auf einem anderen Runner-Image
   schlägt `apt-get download` fehl.
2. **Drei Geheimnisse für kontor** — nur wenn hochgeladen werden soll (siehe
   unten). Ohne sie bricht der Upload-Schritt mit einer klaren Meldung ab; das
   Training selbst läuft trotzdem.

`Pymann/aiml` und `Pymann/exodus` sind öffentlich, der Workflow braucht für
sie kein Token.

exodus wird normal installiert. Bis zum 23.11.2026 fehlten im exodus-Paket
die Unterpakete (`ModuleNotFoundError: No module named 'exodus.core'`); seit
exodus `fd39730` packt `pyproject.toml` alle `exodus*`-Pakete.

aiml wird wie in der aiml-CI gebaut: Systempakete (`g++ dpkg-dev patchelf`),
die gepinnten .debs über `tools/ci/fetch_pinned_debs.py`, `exodus pkg install`,
dann gezielt `exodus.json` (Übersetzer) und `exodus2.json` (Laufzeit). Nicht
`exodus build --all` — das baute jede `exodus*.json` im aiml-Repo, auch asan
und wasm.

## Veröffentlichen nach kontor

Nach einem Lauf, der Gewichte erzeugt hat, packt der Workflow die
`prophecy_*`-Stores und legt sie in die **generische** Ablage von kontor
(`PUT /generic/<pfad>`, `Authorization: Bearer`, mit
`X-Checksum-Sha256`-Prüfung):

```
generic/datacreatures/prophecy/<laufnummer>-<commit>/modelle.tar.gz
generic/datacreatures/prophecy/<laufnummer>-<commit>/modelle.json
generic/datacreatures/prophecy/neueste/modelle.tar.gz
generic/datacreatures/prophecy/neueste/modelle.json
```

`modelle.json` liegt daneben, damit die Herkunft ohne Download lesbar ist:
Laufnummer, Korpus-Commit, aiml-Commit, Schritte, Epochen, die Liste der
Stores, Paketgröße und -Prüfsumme, und wie viele Korpuswörter das Gate ohne
Atlas-Token gefunden hat.

**`neueste` wird nur überschrieben, wenn das Gate grün war und kein Wort
ohne Token meldet.** Kaputte Gewichte als „neueste" zu veröffentlichen wäre schlimmer,
als sie gar nicht zu veröffentlichen; der lauf-eigene Pfad bekommt sie
trotzdem, damit man hineinsehen kann.

Gepackt wird mit `tar --sparse`: ein `kvwal` ist 16 bis 128 MB groß und
besteht überwiegend aus Nullen. Gemessen an einem Lauf mit Atlas, Wortschatz
und Transformer-Gewichten: **111 KB** statt 160 MB.

### Die drei Geheimnisse

| Name | Inhalt |
|---|---|
| `KONTOR_URL` | `https://<host>:8443` — ohne Schrägstrich am Ende |
| `KONTOR_TOKEN` | ein API-Token mit der Rolle `writer` (lesen + schreiben, **kein** Löschen) |
| `KONTOR_CA` | der Inhalt von `tls/ca.crt` der kontor-Installation |

Die CA gehört als Geheimnis hinein und nicht als Datei ins Repo: sie ist zwar
kein Geheimnis im kryptografischen Sinn, verrät aber Host und Aufbau der
eigenen Ablage — und dieses Repo ist öffentlich.

Es wird **nicht** mit `curl -k` gearbeitet. Ohne Zertifikatsprüfung könnte ein
Mittelsmann das Schreibtoken abfangen; das Serverzertifikat trägt die IP im
SAN, also ist echte Prüfung gegen die eigene CA möglich.

Das Token legt man **vom auslieferenden Rechner aus** an — dort liegt
`tls/` mit CA, Schlüsseln und dem Admin-Token, und dort bleibt es auch
(kontor-README: *„`tls/ca.crt` is the only thing clients need, and it stays on
the deploying machine"*). Nicht auf dem Server: dessen Verzeichnis enthält nur
die Zertifikate, die er vorzeigt.

```bash
cd <kontor-checkout>          # hier: projects/python/test/kontor
curl --cacert tls/ca.crt \
     -H "Authorization: Bearer $(cat tls/admin-token)" \
     -H 'Content-Type: application/json' \
     --data '{"label":"gha-training","roles":["writer"]}' \
     https://151.80.143.81:8443/api/v1/tokens
```

Die Antwort zeigt das Geheimnis **einmal** — das gehört nach
*Settings → Secrets and variables → Actions* als `KONTOR_TOKEN`. Widerrufen
später mit `DELETE /api/v1/tokens/<id>`.

### In einem Aufruf

```bash
./tools/einrichten.sh            # --trocken zeigt vorher, was passieren würde
```

Beim ersten Mal fragt es drei örtliche Angaben ab (kontor-Adresse, Pfad zu
`tls/ca.crt`, Pfad zur Datei mit dem Schreibtoken) und merkt sie in
`tools/einrichten.conf`. Die Datei ist **nicht eingecheckt**: dieses Repo ist
öffentlich, und Adresse und Pfade der eigenen Ablage gehören nicht hinein.

Danach in dieser Reihenfolge:

1. **kontor fragen, ob das Token trägt** — vor dem Schreiben, nicht danach.
   Ein Geheimnis, das man nicht mehr auslesen kann, soll nicht schon falsch
   hineingehen.
2. **GitHub-Zugang suchen** — `GH_TOKEN`/`GITHUB_TOKEN`, sonst der
   git-Credential-Helfer (`git credential fill`), sonst Eingabe von Hand. Ein
   PAT lässt sich nur auf github.com erzeugen, eine API dafür gibt es nicht —
   aber meistens liegt schon eines da, sonst könnte man nicht pushen. Reicht
   das Recht nicht, sagt das Skript, welches fehlt, und bricht ab, bevor es
   schreibt.
3. **Setzen und gegenprüfen** — GitHub nennt danach die Namen (nie die Werte).

Das Token steht nie in einem Argument, sondern immer in einer Datei oder auf
der Standardeingabe: Argumente stehen in der Prozessliste und in der
Shell-Historie. Die Eingabe des PAT ist verdeckt.

Wer es einzeln will, nimmt `tools/geheimnisse_setzen.py` direkt — dasselbe
ohne die Abfragen.

### Das Token bleibt nicht öffentlich einsehbar

Dieses Repo ist öffentlich, das Schreibtoken darf es nicht sein. Was dafür
gilt:

* **Actions-Secrets sind auch in einem öffentlichen Repo nicht lesbar** —
  nicht über die Weboberfläche, nicht über die API, auch nicht von
  Mitlesenden. Nur Läufe bekommen sie als Umgebungsvariable.
* Der Workflow ist **`workflow_dispatch`-only**. Ein Fork oder ein Pull
  Request von außen kann ihn nicht auslösen und kommt damit nie an die
  Geheimnisse. Das ist der Grund, warum es keinen `push`-Auslöser gibt.
* GitHub **maskiert** Geheimniswerte in den Logs, und der Upload-Schritt gibt
  das Token ohnehin nie aus — es geht nur als `Authorization`-Kopfzeile in
  `curl`.
* Im Repo liegt es nirgends; `.gitignore` sperrt `*.token`, `tls/` und
  `*secret*` zusätzlich ab.
* **Was in einem öffentlichen Repo dagegen wirklich öffentlich ist: die
  Artefakte eines Laufes.** `aiondb` (die Gewichte) und `berichte` (die Logs)
  kann jeder herunterladen. Ein Token steht in keinem von beiden — aber die
  Modelle liegen damit offen. Wer das nicht will, schaltet das Repo privat;
  der Workflow läuft unverändert.
* Das Token ist **jederzeit ersetzbar**: Die Antwort beim Anlegen enthält eine
  `id`, und `DELETE /api/v1/tokens/<id>` (mit dem Admin-Token) widerruft es.
  Danach ein neues anlegen und das Geheimnis überschreiben.

Die Rolle ist bewusst `writer` und nicht `maintainer`: lesen und schreiben,
**kein Löschen**. Nachgemessen am 25.11.2026 — die generische Ablage hat
ohnehin keinen Löschendpunkt (`DELETE` → `404 no such endpoint`), und ein
Upload mit falscher Prüfsumme wird mit `400 checksum mismatch` abgewiesen.

Prüfen, dass es trägt, bevor ein Lauf startet:

```bash
curl --cacert tls/ca.crt -H "Authorization: Bearer <token>" \
     https://151.80.143.81:8443/api/v1/whoami
# {"name":"gha-training","kind":"token","roles":["writer"]}
```

### Warum der aiml-Build gecacht wird

`out/aiml/aiml` und `libaiml.so` sind je rund 90 MB und binden LLVM ein. Der
Cache ist auf den aiml-Commit geschlüsselt: einmal bauen je Commit, danach
laden. Ohne das wäre die Übersetzung die teuerste Zeile des Workflows.
Gemessen in Lauf #2 (25.11.2026): der Bau dauert auf dem Runner **7 Minuten**,
der Cache ist rund 670 MB groß. Nach einem neuen aiml-Commit baut der erste
Lauf neu.

### Laufzeiten, gemessen

Auf einem Arbeitsplatzrechner am 25.11.2026, im eigenständigen Paket, gegen
eine frische Datenbank. Die Zahlen sind das, woran sich die CI-Planung
entscheidet — der harte Deckel ist die Wanduhr, nicht die Rechenleistung.

| Schritt | je Epoche | Vorgabe | daraus | Speicher |
|---|---|---|---|---|
| 1 Atlas + Wortschatz | — | einmal | **Sekunden** | klein |
| 2 Embedding | 1:49 | `DC_EPOCHEN` | 15 Epochen ≈ **27 min** | 108 MB |
| 3 Kopf (item_head) | — | — | **2,9 s** | 74 MB |
| 4 Transformer | ~90 s | **60** | **≈ 90 min** | — |
| 5 Chance-Kopf | — | `CS_EPOCHEN` | nicht gemessen | — |

Die ganze Kette liegt damit grob bei zwei Stunden und passt in einen Job. Der
Transformer ist der teure Teil; seine 60 Epochen sind die Vorgabe und lassen
sich mit `DC_EPOCHEN` für eine Rauchprobe heruntersetzen (vorher waren sie
fest verdrahtet — eine Probe hätte 90 Minuten gekostet, bevor ein Fehler im
letzten Schritt auffällt).

Ein Runner ist langsamer als ein Arbeitsplatzrechner; rechne mit dem Zwei- bis
Dreifachen. Auch dann bleibt Luft bis zu den 350 Minuten.

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

* **Das Korpus-Gate ist rot: 1 von 300 Rezeptfolgen wird abgelehnt.** In
  Lauf #2 (25.11.2026, frischer Atlas auf dem Runner) lautete der Grund:
  `'hammer' ist im Korpus tool, nicht weapon`. Die abgelehnte Folge ist
  `<out> hammer x1 … <skill> iron_craft <type> weapon`, also ein Rezept, das
  einen Hammer als Waffe ausgibt, während `hammer` sonst als Werkzeug geführt
  wird. Entfernen oder umbenennen, dann wird das Gate grün und `neueste` in
  kontor wieder beschrieben.
* **45 der 259 Rezepte** tragen eine Prozessmarke (`iron_craft`,
  `fiber_craft`, `bone_craft` …) als Voraussetzung. Früher vermutete Ursache
  der Gate-Ablehnung; in Lauf #2 nannte das Gate stattdessen den
  Art-Widerspruch oben. Ob die Regel Prozessmarken im Fertigkeitsfeld
  annimmt, ist damit nicht abschließend geklärt.
* Die Meldung **„9 Korpus-Wörter ohne Token"** (`rune_craft`, `iron_craft`, …)
  kam von einem veralteten Atlas und ist nach Schritt 1 verschwunden —
  nachgemessen am 25.11.2026, auch in der CI (Lauf #2: 5.618 Atlas-Tokens,
  0 Wörter ohne Token).
