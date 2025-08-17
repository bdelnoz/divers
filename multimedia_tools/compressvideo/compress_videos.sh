# todo
# demander de donner tr les valeurs possibles pour les differentes options dans un --helpdetail arg
#

#!/usr/bin/env bash
# =====================================================================
# Nom du script   : compress_videos.sh
# Auteur          : Bruno Delnoz
# Email           : bruno.delnoz@protonmail.com
# Target usage    : Parcours récursif d'un dossier source, compression
#                   maximale/forte des vidéos en conservant l'arborescence.
# Version         : v2.3 - Date : 2025-08-11
# ---------------------------------------------------------------------
# Changelog (historique complet obligatoire) :
#   - v1.0 (2025-08-11) : Version initiale complète.
#   - v1.1 (2025-08-11) : Ajout des arguments --quality, --height, --formats, --outdir.
#   - v1.2 (2025-08-11) : Application des règles données :
#                         * défauts depuis commande initiale, outdir "compressed", audio aac 48k, etc.
#   - v1.3 (2025-08-11) : Conformité stricte Règles Chat de Formation v34 :
#                         logs nommés, affichage numéroté, backup, HELP enrichi, exemples (incl. wlan1).
#   - v1.4 (2025-08-11) : Ajout --source_dir, création dossier "compressed" au même niveau,
#                         reproduction d'arborescence, profil par défaut si sans args.
#   - v1.5 (2025-08-11) : Comportement modifié : si **aucun argument** passé -> affichage --help et exit.
#                         Robustification de la recherche de fichiers (gestion des espaces),
#                         construction sécurisée des expressions find (pas d'eval),
#                         collecte et affichage post-exécution numéroté des actions,
#                         fallback d'extensions si ffmpeg -formats non concluant,
#                         logs et backup améliorés.
#   - v1.6 (2025-08-11) : Ajout prévisualisation liste des fichiers à compresser
#                         + demande de confirmation explicite avant traitement.
#   - v1.7 (2025-08-11) : Ajout mode simulation (--simulate) : liste fichiers trouvés, aucun traitement.
#   - v1.8 (2025-08-11) : Ajout affichage tailles individuelles + total avant/après,
#                         tableau comparatif avant/après avec pourcentages,
#                         --help enrichi listant plages de valeurs possibles.
#   - v1.9 (2025-08-11) : Correction : simulation calcule désormais tailles correctement.
#                         Suppression de l'affichage de la liste des extensions utilisées
#                         (seule modification par rapport à v1.8). Tout le reste inchangé.
#   - v2.0 (2025-08-11) : Mode --simulate refait pour faire exactement comme --exec mais sans compression.
#                         Tableau avec tous les fichiers, 2 colonnes avant/après compression estimée,
#                         même processus de sélection et confirmation mais sans exécution ffmpeg.
#   - v2.1 (2025-08-11) : Application des nouvelles valeurs par défaut haute compression :
#                         Codec HEVC libx265, profil Main10, résolution 406x720, format yuv420p10le,
#                         ~24fps, bitrate vidéo ~91kbps, audio AAC LC 44.1kHz stéréo 48kbps, conteneur MP4.
#                         Ajout paramètres --profile, --pix_fmt, --fps, --vbitrate, --sample_rate.
#   - v2.2 (2025-08-11) : Ajout paramètres --smin, --smax pour taille minimale/maximale des fichiers à traiter.
#                         --skip_identical pour ignorer fichiers déjà traités dans outdir.
#                         --resume pour reprendre traitement interrompu.
#                         Amélioration gestion d'erreurs ffmpeg avec retry automatique.
#   - v2.3 (2025-08-11) : Affichage estimation taille après traitement en mode --exec avant confirmation.
#                         Estimation temps de traitement en mode --simulate et --exec avant confirmation.
#                         Calcul basé sur taille fichier, résolution cible, codec utilisé.
# =====================================================================

set -euo pipefail
IFS=$'\n\t'

# --------------------------- Métadonnées ------------------------------
SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="v2.3"
DATE="2025-08-11"
LOGFILE="$SCRIPT_DIR/log.${SCRIPT_NAME%.sh}.${VERSION}.log"
BACKUP_BASE_DIR="$SCRIPT_DIR/backup_$(date +%Y%m%d_%H%M%S)"
# ---------------------------------------------------------------------

# --------------------------- Valeurs par défaut -----------------------
DEFAULT_CRF=32
DEFAULT_WIDTH=406
DEFAULT_HEIGHT=720
DEFAULT_AUDIO="aac"
DEFAULT_AUDIO_BITRATE="48k"
DEFAULT_SAMPLE_RATE="44100"
DEFAULT_VIDEO_CODEC="libx265"
DEFAULT_PROFILE="main10"
DEFAULT_PIX_FMT="yuv420p10le"
DEFAULT_FPS="24"
DEFAULT_VBITRATE="91k"
DEFAULT_PRESET="slow"
DEFAULT_FORMATS=()            # vide = on essaiera de détecter via ffmpeg puis fallback
DEFAULT_OUTDIR_NAME="compressed"
DEFAULT_SOURCE_DIR="$(pwd)"
DEFAULT_SIZE_MIN="1M"         # Taille minimale des fichiers à traiter
DEFAULT_SIZE_MAX=""           # Pas de limite maximale par défaut
DEFAULT_RETRY_COUNT=2         # Nombre de tentatives en cas d'échec ffmpeg
# ---------------------------------------------------------------------

