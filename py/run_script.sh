#!/bin/bash
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : run_script.sh
# Target usage : Exécuter un script Python Selenium dans le répertoire courant avec virtualenv
# Version : v1.4 - Date : 2025-07-18

LOGFILE="run_script.log"

function usage() {
  echo "Usage : $0 <script_python.py> [arguments...]"
  echo ""
  echo "Arguments Python possibles pour chatgptcreationtitlefromcontent_loop.py :"
  echo "  --exec                  Lance l'exécution réelle"
  echo "  --test                  Mode test : simule sans modifier les titres"
  echo "  --rulesfile=<fichier>   Chemin vers le fichier de règles (défaut: RuleCreationTitre.txt)"
  echo "  --numchats=<nombre|ALL> Nombre de chats à traiter ou ALL (défaut: 3)"
  echo ""
  echo "Exemples :"
  echo "  $0 chatgptcreationtitlefromcontent_loop.py --exec --numchats=ALL"
  echo "  $0 chatgptcreationtitlefromcontent_loop.py --test --rulesfile=RuleCreationTitre.txt --numchats=5"
  echo "  $0 chatgptcreationtitlefromcontent_loop.py --exec --rulesfile=mesregles.txt --numchats=10"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

SCRIPT="$1"
shift

BASE_DIR="$(dirname "$0")"
SCRIPT_PATH="$BASE_DIR/$SCRIPT"
VENV_PYTHON="$BASE_DIR/.venv_selenium/bin/python3"

if [ ! -f "$SCRIPT_PATH" ]; then
  echo "Erreur : script $SCRIPT_PATH introuvable." | tee -a "$LOGFILE"
  exit 2
fi

if [ ! -x "$VENV_PYTHON" ]; then
  echo "Erreur : Python virtualenv non trouvé dans $VENV_PYTHON" | tee -a "$LOGFILE"
  exit 3
fi

echo "=== Début exécution $(date) ===" >> "$LOGFILE"
echo "Exécution du script Python : $SCRIPT_PATH" | tee -a "$LOGFILE"
echo "Arguments Python : $*" | tee -a "$LOGFILE"

"$VENV_PYTHON" "$SCRIPT_PATH" "$@" 2>&1 | tee -a "$LOGFILE"
RET=${PIPESTATUS[0]}

if [ $RET -eq 0 ]; then
  echo "=== Exécution terminée avec succès ===" | tee -a "$LOGFILE"
else
  echo "=== Exécution terminée avec erreur (code $RET) ===" | tee -a "$LOGFILE"
fi

exit $RET

