#!/bin/bash

BASE_DIR="$(dirname "$0")"
CAP_DIR="$BASE_DIR/cap"
OUI_FILE="$BASE_DIR/myinfo/oui.txt"
EXCLUSION_FILE="$BASE_DIR/myinfo/exclusions.txt"
OUTPUT_DIR="$BASE_DIR/results"

mkdir -p "$OUTPUT_DIR"

echo "[*] Début analyse + split : $(date)"

mapfile -t exclusions < "$EXCLUSION_FILE"

# Fonction pour écrire une ligne dans un bloc de 50 max
write_split() {
  local filebase="$1"
  local line="$2"

  if [[ -z "${count[$filebase]}" ]]; then
    count[$filebase]=0
    part[$filebase]=1
    echo "TYPE,MAC,OUI,BSSID" > "$OUTPUT_DIR/${filebase}.part${part[$filebase]}.csv"
  fi

  echo "$line" >> "$OUTPUT_DIR/${filebase}.part${part[$filebase]}.csv"
  ((count[$filebase]++))

  if [[ ${count[$filebase]} -ge 50 ]]; then
    ((part[$filebase]++))
    count[$filebase]=0
    echo "TYPE,MAC,OUI,BSSID" > "$OUTPUT_DIR/${filebase}.part${part[$filebase]}.csv"
  fi
}

#####
# 1️⃣ ANALYSE .CSV
#####
for csv in "$CAP_DIR"/*.csv; do
  [[ ! -f "$csv" ]] && continue
  base=$(basename "$csv")
  filebase="${base%.csv}.filtered"

  echo "[*] CSV : $base"

  awk -F',' '
    NR>1 && NF>1 && $1 !~ /Station/ && $1 !~ /^$/ {
      gsub(/ /,"",$1); print "BSSID," $1
    }
  ' "$csv" > /tmp/bssid_list.txt

  awk -F',' '
    BEGIN {s=0}
    /^$/ {s++}
    s==1 && NF>1 && $1 ~ /Station/ {next}
    s==1 && NF>1 && $1 !~ /^$/ {
      gsub(/ /,"",$1); gsub(/ /,"",$2)
      print "STATION," $1 "," $2
    }
  ' "$csv" > /tmp/station_list.txt

  while IFS=',' read -r type mac; do
    skip=0; for excl in "${exclusions[@]}"; do [[ "$mac" == "$excl" ]] && skip=1 && break; done
    [[ $skip -eq 0 ]] && oui=$(grep -i "^${mac:0:8}" "$OUI_FILE" | awk '{print $2}') && oui=${oui:-unknown} && write_split "$filebase" "$type,$mac,$oui,"
  done < /tmp/bssid_list.txt

  while IFS=',' read -r type station_mac bssid; do
    skip=0; for excl in "${exclusions[@]}"; do [[ "$station_mac" == "$excl" ]] && skip=1 && break; done
    [[ $skip -eq 0 ]] && oui=$(grep -i "^${station_mac:0:8}" "$OUI_FILE" | awk '{print $2}') && oui=${oui:-unknown} && write_split "$filebase" "$type,$station_mac,$oui,$bssid"
  done < /tmp/station_list.txt

done

#####
# 2️⃣ ANALYSE .CAP avec tshark
#####
for cap in "$CAP_DIR"/*.cap; do
  [[ ! -f "$cap" ]] && continue
  base=$(basename "$cap")
  filebase="${base%.cap}.filtered"

  echo "[*] CAP : $base"

  tshark -r "$cap" -Y "wlan.fc.type_subtype == 8" -T fields -e wlan.bssid | sort -u | while read -r mac; do
    [[ -z "$mac" ]] && continue
    skip=0; for excl in "${exclusions[@]}"; do [[ "$mac" == "$excl" ]] && skip=1 && break; done
    [[ $skip -eq 0 ]] && oui=$(grep -i "^${mac:0:8}" "$OUI_FILE" | awk '{print $2}') && oui=${oui:-unknown} && write_split "$filebase" "BSSID,$mac,$oui,"
  done

  tshark -r "$cap" -Y "wlan.fc.type == 2" -T fields -e wlan.sa -e wlan.bssid | sort -u | while read -r sa bssid; do
    [[ -z "$sa" || -z "$bssid" ]] && continue
    [[ "$sa" == "$bssid" ]] && continue
    skip=0; for excl in "${exclusions[@]}"; do [[ "$sa" == "$excl" ]] && skip=1 && break; done
    [[ $skip -eq 0 ]] && oui=$(grep -i "^${sa:0:8}" "$OUI_FILE" | awk '{print $2}') && oui=${oui:-unknown} && write_split "$filebase" "STATION,$sa,$oui,$bssid"
  done

done

echo "[*] Fin analyse & split : $OUTPUT_DIR"
