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
| `itemgen/data/items_augmented.txt` | Rezepte + Eingabezeilen (259 Rezepte, 8.288 Samples, 32 je Rezept) |
| `discovergen/data/discoveries_augmented.txt` | Fund- und Entdeckungsbeispiele (25.000) |
| `data/skill_corpus.txt` | 253 Fertigkeiten × 60 Beispiele |
| `data/combat_skill_corpus.txt` | 166 Kampffertigkeiten × 60 Beispiele |
| `data/combat.txt` | Handbestand + erzeugte Chance/Wucht-Beispiele |
| `prophecy/data/` | Namen, Marken, Cluster, Domänen, Regellisten |
| `prophecy/sources/` | Modell, Trainer, Köpfe, Inferenz |
| `korpusgen/` | der Korpus-Erzeuger (aiml, JIT) |
| `tools/korpus_grundlinie.py` | was ein Korpus hergibt: Grundlinie je Kopf, gleiche Kampf-Metadaten |
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

1. **Ubuntu 24.04.** Das aiml-Paket aus kontor ist auf Noble gebaut; seine
   Systembibliotheken (libc, libstdc++, GL/X11) kommen vom Runner.
2. **Drei Geheimnisse für kontor** (siehe unten). Ohne sie gibt es keinen
   Übersetzer, der Lauf bricht im Schritt „kontor-Zugang“ mit einer klaren
   Meldung ab.

`Pymann/exodus` ist öffentlich, der Workflow braucht dafür kein Token.
`Pymann/aiml` wird nicht mehr ausgecheckt.

exodus wird normal installiert. Bis zum 23.11.2026 fehlten im exodus-Paket
die Unterpakete (`ModuleNotFoundError: No module named 'exodus.core'`); seit
exodus `fd39730` packt `pyproject.toml` alle `exodus*`-Pakete.

aiml wird **nicht gebaut**, sondern aus kontor geladen (siehe „Der
Übersetzer kommt aus kontor“).

### Einzelne Köpfe neu trainieren

Ein Kopf lässt sich allein neu trainieren, ohne Atlas, Embedding und die
übrigen Köpfe noch einmal zu rechnen. Ausgangsstand ist ein veröffentlichtes
Paket aus kontor:

| Eingabe | Wert |
|---|---|
| `schritte` | `3-koepfe` (oder `4-transformer`, `5-chance`); mehrere mit Leerzeichen, z. B. `3-koepfe 5-chance` |
| `koepfe` | z. B. `combat-skill-head` (mehrere mit Leerzeichen) |
| `vorstand` | `latest` oder ein Paket wie `18-1fc8d90c6f8e` |
| `frisch` | an: die Gewichte dieser Köpfe vorher löschen, von Null anfangen; aus: auf dem geladenen Stand weitertrainieren |
| `kontor` | an: das Ergebnis hochladen. Weil alle übrigen Stores aus dem Ausgangsstand kommen, ist das Paket vollständig und wird `latest`, wenn das Gate grün ist. Für Versuche aus lassen. |

`vorstand` und `vorlauf` (Run-ID eines GitHub-Laufs) schließen sich aus.

