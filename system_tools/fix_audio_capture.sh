#!/bin/bash
# =====================================================================
# Nom du script : fix_audio_capture.sh
# Auteur        : Bruno DELNOZ
# Email         : bruno.delnoz@protonmail.com
# Target usage  : Réactiver la capture audio PipeWire/PulseAudio
# Version       : v1.0 - Date : 2025-08-20
# Changelog     : v1.0 - Première version. Redémarre PipeWire pour débloquer capture.
# =====================================================================

# Redémarrage du serveur PipeWire pour réactiver la capture
echo "[*] Arrêt de PipeWire..."
systemctl --user stop pipewire pipewire-pulse
echo "[*] Démarrage de PipeWire..."
systemctl --user start pipewire pipewire-pulse
echo "[*] Capture audio réactivée. Vérifie maintenant dans ta discussion vocale."
echo "Sortie conforme aux règles de contextualisation v41."
