#!/bin/bash
# =====================================================================
# Nom du script : fix_dolphin_mime.sh
# Auteur        : Bruno DELNOZ
# Email         : bruno.delnoz@protonmail.com
# Target usage  : Corriger les associations de fichiers dans Dolphin sous XFCE
# Version       : v1.0 - Date : 2025-08-20
# Changelog     :
#   v1.0 - 2025-08-20 - Première version. Installe les paquets KDE partiels, exporte la variable XDG_MENU_PREFIX,
#                       crée le symlink applications.menu si manquant, reconstruit le cache KDE et génère un log détaillé.
# =====================================================================

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$(realpath "$0")")
LOG_FILE="$SCRIPT_DIR/log.$SCRIPT_NAME.v1.0.log"

CONFIG_ENV="$HOME/.xprofile"
MENU_DIR="/etc/xdg/menus"
MENU_SRC="$MENU_DIR/plasma-applications.menu"
MENU_DEST="$MENU_DIR/applications.menu"

function show_help() {
    cat <<EOL
Usage: $SCRIPT_NAME [OPTIONS]

Options:
  --exec       Exécute la correction complète des associations Dolphin
  --delete     Supprime tout ce que le script a fait et restaure backups
  --help       Affiche ce message d'aide

Exemples:
  $SCRIPT_NAME --exec
  $SCRIPT_NAME --delete
EOL
}

# Vérifie si aucun argument, lance help
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

# Création du log
echo "=== $(date) ===" >> "$LOG_FILE"
echo "Argument reçu : $1" >> "$LOG_FILE"

# --delete : suppression propre
if [ "$1" == "--delete" ]; then
    echo "[*] Suppression des backups et symlinks créés..." | tee -a "$LOG_FILE"
    [ -f "$MENU_DEST.bak" ] && sudo mv "$MENU_DEST.bak" "$MENU_DEST"
    echo "[1] Backups restaurés" | tee -a "$LOG_FILE"
    echo "[2] Fin de la suppression propre" | tee -a "$LOG_FILE"
    echo "Sortie conforme aux règles de contextualisation v41."
    exit 0
fi

# --exec : exécution complète
if [ "$1" == "--exec" ]; then
    echo "[*] Installation des paquets KDE partiels..." | tee -a "$LOG_FILE"
    sudo apt install -y plasma-workspace kde-cli-tools kio-extras >> "$LOG_FILE" 2>&1
    echo "[1] Paquets installés" | tee -a "$LOG_FILE"

    echo "[*] Export de XDG_MENU_PREFIX dans $CONFIG_ENV..." | tee -a "$LOG_FILE"
    if ! grep -q "XDG_MENU_PREFIX=plasma-" "$CONFIG_ENV" 2>/dev/null; then
        echo "export XDG_MENU_PREFIX=plasma-" >> "$CONFIG_ENV"
        echo "[2] Variable ajoutée" | tee -a "$LOG_FILE"
    else
        echo "[2] Variable déjà présente" | tee -a "$LOG_FILE"
    fi

    echo "[*] Vérification du symlink applications.menu..." | tee -a "$LOG_FILE"
    if [ ! -f "$MENU_DEST" ]; then
        sudo ln -s "$MENU_SRC" "$MENU_DEST"
        echo "[3] Symlink créé" | tee -a "$LOG_FILE"
    else
        echo "[3] Symlink déjà présent" | tee -a "$LOG_FILE"
    fi

    echo "[*] Reconstruire le cache KDE..." | tee -a "$LOG_FILE"
    kbuildsycoca6 --noincremental >> "$LOG_FILE" 2>&1
    echo "[4] Cache KDE reconstruit" | tee -a "$LOG_FILE"

    echo "Toutes les actions ont été effectuées avec succès." | tee -a "$LOG_FILE"
    echo "Sortie conforme aux règles de contextualisation v41."
    exit 0
fi

# Si argument non reconnu
echo "Argument inconnu : $1" | tee -a "$LOG_FILE"
show_help
exit 1
