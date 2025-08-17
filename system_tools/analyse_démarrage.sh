#!/bin/bash
# /home/nox/Security/scripts/divers/analyse_démarrage.sh

# Définir le fichier de sortie
OUTPUT_FILE=~/analyse_demarrage.txt

# Créer ou réinitialiser le fichier de sortie
echo "=== Analyse des applications de démarrage ===" > $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Lister les applications dans le répertoire autostart
echo "Applications dans ~/.config/autostart/" >> $OUTPUT_FILE
ls ~/.config/autostart/ >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Afficher les détails des fichiers .desktop
for app in ~/.config/autostart/*; do
  echo "=== $app ===" >> $OUTPUT_FILE
  cat "$app" >> $OUTPUT_FILE
  echo "" >> $OUTPUT_FILE
done

# Lister les applications démarrées par le gestionnaire de session XFCE
echo "=== Applications dans ~/.config/xfce4-session/xfce4-session.rc ===" >> $OUTPUT_FILE
if [ -f ~/.config/xfce4-session/xfce4-session.rc ]; then
  cat ~/.config/xfce4-session/xfce4-session.rc >> $OUTPUT_FILE
else
  echo "Fichier xfce4-session.rc non trouvé." >> $OUTPUT_FILE
fi
echo "" >> $OUTPUT_FILE

# Lister les services activés au niveau de l'utilisateur
echo "=== Services systemd activés pour l'utilisateur ===" >> $OUTPUT_FILE
systemctl --user list-unit-files --state=enabled >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE

# Lister les services système activés
echo "=== Services systemd activés pour le système ===" >> $OUTPUT_FILE
systemctl list-unit-files --state=enabled >> $OUTPUT_FILE

echo "Analyse terminée. Les résultats sont dans $OUTPUT_FILE"
