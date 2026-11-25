#!/usr/bin/env python3
"""Die drei KONTOR_-Geheimnisse in die Actions-Secrets dieses Repos setzen.

WARUM es dieses Skript gibt: `gh` ist nicht ueberall installiert, und die
GitHub-API nimmt Geheimnisse nur verschluesselt an -- mit dem oeffentlichen
Schluessel des Repos, als libsodium-Sealed-Box.  Das von Hand zu bauen ist
genau die Art Handgriff, bei der man das Geheimnis versehentlich in eine
Shell-Historie schreibt.

Das Schreibtoken steht nie in einem Argument, sondern immer in einer DATEI
oder auf der Standardeingabe -- Argumente stehen in der Prozessliste und in
der Shell-Historie.

Aufruf:

    export GH_TOKEN=<PAT mit Recht "Secrets: write" auf dieses Repo>
    python3 tools/geheimnisse_setzen.py \\
        --url https://kontor.example:8443 \\
        --token-datei  ~/kontor-ci.token \\
        --ca-datei     <kontor-checkout>/tls/ca.crt

    # nur zeigen, was passieren wuerde:
    python3 tools/geheimnisse_setzen.py ... --trocken

Braucht `pynacl` (`pip install pynacl`).
"""

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"


def hole(pfad: str, token: str, methode: str = "GET", koerper: dict | None = None):
    daten = json.dumps(koerper).encode() if koerper is not None else None
    anfrage = urllib.request.Request(f"{API}{pfad}", data=daten, method=methode)
    anfrage.add_header("Authorization", f"Bearer {token}")
    anfrage.add_header("Accept", "application/vnd.github+json")
    anfrage.add_header("X-GitHub-Api-Version", "2022-11-28")
    if daten is not None:
        anfrage.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(anfrage, timeout=60) as antwort:
            roh = antwort.read()
            return antwort.status, (json.loads(roh) if roh else None)
    except urllib.error.HTTPError as fehler:
        return fehler.code, fehler.read().decode(errors="replace")


def lies(pfad: str) -> str:
    """Eine Datei, oder die Standardeingabe bei `-`."""
    if pfad == "-":
        return sys.stdin.read().strip()
    with open(os.path.expanduser(pfad), encoding="utf-8") as datei:
        return datei.read().strip()


def main() -> int:
    teiler = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    teiler.add_argument("--repo", default="Pymann/dc_traincorp")
    teiler.add_argument("--url", required=True, help="KONTOR_URL, ohne Schraegstrich am Ende")
    teiler.add_argument("--token-datei", required=True, help="Datei mit dem kontor-Schreibtoken, oder -")
    teiler.add_argument("--ca-datei", required=True, help="tls/ca.crt der kontor-Installation")
    teiler.add_argument("--trocken", action="store_true", help="nichts setzen, nur berichten")
    wahl = teiler.parse_args()

    gh = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not gh:
        print("GH_TOKEN fehlt (PAT mit Recht 'Secrets: write' auf das Repo).", file=sys.stderr)
        return 2

    werte = {
        "KONTOR_URL": wahl.url.rstrip("/"),
        "KONTOR_TOKEN": lies(wahl.token_datei),
        "KONTOR_CA": lies(wahl.ca_datei),
    }
    for name, wert in werte.items():
        if not wert:
            print(f"{name} ist leer.", file=sys.stderr)
            return 2
    if "BEGIN CERTIFICATE" not in werte["KONTOR_CA"]:
        print("--ca-datei sieht nicht wie ein PEM-Zertifikat aus.", file=sys.stderr)
        return 2

    print(f"Repo   : {wahl.repo}")
    for name, wert in werte.items():
        # Nie den Wert ausgeben.  Laenge und Rand genuegen zum Wiedererkennen.
        rand = f"{wert[:4]}…{wert[-4:]}" if len(wert) > 12 else "…"
        print(f"  {name:13s} {len(wert):5d} Zeichen  {rand}")
    if wahl.trocken:
        print("\n--trocken: nichts gesetzt.")
        return 0

    stand, schluessel = hole(f"/repos/{wahl.repo}/actions/secrets/public-key", gh)
    if stand != 200 or not isinstance(schluessel, dict):
        print(f"\nSchluessel nicht zu holen (HTTP {stand}): {schluessel}", file=sys.stderr)
        return 1

    from nacl.public import PublicKey, SealedBox  # erst hier: nur wenn wirklich gesetzt wird

    kiste = SealedBox(PublicKey(base64.b64decode(schluessel["key"])))
    fehler = 0
    print()
    for name, wert in werte.items():
        stand, antwort = hole(
            f"/repos/{wahl.repo}/actions/secrets/{name}", gh, "PUT",
            {"encrypted_value": base64.b64encode(kiste.encrypt(wert.encode())).decode(),
             "key_id": schluessel["key_id"]},
        )
        if stand in (201, 204):
            print(f"  {name:13s} {'angelegt' if stand == 201 else 'ersetzt'}")
        else:
            print(f"  {name:13s} FEHLER HTTP {stand}: {antwort}", file=sys.stderr)
            fehler += 1
    return 1 if fehler else 0


if __name__ == "__main__":
    raise SystemExit(main())
