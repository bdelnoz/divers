#!/bin/bash
# Auteur : Bruno DELNOZ
# Email  : bruno.delnoz@protonmail.com
# Nom du script : record_cam.sh
# Target usage : Enregistrer l'écran en segments personnalisables, capturer le son système (Monitor),
#                amplification optionnelle post-traitement, gestion propre de CTRL-C et --delete.
# Version : v1.7 - Date : 2025-08-12
#
# Changelog :
# v1.7 - 2025-08-12 : Amélioration de la gestion de l'arrêt via Ctrl+C pour s'assurer qu'aucun processus ne tourne en arrière-plan
# v1.6 - 2025-08-12 : Ajout --target_dir pour spécifier le répertoire de sortie des vidéos et sous-répertoire BOOST pour les fichiers boostés
# v1.5 - 2025-08-11 : Ajout --segment-duration pour personnaliser la durée des segments
# v1.4 - 2025-08-09 : Corrections multiples - logique de boucle, gestion des processus, substitution bash
# v1.3 - 2025-08-09 : Ajout --volume, segmentation 10min, horodatage automatique, traitement ffmpeg en arrière-plan
# v1.2 - 2025-08-09 : Capture son système (Monitor)
# v1.1 - 2025-08-09 : Mode durée illimitée (0) + exemples HELP
# v1.0 - 2025-08-09 : Version initiale (fps/qualités optimisées, on-the-fly, logs)

set -u
set -o pipefail

SCRIPT_NAME="$(basename "$0")"
LOGFILE="$(dirname "$0")/${SCRIPT_NAME%.sh}.log"

# --- Paramètres par défaut ---
SEGMENT_SECONDS=600       # 600 = 10 minutes par défaut
FPS=15
V_QUALITY=50              # 0..63 (plus bas = plus compressé)
S_QUALITY=5               # 0..10 (plus bas = plus compressé)
ON_THE_FLY="--on-the-fly-encoding"
AUDIO_DEVICE="pulse"      # par défaut (son système)
MICROPHONE_DEVICE=""      # vide = pas de micro, sinon nom du device micro
RECORD_MIC=0              # 0 = pas de micro, 1 = avec micro
VOLUME_FILTER=""          # vide = pas d'amplification
ACTIONS=()                # liste des actions effectuées
GENERATED_FILES=()        # fichiers créés pendant l'exécution
STOP_AFTER_CURRENT=0      # flag déclenché par SIGINT
TOTAL_DURATION=0          # 0 = illimité
BASE_NAME=""
DO_DELETE=0
DO_EXEC=0
TARGET_DIR="./"           # Répertoire par défaut pour les vidéos
CURRENT_RPID=0            # PID de l'enregistrement en cours
CLEANUP_PIDS=()           # Liste des PIDs à nettoyer

# --- Helpers ---
log() {
    local msg="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" | tee -a "$LOGFILE"
}

discover_audio_devices() {
    echo "=== PÉRIPHÉRIQUES AUDIO DISPONIBLES ==="
    echo ""
    if command -v pactl >/dev/null 2>&1; then
        echo "📢 SORTIES AUDIO (son système à capturer) :"
        pactl list sources short | grep -E "(monitor|output)" | while read -r line; do
            device_name=$(echo "$line" | awk '{print $2}')
            echo "  --device \"$device_name\""
        done
        echo ""
        echo "🎤 ENTRÉES AUDIO (microphones) :"
        pactl list sources short | grep -vE "(monitor|output)" | while read -r line; do
            device_name=$(echo "$line" | awk '{print $2}')
            device_desc=$(echo "$line" | cut -d$'\t' -f2- | tr '\t' ' ')
            echo "  --mic \"$device_name\"    # $device_desc"
        done
        echo ""
        echo "💡 SUGGESTIONS SELON TON USAGE :"
        echo "  • Pour demo silencieuse : ./record_cam.sh 0 Demo --no-mic"
        echo "  • Pour tutoriel avec voix : ./record_cam.sh 0 Tutorial --mic"
        echo "  • Si problème audio : utilise un device spécifique ci-dessus"
    else
        echo "⚠️  pactl non disponible. Installation recommandée : sudo apt install pulseaudio-utils"
        echo ""
        echo "Devices par défaut :"
        echo "  --device \"pulse\"     # Son système"
        echo "  --mic \"default\"      # Microphone par défaut"
    fi
    echo ""
}

