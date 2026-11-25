# Disease-Namens-Listen

7 Kategorien parallel zur Taxonomie in
`doc/backlog/2026-06-08_disease_and_healing.md`.  Jede Datei enthält eine
Liste von kanonischen Disease-Namen (eine pro Zeile, kebab-case oder
snake_case, lowercase).  Kommentare mit `#`, Leerzeilen ignoriert.

| Kind | Datei | Wesen |
|---|---|---|
| 1 | `toxic.txt` | chemisch (Gifte, Drogen-Entzug) |
| 2 | `biological.txt` | infektiös (Pest, Parasiten) |
| 3 | `physical.txt` | akut (Brüche, Blutungen) |
| 4 | `magical.txt` | übernatürlich (Flüche) |
| 5 | `mental.txt` | psychisch (Verzweiflung, Wahn) |
| 6 | `environmental.txt` | umwelt (Strahlung, Erfrierung) |
| 7 | `genetic.txt` | progressiv / Erbkrankheiten (nicht curable) |

`adjective.txt` — gemeinsame Modifier-Adjektive (z.B. "creeping",
"raging", "dormant") für die Namensbildung.

`epidemic_names.txt` — Welt-Event-Namen (z.B. "The Great Fading",
"Rusted Death") — werden vom Server beim Epidemic-Spawn aus der Kategorie
gerollt.

## Format-Konvention

- Eine Zeile = ein Name
- Kebab-case (`cellular-decay`) oder snake_case (`cellular_decay`) — wir
  haben uns auf snake_case geeinigt für ML-Trainingsdaten
- Leerzeilen + `#` Kommentare werden ignoriert vom Loader
- Aktueller Bestand ist Seed/Skeleton: jede Datei hat ~10-15 Beispiele,
  ML kann später daraus generieren oder Player-Input erweitert die Listen
