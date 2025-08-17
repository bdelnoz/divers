#!/bin/bash
# Auteur : Bruno Delnoz
# Email  : bruno.delnoz@protonmail.com
# Version : 1.0 - 2025-07-19

DURATION=60
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/wifi_attack.log"
CSV_FILE="$LOG_DIR/wifi_attack.csv"

print_help() {
    echo "Usage: $0 --interface <wlanX> --mode <tcpdump|wifi>"
    echo ""
    echo "  --interface <wlanX>   Interface à surveiller (ex: wlan0, wlan1)"
    echo "  --mode <tcpdump|wifi> Mode de détection :"
    echo "                        tcpdump = ICMP/UDP"
    echo "                        wifi    = trames deauth/disassoc"
    exit 0
}

INTERFACE=""
MODE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --interface)
            INTERFACE="$2"
            shift 2
            ;;
        --mode)
            MODE="$2"
            shift 2
            ;;
        --help)
            print_help
            ;;
        *)
            print_help
            ;;
    esac
done

if [ -z "$INTERFACE" ] || [ -z "$MODE" ]; then
    print_help
fi

mkdir -p "$LOG_DIR"
[[ ! -f "$CSV_FILE" ]] && echo "Timestamp,Event,Details" > "$CSV_FILE"

check_monitor_support() {
    iw list | grep -A 10 'Supported interface modes' | grep -q 'monitor'
}

set_monitor_mode() {
    echo "$(date) : Vérification du support monitor pour $INTERFACE" | tee -a "$LOG_FILE"
    check_monitor_support
    if [ $? -ne 0 ]; then
        echo "$(date),Error,Monitor mode non supporté" >> "$CSV_FILE"
        echo "🔴 Monitor mode non supporté. Bascule vers mode tcpdump."
        MODE="tcpdump"
        return
    fi

    STATUS=$(nmcli -t -f DEVICE,STATE dev | grep "$INTERFACE" | cut -d: -f2)
    if [ "$STATUS" = "connected" ]; then
        nmcli dev disconnect "$INTERFACE"
    else
        echo "⚠️ $INTERFACE non connectée. Skipping disconnect."
    fi

    ip link set "$INTERFACE" down
    iw dev "$INTERFACE" set type monitor
    ip link set "$INTERFACE" up
    echo "$(date),Info,Monitor mode activé ($INTERFACE)" >> "$CSV_FILE"
}

restore_network() {
    ip link set "$INTERFACE" down
    iw dev "$INTERFACE" set type managed
    ip link set "$INTERFACE" up
    nmcli dev connect "$INTERFACE"
    nmcli radio wifi on
    echo "$(date),Restore,Interface restaurée en managed" >> "$CSV_FILE"
    echo ""
    echo "===== LOG COMPLET ====="
    cat "$LOG_FILE"
}

detect_tcpdump() {
    tcpdump -i "$INTERFACE" -nn -v -c 100 'icmp or udp' >> "$LOG_FILE"
    if grep -E "Destination Unreachable|Time Exceeded" "$LOG_FILE" > /dev/null; then
        echo "$(date),Attack,ICMP/UDP suspect" >> "$CSV_FILE"
    fi
}

detect_wifi() {
    tshark -I -i "$INTERFACE" -Y "wlan.fc.type_subtype == 0x0c || wlan.fc.type_subtype == 0x0a" -a duration:5 >> "$LOG_FILE" 2>&1
    if grep -E "Deauthentication|Disassociation" "$LOG_FILE" > /dev/null; then
        echo "$(date),Attack,Deauth/Disassoc détecté" >> "$CSV_FILE"
    else
        echo "$(date),Info,tshark n'a rien détecté (interface: $INTERFACE)" >> "$CSV_FILE"
    fi
}

monitor_wifi() {
    iw dev "$INTERFACE" scan >> "$LOG_FILE"
    if grep -E "Disconnected|Deauthenticating" "$LOG_FILE" > /dev/null; then
        echo "$(date),Suspicious,Déconnexion suspecte" >> "$CSV_FILE"
    fi
}

trap 'restore_network; echo "$(date),Stop,Arrêt par l’utilisateur (CTRL-C)" >> "$CSV_FILE"; exit 0' SIGINT

set_monitor_mode

if [ "$MODE" = "wifi" ] && ! check_monitor_support; then
    echo "$(date) : Mode monitor non dispo, bascule sur tcpdump" | tee -a "$LOG_FILE"
    MODE="tcpdump"
fi

while true; do
    end_time=$((SECONDS + DURATION))
    while [ $SECONDS -lt $end_time ]; do
        if [ "$MODE" = "tcpdump" ]; then
            detect_tcpdump
        elif [ "$MODE" = "wifi" ]; then
            detect_wifi
        fi
        monitor_wifi
        sleep 5
    done
    sleep 10
done
