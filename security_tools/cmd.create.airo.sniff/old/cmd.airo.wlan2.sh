#!/bin/bash

set -euo pipefail

DEFAULT_IFACE="wlan2"
DEFAULT_DURATION=60

IFACE=${1:-$DEFAULT_IFACE}
DURATION=${2:-$DEFAULT_DURATION}

DIR="/home/nox/Security/scripts/data/airodump-sniff"
NOW=$(date +'%Y%m%d-%H%M%S')
OUTPUT_PREFIX="sniff-airodump-${IFACE}-$NOW"
USER="nox"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

cleanup() {
  log "Interrupt received (Ctrl+C), switching $IFACE back to managed mode..."
  sudo ip link set "$IFACE" down
  sudo iw dev "$IFACE" set type managed
  sudo ip link set "$IFACE" up
  log "Done."
  exit 130
}

trap cleanup INT

log "Selected interface: $IFACE"
log "Scan duration: $DURATION seconds"

log "Checking interface $IFACE..."
if ! ip link show "$IFACE" > /dev/null 2>&1; then
  log "Error: Interface $IFACE not found."
  exit 1
fi

log "Switching $IFACE to monitor mode..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up

log "Changing working directory to: $DIR"
cd "$DIR" || { log "Error: Cannot access directory $DIR"; exit 1; }

log "Starting airodump-ng on $IFACE for $DURATION seconds..."

sudo airodump-ng --gpsd --showack --real-time --manufacturer --uptime --beacons -b abg --write "$OUTPUT_PREFIX" --output-format csv,pcap "$IFACE" &
AIRO_PID=$!

sleep "$DURATION"

log "Time's up, stopping airodump-ng (PID $AIRO_PID)..."
sudo kill "$AIRO_PID"
wait "$AIRO_PID" 2>/dev/null || true

log "Changing ownership of generated files..."
sudo chown "$USER":"$USER" "$DIR"/*.*

log "Generated files:"
ls -lrt "$DIR"/*.*

log "Script finished. Pausing for 5 seconds..."
sleep 5

log "Switching $IFACE back to managed mode..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type managed
sudo ip link set "$IFACE" up

log "Done."
