#!/bin/bash

BACKUP_DIR="${1:-$HOME/Documents/IphoneBackup/00008101-0006612C1A6A001E}"
OUTPUT="export_ALL_SMS.csv"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Erreur : dossier introuvable : $BACKUP_DIR"
  exit 2
fi

echo "Extraction de tous les SMS dans $BACKUP_DIR"

echo "date,direction,phone_number,message" > "$OUTPUT"

search_all_sms() {
  local file="$1"
  if sqlite3 "$file" "SELECT name FROM sqlite_master WHERE type='table' AND name='message';" 2>/dev/null | grep -q message; then
    sqlite3 -csv "$file" <<EOF
.headers off
.mode csv
SELECT
  datetime(message.date / 1000000000 + strftime('%s','2001-01-01'), 'unixepoch') AS date,
  CASE WHEN message.is_from_me=1 THEN 'Sent' ELSE 'Received' END AS direction,
  handle.id AS phone_number,
  message.text AS message
FROM message
LEFT JOIN handle ON message.handle_id = handle.ROWID
ORDER BY date DESC;
EOF
  fi
}

find "$BACKUP_DIR" -type f | while read -r file; do
  results=$(search_all_sms "$file")
  if [ -n "$results" ]; then
    echo "$results"
  fi
done >> "$OUTPUT"

echo "Extraction terminée : $OUTPUT"

kate "$OUTPUT" &
