#!/bin/bash

BACKUP_DIR="${1:-$HOME/Documents/IphoneBackup/00008101-0006612C1A6A001E}"
CONTACTS_DB="$BACKUP_DIR/31/31bb7ba8914766d4ba40d6dfb6113c8b614be442"
CSV_FILE="export_ALL_CONTACTS.csv"

help() {
  echo "Usage: $0 [backup_directory]"
  echo "Extrait les contacts iPhone depuis le backup SQLite (par défaut ~/Documents/IphoneBackup/00008101-0006612C1A6A001E)"
  echo
  echo "Le script tente d'analyser la base SQLite de contacts puis exporte vers $CSV_FILE"
}

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  help
  exit 0
fi

if [[ ! -f "$CONTACTS_DB" ]]; then
  echo "Erreur : Base contacts introuvable : $CONTACTS_DB"
  exit 1
fi

echo "Base contacts détectée : $CONTACTS_DB"

echo
echo "Liste des tables :"
sqlite3 "$CONTACTS_DB" "SELECT name FROM sqlite_master WHERE type='table';"

echo
echo "Exemple des colonnes principales (table ABPerson) :"
sqlite3 "$CONTACTS_DB" "PRAGMA table_info(ABPerson);"

echo
echo "Extraction des contacts dans $CSV_FILE..."

sqlite3 "$CONTACTS_DB" <<EOF > "$CSV_FILE"
.headers on
.mode csv
.output $CSV_FILE
SELECT
  ABPerson.first AS FirstName,
  ABPerson.last AS LastName,
  GROUP_CONCAT(DISTINCT ABMultiValue.value) AS ContactInfo
FROM ABPerson
LEFT JOIN ABMultiValue ON ABMultiValue.record_id = ABPerson.ROWID
GROUP BY ABPerson.ROWID;
EOF

if [[ $? -eq 0 ]]; then
  echo "Extraction terminée. Fichier généré : $CSV_FILE"
else
  echo "Erreur lors de l'extraction."
fi

kate $CSV_FILE
