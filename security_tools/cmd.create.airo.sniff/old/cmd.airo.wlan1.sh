#!/bin/bash

set -euo pipefail

# Interface par défaut et durée de scan par défaut
DEFAULT_IFACE="wlan1"
DEFAULT_DURATION=60

# Utilisation des paramètres passés en ligne de commande ou valeurs par défaut
IFACE=${1:-$DEFAULT_IFACE}
DURATION=${2:-$DEFAULT_DURATION}

# Dossier de travail et nom de sortie
DIR="/home/nox/Security/scripts/data/airodump-sniff"
NOW=$(date +'%Y%m%d-%H%M%S')
OUTPUT_PREFIX="sniff-airodump-${IFACE}-$NOW"
USER="nox"

# Fonction de journalisation
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Fonction de nettoyage en cas d'interruption (Ctrl+C)
cleanup() {
  log "Interruption reçue (Ctrl+C), retour de $IFACE en mode managed..."
  sudo ip link set "$IFACE" down
  sudo iw dev "$IFACE" set type managed
  sudo ip link set "$IFACE" up
  log "Fait."
  exit 130
}

# Déclenche le nettoyage si interruption
trap cleanup INT

log "Interface sélectionnée : $IFACE"
log "Durée du scan : $DURATION secondes"

log "Vérification de l’interface $IFACE..."
if ! ip link show "$IFACE" > /dev/null 2>&1; then
  log "Erreur : interface $IFACE introuvable."
  exit 1
fi

log "Passage de $IFACE en mode moniteur..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type monitor
sudo ip link set "$IFACE" up

log "Changement du répertoire de travail vers : $DIR"
cd "$DIR" || { log "Erreur : impossible d’accéder au dossier $DIR"; exit 1; }

log "Lancement de airodump-ng sur $IFACE pour $DURATION secondes..."

sudo airodump-ng  --showack --real-time --manufacturer --uptime --beacons -b abg --write "$OUTPUT_PREFIX" --output-format csv,pcap "$IFACE" &
AIRO_PID=$!

# Attente de la fin du scan
sleep "$DURATION"

log "Temps écoulé, arrêt de airodump-ng (PID $AIRO_PID)..."
sudo kill "$AIRO_PID"
wait "$AIRO_PID" 2>/dev/null || true

log "Changement du propriétaire des fichiers générés..."
sudo chown "$USER":"$USER" "$DIR"/*.*

log "Fichiers générés :"
ls -lrt "$DIR"/*.*

log "Script terminé. Pause de 5 secondes..."
sleep 5

log "Retour de $IFACE en mode managed..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type managed
sudo ip link set "$IFACE" up

log "Fait."