# --------------------------- Variables runtime ------------------------
CRF_VALUE=""
MAX_WIDTH=""
MAX_HEIGHT=""
AUDIO_CODEC=""
AUDIO_BITRATE=""
SAMPLE_RATE=""
VIDEO_CODEC=""
PROFILE=""
PIX_FMT=""
FPS=""
VBITRATE=""
PRESET=""
FORMATS=()
OUTDIR=""
SOURCE_DIR=""
SIZE_MIN=""
SIZE_MAX=""
RETRY_COUNT=""
EXEC_FLAG=0
SIMULATE_FLAG=0
DELETE_ONLY=0
SKIP_IDENTICAL=0
RESUME_MODE=0
PROCESSED_FILES=()   # fichiers créés
ACTION_LOGS=()       # actions réalisées
FILES_TO_PROCESS=()
SKIPPED_FILES=()     # fichiers ignorés
FAILED_FILES=()      # fichiers ayant échoué
declare -A SIZE_BEFORE
declare -A SIZE_AFTER
# ---------------------------------------------------------------------

# --------------------------- HELP (obligatoire) -----------------------
show_help() {
cat <<'EOF'
Usage : ./compress_videos.sh --exec [options]
      ./compress_videos.sh --simulate [options]
      ./compress_videos.sh --delete [--source_dir <chemin>] [--outdir <chemin>]

Options principales :
 --exec                 Lance la compression (obligatoire pour exécution)
 --simulate             Mode simulation : même processus que --exec mais sans compression réelle
                        Affiche tableau avec tous fichiers, tailles avant/après estimées
 --delete               Supprime tout le dossier de sortie (backup préalable)
 --resume               Reprend un traitement interrompu (ignore fichiers déjà traités)
 --skip_identical       Ignore les fichiers déjà présents dans le dossier de sortie
 --source_dir <chemin>  Dossier source contenant les vidéos (défaut: dossier courant)
 --outdir <dossier>     Dossier de sortie (défaut: parent(source)/compressed)
 --formats "<liste>"    Extensions à traiter (ex: "mp4 mov avi") (si vide -> détection / fallback)

Options filtrage taille :
 --smin <taille>        Taille minimale des fichiers (ex: 1M, 500K, 2G) (défaut: 1M)
 --smax <taille>        Taille maximale des fichiers (ex: 1G, 500M) (défaut: aucune limite)

Options vidéo (défauts optimisés compression max) :
 --codec <codec>        Codec vidéo (défaut: libx265)
 --profile <profile>    Profil encodeur (défaut: main10)
 --quality <valeur>     CRF pour qualité vidéo (défaut: 32)
 --width <pixels>       Largeur maximale de sortie (défaut: 406)
 --height <pixels>      Hauteur maximale de sortie (défaut: 720)
 --pix_fmt <format>     Format pixel (défaut: yuv420p10le)
 --fps <fps>            Framerate cible (défaut: 24)
 --vbitrate <bitrate>   Bitrate vidéo max (défaut: 91k)
 --preset <preset>      Preset encodeur (défaut: slow)
 --retry <count>        Nombre de tentatives en cas d'échec (défaut: 2)

Options audio (défauts optimisés compression max) :
 --audio <codec>        Codec audio (défaut: aac)
 --abitrate <bitrate>   Débit audio (défaut: 48k)
 --sample_rate <rate>   Fréquence échantillonnage (défaut: 44100)

Exemples :
 # Compression basique avec profil défaut (haute compression)
 ./compress_videos.sh --exec --source_dir /home/videos

 # Simulation avec wlan1 (interface réseau) pour transfert
 ./compress_videos.sh --simulate --source_dir /mnt/wlan1/videos --quality 28

 # Compression personnalisée avec filtres taille
 ./compress_videos.sh --exec --width 720 --height 480 --smin 10M --smax 1G

 # Reprendre traitement interrompu
 ./compress_videos.sh --exec --resume --skip_identical

 # Compression ultra avec paramètres par défaut
 ./compress_videos.sh --exec

Profil par défaut (compression maximale) :
 - Vidéo : HEVC (H.265) libx265, profil Main10, 406×720, yuv420p10le, 24fps, ~91kbps
 - Audio : AAC LC, 44.1kHz stéréo, 48kbps
 - Conteneur : MP4

Logs détaillés : log.compress_videos.v2.3.log
Backup avant suppression : backup_YYYYMMDD_HHMMSS
EOF
}
# ---------------------------------------------------------------------

