#!/bin/bash
# Auteur: Bruno Delnoz
# Email: bruno.delnoz@protonmail.com
# Script pour créer un skill OVOS simple qui lance une commande (ex: terminal)
# Usage : ./createskill.sh <nom_skill> <commande_a_executer>

set -e

# Répertoire de travail courant
BASE_DIR=$(pwd)
SKILLS_DIR="$BASE_DIR/skills"

NOM_SKILL=$1
COMMANDE=$2

if [ -z "$NOM_SKILL" ] || [ -z "$COMMANDE" ]; then
  echo "Usage: $0 <nom_skill> <commande_a_executer>"
  echo "Exemple: $0 ouvrirTerminal gnome-terminal"
  exit 1
fi

echo "[+] === CREATE SKILL $NOM_SKILL ==="

# Créer l'arborescence du skill
mkdir -p "$SKILLS_DIR/$NOM_SKILL/locale/en-us"
mkdir -p "$SKILLS_DIR/$NOM_SKILL/locale/fr-fr"

# Créer le fichier intent en anglais
cat > "$SKILLS_DIR/$NOM_SKILL/locale/en-us.intent" << EOF
$NOM_SKILL.intent
open $NOM_SKILL
launch $NOM_SKILL
start $NOM_SKILL
EOF

# Créer le fichier intent en français
cat > "$SKILLS_DIR/$NOM_SKILL/locale/fr-fr.intent" << EOF
$NOM_SKILL.intent
ouvre $NOM_SKILL
lance $NOM_SKILL
démarre $NOM_SKILL
EOF

# Créer le fichier vocabulaire (vide pour simplifier)
touch "$SKILLS_DIR/$NOM_SKILL/locale/en-us.vocab"
touch "$SKILLS_DIR/$NOM_SKILL/locale/fr-fr.vocab"

# Créer le fichier __init__.py du skill
cat > "$SKILLS_DIR/$NOM_SKILL/__init__.py" << EOF
from ovos_bus_client.skills.ovos import OVOSSkill

class ${NOM_SKILL^}Skill(OVOSSkill):
    def __init__(self):
        super().__init__()

    def initialize(self):
        @self.intent_handler("${NOM_SKILL}.intent")
        def handle_intent(_):
            self.log.info("Commande reçue : lancement de $COMMANDE")
            import subprocess
            subprocess.Popen(["$COMMANDE"])
EOF

# Vérifier si config OVOS existe sinon créer config minimale
CONF_FILE="$HOME/.config/openvoiceos/config.json"
if [ ! -f "$CONF_FILE" ]; then
  echo "[+] Création config minimale OVOS en $CONF_FILE"
  mkdir -p "$(dirname "$CONF_FILE")"
  cat > "$CONF_FILE" << EOF
{
  "skills": {
    "directory": "$SKILLS_DIR"
  },
  "listener": {
    "port": 8181
  },
  "websocket": {
    "host": "127.0.0.1",
    "port": 8181
  }
}
EOF
fi

# Démarrer OVOS Core si non actif
if ! pgrep -f ovos-core >/dev/null; then
  echo "[+] OVOS Core non détecté, lancement en arrière-plan..."
  nohup "$HOME/ovos-env/bin/ovos-core" &>/dev/null &
  sleep 5
else
  echo "[+] OVOS Core déjà actif."
fi

# Démarrer ovos-listen si non actif
if ! pgrep -f ovos-listen >/dev/null; then
  echo "[+] Lancement ovos-listen en arrière-plan..."
  nohup "$HOME/ovos-env/bin/ovos-listen" &>/dev/null &
  sleep 5
else
  echo "[+] ovos-listen déjà actif."
fi

echo "[+] Skill '$NOM_SKILL' créé dans $SKILLS_DIR/$NOM_SKILL"
echo "[+] Commande configurée : $COMMANDE"
echo "[+] OVOS prêt, lancez 'ovos-listen' dans ce répertoire ou en arrière-plan."
echo "[+] Exemple : dites '$NOM_SKILL' pour lancer la commande."

exit 0

