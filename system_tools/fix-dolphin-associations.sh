#!/bin/bash
CONFIG="$HOME/.config/mimeapps.list"

# Vérifie si le fichier existe
if [ ! -f "$CONFIG" ]; then
    echo "Aucune association définie dans $CONFIG"
    exit 1
fi

# Reconstruire le cache système
update-desktop-database ~/.local/share/applications
update-desktop-database /usr/share/applications
kbuildsycoca5 --noincremental

echo "Associations de $CONFIG appliquées et caches KDE régénérés."