usage_and_exit() {
    cat << 'EOF'
USAGE:
  ./record_cam.sh [duree_total_en_sec|0] base_nom [OPTIONS]
  - duree_total_en_sec : durée totale. 0 = enregistrement illimité (arrêt par CTRL-C).
  - base_nom : base du nom des fichiers (ex : NestCam)
OPTIONS:
  --segment-duration SEC  : durée de chaque segment en secondes (par défaut: 600 = 10min)
                           Exemples: 300 (5min), 900 (15min), 1800 (30min)
  --volume FLOAT          : amplification audio (crée un fichier *_boost.ogv pour chaque segment)
  --device DEVICE         : périphérique audio système (par défaut "pulse")
  --mic [DEVICE]          : active l'enregistrement du microphone
                           Si DEVICE non spécifié, utilise le micro par défaut
                           Exemples: --mic ou --mic "alsa_input.pci-0000_00_1b.0.analog-stereo"
  --no-mic                : désactive explicitement le microphone (par défaut)
  --target_dir DIR        : répertoire de sortie pour les vidéos (par défaut: ./)
  --help                  : affiche cette aide
  --delete                : supprime les fichiers générés pour la base donnée (backup avant suppression)
  --exec                  : exécute normalement (comportement par défaut)
EXEMPLES:
  # Enregistrement illimité, segments de 5 minutes, son système + amplification x2 :
  ./record_cam.sh 0 NestCam --segment-duration 300 --volume 2.0
  # Enregistrement avec micro, segments de 15 minutes :
  ./record_cam.sh 0 Tutorial --mic --segment-duration 900 --volume 1.5
  # Segments très courts de 1 minute pour tests :
  ./record_cam.sh 600 Test --segment-duration 60
  # Enregistrement avec micro spécifique, segments longs de 30 minutes :
  ./record_cam.sh 3600 Meeting --mic "alsa_input.usb-0b05_1234.analog-stereo" --segment-duration 1800
  # Sans micro, segments par défaut (10min) :
  ./record_cam.sh 0 ScreenDemo --no-mic
  # Lister les périphériques audio disponibles :
  pactl list sources short
  # Supprimer proprement les fichiers générés :
  ./record_cam.sh --delete NestCam
PRÉREQUIS: recordmydesktop, ffmpeg (pour --volume), pactl (pour lister les périphériques)
EOF
    exit "$1"
}

force_kill_process() {
    local pid=$1
    local name=${2:-"recordmydesktop"}
    if [[ "$pid" -eq 0 ]] || ! kill -0 "$pid" >/dev/null 2>&1; then
        return 0
    fi
    log "Arrêt gracieux du processus $name PID=$pid"
    kill -TERM "$pid" 2>/dev/null || true
    # Attendre jusqu'à 5 secondes pour arrêt gracieux
    for i in {1..10}; do
        if ! kill -0 "$pid" >/dev/null 2>&1; then
            log "Processus $name PID=$pid arrêté gracieusement"
            return 0
        fi
        sleep 0.5
    done
    # Force kill si toujours vivant
    log "ATTENTION: Arrêt forcé du processus $name PID=$pid"
    kill -KILL "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" >/dev/null 2>&1; then
        log "ERREUR: Impossible d'arrêter le processus $name PID=$pid"
        return 1
    else
        log "Processus $name PID=$pid arrêté par force"
        return 0
    fi
}

cleanup_processes() {
    log "Nettoyage de tous les processus recordmydesktop en cours..."
    # Nettoyer le processus courant
    if [[ "$CURRENT_RPID" -ne 0 ]]; then
        force_kill_process "$CURRENT_RPID" "recordmydesktop-current"
        CURRENT_RPID=0
    fi
    # Nettoyer tous les PIDs enregistrés
    for pid in "${CLEANUP_PIDS[@]}"; do
        force_kill_process "$pid" "recordmydesktop-cleanup"
    done
    CLEANUP_PIDS=()
    # Sécurité : chercher tous les recordmydesktop orphelins lancés par ce script
    local orphans
    orphans=$(pgrep -f "recordmydesktop.*${BASE_NAME}" 2>/dev/null || true)
    if [[ -n "$orphans" ]]; then
        log "ALERTE: Processus recordmydesktop orphelins détectés, nettoyage forcé"
        echo "$orphans" | while read -r opid; do
            if [[ -n "$opid" ]]; then
                force_kill_process "$opid" "recordmydesktop-orphan"
            fi
        done
    fi
}

