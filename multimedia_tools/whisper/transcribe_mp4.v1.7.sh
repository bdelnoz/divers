#!/bin/bash
#
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Nom du script : transcribe_mp4.sh
# Target usage : Transcription d'un fichier MP4 en texte avec whisper.cpp
# Version : v1.7 - Date : 2025-08-12
# Changelog :
#   v1.0 - 2025-08-10 - Script initial pour transcrire un MP4 avec whisper.cpp
#   v1.1 - 2025-08-11 - Ajout gestion logs, help, et vérification binaire whisper
#   v1.2 - 2025-08-11 - Ajout affichage actions et support arguments doubles tirets
#   v1.3 - 2025-08-12 - Correction chemin du binaire whisper dans whisper.cpp/build/bin
#   v1.4 - 2025-08-12 - Correction nom binaire (whisper-cli), gestion modèles, logs propres, actions numérotées
#   v1.5 - 2025-08-12 - Ajout toutes valeurs options possibles langues et modèles
#   v1.6 - 2025-08-12 - Langue par défaut française au lieu d'auto-détection
#   v1.7 - 2025-08-12 - Correction gestion espaces dans noms fichiers, protection quotes

set -e

# Variables globales
WHISPER_BIN="./whisper.cpp/build/bin/whisper-cli"
MODELS_DIR="./whisper.cpp/models"
LOG_FILE="log.transcribe_mp4.v1.7.log"
ACTIONS_LOG=()

# Fonction de logging
log_action() {
    local action="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $action" >> "$LOG_FILE"
    ACTIONS_LOG+=("$action")
}

# Fonction d'affichage des actions
show_actions() {
    echo ""
    echo "=== ACTIONS EXECUTEES ==="
    for i in "${!ACTIONS_LOG[@]}"; do
        echo "$((i+1)). ${ACTIONS_LOG[$i]}"
    done
}

# Fonction --help
show_help() {
    cat << EOF
USAGE: $0 --file <chemin_fichier_mp4> [OPTIONS]

OPTIONS OBLIGATOIRES:
  --file <path>       Chemin complet du fichier MP4 à transcrire (avec quotes si espaces)

OPTIONS FACULTATIVES:
  --exec              Lance la transcription (sinon simulation)
  --model <name>      Modèle whisper à utiliser (défaut: base)
  --lang <code>       Code langue (défaut: fr - français)
  --keep-audio        Conserve le fichier WAV temporaire
  --threads <n>       Nombre de threads (défaut: auto)
  --output-format <f> Format de sortie (défaut: txt,srt,vtt)
  --delete            Supprime tous les fichiers générés
  --help              Affiche cette aide

MODELES DISPONIBLES:
  tiny     (39 MB)  - Le plus rapide, moins précis
  base     (142 MB) - Bon compromis vitesse/qualité
  small    (244 MB) - Meilleure qualité que base
  medium   (769 MB) - Très bonne qualité
  large    (1550 MB)- Meilleure qualité possible
  large-v2 (1550 MB)- Version améliorée de large
  large-v3 (1550 MB)- Dernière version large

LANGUES SUPPORTEES (codes ISO):
  af (afrikaans)    am (amharic)      ar (arabic)       as (assamese)
  az (azerbaijani)  ba (bashkir)      be (belarusian)   bg (bulgarian)
  bn (bengali)      bo (tibetan)      br (breton)       bs (bosnian)
  ca (catalan)      cs (czech)        cy (welsh)        da (danish)
  de (german)       el (greek)        en (english)      es (spanish)
  et (estonian)     eu (basque)       fa (persian)      fi (finnish)
  fo (faroese)      fr (french)       gl (galician)     gu (gujarati)
  ha (hausa)        haw (hawaiian)    he (hebrew)       hi (hindi)
  hr (croatian)     ht (haitian)      hu (hungarian)    hy (armenian)
  id (indonesian)   is (icelandic)    it (italian)      ja (japanese)
  jw (javanese)     ka (georgian)     kk (kazakh)       km (khmer)
  kn (kannada)      ko (korean)       la (latin)        lb (luxembourgish)
  ln (lingala)      lo (lao)          lt (lithuanian)   lv (latvian)
  mg (malagasy)     mi (maori)        mk (macedonian)   ml (malayalam)
  mn (mongolian)    mr (marathi)      ms (malay)        mt (maltese)
  my (myanmar)      ne (nepali)       nl (dutch)        nn (nynorsk)
  no (norwegian)    oc (occitan)      pa (punjabi)      pl (polish)
  ps (pashto)       pt (portuguese)   ro (romanian)     ru (russian)
  sa (sanskrit)     sd (sindhi)       si (sinhala)      sk (slovak)
  sl (slovenian)    sn (shona)        so (somali)       sq (albanian)
  sr (serbian)      su (sundanese)    sv (swedish)      sw (swahili)
  ta (tamil)        te (telugu)       tg (tajik)        th (thai)
  tk (turkmen)      tl (tagalog)      tr (turkish)      tt (tatar)
  uk (ukrainian)    ur (urdu)         uz (uzbek)        vi (vietnamese)
  yi (yiddish)      yo (yoruba)       zh (chinese)

EXEMPLES:
  $0 --file "/home/user/video avec espaces.mp4" --exec
  $0 --file /home/user/video.mp4 --exec --model small --lang en
  $0 --file "/path/file name.mp4" --exec --keep-audio --threads 8
  $0 --file video.mp4 --exec --model medium --lang de
  $0 --delete --file "/path/video name.mp4"

DESCRIPTION:
Transcrit un fichier MP4 en texte avec whisper.cpp.
Extrait l'audio en WAV 16kHz mono, puis transcrit avec le modèle choisi.
Génère fichiers .txt, .srt, .vtt dans le même répertoire que la vidéo.
Langue par défaut : français (fr).
Gère correctement les noms de fichiers avec espaces.

PRÉREQUIS:
- whisper.cpp compilé dans ./whisper.cpp/build/bin/whisper-cli
- ffmpeg installé
- Modèles téléchargés dans ./whisper.cpp/models/

EOF
}

