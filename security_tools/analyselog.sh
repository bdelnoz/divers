#!/bin/bash

START="21:51"
END="22:04"
USER="nox"
DEST="/home/$USER/Security/2analyze"

mkdir -p "$DEST"

echo "Analyse des logs du $START au $END"

sudo journalctl --since "$START" --until "$END" | grep -Ei 'shutdown|reboot|sleep|wake|power|pm-utils|acpi' > "$DEST/power_acpi.log"

sudo journalctl _COMM=Xorg --since "$START" --until "$END" | grep -Ei 'error|fail|warn' > "$DEST/xorg.log"

sudo journalctl -u gdm --since "$START" --until "$END" | grep -Ei 'error|fail|warn' > "$DEST/gdm.log"

sudo journalctl -k --since "$START" --until "$END" | grep -Ei 'error|fail|warn|panic' > "$DEST/kernel.log"

sudo journalctl _UID=$(id -u "$USER") --since "$START" --until "$END" | grep -Ei 'error|fail|warn' > "$DEST/session_user.log"

echo "Analyse terminée, fichiers sauvegardés dans $DEST"
