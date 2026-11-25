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
Stapelgröße, welche Köpfe Schritt 3 trainiert (`koepfe`, leer = alle fünf,
z. B. `world-entity-head` für einen einzelnen), und die Run-ID eines früheren
Laufes, dessen `aiondb` fortgesetzt wird.

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

### Der Übersetzer kommt aus kontor

`out/aiml/aiml` und `libaiml.so` sind je rund 90 MB und binden LLVM 18 ein.
Gemessen in Lauf #2 (25.11.2026): der Bau dauert auf dem Runner **7 Minuten**.
Darum liegt der fertige Übersetzer in kontor, **geschlüsselt auf den
aiml-Commit**:

```
generic/aiml/<commit-sha>/aiml-x86_64-linux.tar.gz     185 MB → 56 MB gepackt
```

Der Lauf versucht zu laden; liegt der Stand dort nicht, wird gebaut und das
Ergebnis **für den nächsten Lauf abgelegt**. Einmal bauen je aiml-Commit.

| `aiml_quelle` | |
|---|---|
| `auto` (Vorgabe) | laden; liegt nichts da, bauen und ablegen |
| `kontor` | nur laden; liegt nichts da, abbrechen |
| `bauen` | bauen, auch wenn etwas daliegt, und ablegen |

Das ersetzt den GHA-Cache, es tritt nicht daneben: zwei Speicher für dieselbe
Sache wären zwei Wahrheiten. kontor ist der haltbarere — Caches verfallen nach
sieben Tagen ohne Zugriff und gelten nur je Repo, während derselbe Übersetzer
auch für 9rooms und datacreatures taugt. Und er ist schlanker: 56 MB statt
rund 670 MB, weil nur Binary und Laufzeit abgelegt werden, nicht der ganze
Baubaum samt apt-Beiwerk.

Warum die **generische** Ablage und nicht `/exodus/<name>/<version>/package`:
dort müssen Name und Version mit dem Manifest übereinstimmen, und aiml trägt
eine Version über alle Commits — jeder neue Stand würde den alten
überschreiben. Hier ist der Commit der Schlüssel.

Ohne die `KONTOR_*`-Geheimnisse läuft der Workflow trotzdem: dann wird gebaut
und nichts abgelegt.

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

Auf dem Runner war das Embedding **schneller** als auf dem
Arbeitsplatzrechner: Lauf #3 (25.11.2026, `ubuntu-24.04`) brauchte **31 s je
Epoche**, 15 Epochen in gut 8 Minuten (Verlust 965 → 38, noch fallend). Der
ganze Lauf samt aiml-Bau dauerte 14 Minuten.

Schritt 3 auf dem Runner, Lauf #5 (25.11.2026, 15 Epochen): **81 Minuten**,
fast alles im World-Entity-Kopf.

| Kopf | Dauer |
|---|---|
| item_head | 6 s |
| skill_head | 9 min |
| combat_skill_head | 4 min |
| world_entity_head | **68 min** (Epoche 0: 1:21, Epoche 14: 5:51) |
| combat_score_head | 6 s |

**Diese 15 Epochen waren falsch.** Bis zum 25.11.2026 setzte der Workflow
`DC_EPOCHEN=15` für alle Apps; die Köpfe haben aber eigene Vorgaben. Seitdem
ist `epochen` leer voreingestellt und jede App nimmt ihre eigene Zahl.
Hochgerechnet aus Lauf #5 (linear, ohne die Verlangsamung beim
World-Entity-Kopf):

| Kopf | Vorgabe | Lauf #5 | hochgerechnet |
|---|---|---|---|
| item_head | 1200 | 15 | ≈ 6 min |
| skill_head | 200 | 15 | ≈ **2 h** |
| combat_skill_head | 150 | 15 | ≈ 40 min |
| world_entity_head | 60 | 15 | ≥ 80 min |
| combat_score_head | 150 | 15 | ≈ 1 min |
| Embedding | 30 | 15 | ≈ 16 min |
| Chance-Kopf (`CS_EPOCHEN`) | 1500 | — | nicht gemessen |

Alle fünf Köpfe zusammen passen damit vermutlich **nicht** in einen Job
(350 min). Darum über `koepfe` verteilen, z. B. ein Lauf mit `skill-head`,
einer mit `world-entity-head`, einer mit den übrigen drei, jeweils mit der
Run-ID des vorigen als `vorlauf`.