# --------------------------- Pré-requis --------------------------------
check_prerequisites() {
 local miss=0
 for cmd in ffmpeg find mkdir cp date awk sed stat numfmt basename dirname printf du; do
   if ! command -v "${cmd%% *}" >/dev/null 2>&1 ; then
     echo "[ERREUR] commande requise manquante : $cmd" | tee -a "$LOGFILE"
     miss=1
   fi
 done
 if [ "$miss" -eq 1 ]; then
   echo "[ERREUR] Installez les dépendances et relancez." | tee -a "$LOGFILE"
   exit 1
 fi
}
# ---------------------------------------------------------------------

# --------------------------- Fonctions utilitaires ---------------------
_safe_mkdir() {
 mkdir -p "$1"
 echo "[INFO] mkdir -p $1" | tee -a "$LOGFILE"
}

_backup_and_remove_outdir() {
 echo "[INFO] Backup avant suppression -> $BACKUP_BASE_DIR" | tee -a "$LOGFILE"
 _safe_mkdir "$BACKUP_BASE_DIR"
 if [ -d "$OUTDIR" ]; then
   cp -a "$OUTDIR" "$BACKUP_BASE_DIR/" 2>>"$LOGFILE" || true
   echo "[INFO] Copie de $OUTDIR vers $BACKUP_BASE_DIR/" | tee -a "$LOGFILE"
 fi
 if [ -f "$LOGFILE" ]; then
   cp -a "$LOGFILE" "$BACKUP_BASE_DIR/" 2>/dev/null || true
 fi
 echo "[INFO] Suppression de $OUTDIR" | tee -a "$LOGFILE"
 rm -rf "$OUTDIR"
 echo "[OK] Suppression effectuée." | tee -a "$LOGFILE"
}

delete_created_files() {
 _backup_and_remove_outdir
 exit 0
}

# Conversion taille en octets pour comparaisons
size_to_bytes() {
 local size="$1"
 case "${size: -1}" in
   K|k) echo "$((${size%?} * 1024))" ;;
   M|m) echo "$((${size%?} * 1024 * 1024))" ;;
   G|g) echo "$((${size%?} * 1024 * 1024 * 1024))" ;;
   T|t) echo "$((${size%?} * 1024 * 1024 * 1024 * 1024))" ;;
   *) echo "${size}" ;;
 esac
}

# Vérification si fichier correspond aux critères de taille
check_file_size() {
 local filepath="$1"
 local filesize
 filesize=$(stat -c%s "$filepath" 2>/dev/null || echo 0)

 # Vérification taille minimale
 if [ -n "$SIZE_MIN" ]; then
   local min_bytes
   min_bytes=$(size_to_bytes "$SIZE_MIN")
   if [ "$filesize" -lt "$min_bytes" ]; then
     return 1
   fi
 fi

 # Vérification taille maximale
 if [ -n "$SIZE_MAX" ]; then
   local max_bytes
   max_bytes=$(size_to_bytes "$SIZE_MAX")
   if [ "$filesize" -gt "$max_bytes" ]; then
     return 1
   fi
 fi

 return 0
}

