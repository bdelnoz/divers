#!/bin/bash
# Nom du script : mp4_to_images_per_second.sh
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Version : v3.1.5 - Date : 2025-08-21
# Changelog :
# v1.0 - Création script initial
# v2.0 - Ajout --exec, --remove
# v2.5 - Ajout --target directory
# v3.0 - Ajout --fps
# v3.1.4 - Correction chemin avec espaces
# v3.1.5 - Ajout --start et --stop pour découpe temporelle, conformité v41

SCRIPT_NAME=$(basename "$0")
LOG_FILE="./log.${SCRIPT_NAME}.v3.1.5.log"

function help_msg() {
    echo "Usage: $SCRIPT_NAME --exec|--remove [--target <répertoire_destination>] [--fps <n>] [--start <seconds>] [--stop <seconds>] <fichier_mp4>"
    echo ""
    echo "Options:"
    echo "  --exec               Exécute l'extraction d'images"
    echo "  --remove             Supprime toutes les images générées précédemment"
    echo "  --target <dir>       Répertoire destination pour les images (par défaut, même répertoire que le MP4)"
    echo "  --fps <n>            Nombre d'images par seconde (par défaut 1)"
    echo "  --start <seconds>    Début de l'extraction (en secondes ou HH:MM:SS)"
    echo "  --stop <seconds>     Fin de l'extraction (en secondes ou HH:MM:SS)"
    echo "  --help               Affiche ce message"
    echo ""
    echo "Exemples :"
    echo "  $SCRIPT_NAME --exec /mnt/videos/video.mp4"
    echo "  $SCRIPT_NAME --exec --target /mnt/images --fps 5 --start 0 --stop 120 /mnt/videos/video.mp4"
    echo "  $SCRIPT_NAME --remove --target /mnt/images"
}

# Si aucun argument, afficher le help
if [ $# -eq 0 ]; then
    help_msg
    exit 0
fi

# Variables par défaut
FPS=1
TARGET_DIR=""
START=""
STOP=""
ACTION=""
INPUT_FILE=""

# Lecture des arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --exec)
            ACTION="exec"; shift ;;
        --remove)
            ACTION="remove"; shift ;;
        --target)
            TARGET_DIR="$2"; shift 2 ;;
        --fps)
            FPS="$2"; shift 2 ;;
        --start)
            START="$2"; shift 2 ;;
        --stop)
            STOP="$2"; shift 2 ;;
        --help)
            help_msg; exit 0 ;;
        *)
            INPUT_FILE="$1"; shift ;;
    esac
done

# Vérification prérequis
if ! command -v ffmpeg &> /dev/null; then
    echo "Erreur : ffmpeg non installé" | tee -a "$LOG_FILE"
    exit 1
fi

# Vérification action
if [ -z "$ACTION" ]; then
    echo "Erreur : aucune action spécifiée (--exec ou --remove)" | tee -a "$LOG_FILE"
    help_msg
    exit 1
fi

# Extraction des infos
if [ -n "$INPUT_FILE" ]; then
    if [ ! -f "$INPUT_FILE" ]; then
        echo "Erreur : fichier source introuvable" | tee -a "$LOG_FILE"
        exit 1
    fi
    BASENAME=$(basename "$INPUT_FILE")
    FILEDIR=$(dirname "$INPUT_FILE")
    FILENAME="${BASENAME%.*}"
fi

# Définition répertoire target
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$FILEDIR/${FILENAME}_images"
fi
mkdir -p "$TARGET_DIR"

# Fonction suppression
if [ "$ACTION" == "remove" ]; then
    echo "Suppression des images dans $TARGET_DIR" | tee -a "$LOG_FILE"
    rm -f "$TARGET_DIR/$FILENAME"*".jpg"
    echo "Suppression terminée" | tee -a "$LOG_FILE"
    exit 0
fi

# Construction options ffmpeg
FFMPEG_OPTIONS="-i \"$INPUT_FILE\" -qscale:v 2 -vf fps=$FPS"
if [ -n "$START" ]; then
    FFMPEG_OPTIONS="$FFMPEG_OPTIONS -ss $START"
fi
if [ -n "$STOP" ]; then
    FFMPEG_OPTIONS="$FFMPEG_OPTIONS -to $STOP"
fi

# Commande extraction
echo "Extraction des images..." | tee -a "$LOG_FILE"
CMD="ffmpeg $FFMPEG_OPTIONS \"$TARGET_DIR/$FILENAME.%03d.jpg\""
eval $CMD | tee -a "$LOG_FILE"
echo "Extraction terminée dans $TARGET_DIR" | tee -a "$LOG_FILE"

# Liste numérotée des actions
echo ""
echo "Actions réalisées :"
echo "1. Fichier source : $INPUT_FILE"
echo "2. Répertoire cible : $TARGET_DIR"
echo "3. FPS : $FPS"
[ -n "$START" ] && echo "4. Début extraction : $START"
[ -n "$STOP" ] && echo "5. Fin extraction : $STOP"
echo "6. Commande exécutée : $CMD"

echo "Sortie conforme aux règles de contextualisation v41."