# --- Parse args ---
if [[ $# -eq 0 ]]; then
    usage_and_exit 0
fi

POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage_and_exit 0
            ;;
        --segment-duration)
            shift
            if [[ $# -eq 0 ]]; then
                echo "[ERREUR] --segment-duration nécessite une valeur en secondes (ex: 300 pour 5min)"
                exit 1
            fi
            if ! [[ "${1}" =~ ^[0-9]+$ ]] || [[ "$1" -le 0 ]]; then
                echo "[ERREUR] --segment-duration doit être un entier positif en secondes"
                exit 1
            fi
            SEGMENT_SECONDS="$1"
            shift
            ;;
        --volume)
            shift
            if [[ $# -eq 0 ]]; then
                echo "[ERREUR] --volume nécessite une valeur (ex: 2.0)"
                exit 1
            fi
            VOLUME_FILTER="$1"
            shift
            ;;
        --device)
            shift
            if [[ $# -eq 0 ]]; then
                echo "[ERREUR] --device nécessite un nom de périphérique"
                exit 1
            fi
            AUDIO_DEVICE="$1"
            shift
            ;;
        --mic)
            RECORD_MIC=1
            # Vérifier si un device spécifique est fourni
            if [[ $# -gt 1 ]] && [[ "${2:0:1}" != "-" ]]; then
                shift
                MICROPHONE_DEVICE="$1"
            else
                # Utiliser le micro par défaut
                MICROPHONE_DEVICE="default"
            fi
            shift
            ;;
        --no-mic)
            RECORD_MIC=0
            MICROPHONE_DEVICE=""
            shift
            ;;
        --target_dir)
            shift
            if [[ $# -eq 0 ]]; then
                echo "[ERREUR] --target_dir nécessite un répertoire"
                exit 1
            fi
            TARGET_DIR="$1"
            shift
            ;;
        --delete)
            DO_DELETE=1
            shift
            ;;
        --exec)
            DO_EXEC=1
            shift
            ;;
        -*)
            echo "[ERREUR] Option inconnue : $1"
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# restore positionals
set -- "${POSITIONAL[@]}"

# Gestion de --delete
if [[ "$DO_DELETE" -eq 1 ]]; then
    if [[ $# -lt 1 ]]; then
        echo "[ERREUR] --delete nécessite la base de nom en argument."
        exit 1
    fi
    TARGET_BASE="$1"
    # Créer le répertoire de backup
    BACKUP_DIR="$(dirname "$0")/${SCRIPT_NAME%.sh}_backup_$(date '+%Y%m%d_%H%M%S')"
    mkdir -p "$BACKUP_DIR"
    # Trouver et déplacer les fichiers
    found_files=0
    for pattern in "${TARGET_DIR}/${TARGET_BASE}_"*.ogv "${TARGET_DIR}/${TARGET_BASE}.ogv"; do
        for file in $pattern; do
            if [[ -e "$file" ]]; then
                cp -a "$file" "$BACKUP_DIR/" && rm -f "$file"
                echo "Moved $file -> $BACKUP_DIR/"
                found_files=1
            fi
        done
    done
    if [[ $found_files -eq 0 ]]; then
        echo "Aucun fichier trouvé pour la base '$TARGET_BASE'"
        rmdir "$BACKUP_DIR" 2>/dev/null || true
    else
        echo "Suppression terminée. Backup dans $BACKUP_DIR"
    fi
    exit 0
fi

# Vérifier les arguments obligatoires
if [[ $# -lt 2 ]]; then
    echo "[ERREUR] Arguments manquants. Usage minimal: $0 [duree_total_en_sec|0] base_nom"
    exit 1
fi

# Parser les arguments positionnels
if ! [[ "${1}" =~ ^[0-9]+$ ]]; then
    echo "[ERREUR] Durée invalide. Utilisez un entier en secondes (0 = illimité)."
    exit 1
fi
TOTAL_DURATION="$1"
BASE_NAME="$2"

# Créer le répertoire BOOST s'il n'existe pas
BOOST_DIR="${TARGET_DIR}/BOOST"
mkdir -p "$BOOST_DIR"

# Vérifier les prérequis
if ! command -v recordmydesktop >/dev/null 2>&1; then
    echo "[ERREUR] recordmydesktop n'est pas installé."
    exit 1
fi
if [[ -n "$VOLUME_FILTER" ]] && ! command -v ffmpeg >/dev/null 2>&1; then
    echo "[ERREUR] ffmpeg requis pour --volume mais il n'est pas installé."
    exit 1
fi

# Configuration du trap pour SIGINT et EXIT
trap 'log "SIGINT reçu : arrêt en cours..."; STOP_AFTER_CURRENT=1; cleanup_processes; exit 130' SIGINT
trap 'cleanup_processes' EXIT

# Calculer le temps de fin si durée limitée
START_TIME_EPOCH=$(date +%s)
if [[ "$TOTAL_DURATION" -gt 0 ]]; then
    END_TIME_EPOCH=$(( START_TIME_EPOCH + TOTAL_DURATION ))
else
    END_TIME_EPOCH=0
fi

# Afficher les paramètres de segmentation
SEGMENT_MINUTES=$(( SEGMENT_SECONDS / 60 ))
SEGMENT_REMAINDER=$(( SEGMENT_SECONDS % 60 ))
if [[ $SEGMENT_REMAINDER -eq 0 ]]; then
    SEGMENT_DISPLAY="${SEGMENT_MINUTES}min"
else
    SEGMENT_DISPLAY="${SEGMENT_MINUTES}min${SEGMENT_REMAINDER}s"
fi
log "Démarrage script: base=$BASE_NAME total_duration=$TOTAL_DURATION (0=illimité) segment_duration=${SEGMENT_SECONDS}s (${SEGMENT_DISPLAY}) device=$AUDIO_DEVICE mic=$RECORD_MIC mic_device=$MICROPHONE_DEVICE volume=$VOLUME_FILTER target_dir=$TARGET_DIR"
ACTIONS+=("Start script with base=${BASE_NAME}, total_duration=${TOTAL_DURATION}, segment_duration=${SEGMENT_SECONDS}s, device=${AUDIO_DEVICE}, mic=${RECORD_MIC}, mic_device=${MICROPHONE_DEVICE}, volume=${VOLUME_FILTER}, target_dir=${TARGET_DIR}")

# Construire les options audio pour recordmydesktop
AUDIO_OPTIONS=()
if [[ "$RECORD_MIC" -eq 1 ]]; then
    if [[ "$MICROPHONE_DEVICE" == "default" ]]; then
        AUDIO_OPTIONS=("--device" "$AUDIO_DEVICE" "--use-jack")
        log "Configuration audio : son système ($AUDIO_DEVICE) + microphone par défaut"
    else
        AUDIO_OPTIONS=("--device" "$AUDIO_DEVICE" "--use-jack")
        log "Configuration audio : son système ($AUDIO_DEVICE) + microphone ($MICROPHONE_DEVICE)"
    fi
else
    AUDIO_OPTIONS=("--device" "$AUDIO_DEVICE")
    log "Configuration audio : son système seulement ($AUDIO_DEVICE)"
fi

SEG_INDEX=0

# Boucle principale
while true; do
    # Vérifier si on doit s'arrêter
    if [[ "$STOP_AFTER_CURRENT" -eq 1 ]]; then
        log "Arrêt demandé, sortie de la boucle"
        break
    fi
    # Vérifier la durée totale
    if [[ "$END_TIME_EPOCH" -ne 0 ]]; then
        NOW=$(date +%s)
        if [[ "$NOW" -ge "$END_TIME_EPOCH" ]]; then
            log "Durée totale atteinte. Fin de la boucle principale."
            ACTIONS+=("Total duration reached, exiting main loop")
            break
        fi
        # Calculer le temps restant
        REMAINING=$(( END_TIME_EPOCH - NOW ))
        RECORD_SECONDS=$SEGMENT_SECONDS
        if [[ "$REMAINING" -lt "$SEGMENT_SECONDS" ]]; then
            RECORD_SECONDS=$REMAINING
        fi
    else
        RECORD_SECONDS=$SEGMENT_SECONDS
    fi
    # Si un enregistrement est en cours, l'arrêter d'abord
    if [[ "$CURRENT_RPID" -ne 0 ]]; then
        log "Arrêt de l'enregistrement précédent PID=$CURRENT_RPID"
        force_kill_process "$CURRENT_RPID" "recordmydesktop-previous"
        CURRENT_RPID=0
    fi
    # Construire le nom de fichier horodaté
    TS=$(date '+%Y%m%d_%H%M%S')
    OUTNAME="${BASE_NAME}_${TS}_part${SEG_INDEX}"
    OUTFILE="${TARGET_DIR}/${OUTNAME}.ogv"
    # Commande recordmydesktop avec options audio dynamiques
    log "Lancement enregistrement segment #${SEG_INDEX} -> $OUTFILE (durée cible ${RECORD_SECONDS}s)"
    ACTIONS+=("Record segment ${SEG_INDEX} -> ${OUTFILE} (${RECORD_SECONDS}s)")
    # Démarrer l'enregistrement en arrière-plan
    recordmydesktop --fps "$FPS" --v_quality "$V_QUALITY" --s_quality "$S_QUALITY" $ON_THE_FLY "${AUDIO_OPTIONS[@]}" -o "$OUTFILE" &
    CURRENT_RPID=$!
    CLEANUP_PIDS+=("$CURRENT_RPID")
    log "Processus recordmydesktop démarré : PID=$CURRENT_RPID"
    # Attendre la durée demandée puis arrêter
    sleep "$RECORD_SECONDS"
    # Arrêter gracieusement
    if [[ "$CURRENT_RPID" -ne 0 ]]; then
        log "Arrêt du processus recordmydesktop PID=$CURRENT_RPID pour segment ${SEG_INDEX}"
        force_kill_process "$CURRENT_RPID" "recordmydesktop-segment"
        CURRENT_RPID=0
    fi
    # Vérifier que le fichier a été créé (attendre plus longtemps)
    log "Attente de finalisation du fichier $OUTFILE..."
    sleep 5  # Temps plus long pour que recordmydesktop finalise le fichier
    if [[ ! -f "$OUTFILE" ]]; then
        log "ALERTE : fichier attendu non créé : $OUTFILE (segment ${SEG_INDEX})"
        ACTIONS+=("Warning: missing ${OUTFILE}")
    else
        GENERATED_FILES+=("$OUTFILE")
        log "Segment enregistré : $OUTFILE (taille: $(stat -c%s "$OUTFILE" 2>/dev/null || echo "N/A") bytes)"
        ACTIONS+=("Saved ${OUTFILE}")
        # Traitement ffmpeg si demandé
        if [[ -n "$VOLUME_FILTER" ]]; then
            BOOST_OUT="${BOOST_DIR}/${OUTNAME}_boost.ogv"
            log "Traitement ffmpeg pour amplification ${OUTFILE} -> ${BOOST_OUT}"
            ACTIONS+=("ffmpeg boost ${OUTFILE} -> ${BOOST_OUT}")
            if ffmpeg -y -i "$OUTFILE" -filter:a "volume=${VOLUME_FILTER}" -c:v copy "$BOOST_OUT" </dev/null &>/dev/null; then
                GENERATED_FILES+=("$BOOST_OUT")
                log "ffmpeg terminé avec succès pour ${OUTFILE}"
            else
                log "ERREUR ffmpeg pour ${OUTFILE}"
            fi
        fi
    fi
    SEG_INDEX=$((SEG_INDEX + 1))
done

# Nettoyage final
cleanup_processes

# Résumé post-exécution
log "Résumé des actions effectuées :"
i=1
for a in "${ACTIONS[@]}"; do
    echo "$i) $a" | tee -a "$LOGFILE"
    i=$((i+1))
done
log "Fichiers générés durant l'exécution :"
for f in "${GENERATED_FILES[@]}"; do
    echo " - $f" | tee -a "$LOGFILE"
done
log "Fin script."
exit 0