# Détection d'extensions par ffmpeg, fallback si résultat non fiable.
detect_formats() {
 if [ ${#FORMATS[@]} -eq 0 ]; then
   mapfile -t ff_exs < <(ffmpeg -formats 2>/dev/null | awk '/^[ ]*E/ {print $2}' | tr -d '*' | tr '[:upper:]' '[:lower:]' | sort -u)
   # Filtrer pour garder des tokens plausibles d'extensions (2-4 alphanum chars)
   filtered=()
   for e in "${ff_exs[@]}"; do
     if [[ "$e" =~ ^[a-z0-9]{2,4}$ ]]; then
       filtered+=("$e")
     fi
   done
   # Si la détection donne une liste plausible on l'utilise, sinon fallback commun.
   if [ ${#filtered[@]} -ge 3 ]; then
     FORMATS=("${filtered[@]}")
   else
     FORMATS=(mp4 mov mkv m4v avi mpg mpeg webm ts flv ogv)
   fi
 fi
}

# Construction sécurisé de l'expression find
build_find_expr() {
 find_expr=( -type f '(' )
 first=1
 for ext in "${FORMATS[@]}"; do
   [ -z "$ext" ] && continue
   if [ "$first" -eq 1 ]; then
     find_expr+=( -iname "*.${ext}" )
     first=0
   else
     find_expr+=( -o -iname "*.${ext}" )
   fi
 done
 find_expr+=( ')' -print0 )
}

# Vérification si fichier de sortie existe déjà
output_file_exists() {
 local infile="$1"
 local SOURCE_ABS="$2"
 local OUTDIR_ABS="$3"

 local relpath="${infile#$SOURCE_ABS/}"
 local dirpath="$(dirname "$relpath")"
 local target_dir="$OUTDIR_ABS/$dirpath"
 local base_name="$(basename "${infile%.*}")"
 local OUTPUT_FILE="$target_dir/${base_name}_mini.mp4"

 [ -f "$OUTPUT_FILE" ]
}

# Récupération fichiers dans FILES_TO_PROCESS (gestion espaces + filtres)
gather_files() {
 FILES_TO_PROCESS=()
 SKIPPED_FILES=()
 local SOURCE_ABS="$(cd "$SOURCE_DIR" && pwd)"
 local OUTDIR_ABS="$(cd "$(dirname "$OUTDIR")" && pwd)/$(basename "$OUTDIR")"

 while IFS= read -r -d '' file; do
   # Filtrage par taille
   if ! check_file_size "$file"; then
     SKIPPED_FILES+=("$file (taille hors critères)")
     continue
   fi

   # Mode resume/skip_identical : vérifier si déjà traité
   if { [ "$RESUME_MODE" -eq 1 ] || [ "$SKIP_IDENTICAL" -eq 1 ]; } && output_file_exists "$file" "$SOURCE_ABS" "$OUTDIR_ABS"; then
     SKIPPED_FILES+=("$file (déjà traité)")
     continue
   fi

   FILES_TO_PROCESS+=("$file")
 done < <(find "$SOURCE_ABS" "${find_expr[@]}")
}

human_size() {
 if command -v numfmt >/dev/null 2>&1; then
   numfmt --to=iec --suffix=B "$1"
 else
   echo "${1}B"
 fi
}

# Estimation heuristique du ratio post-compression selon codec/crf/bitrate
estimate_ratio() {
 local codec="$1"
 local crf="$2"
 local vbitrate="$3"

 # Pour des bitrates très bas comme 91k, ratio plus agressif
 case "$vbitrate" in
   *k)
     vbit_num="${vbitrate%k}"
     if [ "$vbit_num" -le 100 ]; then
       echo "0.08"  # Compression très agressive pour bitrate bas
       return
     fi
     ;;
 esac

 case "$codec" in
   libx265|x265|hevc)
     if [ "$crf" -le 20 ]; then echo "0.85"
     elif [ "$crf" -le 28 ]; then echo "0.50"
     elif [ "$crf" -le 40 ]; then echo "0.25"
     else echo "0.12"; fi
     ;;
   libaom-av1|av1)
     if [ "$crf" -le 25 ]; then echo "0.75"
     elif [ "$crf" -le 35 ]; then echo "0.40"
     elif [ "$crf" -le 45 ]; then echo "0.20"
     else echo "0.12"; fi
     ;;
   libvpx-vp9|vp9)
     if [ "$crf" -le 25 ]; then echo "0.80"
     elif [ "$crf" -le 35 ]; then echo "0.45"
     elif [ "$crf" -le 45 ]; then echo "0.22"
     else echo "0.12"; fi
     ;;
   *)
     if [ "$crf" -le 25 ]; then echo "0.70"
     elif [ "$crf" -le 35 ]; then echo "0.40"
     else echo "0.25"; fi
     ;;
 esac
}

# Estimation du temps de traitement par fichier (en secondes)
estimate_processing_time() {
 local filesize="$1"    # taille en octets
 local codec="$2"       # codec vidéo
 local preset="$3"      # preset ffmpeg
 local target_width="$4"  # résolution cible
 local target_height="$5" # résolution cible

 # Facteurs de base selon codec (secondes par MB)
 local base_factor
 case "$codec" in
   libx265|x265|hevc) base_factor=15 ;;      # HEVC plus lent
   libaom-av1|av1) base_factor=25 ;;         # AV1 très lent
   libvpx-vp9|vp9) base_factor=12 ;;         # VP9 modéré
   libx264|x264) base_factor=8 ;;            # H.264 rapide
   *) base_factor=10 ;;                      # Défaut
 esac

 # Facteur preset
 local preset_multiplier
 case "$preset" in
   ultrafast) preset_multiplier="0.3" ;;
   superfast) preset_multiplier="0.5" ;;
   veryfast) preset_multiplier="0.7" ;;
   faster) preset_multiplier="0.9" ;;
   fast) preset_multiplier="1.0" ;;
   medium) preset_multiplier="1.3" ;;
   slow) preset_multiplier="2.0" ;;
   slower) preset_multiplier="3.5" ;;
   veryslow) preset_multiplier="6.0" ;;
   *) preset_multiplier="2.0" ;;
 esac

 # Facteur résolution (pixels totaux en millions)
 local target_pixels=$((target_width * target_height))
 local resolution_factor
 if [ "$target_pixels" -lt 500000 ]; then          # < 0.5MP
   resolution_factor="0.7"
 elif [ "$target_pixels" -lt 1000000 ]; then       # < 1MP
   resolution_factor="0.9"
 elif [ "$target_pixels" -lt 2000000 ]; then       # < 2MP (1080p)
   resolution_factor="1.0"
 else                                               # > 2MP
   resolution_factor="1.3"
 fi

 # Calcul final : (taille_en_MB) * base_factor * preset_multiplier * resolution_factor
 local size_mb=$((filesize / 1024 / 1024))
 if [ "$size_mb" -eq 0 ]; then size_mb=1; fi

 awk -v s="$size_mb" -v b="$base_factor" -v p="$preset_multiplier" -v r="$resolution_factor" \
     'BEGIN{printf("%.0f", s * b * p * r)}'
}

