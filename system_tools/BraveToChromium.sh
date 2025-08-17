#!/bin/bash
# Migration Brave -> Chromium
# Compatible Linux (Debian/Kali)

BRAVE=~/.config/BraveSoftware/Brave-Browser/Default
CHROM=~/.config/chromium/Default

mkdir -p "$CHROM"

FILES=("Bookmarks" "Preferences" "History" "Cookies" "Login Data")

for file in "${FILES[@]}"; do
    if [ -f "$BRAVE/$file" ]; then
        cp "$BRAVE/$file" "$CHROM/"
        echo "Copié : $file"
    else
        echo "Non trouvé : $file"
    fi
done

echo "Migration terminée. Relance Chromium pour tester."
