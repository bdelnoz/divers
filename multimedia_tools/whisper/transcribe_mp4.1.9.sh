#!/bin/bash
#
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Nom du script : transcribe_mp4.sh
# Target usage : Transcription d'un fichier MP4 en texte avec whisper.cpp
# Version : v1.9 - Date : 2025-08-16
# Changelog :
#   v1.0 - 2025-08-10 - Script initial pour transcrire un MP4 avec whisper.cpp
#   v1.1 - 2025-08-11 - Ajout gestion logs, help, et vérification binaire whisper
#   v1.2 - 2025-08-11 - Ajout affichage actions et support arguments doubles tirets
#   v1.3 - 2025-08-12 - Correction chemin du binaire whisper dans whisper.cpp/build/bin
#   v1.4 - 2025-08-12 - Correction nom binaire (whisper-cli), gestion modèles, logs propres, actions numérotées
#   v1.5 - 2025-08-12 - Ajout toutes valeurs options possibles langues et modèles
#   v1.6 - 2025-08-12 - Langue par défaut française au lieu d'auto-détection
#   v1.7 - 2025-08-12 - Correction gestion espaces dans noms fichiers, protection quotes
#   v1.8 - 2025-08-16 - Ajout analyse audio préalable avec option --analyze
#   v1.9 - 2025-08-16 - Amélioration test: 3 échantillons de 20sec à différents endroits

set -e

# Variables globales
WHISPER_BIN="./whisper.cpp/build/bin/whisper-cli"
MODELS_DIR="./whisper.cpp/models"
LOG_FILE="log.transcribe_mp4.v1.9.log"
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