# Formatage temps en heures/minutes/secondes
format_time() {
 local total_seconds="$1"
 local hours=$((total_seconds / 3600))
 local minutes=$(((total_seconds % 3600) / 60))
 local seconds=$((total_seconds % 60))

 if [ "$hours" -gt 0 ]; then
   printf "%dh%02dm%02ds" "$hours" "$minutes" "$seconds"
 elif [ "$minutes" -gt 0 ]; then
   printf "%dm%02ds" "$minutes" "$seconds"
 else
   printf "%ds" "$seconds"
 fi
}

# Fonction de compression avec retry automatique
compress_with_retry() {
 local infile="$1"
 local output_file="$2"
 local attempt=1
 local success=0

 while [ "$attempt" -le "$RETRY_COUNT" ] && [ "$success" -eq 0 ]; do
   echo "[INFO] Tentative $attempt/$RETRY_COUNT pour : $(basename "$infile")" | tee -a "$LOGFILE"

   # Construction commande ffmpeg avec tous les paramètres
   ffmpeg_cmd=(
     ffmpeg -y -i "$infile"
     -vf "scale=${MAX_WIDTH}:${MAX_HEIGHT}"
     -c:v "$VIDEO_CODEC"
     -profile:v "$PROFILE"
     -preset "$PRESET"
     -crf "$CRF_VALUE"
     -maxrate "$VBITRATE"
     -bufsize "$((${VBITRATE%k} * 2))k"
     -pix_fmt "$PIX_FMT"
     -r "$FPS"
     -c:a "$AUDIO_CODEC"
     -b:a "$AUDIO_BITRATE"
     -ar "$SAMPLE_RATE"
     -ac 2
     -movflags +faststart
     "$output_file"
   )

   if "${ffmpeg_cmd[@]}" 2>&1 | tee -a "$LOGFILE"; then
     if [ -f "$output_file" ] && [ -s "$output_file" ]; then
       success=1
       echo "[OK] Compression réussie (tentative $attempt)" | tee -a "$LOGFILE"
     else
       echo "[ERREUR] Fichier de sortie vide ou inexistant (tentative $attempt)" | tee -a "$LOGFILE"
       rm -f "$output_file" 2>/dev/null || true
     fi
   else
     echo "[ERREUR] Échec ffmpeg (tentative $attempt)" | tee -a "$LOGFILE"
     rm -f "$output_file" 2>/dev/null || true
   fi

   attempt=$((attempt + 1))
 done

 return $((success == 0))
}
# ---------------------------------------------------------------------

