#!/bin/bash

# Définir le répertoire de destination du rapport
USER="nox"
DEST="/home/$USER/Security/2analyze"
OUTFILE="$DEST/desktop_analysis_report.txt"

# Créer le répertoire si nécessaire
mkdir -p "$DEST"

# Commencer le rapport
echo "Rapport d'analyse pour la disparition des icônes du bureau" > "$OUTFILE"
echo "Date de l'analyse: $(date)" >> "$OUTFILE"
echo -e "\n=== Analyse des mises à jour récentes ===" >> "$OUTFILE"

# Vérification des mises à jour récentes
echo "Mises à jour récentes : " >> "$OUTFILE"
grep "upgrade" /var/log/apt/history.log | tail -n 20 >> "$OUTFILE"
echo -e "\n=== Analyse des logs système ===" >> "$OUTFILE"

# Recherche des erreurs système (log d'upgrade, erreur de service, etc.)
echo "Erreur système : " >> "$OUTFILE"
sudo journalctl -b -1 | grep -i error >> "$OUTFILE"
echo -e "\n=== Analyse des logs Xorg ===" >> "$OUTFILE"

# Recherche des erreurs dans les logs Xorg
echo "Erreurs Xorg : " >> "$OUTFILE"
sudo cat /var/log/Xorg.0.log | grep -i error >> "$OUTFILE"
echo -e "\n=== Analyse de xfdesktop ===" >> "$OUTFILE"

# Recherche des logs de xfdesktop
echo "Logs xfdesktop : " >> "$OUTFILE"
sudo journalctl -b | grep -Ei 'xfdesktop|error|fail|warn' >> "$OUTFILE"
echo -e "\n=== Vérification de la configuration de XFCE ===" >> "$OUTFILE"

# Vérifier les fichiers de configuration XFCE
echo "Fichiers de configuration de XFCE : " >> "$OUTFILE"
ls -l ~/.config/xfce4/ >> "$OUTFILE"
echo -e "\n=== Vérification de la session XFCE ===" >> "$OUTFILE"

# Vérifier l'état de la session XFCE
echo "État de la session XFCE : " >> "$OUTFILE"
loginctl show-session $(loginctl | grep $USER | awk '{print $1}') -p Active >> "$OUTFILE"

# Résumé
echo -e "\nAnalyse terminée. Vous pouvez consulter le rapport dans : $OUTFILE"