# Fonction de suppression
delete_files() {
    local file="$1"
    local base_name="${file%.*}"

    log_action "Début suppression fichiers générés pour $file"

    # Fichiers générés
    local files_to_delete=(
        "${base_name}.txt"
        "${base_name}.srt"
        "${base_name}.vtt"
        "${base_name}.wav"
    )

    for f in "${files_to_delete[@]}"; do
        if [ -f "$f" ]; then
            rm -f "$f"
            log_action "Suppression $f"
        fi
    done

    echo "Suppression terminée."
    show_actions
    exit 0
}

# Parse arguments
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

FILE=""
EXECUTE=0
MODEL="base"
LANG="fr"
KEEP_AUDIO=0
THREADS=""
OUTPUT_FORMAT="txt,srt,vtt"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --file) FILE="$2"; shift 2 ;;
        --exec) EXECUTE=1; shift ;;
        --model) MODEL="$2"; shift 2 ;;
        --lang) LANG="$2"; shift 2 ;;
        --keep-audio) KEEP_AUDIO=1; shift ;;
        --threads) THREADS="$2"; shift 2 ;;
        --output-format) OUTPUT_FORMAT="$2"; shift 2 ;;
        --delete)
            if [ -n "$FILE" ]; then
                delete_files "$FILE"
            else
                echo "Erreur : --file requis avec --delete"
                exit 1
            fi
            ;;
        --help) show_help ;;
        *) echo "Argument inconnu: $1"; show_help ;;
    esac
done

# Vérifications
if [ -z "$FILE" ]; then
    echo "Erreur : --file obligatoire"
    show_help
fi

if [ ! -f "$FILE" ]; then
    echo "Erreur : fichier '$FILE' introuvable"
    exit 1
fi

# Vérification prérequis
command -v ffmpeg >/dev/null 2>&1 || { echo "Erreur : ffmpeg requis"; exit 1; }

if [ ! -x "$WHISPER_BIN" ]; then
    echo "Erreur : binaire whisper-cli introuvable ($WHISPER_BIN)"
    echo "Lancez d'abord install_whisper.sh"
    exit 1
