#!/bin/bash
# Installation de la sonde d'activité Epitech.
#
#   curl -fsSL https://zeno.epitech.africa/sonde/install.sh | sudo bash
#
# Généré par Zeno — ne pas modifier à la main.
# AUCUN secret, ni ici ni dans la réponse du serveur : la clé délivrée ne vaut
# que pour CE poste. Le poste arrive « en attente » et ne compte pour rien tant
# qu'un membre de l'équipe pédagogique ne l'a pas rattaché à un étudiant.
set -euo pipefail

BASE="https://zeno.epitech.africa"
EXPECTED_SHA="60bd0b0db09703dce1a79e6b080029ba3d02fc2e17b3172d0a53861805d3b774"
CONF_DIR=/etc/epitech-tracker
DEB=/tmp/epitech-tracker.deb

red()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { red "✗ $*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "à lancer avec sudo : curl -fsSL $BASE/sonde/install.sh | sudo bash"
command -v curl >/dev/null || die "curl est requis"

# 1. Identité déclarée par l'étudiant. Pas de mail Epitech, pas de matricule :
#    juste le nom, confirmé à l'écran juste après.
if [ -r /dev/tty ]; then exec 3</dev/tty; else die "aucun terminal interactif disponible"; fi
printf 'Prénom : ' ; read -r PRENOM <&3
printf 'Nom    : ' ; read -r NOM    <&3
[ -n "$PRENOM" ] && [ -n "$NOM" ] || die "prénom et nom sont obligatoires"

# 2. Enrôlement. Un nom qui ne correspond à aucun étudiant connu n'échoue pas :
#    un pédagogue rattachera le poste ensuite.
bold "→ Vérification de la connexion au serveur…"
bold "→ Enregistrement du poste…"
PAYLOAD="$(printf '{"prenom":%s,"nom":%s,"identite_machine":{"unix_user":%s,"hostname":%s,"fingerprint":%s}}' \
  "$(printf '%s' "$PRENOM" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
  "$(printf '%s' "$NOM"    | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
  "$(printf '%s' "${SUDO_USER:-$(logname 2>/dev/null || echo unknown)}" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')" \
  "$(hostname | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read().strip()))')" \
  "$(cat /sys/class/dmi/id/product_uuid 2>/dev/null | python3 -c 'import json,sys,hashlib;d=sys.stdin.read().strip();print(json.dumps(hashlib.sha256(d.encode()).hexdigest() if d else ""))')")"

RESP="$(curl -fsS -X POST "$BASE/api/sonde/enroll" \
  -H 'Content-Type: application/json' -d "$PAYLOAD")" \
  || die "enregistrement refusé ($BASE injoignable, ou trop de tentatives)."

read -r DEVICE_ID KEY DISPLAY_NAME <<EOF2
$(printf '%s' "$RESP" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("deviceId",""), d.get("key",""), d.get("displayName",""))
')
EOF2
[ -n "$DEVICE_ID" ] && [ -n "$KEY" ] || die "réponse du serveur incomplète : $RESP"

bold ""
bold "  Poste enregistré pour : $DISPLAY_NAME"
bold "  Si ce n'est pas vous, prévenez immédiatement l'équipe pédagogique."
bold ""

# 3. Identité du poste, écrite AVANT l'installation : le paquet refuse de
#    démarrer sans elle, ce qui évite une sonde qui tourne dans le vide.
install -d -m 755 "$CONF_DIR"
umask 077
python3 - "$CONF_DIR/identity.json" "$DEVICE_ID" "$KEY" "$PRENOM" "$NOM" <<'PY'
import json, sys
path, device_id, key, prenom, nom = sys.argv[1:6]
with open(path, "w") as f:
    json.dump({"deviceId": device_id, "key": key,
               "declaredFirstName": prenom, "declaredLastName": nom}, f)
PY
chmod 600 "$CONF_DIR/identity.json"
printf 'EPITECH_TRACKER_API_URL=%s\n' "$BASE" > "$CONF_DIR/tracker.env"
chmod 600 "$CONF_DIR/tracker.env"

# 4. Paquet + vérification d'intégrité (sha256, pas la taille).
bold "→ Téléchargement de l'agent…"
curl -fsSL -o "$DEB" "$BASE/sonde/tools.deb" || die "téléchargement impossible."
if [ -n "$EXPECTED_SHA" ]; then
  GOT="$(sha256sum "$DEB" | cut -d' ' -f1)"
  [ "$GOT" = "$EXPECTED_SHA" ] || die "paquet corrompu (sha256 $GOT ≠ $EXPECTED_SHA)."
fi

bold "→ Installation…"
apt-get install -y "$DEB" >/dev/null || die "installation échouée."
rm -f "$DEB"

for _ in 1 2 3 4 5; do
  systemctl is-active --quiet epitech-tracker && break
  sleep 1
done
systemctl is-active --quiet epitech-tracker \
  || die "le service ne démarre pas — 'journalctl -u epitech-tracker' pour comprendre."

bold ""
bold "✓ Terminé. L'agent tourne et remonte l'activité toutes les 5 minutes."
