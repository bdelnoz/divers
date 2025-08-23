#!/bin/bash
# =====================================================================
# Nom du script : audit_audio.sh
# Auteur        : Bruno DELNOZ
# Email         : bruno.delnoz@protonmail.com
# Target usage  : Collecte complète des infos audio pour diagnostic
# Version       : v1.0 - Date : 2025-08-20
# Changelog     : v1.0 - Première version. Collecte périphériques, mixeur, réglages PulseAudio/ALSA.
# =====================================================================

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$(realpath "$0")")
LOG_FILE="$SCRIPT_DIR/log.$SCRIPT_NAME.v1.0.log"

function show_help() {
    cat <<EOL
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --exec       Collecte complète des infos audio et crée un log
  --help       Affiche ce message d'aide

Exemples:
  $SCRIPT_NAME --exec
EOL
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

if [ "$1" == "--exec" ]; then
    echo "=== $(date) ===" >> "$LOG_FILE"
    echo "[*] Liste des périphériques ALSA" | tee -a "$LOG_FILE"
    aplay -l >> "$LOG_FILE" 2>&1
    echo "[*] Liste des périphériques capture" | tee -a "$LOG_FILE"
    arecord -l >> "$LOG_FILE" 2>&1
    echo "[*] Infos PulseAudio" | tee -a "$LOG_FILE"
    pactl info >> "$LOG_FILE" 2>&1
    pactl list short sources >> "$LOG_FILE" 2>&1
    pactl list short sinks >> "$LOG_FILE" 2>&1
    echo "[*] Mixer ALSA" | tee -a "$LOG_FILE"
    amixer scontrols >> "$LOG_FILE" 2>&1
    echo "[*] Volume et mute status" | tee -a "$LOG_FILE"
    amixer get Master >> "$LOG_FILE" 2>&1
    echo "[*] Capture terminée, log créé : $LOG_FILE" | tee -a "$LOG_FILE"
    echo "Sortie conforme aux règles de contextualisation v41."
    exit 0
fi

echo "Argument inconnu : $1" | tee -a "$LOG_FILE"
show_help
exit 1