**Mehrere Schritte in einem Lauf** (seit 26.11.2026): `schritte` ist ein
Freitext, die Teile werden mit Leerzeichen getrennt und laufen in der
Reihenfolge der Kette, egal in welcher Reihenfolge sie dastehen. Bis dahin war
es eine Auswahl mit genau einem Schritt oder `alles`; Köpfe und Chance-Kopf
brauchten zwei Läufe hintereinander (#33, #34). Beispiel für den vollen
kontor-Stand ohne Atlas, Embedding und Transformer: `schritte` =
`3-koepfe 5-chance`, `koepfe` = `item-head combat-skill-head`, `frisch`,
`emb_mit`, `cs_encoder`, `cs_epochen` = 20, `vorstand` = `latest`.

**Stores verdichten.** Jedes `tensor.save` hängt an das WAL des Stores an,
überschriebene Gewichte bleiben darin liegen. Seit die Köpfe den besten Stand
jeder Epoche sichern (und mit `emb_mit` auch die Einbettung), wuchs das Paket
in Lauf #33 über die Grenze von kontor (`413 Payload Too Large`). Deshalb ruft
jeder Kopf-Trainer am Ende `db.checkpoint` auf, das nur die lebenden Einträge
behält. Der Schritt „Modelle nach kontor“ zeigt vor dem Hochladen die belegte
Größe jedes Stores (`ls -ls`) und die Paketgröße.

`emb_mit` (Versuch, 26.11.2026; bis 0be971c hieß die Eingabe
`kampf_emb_mit` und galt nur für den Kampfskill-Kopf): Item- und
Kampfskill-Kopf lernen die Einbettung mit und legen sie je in einem eigenen
Store ab, `prophecy_item_embedding` und `prophecy_combat_skill_embedding`;
die gemeinsame Einbettung bleibt unberührt. Läuft einer der beiden Köpfe ohne
diese Eingabe, löscht der Workflow seine eigene Einbettung, weil sie dann
nicht mehr zu ihm passt. `prophecy/sources/inference.aiml` hier nimmt die
eigene Einbettung, wenn der Store da ist. **Die Inferenz im Spiel-Repo muss
das nachziehen**, bevor ein Paket damit `latest` wird; sonst rechnen die
Köpfe dort auf der gemeinsamen Einbettung, zu der ihre Gewichte nicht passen.

`cs_encoder` (Schritt `5-chance`): der Chance-Kopf trainiert seinen
Transformer mit (`CS_ENCODER=1`) und sichert ihn in
`prophecy_kampf_transformer`; `chance_kopf.aiml` lädt ihn von dort. Ohne
das rechnet der Kopf auf dem eingefrorenen Transformer (erklärte Streuung
0,12–0,15, Läufe #17/#18).

Beim Item-Kopf sah der Adam-Schritt der Einbettung mit `DC_EMB_MIT` bisher
nur das letzte Beispiel jedes 32er-Stapels: ihr Gradient wurde nach jedem
Beispiel geleert. Seit diesem Stand sammelt sie über den Stapel wie die
übrigen Gewichte.

## Veröffentlichen nach kontor

Nach einem Lauf, der Gewichte erzeugt hat, packt der Workflow die
`prophecy_*`-Stores und die Textdateien, die die Inferenz zur Laufzeit liest,
und legt sie in die **generische** Ablage von kontor
(`PUT /generic/<pfad>`, `Authorization: Bearer`, mit
`X-Checksum-Sha256`-Prüfung):

```
generic/datacreatures/prophecy/<laufnummer>-<commit>/models.tar.gz
generic/datacreatures/prophecy/<laufnummer>-<commit>/models.json
generic/datacreatures/prophecy/latest/models.tar.gz
generic/datacreatures/prophecy/latest/models.json
```

**Textdateien im Paket.** Der Server soll alles aus einer Quelle bekommen,
deshalb liegen alle Textdateien des Repos (`git ls-files '*.txt'`, heute 138,
etwa 9 MB) mit in `models.tar.gz`, jeweils unter demselben Pfad wie im Repo:
die Korpora unter `data/`, `itemgen/data/` und `discovergen/data/`, die Namens-,
Tag-, Regel- und Markenlisten unter `prophecy/data/` und
`prophecy/required_stores.txt`. Gepackt wird der Stand im Arbeitsverzeichnis,
also auch ein im selben Lauf mit `korpus_neu` neu gebauter Korpus. Zur Laufzeit
liest die Inferenz davon selbst nur `itemgen/data/items_augmented.txt`
(`load_recipe_metadata`); die Listen unter `prophecy/data/` stecken zusätzlich
im Store `prophecy_atlas`. Jede Datei steht mit ihrer SHA-256 in `models.json`
unter `text_files`. Pakete bis einschließlich #23 enthalten noch keine
Textdateien. Beim Laden eines Ausgangsstands (`vorstand`) werden nur die Stores
ausgepackt; die Textdateien kommen dann aus dem Repo.

Alles, was in kontor landet — Pfade, Dateinamen, JSON-Schlüssel — ist
englisch; die Ablage teilen sich mehrere Projekte.

`models.json` liegt daneben, damit die Herkunft ohne Download lesbar ist:
Laufnummer, Korpus-Commit, aiml-Commit, Schritte, Epochen, die Liste der
Stores, die Textdateien mit ihren SHA-256 (`text_files`), Paketgröße und -Prüfsumme, und wie viele Korpuswörter das Gate ohne
Atlas-Token gefunden hat.

**`latest` wird nur überschrieben, wenn das Paket vollständig ist, das Gate
grün war und kein Wort ohne Token meldet.** Vollständig heißt: jeder Store aus
[`prophecy/required_stores.txt`](prophecy/required_stores.txt) liegt als
`<name>.kvwal` in `aiondb` — Atlas, Wortschatz, Embedding, alle fünf Köpfe,
Transformer und Chance-Kopf. Geprüft wird das von `tools/package_complete.sh`;
fehlende Stores stehen im Log und in `models.json` (`complete`,
`missing_stores`). Ein halber Lauf, etwa `3-koepfe` ohne `vorlauf`, landet so
nur in seinem eigenen Ordner. Wer die Kette über mehrere Läufe verteilt, setzt
im letzten `vorlauf`, dann trägt dessen `aiondb` den Rest bei.
Kaputte Gewichte als „latest" zu veröffentlichen wäre schlimmer,
als sie gar nicht zu veröffentlichen; der lauf-eigene Pfad bekommt sie
trotzdem, damit man hineinsehen kann.

Geprüft wird nur, dass die Stores da sind, nicht was in ihnen steht; das ist
Sache des Gates. `tools/test_package_complete.sh` (Workflow `Checks`, bei jedem
Push) testet die Prüfung und dass jeder Name der Liste noch unter
`prophecy/sources` vorkommt: wer dort einen Store umbenennt, muss die Liste
nachziehen.

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

Seit 26.11.2026 baut dieser Workflow aiml nicht mehr selbst. Das fertige
Paket legt die **aiml-CI** nach kontor (aiml `.github/workflows/ci.yml`,
Schritt „Put the bundle into kontor“), und zwar erst, nachdem Testkorpus,
valgrind und Leak-Gate grün sind:

```
generic/aiml/<commit-sha>/aiml-x86_64-linux.tar.gz   jeder grüne master-Commit
generic/aiml/<tag>/aiml-x86_64-linux.tar.gz          jedes v*-Release, z. B. v1.0.2.7
generic/aiml/latest/aiml-x86_64-linux.tar.gz         das letzte Release
```

Welcher Stand geladen wird, sagt die Eingabe **`aiml_version`**: Vorgabe
`latest`, sonst ein Tag oder ein Commit. Liegt der Stand nicht in kontor,
bricht der Lauf ab; gebaut wird nicht mehr. `models.json` hält fest, was
geladen wurde (`aiml_version`, `aiml_package_sha256`).

Der Tarball ist ein Venv (`bin/ lib/ env`) aus aiml's
`tools/ci/package_release.sh`: neben `bin/aiml` und `lib/libaiml.so` die
gepinnten Bibliotheken (libyaml-cpp, openblas, libLLVM …) mit RUNPATH
`$ORIGIN`. Der Ladeschritt prüft mit `ldd`, dass keine fehlt, und bricht
sonst mit den Namen ab — so stirbt nicht erst der erste Build mit `cannot
open shared object file` (Lauf #8).

**Rauchprobe Lauf #19** (26.11.2026, `alles`, 2 Epochen, `cs_epochen=50`,
ohne Upload): alle fünf Stufen und das Gate grün, in 8½ Minuten. Geladen
wurde `latest` (v1.0.2.7) in 10 s, `ldd` fand keine fehlende Bibliothek, und
kein Build vermisste ein apt-Paket. Die drei Systempakete (`g++ dpkg-dev
patchelf`) liegen auf `ubuntu-24.04` schon vor.

Warum nicht mehr selbst bauen: Bis Lauf #18 baute der Workflow aiml, wenn
der Commit noch nicht in kontor lag, und legte ihn danach selbst ab. Da
aiml master oft neue Commits hat, war das jeden zweiten bis dritten Lauf
der Fall und kostete 5 bis **30 Minuten** (Lauf #18). Und es legte
ungetestete Stände nach `generic/aiml/`, an denselben Ort, den die aiml-CI
mit getesteten füllt.

Warum die **generische** Ablage und nicht `/exodus/<name>/<version>/package`:
dort müssen Name und Version mit dem Manifest übereinstimmen, und aiml trägt
eine Version über alle Commits. Hier ist der Commit oder Tag der Schlüssel.

**Was jeder Lauf neu holt** (Lauf #7–#9): apt (g++, dpkg-dev, patchelf)
11–18 s, `pip install` exodus rund 15 s, Checkouts und Vorlauf-Artefakt rund
15 s. Ein GHA-Cache dafür spart höchstens eine halbe Minute und lohnt nicht.
Das aiml-Paket aus kontor zu laden dauert rund 6 s.

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

Gemessen mit den Vorgaben, Lauf #7 (25.11.2026):

| Kopf | Epochen | Dauer | Abnahme (nicht trainiert) | vorher, 15 Epochen |
|---|---|---|---|---|
| item_head | 1200 | **6 min** | **107 / 526 richtig (20,3 %)**, Zufall 0,4 % | 2 / 526 |
| combat_score_head | 150 | 50 s | erklärte Streuung **0,85** (Wucht 0,82) | 0,80 (0,77) |

Transformer auf dem Runner, Lauf #14 (25.11.2026, Vorgabe 60 Epochen):
**46 s je Epoche, 46 Minuten**, Verlust 7,37 → 0,86 (5696 Folgen), am Ende
noch fallend. Gate danach 300/298/298/293 angenommen. Das erste Paket in
kontor: `generic/datacreatures/prophecy/14-f2f090a62c76/` und `latest/`,
`models.tar.gz` **146 MB** — mit allen Köpfen ist es nicht mehr die 111 KB
aus der Messung ohne sie.

Der Verlust des Item-Kopfs fällt bis Epoche 1200 noch (5,47 → 4,07); seine
Lernrate ist dann schon auf 1,5·10⁻⁵ gefallen.

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

* **Korpuslücken, gemessen 25.11.2026** (`tools/korpus_grundlinie.py`). Je
  Kopf eine logistische Regression auf dem Wortbeutel, mit derselben
  Aufteilung wie die Trainer (crc32 der Zeile). Das zeigt, was der Korpus
  hergibt, unabhängig vom Modell:

  | Kopf | Klassen | Testzeilen | Grundlinie | Kopf zuletzt |
  |---|---|---|---|---|
  | item_head | 259 | 829 (vorher 526) | **80,7 %** | 20,3 % (Lauf #7) |
  | skill_head | 253 | 1.411 | **88,2 %** | 1 / 1411 (Lauf #12) |
  | combat_skill_head | 166 | 1.008 | **28,1 %**, unter den ersten fünf 65 % (vorher 49,0 % mit Tags) | 11,1 % (Lauf #12) |

  *Skill-Kopf:* der Korpus ist gut lernbar. Alle 253 Fertigkeiten haben 60
  Beispiele, keine zwei haben gleiche Metadaten. Dass der Kopf unter Zufall
  liegt, liegt am Training (tote Schicht, siehe unten), nicht an den Daten.
  Mit einem Viertel der Lernzeilen kommt die Grundlinie schon auf 83 %.

  *Kampfskill-Kopf:* hier begrenzt der Korpus. **18 Gruppen mit 47
  Kampffertigkeiten hatten dieselben Metadaten** (Fundament, Marken,
  Gegenstände, Element, Kategorie), z. B. `hook_strike` = `finishing_blow`,
  `crushing_blow` = `iron_pulse` = `bone_rattle` = `forge_impact`,
  `thunderbolt` = `skyfall` = `stormcall` = `sandstorm`. Ihre Beispiele
  kamen aus denselben Wörtern, kein Modell konnte sie trennen. Mehr
  Beispiele helfen wenig (halber Lernteil 45,9 %, ganzer 49,0 %).

  **Geändert 26.11.2026:**

  1. *Keine eigenen Tags im Kampfbeutel.* Der Erzeuger legte in jede
     Zeile 1–3 `skill_tags` der Fertigkeit, die der Kampf lehren soll. Die
     zieht das Spiel aber erst beim Lernen (drei zufällige je Fertigkeit,
     später aus der Kampferfahrung mit einem eigenen Modell); vor dem
     Lernen können sie nicht im Beutel liegen. Der Kopf lernte also, die
     Antwort an Wörtern abzulesen, die er im Spiel nie sieht: Grundlinie
     49,0 % mit, 27,6 % ohne sie. Die `skill_tags` bleiben in den
     Metadaten als Vorrat, aus dem das Spiel zieht.
  2. *Kein Element im Kampfbeutel* (Nikolai): das Element soll nicht
     entscheiden, welche Fertigkeit ein Kampf lehrt, es wirkt erst im
     Kampf auf die gelernte. Weder `element_tags` noch der daraus
     abgeleitete Gegner-Aspekt kommen mehr in den Beutel. Die
     `element_tags` aller Fertigkeiten sind unverändert.
  3. *Eigene Waffen für die 47.* Mit Nikolai abgestimmt: je Fertigkeit nur
     `item_name_required`, nach dem Namen gewählt (z. B. `hook_strike` mit
     sword/broadsword/sabre, `finishing_blow` mit
     longsword/greatsword/claymore). Die Spiel-Kopie der Datei muss
     dieselben Werte bekommen.

  Was jetzt entscheidet: Fundament, eine Waffe (je Zeile höchstens eine),
  Gegnerart, Gegnermarken, schon gelernte Fertigkeiten. Grundlinie
  **28,1 %** als oberster Vorschlag, **65 % unter den ersten fünf**, 83 %
  unter den ersten zehn. 17 Gruppen mit 49 Fertigkeiten haben dieselbe
  Waffe, Kategorie und dasselbe Fundament (das Skript listet sie); für sie
  ist der Kopf ein Kandidatenvorschlag, kein eindeutiges Urteil.

  *Item-Kopf:* zwei Lücken, beide behoben:

  1. **Die 108 Rezepte der Blöcke KOCHEN (48) und TRAGBARES (60) hatten nur
     acht Eingaben**, die 151 übrigen 32. Etwa sechs Lernzeilen je Rezept,
     59 Rezepte ohne eine einzige Testzeile; Grundlinie 69,7 % (Kochen) und
     57,1 % (Tragbares) gegen 83,4 % im Hauptteil. Jetzt liest `korpusgen
     rezepte` auch die Rezepte dieser Blöcke und füllt bis 32 auf. Die
     zusätzlichen Zeilen stehen im Eingabeteil, die Blöcke selbst bleiben
     Zeile für Zeile, die Rezeptzeilen auch. Danach: 77,8 % und 75,9 %,
     Hauptteil unverändert 83,5 %, 11 Rezepte ohne Testzeile. 8.288 statt
     5.696 Eingaben; der Item-Kopf braucht entsprechend etwa 45 % länger.
  2. **`stil_von` fand nie ein Cluster.** Es trennte die Kennung an `-`, die
     Kennungen haben aber `_`. Damit trugen alle 4.832 Eingaben das Fundament
     `resource_lore`, und die Prozessmarken des Clusters kamen nie in den
     Beutel. Behoben. Das Fundament ist jetzt die echte Starter-Fertigkeit
     des Handwerks (`rune_sense`, `magic_aptitude`, `animal_sense` …).
     Die Kernstoffe des Clusters, die an derselben Stelle hätten dazukommen
     sollen, sind dagegen gestrichen. Gemessen senkten sie die Grundlinie
     im Hauptteil von 83 % auf 72 %: Eisen und Kupfer, die gar nicht im
     Rezept stehen, machen alle Schmiederezepte gleich.

  Was bleibt und an den Rezeptzeilen hängt (die stehen in der lebenden
  Datenbank, darum hier nicht geändert): vier Paare mit gleichen Zutaten
  und Werkbänken (`trowel`/`morningstar`, `memory_cell`/`elder_ring`,
  `bottle`/`jar`, `transmitter`/`timer`) und 50 Paare, bei denen die Zutaten
  eines Rezepts eine echte Teilmenge eines anderen sind. 21 Ausgaben haben
  mehrere Rezepte (z. B. `choker` aus Rune, Faser oder Edelstein); die
  Grundlinie trennt sie, weil sich die Zutaten unterscheiden. Mehr
  Zutaten machen ein Rezept nicht schwerer: Rezepte mit 7 und 8 Zutaten
  trafen vor der Auffüllung 19 von 20 Testzeilen.

* **`korpusgen alles` schrieb Rezeptzeilen um** (behoben 25.11.2026).
  `alles` rief auch `stoffe` auf, die einmalige Umstellung von Warengruppen
  auf Stoffe. Auf eine Datei angewandt, die schon Stoffe nennt, liest sie
  Stoffnamen wie `fungus`, `herb` oder `food` als Warengruppe: ein Lauf
  änderte 48 Rezeptzeilen (z. B. `console`: fungus, moss, fern, sap → moss).
  Das hätte jeder Workflow-Lauf mit `korpus_neu` getan. `stoffe` läuft
  jetzt nur noch, wenn man es ausdrücklich nennt.

  Dabei gesehen: `alles` mit aiml v1.0.2.5 erzeugt auch den Kampf- und den
  Fertigkeitskorpus nicht byte-gleich zum eingecheckten Stand (andere
  Ziehungen trotz Saat 42). Darum sind die beiden hier nicht neu erzeugt.

* **Behoben 25.11.2026: der Hammer mit zwei Arten.** Das Gate lehnte 1 von
  300 Rezeptfolgen ab (`'hammer' ist im Korpus tool, nicht weapon`): zwei
  Rezepte gaben `hammer` aus, `recipe_tech_tool_hammer` als `tool` und
  `recipe_metal_weapon_hammer` als `weapon`. Die Regel kennt je Ausgabename
  genau eine Art. Das Waffenrezept gibt jetzt `warhammer` aus (steht in
  `names/items/weapon.txt`); Kennung, Zutaten und Art bleiben, damit die
  Kennung in der Spieldatenbank weiter passt. Lauf #6: das Gate nimmt alle 300
  Rezeptfolgen an, alle vier Aufgaben kommen durch.
* **World-Entity-Kopf (Lauf #5, 25.11.2026).** Die Fundart lernte (Abnahme
  80 %, häufigste Art wäre 30 %), aber der Gesamtverlust stieg ab Epoche 2
  (16,1 → 18,5), getrieben vom Namens-Kopf, und jede Epoche dauerte länger
  (1:21 → 5:51). Dazu sicherte die Schleife nach dem Gesamtverlust und
  behielt damit Epoche 2, obwohl die Fundart bis Epoche 14 weiter fiel.
  Geändert: Lernrate fällt mit 1/√(1+Epoche) wie beim Embedding, gesichert
  wird nach dem Fundart-Verlust. **Lauf #6** (nur dieser Kopf, 15 Epochen):
  jede Epoche **35 s, gleichbleibend** (statt 1:21 → 5:51), Gesamtverlust
  fällt durchgehend (16,6 → 15,5), Fundart 0,61, Abnahme **81 %**; der Kopf
  brauchte 9 statt 68 Minuten. Einschränkung: Lauf #6 setzte auf dem Stand
  von Lauf #5 auf, also auf schon trainierten Gewichten. Warum die festen
  0,003 die Epochen verlangsamten, ist nicht nachgewiesen (Vermutung:
  auseinanderlaufende Gewichte im Namens-Kopf, z. B. denormale Zahlen).
* **Item-, Skill- und Kampfskill-Kopf lagen in der Abnahme auf Zufallsniveau**
  (Lauf #5: 2/526, 2/1411, 2/973 richtig). Ursache: der Workflow setzte
  `DC_EPOCHEN=15` für alle Apps, und die Köpfe nahmen das statt ihrer
  Vorgaben (1200, 200, 150). Der Item-Kopf trainierte also 1,25 % seiner
  Epochen, mit `lr=0.0005` — Trainingstreffer 1,8 %, Abnahme Zufall. Behoben
  25.11.2026: `epochen` ist leer voreingestellt. Lauf #7: der Item-Kopf
  trifft mit 1200 Epochen 20,3 % in der Abnahme (vorher 0,4 %).
* **Skill- und Kampfskill-Kopf: tote relu-Schicht.** Mit vollen Epochen
  (Lauf #9, 200 bzw. 150) fiel der Verlust bis Epoche 20 (12,1 → 9,48 bzw.
  7,15 → 6,11) und stand danach **auf die fünfte Stelle fest**; Abnahme 2/1411
  und 2/973, unter Zufall. Das ist dasselbe Bild wie früher beim Item-Kopf:
  `lr=0.005` je Einzelbeispiel treibt alle 64 Einheiten unter 0, dann sind
  alle Gradienten außer dem des Ausgabe-Bias 0 und der Kopf lernt nur noch die
  Klassenhäufigkeit. Der Lauf dauerte 13 + 3 Minuten, nicht 2 h — die
  Hochrechnung oben galt für lebende Schichten. Geändert: `lr=0.0005`, fallend
  mit 1/sqrt(1+Epoche), `DC_LR` wird gelesen, und vor dem Training zählt
  `BagBackbone.wache_einheiten` auf 300 Taschen die feuernden Einheiten — bei
  0 wird die geladene Schicht verworfen und neu gezogen, denn ein toter Stand
  aus dem Vorlauf erholt sich nie.

  Lauf #12 (25.11.2026, auf dem Stand von #9): **Kampfskill-Kopf** — 0 von 64
  wach, neu gezogen, Verlust 4,96 → 2,19, Abnahme **108 / 973 richtig
  (11,1 %)**, Zufall 0,6 %; 5 Minuten. **Skill-Kopf** — 2 von 64 wach, also
  nicht neu gezogen; Verlust fiel nur langsam (11,0 → 9,52), Abnahme 1 / 1411,
  weiter unter Zufall. Darum gilt seitdem: weniger als ein Viertel wach → neu
  ziehen.

  Lauf #13 (nur Skill-Kopf, neu gezogen) lief mit **45 s je Epoche** und
  wurde nach Epoche 80 abgebrochen. Lauf #15 rechnete **dieselben Verluste
  bis auf die vierte Stelle** (12,00 → 11,01 → 10,63 …) mit **5 s je Epoche**,
  200 Epochen in 18 Minuten. Die Langsamkeit in #13 lag also am Runner, nicht
  an der lebenden Schicht. Ergebnis #15: Verlust 12,0 → 9,61, Abnahme
  **15 / 1411 (1,1 %)**, Zufall 0,4 % — lernt, aber stark unteranpassend
  (Trainingstreffer 1,5 %; die logistische Grundlinie des Korpus liegt bei
  88 %). Die Lernrate fällt mit 1/sqrt(1+Epoche) auf 3,7·10⁻⁵ und ist damit
  vermutlich zu klein; offen.
* **Item-Kopf auf dem erweiterten Korpus (07ae0a9, 8.288 Eingaben)**,
  Lauf #15: 55 von 64 Einheiten wach, Verlust 5,08 → 3,59, Abnahme
  **196 / 829 (23,6 %)** statt 20,3 %, 209 von 259 Klassen vorhergesagt;
  18 Minuten. Die Grundlinie (logistische Regression) liegt bei 77,8 % — der
  Kopf ist auch hier weit unter dem, was der Korpus hergibt.
* **Chance-Kopf, Lauf #16 (26.11.2026, eingefrorener Transformer aus #14):**
  drei Fehler auf einmal.
  1. *Tote Schicht.* Mit `lr=0.05` im vollen Stapel stand der Verlust ab
     Epoche 500 auf 0,0509835 = Streuung der Ziele; erklärte Streuung
     −0,0001 in Training und Abnahme. Der Kopf sagte nur den Mittelwert.
     Jetzt `lr=0.005`, mit `CS_LR` überschreibbar, und nach dem Training
     zählt `wache_zaehlen` die feuernden Einheiten (0 → Fehler im Log).
  2. *Falsche Pfade.* Garderobe und Umfeld wurden aus `resources/tags/…`
     gelesen, die Marken liegen in `prophecy/data/tags/…`: „Zusatzmarken: 0,
     Umfeldmarken: 0". Damit war die Garderoben-Variante gleich dem Original
     und die Wetter-Variante auch („Abstand Zeile 0 zu Zeile 3: 0"); die
     Witterungsregel kam gar nicht ins Training. Die Probefolge nannte drei
     Marken, die es nicht gibt (`mud-caked`, `shock-aspect`,
     `minimal-threat`), darum 9 statt 12 Token; ersetzt.
  3. *Absturz am Ende* (`double free or corruption` in `aiml_tensor_free`,
     Exit 134, darum kein Upload nach kontor). Die gelernten Gewichte standen
     in zwei Feldern zugleich (`letzte_gew` im Trainer und `kopf_w` im Kopf),
     `free: trainer` gab sie zweimal frei. Jetzt hält sie nur noch ein Feld.
  Dazu schreibt der Kopf ohne Encoder-Training jetzt auch seinen
  Herkunftssatz (Manifest); vorher tat das nur der `CS_ENCODER`-Weg.

  Lauf #17 (26.11.2026, 02f5fc0): Probefolge 12 Token, 114 Zusatz- und 42
  Umfeldmarken, Abstand Zeile 0 zu 3 jetzt 22,2. 1500 Epochen in 93 s,
  Verlust 0,0458 → 0,0411 und noch fallend, **31 von 64 Einheiten wach**.
  Erklärte Streuung **0,15 im Training, 0,12 in der Abnahme** (RMSE 0,204);
  kein Absturz am Ende, Manifest geschrieben, Paket `17-02f5fc077460`
  (242 MB) ist `latest`. Das ist der eingefrorene Transformer. Der Kommentar
  im Trainer nennt für den alten Kopf 0,78; dahin führt vermutlich erst der
  `CS_ENCODER`-Weg (Transformer lernt mit), der im Workflow noch nicht
  angeboten wird.
* **Neutraining Lauf #18** (26.11.2026, `alles`, Korpus 1fc8d90: erweiterte
  Rezepte, Kampfkorpus ohne Ziel-Tags und ohne Element im Kampfbeutel), alles
  von Null, 2 h 37 min (davon 30 min aiml-Bau, den es seit b84df59 nicht
  mehr gibt). Abnahme (nicht trainierte Zeilen):

  | Kopf | Abnahme | Zufall / Grundlinie | vorher |
  |---|---|---|---|
  | item_head | 199 / 829 (24,0 %) | 0,4 % / 77,8 % | 23,6 % (#15) |
  | skill_head | 143 / 1411 (**10,1 %**) | 0,4 % / 88,2 % | 1,1 % (#15) |
  | combat_skill_head | 58 / 1008 (5,8 %) | 0,6 % / 28,1 % | 11,1 % (#12, alter Korpus) |
  | world_entity_head | Fundart 79,8 % | häufigste 30 % | 81 % (#6) |
  | combat_score_head | erklärte Streuung 0,84, Wucht 0,81 | — | 0,85 / 0,82 |
  | Chance-Kopf | erklärte Streuung 0,11 | — | 0,12 (#17) |

  Transformer 60 Epochen, Verlust 7,14 → 0,94, 56 s je Epoche (57 min).
  Gate 296/298/298/293 angenommen. Paket `18-1fc8d90c6f8e` (164 MB) ist
  `latest`. Der Skill-Kopf profitiert davon, dass er von Null anfängt statt
  auf einem halbtoten Vorlauf; alle Köpfe liegen weiter weit unter ihrer
  Grundlinie.
* **Korpus nach Klassen sortiert, Köpfe lernten ihn in dieser Reihenfolge**
  (gefunden 26.11.2026, behoben in 7527daa). Die Korpora stehen Klasse für
  Klasse (60 Zeilen je Kampffertigkeit am Stück), und Item-, Skill- und
  Kampfskill-Kopf lernten Beispiel für Beispiel genau so. Am Ende jeder
  Epoche kannte der Kopf nur die zuletzt gesehenen Klassen. Lauf #20
  (Kampfskill, lr 0,002, ungemischt): Verlust 2,23, aber **1,6 %** Treffer
  auf den eigenen Lernzeilen. Jetzt mischen die drei Trainer die Reihenfolge
  je Epoche (Fisher-Yates, `Zufall` mit Saat = Epoche + 1, also
  wiederholbar). Kampfskill-Kopf, nur dieser Kopf frisch auf `latest`
  (`vorstand=latest`, `frisch=true`, ohne kontor):

  | Lauf | lr | gemischt | Lernzeilen | Abnahme | Dauer |
  |---|---|---|---|---|---|
  | #18 | 0,0005 | nein | 11,2 % | 58 / 1008 (5,8 %) | — |
  | #21 | 0,0005 | ja | 28,3 % | 109 / 1008 (10,8 %) | 10 min |
  | #22 | 0,002 | ja | 23,5 % | 110 / 1008 (10,9 %) | 37 min |

  Die höhere Lernrate bringt nichts, die Voreinstellung 0,0005 bleibt. Die
  Abnahme bleibt bei rund 11 % gegen 28 % der Grundlinie. Der Kopf sieht die
  Wörter nur durch das eingefrorene 32-dimensionale Embedding (Mittelwert
  über den Beutel); die Grundlinie hat für jedes Wort ein eigenes Gewicht.
  Das ist der nächste Ansatzpunkt (mitlernendes Embedding wie `emb_mit` im
  Item-Kopf). Warum #22 je Epoche 15 s statt 4 s brauchte, ist nicht
  geklärt; der Code war derselbe.

  **Lauf #23** (26.11.2026, 7527daa): Item-, Skill- und Kampfskill-Kopf
  frisch und gemischt auf dem Stand `latest` (#18), kontor an, 36 min.
  Abnahme (nicht trainierte Zeilen):

  | Kopf | Lernzeilen | Abnahme | Grundlinie | #18 (ungemischt) |
  |---|---|---|---|---|
  | item_head | 59,9 % | 369 / 829 (**44,5 %**), 243 von 259 Klassen vorhergesagt | 77,8 % | 24,0 % |
  | skill_head | 90,0 % | 1195 / 1411 (**84,7 %**) | 88,2 % | 10,1 % |
  | combat_skill_head | 28,3 % | 109 / 1008 (**10,8 %**) | 28,1 % | 5,8 % |

  Gate 296/298/298/293 angenommen. Paket `23-7527daa58d92` (180 MB) ist
  `latest`. Der Skill-Kopf liegt jetzt fast auf seiner Grundlinie. Item-Kopf
  (8,5 min) und Kampfskill-Kopf bleiben deutlich darunter.

  **Lauf #24** (26.11.2026, 6867d30, `kampf_emb_mit`, ohne kontor):
  Kampfskill-Kopf frisch, Einbettung lernt mit (Start auf der gemeinsamen,
  gesichert in `prophecy_combat_skill_embedding`). Verlust nach 150 Epochen
  1,70 statt 2,7; **Lernzeilen 49,1 %, Abnahme 211 / 1008 (20,9 %)** statt
  10,8 %, Grundlinie 28,1 %. 17 s je Epoche, 44 min.

  **Lauf #25** (0be971c, wie #24, aber `lernrate` 0.002): Lernzeilen
  62,6 %, Abnahme wieder 211 / 1008 (20,9 %). Der Kopf lernt die Lernzeilen
  auswendig, die Abnahme bewegt sich nicht. Darum sichert der
  Kampfskill-Trainer seit diesem Stand nicht mehr den Stand mit dem kleinsten
  Lernverlust, sondern den mit der besten Quote auf dem Prüfteil (Teil 1 der
  Aufteilung, alle 5 Epochen gemessen), holt ihn vor der Abnahme zurück und
  meldet neben dem obersten Vorschlag auch „unter den ersten fünf".

  **Lauf #28** (b0e2619) misslang in der Auswertung: der gesicherte Stand wurde
  nach dem Training zurückgeladen, danach rechneten die Tensoren mit falschen
  Formen (`tensor.matmul: shape mismatch [1,5618] @ [1,5618]`) und die
  Abnahme lag auf Zufall. Seither misst der Trainer die Abnahme in dem
  Moment, in dem der Prüfteil einen besseren Stand meldet, und lädt nichts
  zurück. Ohne Verbesserung über 25 Epochen hört er auf.

  **Lauf #30** (4f4e030, wie #25 mit Auswahl nach Prüfteil): bester
  Prüfteil schon in Epoche 5 (24,0 %), Abnahme dort **22,2 %, unter den
  ersten fünf 55,4 %** (Grundlinie 28,1 % / 65 %); nach Epoche 30 Schluss,
  10 min. Danach steigt nur noch die Quote auf den Lernzeilen (46 %).
  Nächster Versuch: Gradienten über Stapel von 32 sammeln wie beim
  Item-Kopf (`stapel`, `DC_STAPEL`), statt je Beispiel zu schreiten.

  **Lauf #32** (7a5a79d, Stapel 32; #31 stürzte ohne `keep` auf den
  Adam-Momenten in `aiml_tensor_free` ab): bester Prüfteil in Epoche 35
  (23,3 %), Abnahme dort **22,2 %, Top-5 55,1 %**, Schluss nach Epoche 60.
  Gleich gut wie #30, aber **1,4 s statt 17 s je Epoche**, der ganze Kopf
  in 90 s. Der Kampfskill-Kopf steht damit bei rund 22 % gegen 28,1 % der
  Grundlinie; Lernrate, Auswahl nach Prüfteil und Stapel ändern daran nichts.

* **Chance-Kopf mit mittrainiertem Transformer, Lauf #29** (b0e2619,
  `5-chance`, `cs_encoder`, `cs_epochen` 50, ohne kontor; nach Epoche 15
  abgebrochen, um die Zeiten zu lesen): **4 min 7 s je Epoche** (35.542
  Lernzeilen). Erklärte Streuung in der Abnahme (5.920 Zeilen):

  | Epoche | 1 | 2 | 5 | 9 | 11 | 15 |
  |---|---|---|---|---|---|---|
  | erklärte Streuung | 0,685 | 0,770 | 0,791 | 0,861 | 0,872 | **0,875** |
  | RMSE | 0,122 | 0,104 | 0,099 | 0,081 | 0,078 | 0,077 |

  Vorher 0,12 mit dem eingefrorenen Transformer (#17, #18). Ab Epoche 11
  kaum noch Gewinn; 15–20 Epochen (gut eine Stunde) reichen. Der Encoder
  liegt in `prophecy_kampf_transformer`, den `chance_kopf.aiml` lädt.

  **Lauf #26** (0ab7049, Item-Kopf frisch, `emb_mit`, ohne kontor, 12 min):
  Lernzeilen 92,2 %, **Abnahme 666 / 829 (80,3 %)**, 247 von 259 Klassen
  vorhergesagt. Vorher 44,5 % (#23) bei einer Grundlinie von 77,8 %; der
  Item-Kopf liegt damit erstmals über ihr. Die Einbettung liegt in
  `prophecy_item_embedding`.
* **Paketgröße in kontor:** `14-…` 146 MB, `15-07ae0a94304c` 242 MB,
  `17-02f5fc077460` 242 MB, `18-1fc8d90c6f8e` 164 MB, `23-7527daa58d92` 180 MB (`latest`). Das `--sparse` hilft bei den vollen Stores kaum.
* **45 der 259 Rezepte** tragen eine Prozessmarke (`iron_craft`,
  `fiber_craft`, `bone_craft` …) als Voraussetzung. Früher vermutete Ursache
  der Gate-Ablehnung; in Lauf #2 nannte das Gate stattdessen den
  Art-Widerspruch oben. Ob die Regel Prozessmarken im Fertigkeitsfeld
  annimmt, ist damit nicht abschließend geklärt.
* Die Meldung **„9 Korpus-Wörter ohne Token"** (`rune_craft`, `iron_craft`, …)
  kam von einem veralteten Atlas und ist nach Schritt 1 verschwunden —
  nachgemessen am 25.11.2026, auch in der CI (Lauf #2: 5.618 Atlas-Tokens,
  0 Wörter ohne Token).
