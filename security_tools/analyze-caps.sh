#!/bin/bash

CAP_DIR="/home/nox/Security/airodump-sniff"
OUI_FILE="/home/nox/Security/oui.txt"
EXCLUSION_FILE="/home/nox/Security/cmd.airmon-dos/exclusions.txt"
OUTPUT_DIR="/home/nox/Security/analyses-results"
NOW=$(date +'%Y%m%d-%H%M%S')
RESULT_FILE="${OUTPUT_DIR}/resultats-${NOW}.txt"
CSV_FILE="${OUTPUT_DIR}/resultats-${NOW}.csv"
ENRICHED_CSV_FILE="${OUTPUT_DIR}/resultats-${NOW}.enrichi.csv"
ENRICHED_TXT_FILE="${OUTPUT_DIR}/resultats-${NOW}.enrichi.txt"
MACS_PERSO_CSV="${OUTPUT_DIR}/mes-macs-${NOW}.enrichi.csv"
MACS_PERSO_TXT="${OUTPUT_DIR}/mes-macs-${NOW}.enrichi.txt"

mkdir -p "$OUTPUT_DIR"
TMP_DIR=$(mktemp -d)

AP_MACS="$TMP_DIR/ap_macs.txt"
STA_MACS="$TMP_DIR/sta_macs.txt"
MAC_INFO="$TMP_DIR/mac_info.txt"

# Fonction pour échapper les guillemets
safe() {
  echo "$1" | sed 's/"/\\"/g'
}