Die übrigen Schritte sind auf
dem Runner noch nicht gemessen; bis dahin gilt die Tabelle oben als obere
Schätzung.

### Grenzen, die man kennen muss

* **6 Stunden je Job.** GitHub kappt dort; der Workflow steht auf 350 Minuten.
  Der letzte vollständige Kettenlauf auf einem Arbeitsplatzrechner lag
  zwischen 00:20 und 11:56 Uhr. Darum ist die Kette in Schritte zerlegt, die
  einzeln laufen und sich über die Run-ID verketten — `alles` ist für kurze
  Epochenzahlen gedacht, nicht für den vollen Lauf.
* **Kein Determinismus-Versprechen über Runner hinweg.** Gleicher Seed, andere
  CPU: die Korpora sind reproduzierbar, die Gewichte nicht bitgenau.
* **Leere Eingaben `lernrate`/`stapel` setzen keine Variable.** Bis zum
  25.11.2026 wurden sie direkt als `DC_LR`/`DC_STAPEL` übergeben; ein leeres
  Feld ergab dann eine *vorhandene, leere* Variable, die die Apps statt ihrer
  Vorgabe parsten; in Lauf #4 trainierte der Item-Kopf darum mit `lr=0`.
  Jetzt wird nur exportiert, was gesetzt ist.
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

* **Behoben 25.11.2026: der Hammer mit zwei Arten.** Das Gate lehnte 1 von
  300 Rezeptfolgen ab (`'hammer' ist im Korpus tool, nicht weapon`): zwei
  Rezepte gaben `hammer` aus, `recipe_tech_tool_hammer` als `tool` und
  `recipe_metal_weapon_hammer` als `weapon`. Die Regel kennt je Ausgabename
  genau eine Art. Das Waffenrezept gibt jetzt `warhammer` aus (steht in
  `names/items/weapon.txt`); Kennung, Zutaten und Art bleiben, damit die
  Kennung in der Spieldatenbank weiter passt.
* **World-Entity-Kopf (Lauf #5, 25.11.2026).** Die Fundart lernte (Abnahme
  80 %, häufigste Art wäre 30 %), aber der Gesamtverlust stieg ab Epoche 2
  (16,1 → 18,5), getrieben vom Namens-Kopf, und jede Epoche dauerte länger
  (1:21 → 5:51). Dazu sicherte die Schleife nach dem Gesamtverlust und
  behielt damit Epoche 2, obwohl die Fundart bis Epoche 14 weiter fiel.
  Geändert: Lernrate fällt mit 1/√(1+Epoche) wie beim Embedding, gesichert
  wird nach dem Fundart-Verlust. Ob das auch die Verlangsamung behebt, zeigt
  der nächste Lauf; die Vermutung ist, dass auseinanderlaufende Gewichte im
  Namens-Kopf Rechenzeit kosten (z. B. denormale Zahlen), belegt ist das nicht.
* **Item-, Skill- und Kampfskill-Kopf lagen in der Abnahme auf Zufallsniveau**
  (Lauf #5: 2/526, 2/1411, 2/973 richtig). Ursache: der Workflow setzte
  `DC_EPOCHEN=15` für alle Apps, und die Köpfe nahmen das statt ihrer
  Vorgaben (1200, 200, 150). Der Item-Kopf trainierte also 1,25 % seiner
  Epochen, mit `lr=0.0005` — Trainingstreffer 1,8 %, Abnahme Zufall. Behoben
  25.11.2026: `epochen` ist leer voreingestellt. Ob die Köpfe mit vollen
  Epochen über Zufall kommen, ist auf dem Runner noch nicht gemessen.
* **45 der 259 Rezepte** tragen eine Prozessmarke (`iron_craft`,
  `fiber_craft`, `bone_craft` …) als Voraussetzung. Früher vermutete Ursache
  der Gate-Ablehnung; in Lauf #2 nannte das Gate stattdessen den
  Art-Widerspruch oben. Ob die Regel Prozessmarken im Fertigkeitsfeld
  annimmt, ist damit nicht abschließend geklärt.
* Die Meldung **„9 Korpus-Wörter ohne Token"** (`rune_craft`, `iron_craft`, …)
  kam von einem veralteten Atlas und ist nach Schritt 1 verschwunden —
  nachgemessen am 25.11.2026, auch in der CI (Lauf #2: 5.618 Atlas-Tokens,
  0 Wörter ohne Token).
