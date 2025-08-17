#!/bin/bash

# Couleurs ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ "$1" == "--help" ]]; then
  echo "Usage: $0 [interface] [scan_duration] [dos_interval]"
  echo "  interface: nom de l'interface réseau (défaut: wlan1)"
  echo "  scan_duration: durée du scan en secondes (défaut: 600)"
  echo "  dos_interval: intervalle DOS simulé en secondes (défaut: 30)"
  exit 0
fi

IFACE=${1:-wlan1}
SCAN_DURATION=${2:-600}
DOS_INTERVAL=${3:-30}
LOG_DIR="$HOME/Security/airodump-dos"
DOS_LOG="$LOG_DIR/dos.log"

mkdir -p "$LOG_DIR"
> "$DOS_LOG"

cleanup() {
  echo -e "${CYAN}[*] Arrêt du script et nettoyage...${NC}"
  if [ -n "$AIRODUMP_PID" ]; then
    sudo kill "$AIRODUMP_PID" 2>/dev/null
  fi
  if [ -n "$DOS_PID" ]; then
    kill "$DOS_PID" 2>/dev/null
  fi
  sudo ip link set "$IFACE" down
  sudo ip link set "$IFACE" up
  exit 0
}

trap cleanup SIGINT SIGTERM

echo -e "${CYAN}[*] Vérification interface $IFACE...${NC}"
STATE=$(ip link show "$IFACE" | grep -Po 'state \K\w+')
if [[ "$STATE" != "UP" ]]; then
  echo -e "${YELLOW}[!] Interface $IFACE est DOWN. Remise UP...${NC}"
  sudo ip link set "$IFACE" up
  sleep 3
  STATE2=$(ip link show "$IFACE" | grep -Po 'state \K\w+')
  if [[ "$STATE2" != "UP" ]]; then
    echo -e "${RED}[!] Échec remise UP de $IFACE. Arrêt.${NC}"
    exit 1
  fi
fi
echo -e "${GREEN}[*] Interface $IFACE est UP.${NC}"

echo -e "${CYAN}[*] Passage en mode monitor sur $IFACE...${NC}"
sudo ip link set "$IFACE" down
sleep 1
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up
sleep 1

# Fonction DOS simulée qui tourne en background
dos_simulation() {
  while true; do
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${YELLOW}[*] → DOS : Client FAKE connecté à (notassociated) à $TIMESTAMP${NC}" | tee -a "$DOS_LOG"
    sleep "$DOS_INTERVAL"
  done
}

while true; do
  echo -e "${CYAN}[*] Lancement scan WiFi sur $IFACE pendant $SCAN_DURATION secondes...${NC}"

  sudo airodump-ng --write-interval 1 --output-format csv --write "$LOG_DIR/sniff" "$IFACE" &
  AIRODUMP_PID=$!

  dos_simulation &
  DOS_PID=$!

  sleep "$SCAN_DURATION"

  sudo kill "$AIRODUMP_PID" 2>/dev/null
  wait "$AIRODUMP_PID" 2>/dev/null

  kill "$DOS_PID" 2>/dev/null
  wait "$DOS_PID" 2>/dev/null

  echo -e "${GREEN}[*] Scan terminé.${NC}"
  echo -e "${CYAN}[*] Pause 60 secondes avant le prochain cycle...${NC}"
  sleep 60
done

