#!/usr/bin/env bash
# Die drei KONTOR_-Geheimnisse dieses Repos in einem Aufruf setzen.
#
#   ./tools/einrichten.sh              # setzt sie
#   ./tools/einrichten.sh --trocken    # zeigt nur, was passieren wuerde
#
# Gefragt wird nur nach dem GitHub-PAT (verdeckt).  Alles andere kommt aus
# tools/einrichten.conf -- die Datei ist nicht eingecheckt, weil dieses Repo
# oeffentlich ist und Adresse und Pfade der eigenen Ablage nicht hineingehoeren.
# Fehlt sie, fragt das Skript die drei Angaben einmal ab und legt sie an.
#
# Reihenfolge mit Absicht: ERST pruefen, ob das kontor-Token ueberhaupt traegt,
# DANN in GitHub schreiben.  Ein Geheimnis, das man nicht mehr auslesen kann,
# soll nicht schon falsch hineingehen.
set -euo pipefail

hier="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
wurzel="$(cd "$hier/.." && pwd)"
conf="$hier/einrichten.conf"
trocken=0
[ "${1:-}" = "--trocken" ] && trocken=1

sag()  { printf '%s\n' "$*"; }
nein() { printf '\n%s\n' "FEHLER: $*" >&2; exit 1; }

# ── Voraussetzungen ───────────────────────────────────────────────────────────
command -v curl    >/dev/null || nein "curl fehlt."
command -v python3 >/dev/null || nein "python3 fehlt."
python3 -c 'import nacl.public' 2>/dev/null || nein \
  "pynacl fehlt.  Nachinstallieren mit: python3 -m pip install --user pynacl"

# ── Angaben ───────────────────────────────────────────────────────────────────
if [ -f "$conf" ]; then
  # shellcheck disable=SC1090
  . "$conf"
else
  sag "tools/einrichten.conf gibt es noch nicht -- einmal die drei Angaben:"
  read -r -p "  kontor-Adresse (z.B. https://host:8443): " KONTOR_URL
  read -r -p "  Pfad zu tls/ca.crt der kontor-Installation: " CA_DATEI
  read -r -p "  Pfad zur Datei mit dem kontor-Schreibtoken: " TOKEN_DATEI
  umask 077
  cat > "$conf" <<EOF
# Oertliche Angaben, nicht eingecheckt (.gitignore).
KONTOR_URL="$KONTOR_URL"
CA_DATEI="$CA_DATEI"
TOKEN_DATEI="$TOKEN_DATEI"
EOF
  sag "  -> gemerkt in tools/einrichten.conf"
fi

KONTOR_URL="${KONTOR_URL%/}"
CA_DATEI="${CA_DATEI/#\~/$HOME}"
TOKEN_DATEI="${TOKEN_DATEI/#\~/$HOME}"
[ -n "${KONTOR_URL:-}"  ] || nein "KONTOR_URL ist leer."
[ -r "${CA_DATEI:-}"    ] || nein "CA-Datei nicht lesbar: ${CA_DATEI:-<leer>}"
[ -r "${TOKEN_DATEI:-}" ] || nein "Token-Datei nicht lesbar: ${TOKEN_DATEI:-<leer>}"
grep -q 'BEGIN CERTIFICATE' "$CA_DATEI" || nein "$CA_DATEI sieht nicht wie ein PEM aus."

# ── Traegt das Token? ─────────────────────────────────────────────────────────
sag ""
sag "1/3  kontor fragen, ob das Token traegt"
antwort="$(curl --silent --show-error --max-time 30 --cacert "$CA_DATEI" \
                -H "Authorization: Bearer $(cat "$TOKEN_DATEI")" \
                "$KONTOR_URL/api/v1/whoami")" \
  || nein "kontor nicht erreichbar (Adresse, CA oder Netz).  Antwort: ${antwort:-<keine>}"
case "$antwort" in
  *'"roles"'*write*|*'"roles"'*admin*) sag "     $antwort" ;;
  *) nein "Token taugt nicht zum Schreiben.  Antwort: $antwort" ;;
esac

# ── GitHub-PAT ────────────────────────────────────────────────────────────────
sag ""
sag "2/3  GitHub-Zugang"
repo="$(git -C "$wurzel" remote get-url origin 2>/dev/null \
        | sed -E 's#.*github\.com[:/]+([^/]+/[^/.]+)(\.git)?$#\1#')"
[ -n "$repo" ] || nein "origin ist kein github.com-Repo."

