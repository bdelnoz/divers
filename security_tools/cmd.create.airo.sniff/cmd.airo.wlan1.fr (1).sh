#!/bin/bash

set -euo pipefail

DEFAULT_IFACE="wlan1"
DEFAULT_DURATION=60

# Répertoires de sortie relatifs
LOG_DIR="./Logs"
SNIF_DIR="./Sniffing"

show_help() {
  echo "Usage : $0 [interface] [durée_en_secondes]"
  echo ""
  echo "Lance un scan avec airodump-ng en mode moniteur sur l'interface donnée."
  echo ""
  echo "Arguments :"
  echo "  interface             Nom de l'interface réseau (défaut : $DEFAULT_IFACE)"
  echo "  durée_en_secondes     Durée du scan (défaut : $DEFAULT_DURATION)"
  echo ""
  echo "Exemples :"
  echo "  $0 wlan1 30           Lance un scan de 30 secondes sur wlan1"
  echo "  $0                    Utilise les valeurs par défaut ($DEFAULT_IFACE, $DEFAULT_DURATION)"
  echo ""
  exit 0
}

# Aide si demandé
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
fi

# Paramètres
IFACE=${1:-$DEFAULT_IFACE}
DURATION=${2:-$DEFAULT_DURATION}
NOW=$(date +'%Y%m%d-%H%M%S')
OUTPUT_PREFIX="sniff-airodump-${IFACE}-$NOW"
USER=$(whoami)
GROUP=$(id -gn)

# Création des répertoires s'ils n'existent pas
[[ -d "$LOG_DIR" ]] || mkdir -p "$LOG_DIR"
[[ -d "$SNIF_DIR" ]] || mkdir -p "$SNIF_DIR"

# Fonction de log
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Nettoyage en cas d'interruption
cleanup() {
  log "Interruption reçue (Ctrl+C), retour de $IFACE en mode managed..."
  sudo ip link set "$IFACE" down
  sudo iw dev "$IFACE" set type managed
  sudo ip link set "$IFACE" up
  log "Fait."
  exit 130
}
trap cleanup INT

log "Interface sélectionnée : $IFACE"
log "Durée du scan : $DURATION secondes"

log "Vérification de l’interface $IFACE..."
if ! ip link show "$IFACE" &>/dev/null; then
  log "Erreur : interface $IFACE introuvable."
  exit 1
fi

log "Passage de $IFACE en mode moniteur..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up

log "Changement du répertoire de travail vers : $SNIF_DIR"
cd "$SNIF_DIR" || { log "Erreur : impossible d’accéder au dossier $SNIF_DIR"; exit 1; }

log "Lancement de airodump-ng sur $IFACE pour $DURATION secondes..."

sudo airodump-ng --gpsd --showack --real-time --manufacturer --uptime --beacons -b abg --write "$OUTPUT_PREFIX" --output-format csv,pcap "$IFACE" &
AIRO_PID=$!

sleep "$DURATION"

log "Temps écoulé, arrêt de airodump-ng (PID $AIRO_PID)..."
sudo kill "$AIRO_PID"
wait "$AIRO_PID" 2>/dev/null || true

log "Fichiers générés dans $SNIF_DIR :"
ls -lrt "$OUTPUT_PREFIX".*

log "Retour de $IFACE en mode managed..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type managed
sudo ip link set "$IFACE" up

log "Changement récursif de propriétaire sur le répertoire courant..."
cd ..
chown -R "$USER":"$GROUP" .

log "Fait. Script terminé."
