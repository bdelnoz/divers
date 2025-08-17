#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DIR_CAP="cap"
DIR_CSV="csv"
DIR_MYCSV="mycsv"
DIR_CSVENRICH="csvenrich"
DIR_GENERATED="generated"
LOG_DIR="logs"
TMP_DIR="tmp"
MYINFO_DIR="myinfo"

DEFAULT_IFACE="wlan1"
DEFAULT_DURATION=20

usage() {
  cat <<EOF
Usage: $0 [interface] [durée]
Capture WiFi avancée en mode monitor avec airodump-ng.

Arguments :
  interface : interface WiFi (par défaut : $DEFAULT_IFACE)
  durée     : durée de la capture en secondes (par défaut : $DEFAULT_DURATION)

Exemples :
  $0
  $0 wlan1
  $0 wlan2 60

Fichiers utilisés :
  - myinfo/exclusions.txt (MAC à exclure)
  - myinfo/oui.txt (base OUI fabricant)

Dossiers générés automatiquement :
  cap/, csv/, mycsv/, csvenrich/, generated/, logs/, tmp/, myinfo/

Ce script nécessite sudo en interne, pas à l'appel.
EOF
}

die() {
  echo "ERREUR: $*" >&2
  cleanup
  exit 1
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

prepare_dirs() {
  mkdir -p "$DIR_CAP" "$DIR_CSV" "$DIR_MYCSV" "$DIR_CSVENRICH" "$DIR_GENERATED" "$LOG_DIR" "$TMP_DIR" "$MYINFO_DIR"
}

archive_old_files() {
  for dir in "$DIR_CAP" "$DIR_CSV" "$DIR_MYCSV" "$DIR_CSVENRICH"; do
    find "$dir" -type f ! -name '*.done' -exec bash -c 'mv "$0" "$0.done"' {} \;
  done
}

generate_prefix() {
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local i=1
  local prefix="${timestamp}_$i"
  while [[ -e "$DIR_CAP/${prefix}-01.cap" || -e "$DIR_CSV/${prefix}-01.csv" ]]; do
    ((i++))
    prefix="${timestamp}_$i"
  done
  PREFIX="$prefix"
}

monitor_on() {
  log "Mise en mode monitor de l'interface $IFACE"
  sudo ip link set "$IFACE" down
  sudo iw "$IFACE" set monitor control
  sudo ip link set "$IFACE" up
  sleep 1
  if ! iw "$IFACE" info 2>/dev/null | grep -q "type monitor"; then
    die "L'interface $IFACE n'est PAS en mode monitor. Désactivez NetworkManager/wpa_supplicant, puis relancez."
  fi
  sudo nmcli device set "$IFACE" managed no || log "Attention: Impossible de désactiver NetworkManager sur $IFACE"
}

monitor_off() {
  log "Remise en mode managed de l'interface $IFACE"
  sudo ip link set "$IFACE" down
  sudo iw "$IFACE" set type managed
  sudo ip link set "$IFACE" up
  sleep 1
  sudo nmcli device set "$IFACE" managed yes || log "Attention: Impossible de réactiver NetworkManager sur $IFACE"
}

check_deps() {
  for cmd in sudo timeout airodump-ng tee grep awk sed ip iw nmcli; do
    if ! command -v "$cmd" &>/dev/null; then
      die "Commande requise manquante : $cmd"
    fi
  done
  if [[ ! -f "$MYINFO_DIR/exclusions.txt" ]]; then
    die "Fichier d'exclusions manquant : $MYINFO_DIR/exclusions.txt"
  fi
  if [[ ! -f "$MYINFO_DIR/oui.txt" ]]; then
    die "Fichier OUI manquant : $MYINFO_DIR/oui.txt"
  fi
}

cleanup() {
  monitor_off
}

spinner() {
  local pid=$1
  local delay=0.1
  local spinstr='|/-\'
  while kill -0 "$pid" 2>/dev/null; do
    for ((i=0; i<${#spinstr}; i++)); do
      printf "\rCapture en cours  [%c]  %s" "${spinstr:i:1}" "$(date '+%H:%M:%S')"
      sleep "$delay"
    done
  done
  printf "\rCapture terminée à %s\n" "$(date '+%H:%M:%S')"
}

clean_tmp() {
  local filecount
  local totalsize
  filecount=$(find "$TMP_DIR" -type f | wc -l)
  totalsize=$(du -sm "$TMP_DIR" | awk '{print $1}')
  if ((filecount > 100 || totalsize > 10)); then
    log "Nettoyage du dossier tmp/ ($filecount fichiers, ${totalsize}Mo)"
    rm -f "$TMP_DIR"/*
  fi
}

post_process_csv() {
  local csv_in="$1"
  local csv_filtered="$2"
  local csv_enriched="$3"

  local exclusions
  exclusions=$(grep -v '^\s*#' "$MYINFO_DIR/exclusions.txt" | grep -v '^\s*$' | tr '[:lower:]' '[:upper:]')

  awk -v excl="$exclusions" '
  BEGIN {
    split(excl, arr, "\n");
    for (i in arr) exclude[arr[i]]=1;
  }
  NR==1 { print; next }
  {
    mac=toupper($1);
    if (!(mac in exclude)) print
  }' "$csv_in" > "$csv_filtered"

  awk -F',' 'BEGIN {
    while ((getline line < "'"$MYINFO_DIR/oui.txt"'") > 0) {
      split(line, a, "\t");
      oui[a[1]]=a[2]
    }
  }
  NR==1 { print $0",Manufacturer"; next }
  {
    oui_prefix=toupper(substr($1,1,8));
    manuf=(oui[oui_prefix] ? oui[oui_prefix] : "Unknown");
    print $0","manuf
  }' "$csv_filtered" > "$csv_enriched"
}

main() {
  if [[ $# -eq 0 || "$1" == "--help" ]]; then
    usage
    exit 0
  fi

  IFACE="${1:-$DEFAULT_IFACE}"
  DURATION="${2:-$DEFAULT_DURATION}"

  prepare_dirs
  generate_prefix

  LOG_FILE="$LOG_DIR/${PREFIX}.log"
  exec > >(tee -a "$LOG_FILE") 2>&1

  check_deps
  archive_old_files
  clean_tmp

  log "Début du script all.sh avec interface=$IFACE durée=${DURATION}s"

  monitor_on
  AIRODUMP_CMD=(
    sudo timeout "${DURATION}s" airodump-ng
    --manufacturer
    --showack
    --beacons
    --uptime
    --output-format csv,pcap
    --write "$DIR_CAP/${PREFIX}"
    --write-interval 5
    --update 1
    -b abg
    -c 1,2,3,4,5,6,7,8,9,10,11,12,13,14,36,40,44,48,52,56,60,64,100,104,108,112,116,120,124,128,132,136,140,144,149,153,157,161,165
    "$IFACE"
  )

  log "Lancement de la capture WiFi avec airodump-ng"
  "${AIRODUMP_CMD[@]}" &
  AIRODUMP_PID=$!

  spinner "$AIRODUMP_PID"
  wait "$AIRODUMP_PID"

  CSV_FILE="${DIR_CAP}/${PREFIX}-01.csv"
  if [[ ! -s "$CSV_FILE" ]]; then
    die "Aucun fichier de capture généré. L’interface $IFACE est-elle en monitor ? Un service la bloque-t-il ?"
  fi

  CSV_FILTERED="${DIR_MYCSV}/${PREFIX}-01.filtered.csv"
  CSV_ENRICHED="${DIR_CSVENRICH}/${PREFIX}-01.enriched.csv"
  post_process_csv "$CSV_FILE" "$CSV_FILTERED" "$CSV_ENRICHED"

  cp "${DIR_CAP}/${PREFIX}-01.cap" "$DIR_GENERATED/" 2>/dev/null || true
  cp "${DIR_CSV}/${PREFIX}-01.csv" "$DIR_GENERATED/" 2>/dev/null || true
  cp "$CSV_FILTERED" "$DIR_GENERATED/" 2>/dev/null || true
  cp "$CSV_ENRICHED" "$DIR_GENERATED/" 2>/dev/null || true

  monitor_off

  exec > /dev/tty 2>&1

  echo "====== FICHIERS GÉNÉRÉS ======"
  ls -lh "$DIR_GENERATED"

  echo "====== CONTENU DES CSV ======"
  for f in "$CSV_FILE" "$CSV_FILTERED" "$CSV_ENRICHED"; do
    if [[ -s "$f" ]]; then
      echo "----- $f -----"
      cat "$f"
      echo
    else
      echo "----- $f ----- vide ou absent"
    fi
  done

  echo "====== FIN ======"

  log "Fin du script all.sh"
}

trap cleanup EXIT
main "$@"
