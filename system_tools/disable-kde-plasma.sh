#!/bin/bash
# Script root pour désactiver KDE/Plasma globalement

set -e

echo "Masquage des fichiers autostart KDE/Plasma dans /etc/xdg/autostart/"

shopt -s nullglob
files=( /etc/xdg/autostart/*plasma*.desktop /etc/xdg/autostart/*kde*.desktop )

for f in "${files[@]}"; do
  if [ -f "$f" ]; then
    if ! grep -q "^Hidden=true" "$f"; then
      echo "Masquage $f"
      echo "Hidden=true" >> "$f"
    fi
  fi
done

echo "Suppression des services utilisateurs Plasma/KDE dans /home/*/.config/systemd/user/"
for userhome in /home/*; do
  user_services="$userhome/.config/systemd/user"
  if [ -d "$user_services" ]; then
    echo "Traitement $user_services"
    rm -f "$user_services"/plasma-*.service 2>/dev/null || true
    rm -f "$user_services"/kde-*.service 2>/dev/null || true
  fi
done

echo "Terminé. Pense à redémarrer la machine et/ou faire une nouvelle connexion utilisateur."

