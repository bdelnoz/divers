#!/bin/bash
# oui_lookup.sh
# Usage: oui_lookup.sh MAC_address
# Extrait le préfixe OUI et cherche dans oui.txt

MAC="$1"
OUI=$(echo "$MAC" | awk -F: '{print toupper($1":"$2":"$3)}')

# Cherche dans oui.txt, affiche fabricant ou "Unknown"
FIRM=$(grep "^$OUI" oui.txt | cut -d' ' -f2-)
if [ -z "$FIRM" ]; then
  echo "Unknown"
else
  echo "$FIRM"
fi

