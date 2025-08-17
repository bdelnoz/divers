#!/bin/bash
# Auteur : Bruno DELNOz
# Email  : bruno.delnoz@protonmail.com
# Nom du script : cmd.airo.wlan1.fr.sh
# Target usage : Capture airodump-ng avec gestion automatique des fichiers et restauration interface
# Version : v1.0 - Date : 2025-08-03
# Changelog :
# v1.0 - 2025-08-03 : Script initial complet avec capture, renommage, logs, restauration interface, --help avec exemples, gestion signal et interruptions

set -euo pipefail

# ==============================
# CONFIGURATION
# ==============================
DEFAULT_IFACE="wlan1"
DEFAULT_DURATION=60

BASE_DIR="$(pwd)"
CAP_DIR="${BASE_DIR}/cap"
CSV_DIR="${BASE_DIR}/cap"

mkdir -p "$CAP_DIR" "$CSV_DIR"

show_help() {
  cat << EOF
Usage: $0 [interface] [durée_en_secondes]

Options :
  interface          Interface réseau (défaut: $DEFAULT_IFACE)
  durée_en_secondes  Durée du scan (défaut: $DEFAULT_DURATION)

Exemples :
  $0 wlan1 30
  sudo $0 wlan1 30    # Utiliser sudo si le script n'est pas lancé avec sudo

Fonction :
- Passe l'interface en mode monitor.
- Lance airodump-ng sur toutes les bandes abg avec Manufacturer, Uptime, Beacons.
- Sauvegarde fichiers CSV et PCAP dans ./cap en incrémentant les noms.
- Restaure l'interface en mode managed proprement.
- Logs détaillés dans un fichier .log dans le même dossier.

Important :
- Le script contient tous les sudo nécessaires, pas besoin de lancer "sudo ./script.sh" sauf si tu veux.
EOF
  exit 0
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && show_help

IFACE="${1:-$DEFAULT_IFACE}"
DURATION="${2:-$DEFAULT_DURATION}"
PREFIX="sniff-airodump"

USER=$(whoami)
GROUP=$(id -gn)

LOG_FILE="${BASE_DIR}/$(basename "$0" .sh).log"

log() {
  local msg="[$(date '+%H:%M:%S')] $*"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup() {
  log "Interruption reçue ➜ Restaure $IFACE..."
  sudo ip link set "$IFACE" down
  sudo iw dev "$IFACE" set type managed
  sudo ip link set "$IFACE" up
  sudo nmcli device set "$IFACE" managed yes
  log "Interface rétablie."
  exit 130
}
trap cleanup INT TERM

log "Interface : $IFACE"
log "Durée : $DURATION secondes"

# Désactive NetworkManager sur l'interface
sudo nmcli device set "$IFACE" managed no

if ! ip link show "$IFACE" &>/dev/null; then
  log "Erreur : interface $IFACE introuvable."
  exit 1
fi

log "Passage $IFACE ➜ monitor..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up

log "Lancement airodump-ng..."

(
  sleep "$DURATION"
  log "Durée atteinte ➜ kill -9 airodump-ng..."
  sudo pkill -9 airodump-ng
) &

set +e
sudo airodump-ng \
  --showack --real-time \
  --manufacturer --uptime --beacons \
  -b abg \
  --write "$PREFIX" \
  --output-format csv,pcap \
  "$IFACE"
AIRO_EXIT=$?
set -e

if [[ $AIRO_EXIT -ne 0 && $AIRO_EXIT -ne 137 ]]; then
  log "Attention : airodump-ng s'est terminé avec le code $AIRO_EXIT"
fi

log "Scan terminé ➜ Fichiers générés :"
ls -lh "${PREFIX}-01.cap" "${PREFIX}-01.csv" 2>/dev/null || log "Aucun fichier généré."

get_max_index() {
  local dir=$1
  local prefix=$2
  local ext=$3
  local max=0
  for f in "$dir"/${prefix}-*.${ext}; do
    [[ -e "$f" ]] || continue
    local basefile=$(basename "$f")
    if [[ $basefile =~ ${prefix}-([0-9]+)\.${ext} ]]; then
      local num="${BASH_REMATCH[1]}"
      num=$((10#$num))
      (( num > max )) && max=$num
    fi
  done
  echo "$max"
}

max_cap=$(get_max_index "$CAP_DIR" "$PREFIX" "cap")
max_csv=$(get_max_index "$CSV_DIR" "$PREFIX" "csv")
max_index=$(( max_cap > max_csv ? max_cap : max_csv ))
next_index=$(( max_index + 1 ))

cap_src="${PREFIX}-01.cap"
csv_src="${PREFIX}-01.csv"
cap_dest="${CAP_DIR}/${PREFIX}-$(printf '%02d' "$next_index").cap"
csv_dest="${CSV_DIR}/${PREFIX}-$(printf '%02d' "$next_index").csv"

if [[ -f "$cap_src" ]]; then
  cp -f "$cap_src" "$cap_dest"
  log "Copie $cap_src → $cap_dest"
  rm -f "$cap_src"
else
  log "Fichier $cap_src introuvable, copie annulée."
fi

if [[ -f "$csv_src" ]]; then
  cp -f "$csv_src" "$csv_dest"
  log "Copie $csv_src → $csv_dest"
  rm -f "$csv_src"
else
  log "Fichier $csv_src introuvable, copie annulée."
fi

log "Restauration de l'interface $IFACE en mode managed..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type managed
sudo ip link set "$IFACE" up

sudo nmcli device set "$IFACE" managed yes

sudo chown -R "$USER":"$GROUP" "$CAP_DIR" "$CSV_DIR"

log "Résultats dans :"
ls -lh "$CAP_DIR" "$CSV_DIR"

log "✅ Script terminé proprement."