# Fonction d'analyse audio simplifiée et ciblée
analyze_audio() {
    local file="$1"
    local audio_issues=0

    echo ""
    echo "=== ANALYSE AUDIO POUR WHISPER ==="
    echo "Fichier analysé : $file"
    echo ""

    log_action "Début analyse audio '$file'"

    # Vérification prérequis
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo "❌ ERREUR : ffprobe requis pour l'analyse (paquet ffmpeg)"
        return 1
    fi

    # Extraction infos audio avec ffprobe (sans jq pour plus de compatibilité)
    echo "🔍 DÉTECTION DES FLUX AUDIO :"

    local audio_streams=$(ffprobe -v quiet -select_streams a -show_streams "$file" 2>/dev/null || echo "")

    if [ -z "$audio_streams" ]; then
        echo "❌ AUCUN FLUX AUDIO DÉTECTÉ"
        echo "   → Transcription impossible, le fichier ne contient pas d'audio"
        log_action "Erreur critique : aucun flux audio détecté"
        return 1
    fi

    # Compter les flux audio
    local audio_count=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l)
    echo "✅ Nombre de flux audio : $audio_count"

    # Analyse du premier flux audio (celui qui sera utilisé)
    echo ""
    echo "📊 ANALYSE FLUX AUDIO PRINCIPAL :"

    local codec=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "inconnu")
    local sample_rate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
    local channels=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
    local bit_rate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "inconnu")
    local duration=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")

    echo "  Codec audio : $codec"
    echo "  Fréquence échantillonnage : ${sample_rate} Hz"
    echo "  Nombre de canaux : $channels"
    echo "  Débit : ${bit_rate} bps"
    if [ "$duration" != "0" ] && [ "$duration" != "N/A" ]; then
        echo "  Durée audio : $(printf "%.1f" "$duration")s"
    fi

    echo ""
    echo "✅ COMPATIBILITÉ WHISPER :"

    # Vérification codec
    case "$codec" in
        aac|mp3|wav|flac|m4a|ogg|opus|pcm*)
            echo "  ✅ Codec supporté : $codec"
            ;;
        *)
            echo "  ⚠️  Codec non standard : $codec"
            echo "     → Conversion possible mais à tester"
            audio_issues=$((audio_issues + 1))
            ;;
    esac

    # Vérification fréquence échantillonnage
    if [ "$sample_rate" -ge 16000 ]; then
        echo "  ✅ Fréquence d'échantillonnage : ${sample_rate} Hz (≥16kHz requis)"
    elif [ "$sample_rate" -ge 8000 ]; then
        echo "  ⚠️  Fréquence d'échantillonnage faible : ${sample_rate} Hz"
        echo "     → Qualité de transcription possiblement réduite"
        audio_issues=$((audio_issues + 1))
    else
        echo "  ❌ Fréquence d'échantillonnage très faible : ${sample_rate} Hz"
        echo "     → Qualité de transcription fortement dégradée"
        audio_issues=$((audio_issues + 2))
    fi

    # Vérification canaux
    if [ "$channels" -eq 1 ]; then
        echo "  ✅ Audio mono : optimal pour Whisper"
    elif [ "$channels" -eq 2 ]; then
        echo "  ✅ Audio stéréo : sera converti en mono"
    elif [ "$channels" -gt 2 ]; then
        echo "  ℹ️  Audio multicanal ($channels canaux) : sera converti en mono"
    else
        echo "  ❌ Nombre de canaux invalide : $channels"
        audio_issues=$((audio_issues + 1))
    fi

    # Tests de conversion multiples - 3 échantillons de 20 secondes
    echo ""
    echo "🧪 TESTS DE CONVERSION (3 échantillons de 20 secondes) :"

    # Calcul de la durée totale pour positionner les échantillons
    local total_duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")

    if [ "$total_duration" = "0" ] || [ "$(echo "$total_duration < 60" | bc -l 2>/dev/null || echo "1")" = "1" ]; then
        echo "  ⚠️  Vidéo courte (${total_duration%.*}s) - Test unique de 20 secondes"

        # Test unique pour vidéos courtes
        local test_wav="${file%.*}_whisper_test.wav"
        echo "  Test extraction audio WAV 16kHz mono (20 secondes depuis le début)..."

        if ffmpeg -y -i "$file" -vn -acodec pcm_s16le -ar 16000 -ac 1 -t 20 "$test_wav" >/dev/null 2>&1; then
            echo "  ✅ Conversion réussie"

            # Vérification du fichier généré
            if [ -f "$test_wav" ]; then
                local wav_size=$(stat -c%s "$test_wav" 2>/dev/null || stat -f%z "$test_wav" 2>/dev/null || echo "0")
                if [ "$wav_size" -gt 640000 ]; then  # ~20sec * 16kHz * 2bytes ≈ 640KB minimum
                    echo "  ✅ Fichier WAV valide ($(numfmt --to=iec "$wav_size" 2>/dev/null || echo "${wav_size} bytes"))"
                else
                    echo "  ❌ Fichier WAV trop petit : possiblement vide"
                    audio_issues=$((audio_issues + 2))
                fi
                rm -f "$test_wav"
            fi
        else
            echo "  ❌ ÉCHEC de la conversion audio"
            audio_issues=$((audio_issues + 3))
        fi
    else
        # Tests multiples pour vidéos longues
        echo "  Durée totale : ${total_duration%.*}s - Tests à 3 positions différentes"

        # Calcul des 3 positions : début (10%), milieu (50%), fin (85%)
        local pos1=$(echo "$total_duration * 0.10" | bc -l 2>/dev/null || echo "5")
        local pos2=$(echo "$total_duration * 0.50" | bc -l 2>/dev/null || echo "$(echo "$total_duration / 2" | bc -l)")
        local pos3=$(echo "$total_duration * 0.85" | bc -l 2>/dev/null || echo "$(echo "$total_duration - 25" | bc -l)")

        # Limiter pos3 pour éviter de dépasser la fin
        if [ "$(echo "$pos3 + 20 > $total_duration" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
            pos3=$(echo "$total_duration - 25" | bc -l 2>/dev/null || echo "$pos3")
        fi

        local positions=("$pos1" "$pos2" "$pos3")
        local position_names=("début (10%)" "milieu (50%)" "fin (85%)")
        local test_passed=0

        for i in "${!positions[@]}"; do
            local pos="${positions[$i]}"
            local pos_name="${position_names[$i]}"
            local test_wav="${file%.*}_whisper_test_$((i+1)).wav"

            echo "  Test $((i+1))/3 - Position ${pos_name} (${pos%.*}s) :"

            if ffmpeg -y -i "$file" -vn -acodec pcm_s16le -ar 16000 -ac 1 -ss "$pos" -t 20 "$test_wav" >/dev/null 2>&1; then
                echo "    ✅ Conversion réussie"

                # Vérification du fichier généré
                if [ -f "$test_wav" ]; then
                    local wav_size=$(stat -c%s "$test_wav" 2>/dev/null || stat -f%z "$test_wav" 2>/dev/null || echo "0")
                    local wav_duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$test_wav" 2>/dev/null || echo "0")

                    if [ "$wav_size" -gt 640000 ] && [ "${wav_duration%.*}" -ge 15 ]; then
                        echo "    ✅ Fichier WAV valide - Taille: $(numfmt --to=iec "$wav_size" 2>/dev/null || echo "${wav_size}B") - Durée: ${wav_duration%.*}s"
                        test_passed=$((test_passed + 1))
                    else
                        echo "    ⚠️  Fichier WAV suspect - Taille: $(numfmt --to=iec "$wav_size" 2>/dev/null || echo "${wav_size}B") - Durée: ${wav_duration%.*}s"
                        audio_issues=$((audio_issues + 1))
                    fi
                    rm -f "$test_wav"
                else
                    echo "    ❌ Fichier WAV non créé"
                    audio_issues=$((audio_issues + 1))
                fi
            else
                echo "    ❌ ÉCHEC de la conversion à cette position"
                audio_issues=$((audio_issues + 1))
                rm -f "$test_wav" 2>/dev/null
            fi
        done

        echo ""
        echo "  📊 RÉSULTATS DES TESTS :"
        echo "    Tests réussis : $test_passed/3"

        if [ "$test_passed" -eq 3 ]; then
            echo "    ✅ Toutes les positions testées sont OK"
        elif [ "$test_passed" -ge 2 ]; then
            echo "    ⚠️  Quelques problèmes détectés mais globalement OK"
        elif [ "$test_passed" -eq 1 ]; then
            echo "    ⚠️  Problèmes fréquents - Qualité audio variable"
            audio_issues=$((audio_issues + 1))
        else
            echo "    ❌ Échec sur toutes les positions - Fichier incompatible"
            audio_issues=$((audio_issues + 3))
        fi
    fi

    echo ""
    echo "=== VERDICT AUDIO ==="

    if [ "$audio_issues" -eq 0 ]; then
        echo "✅ AUDIO PARFAITEMENT COMPATIBLE"
        echo "   → Transcription Whisper possible avec qualité optimale"
        log_action "Analyse audio OK : fichier parfaitement compatible"
        return 0
    elif [ "$audio_issues" -le 2 ]; then
        echo "⚠️  AUDIO COMPATIBLE AVEC RÉSERVES ($audio_issues point(s) d'attention)"
        echo "   → Transcription possible, qualité possiblement réduite"
        log_action "Analyse audio : fichier compatible avec réserves ($audio_issues issues)"
        return 0
    else
        echo "❌ AUDIO PROBLÉMATIQUE ($audio_issues problèmes détectés)"
        echo "   → Transcription difficile ou impossible"
        log_action "Analyse audio KO : fichier problématique ($audio_issues problèmes)"
        return 1
    fi
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
  --analyze           Analyse la compatibilité audio du fichier avec Whisper
  --delete            Supprime tous les fichiers générés
  --help              Affiche cette aide

MODELES DISPONIBLES:
  tiny     (39 MB)   - Le plus rapide, moins précis
  base     (142 MB)  - Bon compromis vitesse/qualité
  small    (244 MB)  - Meilleure qualité que base
  medium   (769 MB)  - Très bonne qualité
  large    (1550 MB) - Meilleure qualité
  large-v2 (1550 MB) - Version améliorée de large
  large-v3 (1550 MB) - MEILLEURE qualité possible (recommandé)

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
  $0 --file "/home/user/video avec espaces.mp4" --analyze
  $0 --file "/home/user/video.mp4" --exec
  $0 --file /home/user/video.mp4 --exec --model small --lang en
  $0 --file "/path/file name.mp4" --exec --keep-audio --threads 8
  $0 --file video.mp4 --analyze --exec --model large-v3 --lang de
  $0 --delete --file "/path/video name.mp4"

DESCRIPTION:
Transcrit un fichier MP4 en texte avec whisper.cpp.
Extrait l'audio en WAV 16kHz mono, puis transcrit avec le modèle choisi.
Génère fichiers .txt, .srt, .vtt dans le même répertoire que la vidéo.
Langue par défaut : français (fr).
Gère correctement les noms de fichiers avec espaces.

NOUVELLE FONCTIONNALITÉ --analyze:
Analyse la compatibilité audio du fichier avec Whisper avant transcription.
Vérifie : codec audio, fréquence d'échantillonnage, nombre de canaux.
Effectue 3 tests de conversion de 20 secondes à différentes positions (début, milieu, fin).
Pour vidéos courtes (<60s) : test unique de 20 secondes.
Peut être combiné avec --exec pour analyser puis transcrire si compatible.

PRÉREQUIS:
- whisper.cpp compilé dans ./whisper.cpp/build/bin/whisper-cli
- ffmpeg installé (avec ffprobe pour --analyze)
- Modèles téléchargés dans ./whisper.cpp/models/
- bc (calculatrice en ligne de commande) pour les calculs de positions

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
ANALYZE=0
MODEL="base"
LANG="fr"
KEEP_AUDIO=0
THREADS=""
OUTPUT_FORMAT="txt,srt,vtt"

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --file) FILE="$2"; shift 2 ;;
        --exec) EXECUTE=1; shift ;;
        --analyze) ANALYZE=1; shift ;;
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
        --help) show_help; exit 0 ;;
        *) echo "Argument inconnu: $1"; show_help; exit 1 ;;
    esac
done

# Vérifications
if [ -z "$FILE" ]; then
    echo "Erreur : --file obligatoire"
    show_help
    exit 1
fi

if [ ! -f "$FILE" ]; then
    echo "Erreur : fichier '$FILE' introuvable"
    exit 1
fi

# Analyse audio si demandée
if [ "$ANALYZE" -eq 1 ]; then
    if ! analyze_audio "$FILE"; then
        echo ""
        echo "❌ ANALYSE AUDIO ÉCHOUÉE"
        if [ "$EXECUTE" -eq 1 ]; then
            echo "Transcription annulée à cause des problèmes audio détectés."
            echo "Utilisez --exec sans --analyze pour forcer la transcription."
            exit 1
        else
            echo "Utilisez --exec pour tenter la transcription malgré les problèmes."
            exit 1
        fi
    else
        echo ""
        echo "✅ ANALYSE AUDIO RÉUSSIE"
        if [ "$EXECUTE" -eq 0 ]; then
            echo "Fichier compatible. Ajoutez --exec pour lancer la transcription."
            exit 0
        fi
        echo "Lancement de la transcription..."
    fi
fi

# Vérification prérequis pour transcription
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
