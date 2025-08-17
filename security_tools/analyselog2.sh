#!/bin/bash

START="21:51"
END="22:04"
USER="nox"
DEST="/home/$USER/Security/2analyze"
OUTFILE="$DEST/analyze_result_test.txt"

mkdir -p "$DEST"
echo "Test logs du $START au $END" > "$OUTFILE"

echo -e "\n=== Logs système ===" | tee -a "$OUTFILE"
sudo journalctl --since "$START" --until "$END" | tee -a "$OUTFILE"

echo -e "\n=== Logs Xorg ===" | tee -a "$OUTFILE"
sudo journalctl _COMM=Xorg --since "$START" --until "$END" | tee -a "$OUTFILE"

echo -e "\n=== Logs service GDM ===" | tee -a "$OUTFILE"
sudo journalctl -u gdm --since "$START" --until "$END" | tee -a "$OUTFILE"

DATE=$(date +%F)
START_FULL="$DATE $START"
END_FULL="$DATE $END"

echo -e "\n=== Logs kernel ===" | tee -a "$OUTFILE"
sudo journalctl -k --since "$START_FULL" --until "$END_FULL" | tee -a "$OUTFILE"

echo -e "\n=== Logs session utilisateur ($USER) ===" | tee -a "$OUTFILE"
sudo journalctl _UID=$(id -u "$USER") --since "$START" --until "$END" | tee -a "$OUTFILE"

echo -e "\nAnalyse terminée, résultat dans : $OUTFILE"