# --------------------------- Traitement principal ----------------------
process_files() {
 SOURCE_ABS="$(cd "$SOURCE_DIR" && pwd)"
 OUTDIR_ABS="$(cd "$(dirname "$OUTDIR")" && pwd)/$(basename "$OUTDIR")"

 echo "[INFO] Source absolue   : $SOURCE_ABS" | tee -a "$LOGFILE"
 echo "[INFO] Sortie absolue   : $OUTDIR_ABS" | tee -a "$LOGFILE"

 if [ "$SIMULATE_FLAG" -eq 0 ]; then
   _safe_mkdir "$OUTDIR_ABS"
 fi

 detect_formats
 build_find_expr
 gather_files

 echo "=== Fichiers trouvés (${#FILES_TO_PROCESS[@]}) ===" | tee -a "$LOGFILE"
 if [ ${#SKIPPED_FILES[@]} -gt 0 ]; then
   echo "=== Fichiers ignorés (${#SKIPPED_FILES[@]}) ===" | tee -a "$LOGFILE"
   for skipped in "${SKIPPED_FILES[@]}"; do
     echo "  - $skipped" | tee -a "$LOGFILE"
   done
 fi

 if [ ${#FILES_TO_PROCESS[@]} -eq 0 ]; then
   echo "[INFO] Aucun fichier à traiter." | tee -a "$LOGFILE"
   exit 0
 fi

 # Calcul des tailles avant et estimation après
 total_before=0
 total_after_est=0
 total_time_est=0
 ratio=$(estimate_ratio "$VIDEO_CODEC" "$CRF_VALUE" "$VBITRATE")

 for f in "${FILES_TO_PROCESS[@]}"; do
   size=$(stat -c%s "$f" 2>/dev/null || echo 0)
   SIZE_BEFORE["$f"]="$size"
   estimated_size=$(awk -v s="$size" -v r="$ratio" 'BEGIN{printf("%.0f", s*r)}')
   SIZE_AFTER["$f"]="$estimated_size"
   total_before=$((total_before + size))
   total_after_est=$((total_after_est + estimated_size))

   # Estimation temps de traitement pour ce fichier
   file_time=$(estimate_processing_time "$size" "$VIDEO_CODEC" "$PRESET" "$MAX_WIDTH" "$MAX_HEIGHT")
   total_time_est=$((total_time_est + file_time))
 done

 # Affichage liste numérotée avec tailles
 echo ""
 i=1
 for f in "${FILES_TO_PROCESS[@]}"; do
   before_size=${SIZE_BEFORE["$f"]}
   after_size=${SIZE_AFTER["$f"]}
   if [ "$SIMULATE_FLAG" -eq 1 ]; then
     printf "%3d) %s\n     Avant: %s → Après: %s (est.)\n" "$i" "$f" "$(human_size "$before_size")" "$(human_size "$after_size")" | tee -a "$LOGFILE"
   else
     printf "%3d) %s\n     Avant: %s → Après: %s (est.)\n" "$i" "$f" "$(human_size "$before_size")" "$(human_size "$after_size")" | tee -a "$LOGFILE"
   fi
   i=$((i+1))
 done

 echo "" | tee -a "$LOGFILE"
 printf "=== RÉCAPITULATIF ===\n" | tee -a "$LOGFILE"
 printf "Taille totale avant : %s\n" "$(human_size "$total_before")" | tee -a "$LOGFILE"
 printf "Taille estimée après : %s (ratio %s)\n" "$(human_size "$total_after_est")" "$ratio" | tee -a "$LOGFILE"
 if [ "$total_before" -gt 0 ]; then
   total_gain=$(awk -v b="$total_before" -v a="$total_after_est" 'BEGIN{printf("%.1f", (b-a)/b*100)}')
   printf "Réduction estimée : %s%% (gain ~%s)\n" "$total_gain" "$(human_size $((total_before - total_after_est)))" | tee -a "$LOGFILE"
 fi
 printf "Temps estimé total : %s\n" "$(format_time "$total_time_est")" | tee -a "$LOGFILE"
 echo "" | tee -a "$LOGFILE"

 # Confirmation utilisateur avec informations complètes
 if [ "$SIMULATE_FLAG" -eq 1 ]; then
   printf "Confirmer la SIMULATION de compression de ces %d fichiers ?\n" "${#FILES_TO_PROCESS[@]}" | tee -a "$LOGFILE"
   printf "Temps estimé: %s, Compression estimée: %s → %s (%s%% de réduction)\n" \
          "$(format_time "$total_time_est")" "$(human_size "$total_before")" "$(human_size "$total_after_est")" "$total_gain" | tee -a "$LOGFILE"
 else
   printf "Confirmer la COMPRESSION de ces %d fichiers ?\n" "${#FILES_TO_PROCESS[@]}" | tee -a "$LOGFILE"
   printf "Temps estimé: %s, Compression estimée: %s → %s (%s%% de réduction)\n" \
          "$(format_time "$total_time_est")" "$(human_size "$total_before")" "$(human_size "$total_after_est")" "$total_gain" | tee -a "$LOGFILE"
 fi
 read -r -p "(o/N) : " confirm
 [[ "$confirm" =~ ^[oOyY]$ ]] || { echo "[INFO] Annulé."; exit 0; }

 # Traitement des fichiers
 INDEX=1
 total_after_real=0
 success_count=0
 FAILED_FILES=()

 for infile in "${FILES_TO_PROCESS[@]}"; do
   relpath="${infile#$SOURCE_ABS/}"
   dirpath="$(dirname "$relpath")"
   target_dir="$OUTDIR_ABS/$dirpath"
   base_name="$(basename "${infile%.*}")"
   OUTPUT_FILE="$target_dir/${base_name}_mini.mp4"

   if [ "$SIMULATE_FLAG" -eq 0 ]; then
     # Mode exécution réelle
     _safe_mkdir "$target_dir"
     echo "[$INDEX] Compression : $infile -> $OUTPUT_FILE" | tee -a "$LOGFILE"

     if compress_with_retry "$infile" "$OUTPUT_FILE"; then
       out_size=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
       SIZE_AFTER["$infile"]="$out_size"
       before_size=${SIZE_BEFORE["$infile"]:=$(stat -c%s "$infile" 2>/dev/null || echo 0)}
       total_after_real=$((total_after_real + out_size))
       success_count=$((success_count + 1))

       PROCESSED_FILES+=("$OUTPUT_FILE")
       ACTION_LOGS+=("[$INDEX] Compressé: $infile -> $OUTPUT_FILE")
       echo "[OK] Taille avant: $(human_size "$before_size")  après: $(human_size "$out_size")" | tee -a "$LOGFILE"
     else
       echo "[ÉCHEC] Impossible de compresser : $infile" | tee -a "$LOGFILE"
       FAILED_FILES+=("$infile")
       ACTION_LOGS+=("[$INDEX] ÉCHEC: $infile")
     fi
   else
     # Mode simulation
     echo "[$INDEX] Simulation : $infile -> $OUTPUT_FILE" | tee -a "$LOGFILE"
     ACTION_LOGS+=("[$INDEX] Simulé: $infile -> $OUTPUT_FILE")
     success_count=$((success_count + 1))
   fi

   INDEX=$((INDEX + 1))
 done

 # Affichage tableau final
 echo "" | tee -a "$LOGFILE"
 if [ "$SIMULATE_FLAG" -eq 1 ]; then
   echo "=== Tableau de simulation de compression ===" | tee -a "$LOGFILE"
 else
   echo "=== Récapitulatif des compressions effectuées ===" | tee -a "$LOGFILE"
 fi

 printf "%4s %-70s %12s %12s %8s\n" "No." "Fichier" "Avant" "Après" "Gain%" | tee -a "$LOGFILE"
 echo "$(printf '%*s' 108 '' | tr ' ' '-')" | tee -a "$LOGFILE"

 i=1
 for infile in "${FILES_TO_PROCESS[@]}"; do
   before=${SIZE_BEFORE["$infile"]:-0}
   after=${SIZE_AFTER["$infile"]:-0}
   if [ "$before" -gt 0 ]; then
     gain=$(awk -v b="$before" -v a="$after" 'BEGIN{printf("%.1f", (b-a)/b*100)}')
   else
     gain="0.0"
   fi

   # Marquer les fichiers ayant échoué
   filename="$(basename "$infile")"
   for failed in "${FAILED_FILES[@]}"; do
     if [ "$failed" = "$infile" ]; then
       filename="$filename [ÉCHEC]"
       break
     fi
   done

   printf "%4d %-70.70s %12s %12s %7s\n" "$i" "$filename" "$(human_size "$before")" "$(human_size "$after")" "${gain}%" | tee -a "$LOGFILE"
   i=$((i+1))
 done

 echo "" | tee -a "$LOGFILE"
 printf "Total avant : %s\n" "$(human_size "$total_before")" | tee -a "$LOGFILE"

 if [ "$SIMULATE_FLAG" -eq 1 ]; then
   printf "Total estimé après : %s\n" "$(human_size "$total_after_est")" | tee -a "$LOGFILE"
   if [ "$total_before" -gt 0 ]; then
     total_gain=$(awk -v b="$total_before" -v a="$total_after_est" 'BEGIN{printf("%.1f", (b-a)/b*100)}')
   else
     total_gain="0.0"
   fi
   printf "Réduction estimée : %s%% (codec %s, CRF %s, bitrate %s)\n" "$total_gain" "$VIDEO_CODEC" "$CRF_VALUE" "$VBITRATE" | tee -a "$LOGFILE"
 else
   printf "Total après : %s\n" "$(human_size "$total_after_real")" | tee -a "$LOGFILE"
   if [ "$total_before" -gt 0 ]; then
     total_gain=$(awk -v b="$total_before" -v a="$total_after_real" 'BEGIN{printf("%.1f", (b-a)/b*100)}')
   else
     total_gain="0.0"
   fi
   printf "Réduction réelle : %s%%\n" "$total_gain" | tee -a "$LOGFILE"
   printf "Fichiers traités avec succès : %d/%d\n" "$success_count" "${#FILES_TO_PROCESS[@]}" | tee -a "$LOGFILE"

   if [ ${#FAILED_FILES[@]} -gt 0 ]; then
     echo "" | tee -a "$LOGFILE"
     echo "=== Fichiers ayant échoué ===" | tee -a "$LOGFILE"
     for failed in "${FAILED_FILES[@]}"; do
       echo "  - $failed" | tee -a "$LOGFILE"
     done
   fi
 fi

 # Affichage des actions post-exécution numérotées
 echo "" | tee -a "$LOGFILE"
 echo "=== Actions effectuées ===" | tee -a "$LOGFILE"
 for action in "${ACTION_LOGS[@]}"; do
   echo "$action" | tee -a "$LOGFILE"
 done

 echo "Logs détaillés : $LOGFILE" | tee -a "$LOGFILE"
}
# ---------------------------------------------------------------------

# --------------------------- Entrée principale -------------------------
if [ $# -eq 0 ]; then
 show_help
 exit 0
fi

_safe_mkdir "$SCRIPT_DIR"
: > "$LOGFILE"
echo "[INFO] Lancement script $SCRIPT_NAME $VERSION ($DATE)" | tee -a "$LOGFILE"

check_prerequisites

# Parsing des arguments
while [ $# -gt 0 ]; do
 case "$1" in
   --help) show_help; exit 0 ;;
   --exec) EXEC_FLAG=1; shift ;;
   --simulate) SIMULATE_FLAG=1; EXEC_FLAG=1; shift ;;
   --delete) DELETE_ONLY=1; shift ;;
   --resume) RESUME_MODE=1; shift ;;
   --skip_identical) SKIP_IDENTICAL=1; shift ;;
   --source_dir) SOURCE_DIR="$2"; shift 2 ;;
   --quality|--crf) CRF_VALUE="$2"; shift 2 ;;
   --width) MAX_WIDTH="$2"; shift 2 ;;
   --height) MAX_HEIGHT="$2"; shift 2 ;;
   --smin) SIZE_MIN="$2"; shift 2 ;;
   --smax) SIZE_MAX="$2"; shift 2 ;;
   --retry) RETRY_COUNT="$2"; shift 2 ;;
   --formats) IFS=' ' read -r -a FORMATS <<< "$2"; shift 2 ;;
   --audio) AUDIO_CODEC="$2"; shift 2 ;;
   --abitrate) AUDIO_BITRATE="$2"; shift 2 ;;
   --sample_rate) SAMPLE_RATE="$2"; shift 2 ;;
   --codec) VIDEO_CODEC="$2"; shift 2 ;;
   --profile) PROFILE="$2"; shift 2 ;;
   --pix_fmt) PIX_FMT="$2"; shift 2 ;;
   --fps) FPS="$2"; shift 2 ;;
   --vbitrate) VBITRATE="$2"; shift 2 ;;
   --preset) PRESET="$2"; shift 2 ;;
   --outdir) OUTDIR="$2"; shift 2 ;;
   *)
     echo "[ERREUR] Option inconnue : $1" | tee -a "$LOGFILE"
     show_help
     exit 1
     ;;
 esac
