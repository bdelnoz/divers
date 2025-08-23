#!/bin/bash

CONFIG="$HOME/.config/mimeapps.list"
LOCAL_APPS="$HOME/.local/share/applications"

mkdir -p "$LOCAL_APPS"

# Parcours toutes les associations existantes dans [Default Applications]
grep -A1 '^\[Default Applications\]' "$CONFIG" | grep '=' | while IFS='=' read -r mime desktop; do
    # Nettoyage du nom de fichier
    desktop_file="$LOCAL_APPS/${desktop%-*}-force.desktop"

    cat > "$desktop_file" <<EOL
[Desktop Entry]
Type=Application
Name=Force ${desktop%-*}
Exec=${desktop%-*} %f
MimeType=$mime
Terminal=false
Categories=Utility;
EOL
done

# Reconstruire le cache KDE
update-desktop-database "$LOCAL_APPS"
update-desktop-database /usr/share/applications
kbuildsycoca5 --noincremental

echo "Tous les types MIME existants ont été forcés pour Dolphin."
