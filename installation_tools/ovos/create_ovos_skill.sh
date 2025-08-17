#!/bin/bash
# Auteur: Bruno Delnoz
# Email: bruno.delnoz@protonmail.com

if [ "$EUID" -eq 0 ]; then
  echo "Ne lance pas en root."
  exit 1
fi

if [ $# -ne 3 ]; then
  echo "Usage : $0 <NomIntent> <Commande> <CheminSkillsOVOS>"
  exit 1
fi

BASE_DIR="$(pwd)"
INTENT_NAME=$1
COMMAND=$2
OVOS_SKILLS_DIR=$3

INTENT_DIR="$BASE_DIR/skills/$INTENT_NAME/intents"
INTENT_FILE="$INTENT_DIR/$INTENT_NAME.intent"
SKILL_DIR="$BASE_DIR/skills/$INTENT_NAME"

mkdir -p "$INTENT_DIR"
mkdir -p "$SKILL_DIR"

# Création du fichier intent
echo "$INTENT_NAME" > "$INTENT_FILE"
echo "# Intent créé par script" >> "$INTENT_FILE"

# Création du skill Python minimal
cat > "$SKILL_DIR/__init__.py" <<EOF
from ovos_utils.skills import OVOSSkill

class TerminalOpenerSkill(OVOSSkill):
    def initialize(self):
        self.register_intent_file("$INTENT_NAME.intent", self.handle_open_terminal)

    def handle_open_terminal(self, message):
        import subprocess
        subprocess.Popen("$COMMAND", shell=True)

def create_skill():
    return TerminalOpenerSkill()
EOF

echo "[+] Intent '$INTENT_NAME' créé avec commande '$COMMAND'."

# Copie dans OVOS skills
if [ ! -d "$OVOS_SKILLS_DIR" ]; then
  echo "Erreur: Le dossier OVOS skills '$OVOS_SKILLS_DIR' n'existe pas."
  exit 1
fi

cp -r "$SKILL_DIR" "$OVOS_SKILLS_DIR"
echo "[+] Skill copié dans $OVOS_SKILLS_DIR"

# Redémarrage OVOS (simple kill + relance)
pkill -f ovos || echo "[!] OVOS n'était pas lancé."
"$HOME/ovos-env/bin/ovos-listen" &

echo "[+] OVOS redémarré."

echo "[+] Terminé."