done

# Application valeurs par défaut si non fournies
: "${SOURCE_DIR:=$DEFAULT_SOURCE_DIR}"
: "${CRF_VALUE:=$DEFAULT_CRF}"
: "${MAX_WIDTH:=$DEFAULT_WIDTH}"
: "${MAX_HEIGHT:=$DEFAULT_HEIGHT}"
: "${AUDIO_CODEC:=$DEFAULT_AUDIO}"
: "${AUDIO_BITRATE:=$DEFAULT_AUDIO_BITRATE}"
: "${SAMPLE_RATE:=$DEFAULT_SAMPLE_RATE}"
: "${VIDEO_CODEC:=$DEFAULT_VIDEO_CODEC}"
: "${PROFILE:=$DEFAULT_PROFILE}"
: "${PIX_FMT:=$DEFAULT_PIX_FMT}"
: "${FPS:=$DEFAULT_FPS}"
: "${VBITRATE:=$DEFAULT_VBITRATE}"
: "${PRESET:=$DEFAULT_PRESET}"
: "${SIZE_MIN:=$DEFAULT_SIZE_MIN}"
: "${RETRY_COUNT:=$DEFAULT_RETRY_COUNT}"
: "${OUTDIR:=$(cd "$SOURCE_DIR" && cd .. >/dev/null 2>&1 && pwd)/$DEFAULT_OUTDIR_NAME}"