# Ein PAT laesst sich nur von Hand auf github.com erzeugen -- eine API dafuer
# gibt es nicht.  Aber meistens liegt schon eines da: git hat eines, sonst
# koenntest du nicht pushen.  Darum in dieser Reihenfolge fragen:
#   1. GH_TOKEN/GITHUB_TOKEN aus der Umgebung
#   2. den git-Credential-Helfer (helferunabhaengig, ueber `git credential`)
#   3. von Hand eingeben
quelle=""
if [ -n "${GH_TOKEN:-}" ];     then quelle="GH_TOKEN"
elif [ -n "${GITHUB_TOKEN:-}" ]; then GH_TOKEN="$GITHUB_TOKEN"; quelle="GITHUB_TOKEN"
else
  # GIT_TERMINAL_PROMPT=0 und GIT_ASKPASS sind Pflicht, nicht Vorsicht: findet
  # der Helfer nichts, will `git credential fill` sonst einen Benutzernamen vom
  # Terminal lesen -- und das Skript haengt.  Gemessen 25.11.2026.
  GH_TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' \
              | GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true git credential fill 2>/dev/null \
              | sed -n 's/^password=//p' | head -1 || true)"
  [ -n "$GH_TOKEN" ] && quelle="git-Credential-Helfer"
fi
if [ -z "${GH_TOKEN:-}" ]; then
  sag "     keines gefunden -- eines anlegen auf"
  sag "     https://github.com/settings/personal-access-tokens/new"
  sag "     (nur dieses Repo, Repository permissions -> Secrets: Read and write)"
  read -r -s -p "     hier einfuegen (bleibt unsichtbar), dann Enter: " GH_TOKEN
  printf '\n'
  quelle="Eingabe"
fi
[ -n "$GH_TOKEN" ] || nein "kein Zugang."
export GH_TOKEN
sag "     Quelle: $quelle"

# Reicht es?  Lieber hier scheitern als auf halbem Weg.  Der oeffentliche
# Schluessel liegt hinter demselben Recht wie das Schreiben der Geheimnisse.
stand="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 30 \
         -H "Authorization: Bearer $GH_TOKEN" \
         -H "Accept: application/vnd.github+json" \
         "https://api.github.com/repos/$repo/actions/secrets/public-key")"
case "$stand" in
  200) sag "     Recht auf Geheimnisse: ja" ;;
  401) nein "Zugang abgelehnt (401).  Token abgelaufen oder widerrufen." ;;
  403|404) nein "Zugang reicht nicht ($stand).  Ein klassisches PAT braucht den
         Haken 'repo', ein feingranulares das Recht 'Secrets: Read and write'
         auf $repo.  Neu anlegen:
         https://github.com/settings/personal-access-tokens/new" ;;
  *) nein "unerwartete Antwort von GitHub: HTTP $stand" ;;
esac

# ── Setzen ────────────────────────────────────────────────────────────────────
sag ""
sag "3/3  Geheimnisse setzen"
if [ "$trocken" = "1" ]; then
  python3 "$hier/geheimnisse_setzen.py" --url "$KONTOR_URL" \
      --token-datei "$TOKEN_DATEI" --ca-datei "$CA_DATEI" --trocken
  sag ""
  sag "--trocken: nichts gesetzt."
  exit 0
fi
python3 "$hier/geheimnisse_setzen.py" --url "$KONTOR_URL" \
    --token-datei "$TOKEN_DATEI" --ca-datei "$CA_DATEI"

# Gegenprobe: GitHub nennt die Namen (nie die Werte).
if [ -n "$repo" ]; then
  sag ""
  sag "Gegenprobe -- was GitHub jetzt kennt:"
  curl --silent --max-time 30 -H "Authorization: Bearer $GH_TOKEN" \
       -H "Accept: application/vnd.github+json" \
       "https://api.github.com/repos/$repo/actions/secrets" \
    | python3 -c 'import json,sys
d=json.load(sys.stdin)
namen={s["name"] for s in d.get("secrets",[])}
for n in ("KONTOR_URL","KONTOR_TOKEN","KONTOR_CA"):
    print(f"  {n:13s} {\"steht\" if n in namen else \"FEHLT\"}")
uebrig=sorted(namen-{"KONTOR_URL","KONTOR_TOKEN","KONTOR_CA"})
if uebrig: print("  (weitere: "+", ".join(uebrig)+")")'
fi

unset GH_TOKEN
sag ""
sag "Fertig.  Naechster Schritt:"
sag "  Actions -> Training -> Run workflow, schritte: nur-pruefen"
sag "Das PAT hat seinen Zweck erfuellt -- auf GitHub widerrufen."