# Chargement exclusions dans un tableau associatif (mac en minuscule)
declare -A EXCLUDED
while read -r line; do
    # Extraction MAC depuis la ligne d’exclusion, découpage possible par espace/tabulation
    mac=$(echo "$line" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    [[ -n "$mac" ]] && EXCLUDED["$mac"]=1
done < "$EXCLUSION_FILE"

# Fonction pour savoir si un MAC est exclu
is_excluded_mac() {
    local mac_lc="$1"
    [[ ${EXCLUDED[$mac_lc]} ]] && return 0 || return 1
}

# Choix de l’extension des fichiers à analyser
if [[ "$1" == "DONE" ]]; then
    EXTENSIONS=("cap.done" "csv.done")
    echo "Mode DONE : analyse fichiers .done"
elif [[ "$1" == "NODONE" ]]; then
    EXTENSIONS=("cap" "csv")
    echo "Mode NODONE : pas de renommage"
else
    EXTENSIONS=("cap" "csv")
    echo "Mode normal : analyse fichiers .cap et .csv"
fi

echo "Début analyse dans $CAP_DIR avec extensions : ${EXTENSIONS[*]}" > "$RESULT_FILE"

# Nettoyage fichiers temporaires
> "$MAC_INFO"
> "$AP_MACS"
> "$STA_MACS"

# Analyse fichiers
for ext in "${EXTENSIONS[@]}"; do
    for f in "$CAP_DIR"/*."$ext"; do
        [[ -e "$f" ]] || continue
        if [[ "$ext" == "cap" || "$ext" == "cap.done" ]]; then
            echo "Analyse CAP: $f"
            tshark -r "$f" -Y "wlan.sa || wlan.da" -T fields -e frame.time_epoch -e wlan.bssid -e wlan.sa -e wlan.da 2>/dev/null | \
            while IFS=$'\t' read -r ts bssid sa da; do
                for mac in "$bssid" "$sa" "$da"; do
                    mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
                    [[ "$mac" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]] || continue
                    echo -e "${mac_lc}\t${ts}" >> "$MAC_INFO"
                done
            done
        elif [[ "$ext" == "csv" || "$ext" == "csv.done" ]]; then
            echo "Analyse CSV: $f"
            awk -F',' '
                BEGIN { ap=1; sta=0 }
                /^Station MAC/ { ap=0; sta=1; next }
                /^[[:space:]]*$/ { next }
                ap==1 && /^BSSID/ { next }
                ap==1 { gsub(/"/,"",$1); print toupper($1) > "'"$AP_MACS"'" }
                sta==1 { gsub(/"/,"",$1); print toupper($1) > "'"$STA_MACS"'" }
            ' "$f"
        fi
    done
done

# Déduplication
sort -u "$AP_MACS" -o "$AP_MACS"
sort -u "$STA_MACS" -o "$STA_MACS"
sort -u "$MAC_INFO" -o "$MAC_INFO"

echo "AP MACs trouvés : $(wc -l < "$AP_MACS")"
echo "STA MACs trouvés : $(wc -l < "$STA_MACS")"
echo "Entrées MAC_INFO : $(wc -l < "$MAC_INFO")"

# Préparation fichiers sortie classiques (exclure exclusions)
echo "MAC,TYPE,VENDOR,ROLE,COUNT,FIRST_SEEN" > "$CSV_FILE"
echo -e "MAC\tTYPE\tVENDOR\tROLE\tCOUNT\tFIRST_SEEN" > "$RESULT_FILE"

cat "$AP_MACS" "$STA_MACS" | sort -u | while read -r mac; do
    mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    if is_excluded_mac "$mac_lc"; then
        # Exclure des résultats classiques
        continue
    fi

    role="UNKNOWN"
    if grep -qx "$mac" "$AP_MACS"; then
        role="AP"
    elif grep -qx "$mac" "$STA_MACS"; then
        role="STA"
    fi

    vendor=$(grep -i "^${mac:0:8}" "$OUI_FILE" | head -n1 | cut -f2- -d$'\t')
    vendor=${vendor:-Unknown}
    vendor=$(safe "$vendor")

    count=$(grep -i "^$mac_lc" "$MAC_INFO" | wc -l)
    first_seen_epoch=$(grep -i "^$mac_lc" "$MAC_INFO" | cut -f2 | sort -n | head -n1)
    first_fmt=$(date -d @"$first_seen_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")

    echo "\"$mac\",\"UNKNOWN\",\"$vendor\",\"$role\",\"$count\",\"$first_fmt\"" >> "$CSV_FILE"
    printf "%-20s %-8s %-24s %-6s %-6s %-20s\n" "$mac" "UNKNOWN" "$vendor" "$role" "$count" "$first_fmt" >> "$RESULT_FILE"
done

# Préparation fichiers MACs perso (exclure les exclusions et enregistrer uniquement exclusions)
echo "MAC,TYPE,VENDOR,ROLE,COUNT,FIRST_SEEN" > "$MACS_PERSO_CSV"
echo -e "MAC\tTYPE\tVENDOR\tROLE\tCOUNT\tFIRST_SEEN" > "$MACS_PERSO_TXT"

cat "$AP_MACS" "$STA_MACS" | sort -u | while read -r mac; do
    mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    if ! is_excluded_mac "$mac_lc"; then
        continue
    fi

    role="UNKNOWN"
    if grep -qx "$mac" "$AP_MACS"; then
        role="AP"
    elif grep -qx "$mac" "$STA_MACS"; then
        role="STA"
    fi

    vendor=$(grep -i "^${mac:0:8}" "$OUI_FILE" | head -n1 | cut -f2- -d$'\t')
    vendor=${vendor:-Unknown}
    vendor=$(safe "$vendor")

    count=$(grep -i "^$mac_lc" "$MAC_INFO" | wc -l)
    first_seen_epoch=$(grep -i "^$mac_lc" "$MAC_INFO" | cut -f2 | sort -n | head -n1)
    first_fmt=$(date -d @"$first_seen_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")

    echo "\"$mac\",\"PERSO\",\"$vendor\",\"$role\",\"$count\",\"$first_fmt\"" >> "$MACS_PERSO_CSV"
    printf "%-20s %-8s %-24s %-6s %-6s %-20s\n" "$mac" "PERSO" "$vendor" "$role" "$count" "$first_fmt" >> "$MACS_PERSO_TXT"
done

# Génération fichier enrichi CSV complet (exclure exclusions)
echo "MAC,TYPE,VENDOR,ROLE,COUNT,FIRST_SEEN,TRAME" > "$ENRICHED_CSV_FILE"

cat "$AP_MACS" "$STA_MACS" | sort -u | while read -r mac; do
    mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    if is_excluded_mac "$mac_lc"; then
        continue
    fi

    role="UNKNOWN"
    if grep -qx "$mac" "$AP_MACS"; then
        role="AP"
    elif grep -qx "$mac" "$STA_MACS"; then
        role="STA"
    fi

    vendor=$(grep -i "^${mac:0:8}" "$OUI_FILE" | head -n1 | cut -f2- -d$'\t')
    vendor=${vendor:-Unknown}
    vendor=$(safe "$vendor")

    count=$(grep -i "^$mac_lc" "$MAC_INFO" | wc -l)
    first_seen_epoch=$(grep -i "^$mac_lc" "$MAC_INFO" | cut -f2 | sort -n | head -n1)
    first_fmt=$(date -d @"$first_seen_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")

    trame=$(grep -i "^$mac_lc" "$MAC_INFO" | cut -f3 | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
    trame=$(safe "$trame")

    echo "\"$mac\",\"UNKNOWN\",\"$vendor\",\"$role\",\"$count\",\"$first_fmt\",\"$trame\"" >> "$ENRICHED_CSV_FILE"
done

# Génération fichier enrichi TXT complet (exclure exclusions)
echo -e "MAC\tTYPE\tVENDOR\tROLE\tCOUNT\tFIRST_SEEN\tTRAME" > "$ENRICHED_TXT_FILE"
cat "$AP_MACS" "$STA_MACS" | sort -u | while read -r mac; do
    mac_lc=$(echo "$mac" | tr '[:upper:]' '[:lower:]')
    if is_excluded_mac "$mac_lc"; then
        continue
    fi

    role="UNKNOWN"
    if grep -qx "$mac" "$AP_MACS"; then
        role="AP"
    elif grep -qx "$mac" "$STA_MACS"; then
        role="STA"
    fi

    vendor=$(grep -i "^${mac:0:8}" "$OUI_FILE" | head -n1 | cut -f2- -d$'\t')
    vendor=${vendor:-Unknown}
    vendor=$(safe "$vendor")

    count=$(grep -i "^$mac_lc" "$MAC_INFO" | wc -l)
    first_seen_epoch=$(grep -i "^$mac_lc" "$MAC_INFO" | cut -f2 | sort -n | head -n1)
    first_fmt=$(date -d @"$first_seen_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "N/A")

    trame=$(grep -i "^$mac_lc" "$MAC_INFO" | cut -f3 | sort | uniq -c | sort -nr | head -n1 | awk '{print $2}')
    trame=$(safe "$trame")

    printf "%-20s %-8s %-24s %-6s %-6s %-20s %-10s\n" \
        "$mac" "UNKNOWN" "$vendor" "$role" "$count" "$first_fmt" "$trame" >> "$ENRICHED_TXT_FILE"
done

# Renommage conditionnel en .done
if [[ "$1" == "DONE" ]]; then
    echo "Renommage des fichiers .cap et .csv en .done (uniquement si pas déjà renommés)"
    for f in "$CAP_DIR"/*.{cap,csv}; do
        [[ -e "$f" ]] || continue
        if [[ "$f" != *.done ]]; then
            mv "$f" "${f}.done"
        fi
    done
elif [[ "$1" == "NODONE" ]]; then
    echo "Renommage désactivé (NODONE)"
else
    # Par défaut : renommer
    echo "Renommage des fichiers .cap et .csv en .done (uniquement si pas déjà renommés)"
    for f in "$CAP_DIR"/*.{cap,csv}; do
        [[ -e "$f" ]] || continue
        if [[ "$f" != *.done ]]; then
            mv "$f" "${f}.done"
        fi
    done
fi

echo -e "\nFichiers générés :"
echo " - TXT : $RESULT_FILE"
echo " - CSV : $CSV_FILE"
echo " - Enrichi CSV : $ENRICHED_CSV_FILE"
echo " - Enrichi TXT : $ENRICHED_TXT_FILE"
echo " - MACs Perso (CSV) : $MACS_PERSO_CSV"
echo " - MACs Perso (TXT) : $MACS_PERSO_TXT"

echo "Analyse terminée."

rm -rf "$TMP_DIR"