echo "[INFO] Paramètres utilisés (profil haute compression) :" | tee -a "$LOGFILE"
echo "       SOURCE_DIR   = $SOURCE_DIR" | tee -a "$LOGFILE"
echo "       OUTDIR       = $OUTDIR" | tee -a "$LOGFILE"
echo "       VIDEO_CODEC  = $VIDEO_CODEC" | tee -a "$LOGFILE"
echo "       PROFILE      = $PROFILE" | tee -a "$LOGFILE"
echo "       RESOLUTION   = ${MAX_WIDTH}x${MAX_HEIGHT}" | tee -a "$LOGFILE"
echo "       PIX_FMT      = $PIX_FMT" | tee -a "$LOGFILE"
echo "       FPS          = $FPS" | tee -a "$LOGFILE"
echo "       CRF_VALUE    = $CRF_VALUE" | tee -a "$LOGFILE"
echo "       VBITRATE     = $VBITRATE" | tee -a "$LOGFILE"
echo "       PRESET       = $PRESET" | tee -a "$LOGFILE"
echo "       AUDIO_CODEC  = $AUDIO_CODEC" | tee -a "$LOGFILE"
echo "       AUDIO_BITRATE= $AUDIO_BITRATE" | tee -a "$LOGFILE"
echo "       SAMPLE_RATE  = $SAMPLE_RATE" | tee -a "$LOGFILE"
echo "       SIZE_MIN     = $SIZE_MIN" | tee -a "$LOGFILE"
echo "       SIZE_MAX     = ${SIZE_MAX:-(aucune limite)}" | tee -a "$LOGFILE"
echo "       RETRY_COUNT  = $RETRY_COUNT" | tee -a "$LOGFILE"
echo "       FORMATS      = ${FORMATS[*]:-(auto)}" | tee -a "$LOGFILE"
echo "       SKIP_IDENTICAL = $SKIP_IDENTICAL" | tee -a "$LOGFILE"
echo "       RESUME_MODE  = $RESUME_MODE" | tee -a "$LOGFILE"
echo "       MODE         = $([ "$SIMULATE_FLAG" -eq 1 ] && echo "SIMULATION" || echo "EXECUTION")" | tee -a "$LOGFILE"

if [ "${DELETE_ONLY:-0}" = 1 ]; then
 delete_created_files
fi

if [ "$EXEC_FLAG" -ne 1 ]; then
 echo "[ERREUR] Aucune action : pour exécuter la compression, ajoutez --exec ou --simulate" | tee -a "$LOGFILE"
 echo "Voir --help pour exemples." | tee -a "$LOGFILE"
 exit 1
fi

SOURCE_ABS="$(cd "$SOURCE_DIR" && pwd)"
process_files

exit 0



