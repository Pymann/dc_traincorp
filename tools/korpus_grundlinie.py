#!/usr/bin/env python3
"""Wie viel ein Korpus ueberhaupt hergibt -- ohne aiml, ohne Gewichte.

Fuer jeden Klassifikations-Kopf (Item, Fertigkeit, Kampffertigkeit) wird eine
einfache logistische Regression auf dem Wortbeutel trainiert, mit DERSELBEN
Aufteilung wie die Trainer (crc32 der Zeile, prophecy/sources/aufteilung.aiml),
und auf dem Testteil gemessen.  Das ist die Grundlinie:

* liegt der Kopf weit UNTER ihr, liegt es am Modell oder am Training;
* liegt schon die Grundlinie niedrig, liegt es am Korpus -- Klassen, die man
  aus der Eingabe nicht unterscheiden kann.

Dazu: Kampffertigkeiten, deren Metadaten (Fundament, Marken, Gegenstaende,
Element, Kategorie) GLEICH sind.  Deren Beispiele werden aus denselben
Woertern gezogen; kein Modell kann sie trennen.

    python3 -m pip install scikit-learn pyyaml
    python3 tools/korpus_grundlinie.py
"""
import sys
import zlib
from collections import Counter, defaultdict
from pathlib import Path

try:
    import yaml
    from sklearn.feature_extraction.text import CountVectorizer
    from sklearn.linear_model import LogisticRegression
except ImportError:
    sys.exit("braucht scikit-learn und pyyaml: python3 -m pip install scikit-learn pyyaml")

WURZEL = Path(__file__).resolve().parent.parent


def teil_von(zeile: str) -> int:
    """Wie teil_von in aufteilung.aiml: 0 lernen, 1 pruefen, 2 testen."""
    s = zeile.strip()
    if not s:
        return 0
    u = zlib.crc32(s.encode())
    v = abs(u - 2**32 if u >= 2**31 else u)
    eimer = v % 100
    return 0 if eimer < 80 else (1 if eimer < 90 else 2)


def lesen(pfad: str, art: str, eingabe: int, ziel: int):
    xs, ys, teile = [], [], []
    for roh in (WURZEL / pfad).open():
        s = roh.strip()
        if not s or s.startswith("#"):
            continue
        sp = [x.strip() for x in s.split("|")]
        if sp[0] != art or len(sp) <= max(eingabe, ziel):
            continue
        xs.append(sp[eingabe])
        ys.append(sp[ziel].split(",")[0].strip())
        teile.append(teil_von(s))
    return xs, ys, teile


def grundlinie(name, xs, ys, teile, gruppe_von=None):
    lern = [i for i, t in enumerate(teile) if t == 0]
    test = [i for i, t in enumerate(teile) if t == 2]
    vec = CountVectorizer(token_pattern=r"\S+", binary=True)
    a = vec.fit_transform(xs)
    m = LogisticRegression(max_iter=2000, C=5).fit(a[lern], [ys[i] for i in lern])
    vorh = m.predict(a[test])
    treffer = sum(vorh[k] == ys[i] for k, i in enumerate(test))
    klassen = len(set(ys))
    ohne_test = klassen - len({ys[i] for i in test})
    zeile = (f"{name:16s} {klassen:4d} Klassen  {len(lern):6d} lernen  {len(test):5d} testen  "
             f"Grundlinie {treffer / len(test):6.1%}")
    if gruppe_von:
        g = sum(vorh[k] in gruppe_von.get(ys[i], {ys[i]}) for k, i in enumerate(test))
        zeile += f"  (gleiche Metadaten als richtig: {g / len(test):.1%})"
    if ohne_test:
        zeile += f"  {ohne_test} Klassen ohne Testzeile"
    print(zeile)
    return vorh, test


def gleiche_kampf_metadaten():
    felder = ["foundation", "skill_tags", "item_name_required", "element_tags", "category"]
    daten = yaml.safe_load((WURZEL / "prophecy/data/skills/combat_skill_metadata.yml").open())["skills"]

    def abdruck(s):
        return frozenset((f, str(w)) for f in felder
                         for w in (s[f] if isinstance(s[f], list) else [s[f]]))

    gruppen = defaultdict(set)
    for s in daten:
        gruppen[abdruck(s)].add(s["id"])
    return {s["id"]: gruppen[abdruck(s)] for s in daten}, [g for g in gruppen.values() if len(g) > 1]


def main():
    vorh, test = None, None
    xs, ys, teile = lesen("itemgen/data/items_augmented.txt", "sample", 1, 2)
    vorh, test = grundlinie("item_head", xs, ys, teile)
    for teil, erkenne in [("  Hauptteil", lambda y: "_kitchen_" not in y and "_bench_" not in y),
                          ("  KOCHEN", lambda y: "_kitchen_" in y),
                          ("  TRAGBARES", lambda y: "_bench_" in y)]:
        idx = [k for k, i in enumerate(test) if erkenne(ys[i])]
        if idx:
            t = sum(vorh[k] == ys[test[k]] for k in idx)
            print(f"{teil:16s} {len(idx):5d} testen  Grundlinie {t / len(idx):6.1%}")
    je = Counter(ys)
    print(f"  Eingaben je Rezept: {sorted(Counter(je.values()).items())}")

    grundlinie("skill_head", *lesen("data/skill_corpus.txt", "sample", 1, 3))

    gruppe_von, gleich = gleiche_kampf_metadaten()
    grundlinie("combat_skill", *lesen("data/combat_skill_corpus.txt", "combat", 1, 2), gruppe_von)
    print(f"  {len(gleich)} Gruppen mit gleichen Metadaten, {sum(map(len, gleich))} Kampffertigkeiten:")
    for g in sorted(gleich, key=lambda g: (-len(g), sorted(g))):
        print("   ", ", ".join(sorted(g)))


if __name__ == "__main__":
    main()
