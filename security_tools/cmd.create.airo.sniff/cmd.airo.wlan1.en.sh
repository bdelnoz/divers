#!/bin/bash

set -euo pipefail

DEFAULT_IFACE="wlan1"
DEFAULT_DURATION=60

# Relative output directories
LOG_DIR="./Logs"
SNIF_DIR="./Sniffing"

show_help() {
  echo "Usage: $0 [interface] [duration_in_seconds]"
  echo ""
  echo "Starts a scan with airodump-ng in monitor mode on the given interface."
  echo ""
  echo "Arguments:"
  echo "  interface             Network interface name (default: $DEFAULT_IFACE)"
  echo "  duration_in_seconds   Scan duration (default: $DEFAULT_DURATION)"
  echo ""
  echo "Examples:"
  echo "  $0 wlan1 30           Starts a 30-second scan on wlan1"
  echo "  $0                    Uses default values ($DEFAULT_IFACE, $DEFAULT_DURATION)"
  echo ""
  exit 0
}

# Help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
fi

# Parameters
IFACE=${1:-$DEFAULT_IFACE}
DURATION=${2:-$DEFAULT_DURATION}
NOW=$(date +'%Y%m%d-%H%M%S')
OUTPUT_PREFIX="sniff-airodump-${IFACE}-$NOW"
USER=$(whoami)
GROUP=$(id -gn)

# Create output directories if they don't exist
[[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR"
[[ -d "$SNIF_DIR" ]] || mkdir -p "$SNIF_DIR"

# Logging function
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Cleanup on interruption
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
if ! ip link show "$IFACE" &>/dev/null; then
  log "Error: interface $IFACE not found."
  exit 1
fi

log "Switching $IFACE to monitor mode..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up

log "Changing working directory to: $SNIF_DIR"
cd "$SNIF_DIR" || { log "Error: cannot access directory $SNIF_DIR"; exit 1; }

log "Starting airodump-ng on $IFACE for $DURATION seconds..."

sudo airodump-ng --gpsd --showack --real-time --manufacturer --uptime --beacons -b abg --write "$OUTPUT_PREFIX" --output-format csv,pcap "$IFACE" &
AIRO_PID=$!

sleep "$DURATION"

log "Time elapsed, stopping airodump-ng (PID $AIRO_PID)..."
sudo kill "$AIRO_PID"
wait "$AIRO_PID" 2>/dev/null || true

log "Files generated in $SNIF_DIR:"
ls -lrt "$OUTPUT_PREFIX".*

log "Switching $IFACE back to managed mode..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type managed
sudo ip link set "$IFACE" up

log "Recursively changing ownership of current directory..."
cd ..
chown -R "$USER":"$GROUP" .

log "Done. Script finished."