fi

# Vérification modèle
MODEL_FILE="$MODELS_DIR/ggml-${MODEL}.bin"
if [ ! -f "$MODEL_FILE" ]; then
    echo "Erreur : modèle '$MODEL_FILE' introuvable"
    echo "Modèles disponibles dans $MODELS_DIR :"
    ls -1 "$MODELS_DIR"/*.bin 2>/dev/null || echo "Aucun modèle trouvé"
    exit 1
fi

log_action "Début transcription fichier '$FILE' avec modèle $MODEL, langue $LANG"

if [ "$EXECUTE" -eq 0 ]; then
    echo "Option --exec non fournie, simulation uniquement."
    echo "Commande qui serait exécutée :"
    echo "\"$WHISPER_BIN\" -m \"$MODEL_FILE\" -f \"<audio.wav>\" -l $LANG -otxt -osrt -ovtt"
    if [ -n "$THREADS" ]; then
        echo "  avec $THREADS threads"
    fi
    exit 0
fi

# Variables fichiers - échappement correct des espaces
BASE_NAME="${FILE%.*}"
AUDIO_WAV="${BASE_NAME}.wav"

echo "1. Extraction audio en WAV 16kHz mono..."
ffmpeg -y -i "$FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$AUDIO_WAV"
log_action "Extraction audio vers '$AUDIO_WAV'"

echo "2. Transcription avec whisper.cpp (modèle: $MODEL, langue: $LANG)..."

# Construction commande whisper avec quotes pour gestion espaces
WHISPER_CMD="\"$WHISPER_BIN\" -m \"$MODEL_FILE\" -f \"$AUDIO_WAV\" -l $LANG --suppress-nst"

# Ajout options de sortie selon OUTPUT_FORMAT
if [[ "$OUTPUT_FORMAT" == *"txt"* ]]; then
    WHISPER_CMD="$WHISPER_CMD -otxt"
fi
if [[ "$OUTPUT_FORMAT" == *"srt"* ]]; then
    WHISPER_CMD="$WHISPER_CMD -osrt"
fi
if [[ "$OUTPUT_FORMAT" == *"vtt"* ]]; then
    WHISPER_CMD="$WHISPER_CMD -ovtt"
fi

# Ajout threads si spécifié
if [ -n "$THREADS" ]; then
    WHISPER_CMD="$WHISPER_CMD -t $THREADS"
fi

# Exécution avec eval pour gérer les quotes
eval $WHISPER_CMD
log_action "Transcription terminée avec modèle $MODEL, langue $LANG"

if [ "$KEEP_AUDIO" -eq 0 ]; then
    echo "3. Suppression fichier audio temporaire..."
    rm -f "$AUDIO_WAV"
    log_action "Suppression audio temporaire '$AUDIO_WAV'"
else
    echo "3. Conservation fichier audio (--keep-audio)"
    log_action "Conservation audio '$AUDIO_WAV'"
fi

echo ""
echo "=== TRANSCRIPTION TERMINEE ==="
echo "Fichiers générés :"
if [[ "$OUTPUT_FORMAT" == *"txt"* ]]; then
    echo "  - Texte : ${BASE_NAME}.txt"
fi
if [[ "$OUTPUT_FORMAT" == *"srt"* ]]; then
    echo "  - Sous-titres SRT : ${BASE_NAME}.srt"
fi
if [[ "$OUTPUT_FORMAT" == *"vtt"* ]]; then
    echo "  - Sous-titres VTT : ${BASE_NAME}.vtt"
fi
if [ "$KEEP_AUDIO" -eq 1 ]; then
    echo "  - Audio WAV : $AUDIO_WAV"
fi

echo ""
echo "Paramètres utilisés :"
echo "  - Modèle : $MODEL"
echo "  - Langue : $LANG"
echo "  - Threads : ${THREADS:-auto}"
echo "  - Formats : $OUTPUT_FORMAT"

show_actions
log_action "Transcription complète terminée avec succès"

exit 0
