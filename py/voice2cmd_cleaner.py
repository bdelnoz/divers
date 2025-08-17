#!/usr/bin/env python3
import os
import subprocess
import shutil

# 🔻 1. Tuer les processus liés au script voice2cmd.py
print("🔻 Arrêt des processus voice2cmd.py...")
subprocess.run(["pkill", "-f", "voice2cmd.py"])

# 🧹 2. Supprimer le modèle VOSK local
model_path = os.path.expanduser("~/venv-voix-joplin/model")
if os.path.exists(model_path):
    print(f"🧹 Suppression du modèle VOSK : {model_path}")
    shutil.rmtree(model_path)
else:
    print("✅ Aucun modèle VOSK trouvé.")
#
# # 🗑️ 3. Supprimer les notes Joplin contenant 'Commande vocale'
# print("🗑️ Suppression des notes Joplin liées...")
# try:
#     result = subprocess.run(["joplin", "search", "Commande vocale", "--json"], capture_output=True, text=True)
#     notes = eval(result.stdout)
#     for note in notes:
#         subprocess.run(["joplin", "rm", note['id']])
#     print(f"✅ {len(notes)} note(s) supprimée(s).")
# except Exception as e:
#     print(f"⚠️ Erreur lors de la suppression des notes Joplin : {e}")

# # 🚫 4. Supprimer le script lui-même (optionnel)
# script_path = "/home/nox/Security/scripts/divers/py/voice2cmd.py"
# if os.path.exists(script_path):
#     print(f"🚫 Suppression du script : {script_path}")
#     os.remove(script_path)
#
print("✅ Nettoyage terminé.")

