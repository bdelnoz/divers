#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys
import json

dry_run = "--dry-run" in sys.argv

def delete_path(path):
    if os.path.exists(path):
        if dry_run:
            print(f"[DRY-RUN] 🗑️ {path}")
        else:
            if os.path.isfile(path):
                os.remove(path)
            else:
                shutil.rmtree(path)
            print(f"🗑️ Supprimé : {path}")

print("🔻 Arrêt des processus voice2cmd.py...")
if dry_run:
    print("[DRY-RUN] pkill -f voice2cmd.py")
else:
    subprocess.run(["pkill", "-f", "voice2cmd.py"], stderr=subprocess.DEVNULL)

# 🧹 Supprimer l'environnement virtuel
delete_path(os.path.expanduser("~/venv-voix-joplin"))

# 🗑️ Supprimer les modèles VOSK
for model in ["~/vosk-model-fr-0.22", "~/vosk-model-small-fr-0.22"]:
    delete_path(os.path.expanduser(model))

# 🗑️ Supprimer les archives téléchargées
for archive in ["~/vosk-fr.zip", "~/vosk-model-fr-0.22.zip"]:
    delete_path(os.path.expanduser(archive))

# 🗑️ Supprimer les scripts installés
for script in [
    "~/Security/scripts/divers/py/voice2cmd.py",
    "~/Security/scripts/divers/py/setupenv_voix_joplin.sh",
    "~/Security/scripts/divers/py/setupenv_voix_joplin_top.sh"
]:
    delete_path(os.path.expanduser(script))

# 🗑️ Supprimer les notes Joplin contenant "Commande vocale"
print("🔍 Recherche des notes Joplin liées...")
try:
    if dry_run:
        print("[DRY-RUN] joplin search 'Commande vocale' --json")
    else:
        result = subprocess.run(
            ["joplin", "search", "Commande vocale", "--json"],
            capture_output=True, text=True
        )
        if result.stdout.strip():
            notes = json.loads(result.stdout)
            for note in notes:
                subprocess.run(["joplin", "rm", note["id"]])
            print(f"✅ {len(notes)} note(s) supprimée(s).")
        else:
            print("✅ Aucune note Joplin trouvée.")
except FileNotFoundError:
    print("⚠️ Joplin CLI introuvable, étape ignorée.")

print("✅ Désinstallation complète terminée." if not dry_run else "✅ Simulation terminée.")
