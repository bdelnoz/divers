#!/bin/bash
#
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Nom du script : transcribe_mp4.sh
# Target usage : Transcription d'un fichier MP4 en texte avec whisper.cpp
# Version : v2.1 - Date : 2025-08-17
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
#   v2.0 - 2025-08-17 - Ajout --folder pour traitement par lot + analyse détaillée avec solutions
#   v2.1 - 2025-08-17 - Correction détection fichiers vidéo + debug amélioré

set -e

# Variables globales
WHISPER_BIN="./whisper.cpp/build/bin/whisper-cli"
MODELS_DIR="./whisper.cpp/models"
LOG_FILE="log.transcribe_mp4.v2.0.log"
ACTIONS_LOG=()

# Extensions vidéo supportées
VIDEO_EXTENSIONS=("mp4" "avi" "mkv" "mov" "wmv" "flv" "webm" "m4v" "3gp" "ogv" "ts" "mts" "m2ts")

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

# Fonction pour détecter les extensions vidéo
is_video_file() {
    local file="$1"
    local extension="${file##*.}"
    extension="${extension,,}" # conversion en minuscules

    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [ "$extension" = "$ext" ]; then
            return 0
        fi
    done
    return 1
}

# Fonction d'analyse audio détaillée avec solutions précises
analyze_audio() {
    local file="$1"
    local audio_issues=0
    local solutions=()
    local critical_issues=()

    echo ""
    echo "=== ANALYSE AUDIO DETAILLEE POUR WHISPER ==="
    echo "Fichier analysé : $file"
    echo ""

    log_action "Début analyse audio détaillée '$file'"

    # Vérification prérequis
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo "❌ ERREUR CRITIQUE : ffprobe requis pour l'analyse"
        critical_issues+=("Installer le paquet ffmpeg : sudo apt install ffmpeg (Ubuntu/Debian) ou brew install ffmpeg (macOS)")
        return 1
    fi

    # Extraction infos audio avec ffprobe
    echo "🔍 DÉTECTION DES FLUX AUDIO :"

    local audio_streams=$(ffprobe -v quiet -select_streams a -show_streams "$file" 2>/dev/null || echo "")

    if [ -z "$audio_streams" ]; then
        echo "❌ ERREUR CRITIQUE : AUCUN FLUX AUDIO DÉTECTÉ"
        critical_issues+=("Le fichier ne contient pas de piste audio utilisable")
        critical_issues+=("SOLUTIONS POSSIBLES :")
        critical_issues+=("  1. Vérifier que le fichier n'est pas corrompu : ffprobe -v error '$file'")
        critical_issues+=("  2. Essayer de réencoder : ffmpeg -i '$file' -c:v copy -c:a aac '$file.fixed.mp4'")
        critical_issues+=("  3. Utiliser un autre fichier source avec audio")
        log_action "Erreur critique : aucun flux audio détecté"

        echo ""
        echo "🚨 PROBLÈMES CRITIQUES DÉTECTÉS :"
        for issue in "${critical_issues[@]}"; do
            echo "   $issue"
        done
        return 1
    fi

    # Compter les flux audio
    local audio_count=$(ffprobe -v quiet -select_streams a -show_entries stream=index -of csv=p=0 "$file" 2>/dev/null | wc -l)
    echo "✅ Nombre de flux audio : $audio_count"

    if [ "$audio_count" -gt 1 ]; then
        echo "ℹ️  Note : Whisper utilisera automatiquement le premier flux audio"
    fi

    # Analyse détaillée du premier flux audio
    echo ""
    echo "📊 ANALYSE DÉTAILLÉE DU FLUX AUDIO PRINCIPAL :"

    local codec=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "inconnu")
    local sample_rate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=sample_rate -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
    local channels=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=channels -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
    local bit_rate=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "inconnu")
    local duration=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")
    local bit_depth=$(ffprobe -v quiet -select_streams a:0 -show_entries stream=bits_per_sample -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "inconnu")

    echo "  Codec audio : $codec"
    echo "  Fréquence échantillonnage : ${sample_rate} Hz"
    echo "  Nombre de canaux : $channels"
    echo "  Débit binaire : ${bit_rate} bps"
    echo "  Profondeur bits : ${bit_depth} bits"
    if [ "$duration" != "0" ] && [ "$duration" != "N/A" ]; then
        echo "  Durée audio : $(printf "%.1f" "$duration")s"
    fi

    echo ""
    echo "✅ ANALYSE DE COMPATIBILITÉ WHISPER :"

    # === ANALYSE CODEC ===
    echo ""
    echo "🔧 CODEC AUDIO :"
    case "$codec" in
        aac)
            echo "  ✅ AAC : Codec optimal pour Whisper"
            ;;
        mp3)
            echo "  ✅ MP3 : Parfaitement supporté"
            ;;
        wav|pcm*)
            echo "  ✅ WAV/PCM : Format natif Whisper, aucune conversion nécessaire"
            ;;
        flac)
            echo "  ✅ FLAC : Excellente qualité, bien supporté"
            ;;
        ogg|vorbis|opus)
            echo "  ✅ OGG/Vorbis/Opus : Bien supporté"
            ;;
        ac3|eac3)
            echo "  ⚠️  AC-3/E-AC-3 : Supporté mais conversion recommandée"
            solutions+=("Convertir en AAC pour de meilleures performances : ffmpeg -i '$file' -c:v copy -c:a aac -b:a 128k '$file.aac.mp4'")
            audio_issues=$((audio_issues + 1))
            ;;
        dts|truehd)
            echo "  ⚠️  DTS/TrueHD : Format HD, conversion nécessaire"
            solutions+=("Convertir obligatoirement : ffmpeg -i '$file' -c:v copy -c:a aac -b:a 192k '$file.converted.mp4'")
            audio_issues=$((audio_issues + 1))
            ;;
        *)
            echo "  ❌ Codec non standard ou inconnu : $codec"
            solutions+=("SOLUTION URGENTE - Convertir le codec : ffmpeg -i '$file' -c:v copy -c:a aac -b:a 128k '$file.fixed.mp4'")
            audio_issues=$((audio_issues + 2))
            ;;
    esac

    # === ANALYSE FRÉQUENCE D'ÉCHANTILLONNAGE ===
    echo ""
    echo "📡 FRÉQUENCE D'ÉCHANTILLONNAGE :"
    if [ "$sample_rate" -ge 44100 ]; then
        echo "  ✅ ${sample_rate} Hz : Excellente qualité (≥44.1kHz)"
    elif [ "$sample_rate" -ge 22050 ]; then
        echo "  ✅ ${sample_rate} Hz : Très bonne qualité (≥22kHz)"
    elif [ "$sample_rate" -ge 16000 ]; then
        echo "  ✅ ${sample_rate} Hz : Qualité correcte (≥16kHz requis minimum)"
    elif [ "$sample_rate" -ge 8000 ]; then
        echo "  ⚠️  ${sample_rate} Hz : Fréquence faible, qualité dégradée"
        solutions+=("Améliorer la qualité : ffmpeg -i '$file' -c:v copy -c:a aac -ar 22050 '$file.22k.mp4'")
        audio_issues=$((audio_issues + 1))
    else
        echo "  ❌ ${sample_rate} Hz : Fréquence très faible, transcription fortement compromise"
        solutions+=("SOLUTION URGENTE - Réchantillonner : ffmpeg -i '$file' -c:v copy -c:a aac -ar 16000 '$file.16k.mp4'")
        audio_issues=$((audio_issues + 2))
    fi

    # === ANALYSE CANAUX ===
    echo ""
    echo "🔊 CONFIGURATION DES CANAUX :"
    if [ "$channels" -eq 1 ]; then
        echo "  ✅ Audio MONO : Configuration optimale pour Whisper"
    elif [ "$channels" -eq 2 ]; then
        echo "  ✅ Audio STÉRÉO : Sera automatiquement converti en mono"
        echo "     ℹ️  Whisper mixe automatiquement les canaux L+R"
    elif [ "$channels" -gt 2 ] && [ "$channels" -le 8 ]; then
        echo "  ℹ️  Audio MULTICANAL ($channels canaux) : Conversion automatique en mono"
        echo "     ℹ️  Pour préserver une piste spécifique :"
        solutions+=("Extraire canal spécifique : ffmpeg -i '$file' -af 'pan=mono|c0=0.5*c0+0.5*c1' -c:v copy '$file.mono.mp4'")
    else
        echo "  ❌ Configuration de canaux invalide : $channels"
        solutions+=("SOLUTION - Forcer stéréo : ffmpeg -i '$file' -c:v copy -ac 2 '$file.stereo.mp4'")
        audio_issues=$((audio_issues + 1))
    fi

    # === ANALYSE DÉBIT BINAIRE ===
    echo ""
    echo "💾 DÉBIT BINAIRE :"
    if [ "$bit_rate" != "inconnu" ] && [ "$bit_rate" != "N/A" ]; then
        local bit_rate_kb=$((bit_rate / 1000))
        if [ "$bit_rate_kb" -ge 128 ]; then
            echo "  ✅ ${bit_rate_kb} kbps : Débit excellent pour la transcription"
        elif [ "$bit_rate_kb" -ge 64 ]; then
            echo "  ✅ ${bit_rate_kb} kbps : Débit suffisant"
        elif [ "$bit_rate_kb" -ge 32 ]; then
            echo "  ⚠️  ${bit_rate_kb} kbps : Débit faible, qualité possiblement réduite"
            solutions+=("Améliorer le débit : ffmpeg -i '$file' -c:v copy -c:a aac -b:a 128k '$file.128k.mp4'")
            audio_issues=$((audio_issues + 1))
        else
            echo "  ❌ ${bit_rate_kb} kbps : Débit très faible, qualité fortement compromise"
            solutions+=("SOLUTION URGENTE - Augmenter le débit : ffmpeg -i '$file' -c:v copy -c:a aac -b:a 128k '$file.highq.mp4'")
            audio_issues=$((audio_issues + 2))
        fi
    else
        echo "  ℹ️  Débit inconnu (format lossless probable)"
    fi

    # Tests de conversion pratiques
    echo ""
    echo "🧪 TESTS DE CONVERSION WHISPER (3 échantillons de 20 secondes) :"

    # Calcul de la durée totale
    local total_duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null || echo "0")

    if [ "$total_duration" = "0" ] || [ "$(echo "$total_duration < 60" | bc -l 2>/dev/null || echo "1")" = "1" ]; then
        echo "  ⚠️  Vidéo courte (${total_duration%.*}s) - Test unique de 20 secondes"

        # Test unique pour vidéos courtes
        local test_wav="${file%.*}_whisper_test.wav"
        echo "  🔄 Test extraction audio WAV 16kHz mono (20 premières secondes)..."

        if ffmpeg -y -i "$file" -vn -acodec pcm_s16le -ar 16000 -ac 1 -t 20 "$test_wav" >/dev/null 2>&1; then
            # Vérification qualité du fichier généré
            if [ -f "$test_wav" ]; then
                local wav_size=$(stat -c%s "$test_wav" 2>/dev/null || stat -f%z "$test_wav" 2>/dev/null || echo "0")
                local wav_duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$test_wav" 2>/dev/null || echo "0")
                local expected_size=$((20 * 16000 * 2)) # 20sec * 16kHz * 2bytes

                if [ "$wav_size" -gt $((expected_size / 2)) ] && [ "${wav_duration%.*}" -ge 15 ]; then
                    echo "    ✅ Conversion réussie - Taille: $(numfmt --to=iec "$wav_size" 2>/dev/null || echo "${wav_size}B") - Durée: ${wav_duration%.*}s"
                else
                    echo "    ❌ Fichier WAV défaillant - Taille: $(numfmt --to=iec "$wav_size" 2>/dev/null || echo "${wav_size}B")"
                    solutions+=("PROBLÈME DE CONVERSION - Essayer : ffmpeg -i '$file' -vn -acodec pcm_s16le -ar 16000 -ac 1 '$file.debug.wav'")
                    audio_issues=$((audio_issues + 2))
                fi
                rm -f "$test_wav"
            fi
        else
            echo "    ❌ ÉCHEC TOTAL de la conversion audio"
            solutions+=("ERREUR CRITIQUE - Vérifier l'intégrité : ffmpeg -v error -i '$file' -f null - 2>error.log")
            audio_issues=$((audio_issues + 3))
        fi
    else
        # Tests multiples pour vidéos longues
        echo "  📏 Durée totale : ${total_duration%.*}s - Tests à 3 positions stratégiques"

        # Calcul des 3 positions optimales
        local pos1=$(echo "$total_duration * 0.10" | bc -l 2>/dev/null || echo "5")
        local pos2=$(echo "$total_duration * 0.50" | bc -l 2>/dev/null || echo "$(echo "$total_duration / 2" | bc -l)")
        local pos3=$(echo "$total_duration * 0.85" | bc -l 2>/dev/null || echo "$(echo "$total_duration - 25" | bc -l)")

        # Sécuriser pos3 pour éviter de dépasser
        if [ "$(echo "$pos3 + 20 > $total_duration" | bc -l 2>/dev/null || echo "0")" = "1" ]; then
            pos3=$(echo "$total_duration - 25" | bc -l 2>/dev/null || echo "$pos3")
        fi

        local positions=("$pos1" "$pos2" "$pos3")
        local position_names=("DÉBUT (10%)" "MILIEU (50%)" "FIN (85%)")
        local test_passed=0
        local test_issues=()

        for i in "${!positions[@]}"; do
            local pos="${positions[$i]}"
            local pos_name="${position_names[$i]}"
            local test_wav="${file%.*}_whisper_test_$((i+1)).wav"

            echo "  🔄 Test $((i+1))/3 - ${pos_name} à ${pos%.*}s :"

            if ffmpeg -y -i "$file" -vn -acodec pcm_s16le -ar 16000 -ac 1 -ss "$pos" -t 20 "$test_wav" >/dev/null 2>&1; then
                if [ -f "$test_wav" ]; then
                    local wav_size=$(stat -c%s "$test_wav" 2>/dev/null || stat -f%z "$test_wav" 2>/dev/null || echo "0")
                    local wav_duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$test_wav" 2>/dev/null || echo "0")
                    local expected_size=$((20 * 16000 * 2))

                    if [ "$wav_size" -gt $((expected_size / 2)) ] && [ "${wav_duration%.*}" -ge 15 ]; then
                        echo "    ✅ Test réussi - ${wav_size} bytes, ${wav_duration%.*}s"
                        test_passed=$((test_passed + 1))
                    else
                        echo "    ⚠️  Test suspect - Taille: ${wav_size}B, Durée: ${wav_duration%.*}s"
                        test_issues+=("Position ${pos_name}: fichier WAV anormalement petit")
                        audio_issues=$((audio_issues + 1))
                    fi
                    rm -f "$test_wav"
                else
                    echo "    ❌ Fichier WAV non créé"
                    test_issues+=("Position ${pos_name}: échec création WAV")
                    audio_issues=$((audio_issues + 1))
                fi
            else
                echo "    ❌ ÉCHEC conversion à cette position"
                test_issues+=("Position ${pos_name}: erreur ffmpeg lors de la conversion")
                audio_issues=$((audio_issues + 1))
                rm -f "$test_wav" 2>/dev/null
            fi
        done

        echo ""
        echo "  📊 RÉSULTATS DÉTAILLÉS DES TESTS :"
        echo "    Tests réussis : $test_passed/3"

        if [ "$test_passed" -eq 3 ]; then
            echo "    ✅ TOUS LES TESTS RÉUSSIS : Fichier parfaitement compatible"
        elif [ "$test_passed" -eq 2 ]; then
            echo "    ⚠️  2/3 tests réussis : Compatible avec quelques réserves"
            for issue in "${test_issues[@]}"; do
                echo "      • $issue"
            done
        elif [ "$test_passed" -eq 1 ]; then
            echo "    ⚠️  1/3 test réussi : Problèmes fréquents détectés"
            solutions+=("Réencoder le fichier complet : ffmpeg -i '$file' -c:v copy -c:a aac -ar 22050 -b:a 128k '$file.reencoded.mp4'")
        else
            echo "    ❌ AUCUN TEST RÉUSSI : Fichier incompatible ou corrompu"
            solutions+=("SOLUTION D'URGENCE - Réencoder complètement : ffmpeg -i '$file' -c:v libx264 -c:a aac -ar 16000 -ac 1 -b:a 96k '$file.fixed.mp4'")
            audio_issues=$((audio_issues + 3))
        fi
    fi

    # === VERDICT FINAL AVEC SOLUTIONS ===
    echo ""
    echo "========================================"
    echo "=== VERDICT FINAL DE COMPATIBILITÉ ==="
    echo "========================================"

    if [ "$audio_issues" -eq 0 ]; then
        echo "✅ FICHIER PARFAITEMENT COMPATIBLE AVEC WHISPER"
        echo "   → Transcription possible avec qualité OPTIMALE"
        echo "   → Aucune modification nécessaire"
        log_action "Analyse audio parfaite : fichier optimal pour Whisper"
        return 0

    elif [ "$audio_issues" -le 2 ]; then
        echo "⚠️  FICHIER COMPATIBLE AVEC RÉSERVES ($audio_issues point(s) d'attention)"
        echo "   → Transcription possible, qualité BONNE à CORRECTE"
        echo "   → Améliorations recommandées mais optionnelles"

        if [ "${#solutions[@]}" -gt 0 ]; then
            echo ""
            echo "💡 SOLUTIONS RECOMMANDÉES POUR OPTIMISER :"
            for i in "${!solutions[@]}"; do
                echo "   $((i+1)). ${solutions[$i]}"
            done
        fi

        log_action "Analyse audio OK avec réserves : $audio_issues issues, ${#solutions[@]} solutions proposées"
        return 0

    elif [ "$audio_issues" -le 4 ]; then
        echo "⚠️  FICHIER PROBLÉMATIQUE ($audio_issues problèmes détectés)"
        echo "   → Transcription DIFFICILE, qualité DÉGRADÉE probable"
        echo "   → Corrections FORTEMENT recommandées"

        echo ""
        echo "🔧 SOLUTIONS OBLIGATOIRES POUR CORRIGER :"
        for i in "${!solutions[@]}"; do
            echo "   $((i+1)). ${solutions[$i]}"
        done

        log_action "Analyse audio problématique : $audio_issues problèmes, corrections nécessaires"
        return 1

    else
        echo "❌ FICHIER INCOMPATIBLE AVEC WHISPER ($audio_issues problèmes critiques)"
        echo "   → Transcription IMPOSSIBLE en l'état"
        echo "   → Corrections OBLIGATOIRES avant utilisation"

        echo ""
        echo "🚨 SOLUTIONS D'URGENCE POUR RENDRE COMPATIBLE :"
        for i in "${!solutions[@]}"; do
            echo "   $((i+1)). ${solutions[$i]}"
        done

        # Ajouter une solution universelle de dernier recours
        echo "   $((${#solutions[@]}+1)). SOLUTION UNIVERSELLE (dernier recours) :"
        echo "       ffmpeg -i '$file' -vn -acodec pcm_s16le -ar 16000 -ac 1 '$file.whisper-ready.wav'"
        echo "       Puis utilisez directement le fichier WAV avec Whisper"

        log_action "Analyse audio critique : fichier incompatible, $audio_issues problèmes"
        return 1
    fi
}

# Fonction --help mise à jour
show_help() {
    cat << EOF
USAGE: $0 [--file <fichier> | --folder <répertoire>] [OPTIONS]

OPTIONS PRINCIPALES:
  --file <path>       Chemin complet du fichier vidéo à transcrire
  --folder <path>     Répertoire contenant les fichiers vidéo à traiter en lot

OPTIONS FACULTATIVES:
  --exec              Lance la transcription (sinon simulation)
  --model <name>      Modèle whisper à utiliser (défaut: base)
  --lang <code>       Code langue (défaut: fr - français)
  --keep-audio        Conserve les fichiers WAV temporaires
  --threads <n>       Nombre de threads (défaut: auto)
  --output-format <f> Format de sortie (défaut: txt,srt,vtt)
  --analyze           Analyse la compatibilité audio avec solutions détaillées
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

EXTENSIONS VIDÉO SUPPORTÉES (mode --folder):
  .mp4 .avi .mkv .mov .wmv .flv .webm .m4v .3gp .ogv .ts .mts .m2ts

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

EXEMPLES D'UTILISATION:

  # Analyser un seul fichier
  $0 --file "/home/user/video.mp4" --analyze

  # Analyser puis transcrire un fichier
  $0 --file "/home/user/video.mp4" --analyze --exec

  # Traiter tous les fichiers d'un dossier
  $0 --folder "/media/nox/data2/Videos/VOIX_suspectes/BOOST-other" --exec

  # Analyser tous les fichiers d'un dossier
  $0 --folder "/path/to/videos" --analyze

  # Transcription avec modèle spécifique
  $0 --folder "/path/videos" --exec --model large-v3 --lang en

  # Supprimer tous les fichiers générés d'un dossier
  $0 --folder "/path/videos" --delete

DESCRIPTION:
Transcrit un ou plusieurs fichiers vidéo en texte avec whisper.cpp.
Mode --file : traite un seul fichier
Mode --folder : traite automatiquement tous les fichiers vidéo du répertoire
Extrait l'audio en WAV 16kHz mono, puis transcrit avec le modèle choisi.
Génère fichiers .txt, .srt, .vtt dans le même répertoire que les vidéos.

ANALYSE DÉTAILLÉE (--analyze):
- Détection précise des problèmes audio (codec, fréquence, canaux, débit)
- Solutions concrètes avec commandes ffmpeg prêtes à l'emploi
- Tests de conversion à 3 positions différentes du fichier
- Diagnostic complet avec verdict de compatibilité Whisper

TRAITEMENT PAR LOT (--folder):
- Détection automatique des extensions vidéo supportées
- Traitement séquentiel de tous les fichiers compatibles
- Logs détaillés pour chaque fichier traité
- Résumé final avec statistiques de réussite/échec

PRÉREQUIS:
- whisper.cpp compilé dans ./whisper.cpp/build/bin/whisper-cli
- ffmpeg installé (avec ffprobe pour --analyze)
- bc (calculatrice) pour les calculs de positions temporelles
- Modèles téléchargés dans ./whisper.cpp/models/

EOF
}

# Fonction de traitement par lot d'un dossier
process_folder() {
    local folder="$1"
    local analyze_only="$2"
    local execute="$3"

    if [ ! -d "$folder" ]; then
        echo "❌ Erreur : le répertoire '$folder' n'existe pas"
        return 1
    fi

    log_action "Début traitement dossier '$folder'"

    echo ""
    echo "=== TRAITEMENT PAR LOT DU DOSSIER ==="
    echo "Répertoire : $folder"
    echo ""

    # Recherche des fichiers vidéo - méthode simplifiée et robuste
    local video_files=()
    local total_files=0

    echo "🔍 Recherche des fichiers vidéo..."
    echo "Extensions recherchées : ${VIDEO_EXTENSIONS[*]}"
    echo ""

    # Parcourir tous les fichiers du dossier
    for file in "$folder"/*; do
        # Vérifier que c'est un fichier (pas un dossier)
        if [ -f "$file" ]; then
            # Extraire l'extension et la convertir en minuscules
            local filename=$(basename "$file")
            local extension="${filename##*.}"
            extension="${extension,,}" # conversion en minuscules

            # Vérifier si l'extension est dans notre liste
            for supported_ext in "${VIDEO_EXTENSIONS[@]}"; do
                if [ "$extension" = "$supported_ext" ]; then
                    video_files+=("$file")
                    ((total_files++))
                    echo "   ✅ Trouvé: $filename (.$extension)"
                    break
                fi
            done
        fi
    done
    echo ""

    if [ "$total_files" -eq 0 ]; then
        echo "❌ Aucun fichier vidéo trouvé dans le répertoire"
        echo ""
        echo "🔍 DEBUG - Fichiers présents dans le dossier :"
        ls -la "$folder" | head -10
        echo ""
        echo "🔍 Extensions détectées dans le dossier :"
        for file in "$folder"/*; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                local ext="${filename##*.}"
                echo "   $filename -> .$ext"
            fi
        done | head -10
        echo ""
        echo "Extensions recherchées : ${VIDEO_EXTENSIONS[*]}"
        return 1
    fi

    echo "✅ $total_files fichier(s) vidéo détecté(s) :"
    for i in "${!video_files[@]}"; do
        local basename=$(basename "${video_files[$i]}")
        echo "   $((i+1)). $basename"
    done

    # Statistiques de traitement
    local processed=0
    local successful=0
    local failed=0
    local skipped=0
    local analysis_passed=0
    local analysis_failed=0

    echo ""
    echo "=== DÉBUT DU TRAITEMENT ==="

    for i in "${!video_files[@]}"; do
        local file="${video_files[$i]}"
        local basename=$(basename "$file")
        local file_num=$((i+1))

        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📁 FICHIER $file_num/$total_files : $basename"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

        processed=$((processed + 1))

        # Vérification si les fichiers de sortie existent déjà
        local base_name="${file%.*}"
        local output_exists=false

        if [[ "$OUTPUT_FORMAT" == *"txt"* ]] && [ -f "${base_name}.txt" ]; then
            output_exists=true
        fi
        if [[ "$OUTPUT_FORMAT" == *"srt"* ]] && [ -f "${base_name}.srt" ]; then
            output_exists=true
        fi
        if [[ "$OUTPUT_FORMAT" == *"vtt"* ]] && [ -f "${base_name}.vtt" ]; then
            output_exists=true
        fi

        if [ "$output_exists" = true ] && [ "$execute" -eq 1 ] && [ "$analyze_only" -eq 0 ]; then
            echo "⏭️  Fichiers de transcription déjà présents, passage au suivant..."
            echo "   (Utilisez --delete pour supprimer les fichiers existants)"
            skipped=$((skipped + 1))
            continue
        fi

        # Phase d'analyse
        if [ "$analyze_only" -eq 1 ] || ([ "$ANALYZE" -eq 1 ] && [ "$execute" -eq 1 ]); then
            echo "🔍 ANALYSE DE COMPATIBILITÉ AUDIO..."

            if analyze_audio "$file"; then
                analysis_passed=$((analysis_passed + 1))
                echo "✅ Fichier compatible pour transcription Whisper"

                # Si c'est seulement une analyse, passer au suivant
                if [ "$analyze_only" -eq 1 ]; then
                    continue
                fi
            else
                analysis_failed=$((analysis_failed + 1))
                echo "❌ Fichier incompatible ou problématique"

                # En mode analyse + exec, arrêter le traitement de ce fichier si analyse échoue
                if [ "$execute" -eq 1 ]; then
                    echo "⏭️  Transcription annulée pour ce fichier à cause des problèmes détectés"
                    failed=$((failed + 1))
                    continue
                else
                    # Mode analyse seule, continuer avec les autres fichiers
                    continue
                fi
            fi
        fi

        # Phase de transcription
        if [ "$execute" -eq 1 ] && [ "$analyze_only" -eq 0 ]; then
            echo ""
            echo "🎙️  LANCEMENT DE LA TRANSCRIPTION..."

            if process_single_file "$file"; then
                successful=$((successful + 1))
                echo "✅ Transcription réussie pour : $basename"
            else
                failed=$((failed + 1))
                echo "❌ Échec de la transcription pour : $basename"
            fi
        fi
    done

    # Rapport final
    echo ""
    echo "========================================"
    echo "=== RAPPORT FINAL DE TRAITEMENT ==="
    echo "========================================"
    echo "📊 Statistiques :"
    echo "   • Fichiers traités : $processed/$total_files"

    if [ "$analyze_only" -eq 1 ] || [ "$ANALYZE" -eq 1 ]; then
        echo "   • Analyses réussies : $analysis_passed"
        echo "   • Analyses échouées : $analysis_failed"
    fi

    if [ "$execute" -eq 1 ] && [ "$analyze_only" -eq 0 ]; then
        echo "   • Transcriptions réussies : $successful"
        echo "   • Transcriptions échouées : $failed"
        echo "   • Fichiers ignorés (déjà traités) : $skipped"

        local success_rate=0
        if [ "$processed" -gt 0 ]; then
            success_rate=$(( (successful * 100) / processed ))
        fi
        echo "   • Taux de réussite : ${success_rate}%"
    fi

    echo ""
    if [ "$successful" -gt 0 ] || [ "$analysis_passed" -gt 0 ]; then
        echo "✅ Traitement du dossier terminé avec succès"
    elif [ "$failed" -gt 0 ] || [ "$analysis_failed" -gt 0 ]; then
        echo "⚠️  Traitement terminé avec des erreurs"
    else
        echo "ℹ️  Aucun fichier n'a nécessité de traitement"
    fi

    log_action "Traitement dossier terminé: $successful réussies, $failed échouées sur $total_files fichiers"

    return 0
}

# Fonction de traitement d'un seul fichier (extraite pour réutilisation)
process_single_file() {
    local file="$1"
    local base_name="${file%.*}"
    local audio_wav="${base_name}.wav"

    # Extraction audio
    echo "1. Extraction audio en WAV 16kHz mono..."
    if ! ffmpeg -y -i "$file" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$audio_wav" >/dev/null 2>&1; then
        echo "❌ Erreur lors de l'extraction audio"
        return 1
    fi
    log_action "Extraction audio vers '$audio_wav'"

    # Transcription
    echo "2. Transcription avec whisper.cpp (modèle: $MODEL, langue: $LANG)..."

    # Construction commande whisper avec quotes pour gestion espaces
    local whisper_cmd="\"$WHISPER_BIN\" -m \"$MODEL_FILE\" -f \"$audio_wav\" -l $LANG --suppress-nst"

    # Ajout options de sortie selon OUTPUT_FORMAT
    if [[ "$OUTPUT_FORMAT" == *"txt"* ]]; then
        whisper_cmd="$whisper_cmd -otxt"
    fi
    if [[ "$OUTPUT_FORMAT" == *"srt"* ]]; then
        whisper_cmd="$whisper_cmd -osrt"
    fi
    if [[ "$OUTPUT_FORMAT" == *"vtt"* ]]; then
        whisper_cmd="$whisper_cmd -ovtt"
    fi

    # Ajout threads si spécifié
    if [ -n "$THREADS" ]; then
        whisper_cmd="$whisper_cmd -t $THREADS"
    fi

    # Exécution avec eval pour gérer les quotes
    if ! eval $whisper_cmd >/dev/null 2>&1; then
        echo "❌ Erreur lors de la transcription Whisper"
        rm -f "$audio_wav" 2>/dev/null
        return 1
    fi

    log_action "Transcription terminée avec modèle $MODEL, langue $LANG"

    # Nettoyage audio temporaire
    if [ "$KEEP_AUDIO" -eq 0 ]; then
        echo "3. Suppression fichier audio temporaire..."
        rm -f "$audio_wav"
        log_action "Suppression audio temporaire '$audio_wav'"
    else
        echo "3. Conservation fichier audio (--keep-audio)"
        log_action "Conservation audio '$audio_wav'"
    fi

    return 0
}

# Fonction de suppression mise à jour pour supporter les dossiers
delete_files() {
    local target="$1"

    if [ -f "$target" ]; then
        # Mode fichier unique
        local base_name="${target%.*}"
        log_action "Début suppression fichiers générés pour $target"

        local files_to_delete=(
            "${base_name}.txt"
            "${base_name}.srt"
            "${base_name}.vtt"
            "${base_name}.wav"
        )

        local deleted_count=0
        for f in "${files_to_delete[@]}"; do
            if [ -f "$f" ]; then
                rm -f "$f"
                log_action "Suppression $f"
                deleted_count=$((deleted_count + 1))
            fi
        done

        echo "✅ Suppression terminée : $deleted_count fichier(s) supprimé(s)"

    elif [ -d "$target" ]; then
        # Mode dossier
        log_action "Début suppression fichiers générés dans dossier $target"

        echo "🗑️  Suppression des fichiers générés dans : $target"
        echo ""

        local deleted_count=0
        local extensions=("txt" "srt" "vtt" "wav")

        for ext in "${extensions[@]}"; do
            local count=0
            while IFS= read -r -d '' file; do
                if [ -f "$file" ]; then
                    # Vérifier si le fichier correspond à une vidéo source
                    local base_name="${file%.*}"
                    local has_video_source=false

                    for video_ext in "${VIDEO_EXTENSIONS[@]}"; do
                        if [ -f "${base_name}.${video_ext}" ]; then
                            has_video_source=true
                            break
                        fi
                    done

                    if [ "$has_video_source" = true ]; then
                        rm -f "$file"
                        echo "   Supprimé: $(basename "$file")"
                        count=$((count + 1))
                        deleted_count=$((deleted_count + 1))
                        log_action "Suppression $file"
                    fi
                fi
            done < <(find "$target" -maxdepth 1 -type f -name "*.${ext}" -print0 2>/dev/null)

            if [ "$count" -gt 0 ]; then
                echo "     → $count fichier(s) .$ext supprimé(s)"
            fi
        done

        echo ""
        echo "✅ Suppression terminée : $deleted_count fichier(s) supprimé(s) au total"

    else
        echo "❌ Erreur : '$target' n'est ni un fichier ni un répertoire"
        return 1
    fi

    show_actions
    exit 0
}

# Parse arguments mis à jour
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

FILE=""
FOLDER=""
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
        --folder) FOLDER="$2"; shift 2 ;;
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
            elif [ -n "$FOLDER" ]; then
                delete_files "$FOLDER"
            else
                echo "❌ Erreur : --file ou --folder requis avec --delete"
                exit 1
            fi
            ;;
        --help) show_help; exit 0 ;;
        *) echo "❌ Argument inconnu: $1"; show_help; exit 1 ;;
    esac
done

# Vérifications des arguments
if [ -z "$FILE" ] && [ -z "$FOLDER" ]; then
    echo "❌ Erreur : --file ou --folder obligatoire"
    show_help
    exit 1
fi

if [ -n "$FILE" ] && [ -n "$FOLDER" ]; then
    echo "❌ Erreur : --file et --folder sont mutuellement exclusifs"
    show_help
    exit 1
fi

# Vérification existence fichier/dossier
if [ -n "$FILE" ] && [ ! -f "$FILE" ]; then
    echo "❌ Erreur : fichier '$FILE' introuvable"
    exit 1
fi

if [ -n "$FOLDER" ] && [ ! -d "$FOLDER" ]; then
    echo "❌ Erreur : répertoire '$FOLDER' introuvable"
    exit 1
fi

# Mode dossier
if [ -n "$FOLDER" ]; then
    if [ "$ANALYZE" -eq 1 ] && [ "$EXECUTE" -eq 0 ]; then
        # Mode analyse seule du dossier
        process_folder "$FOLDER" 1 0
    elif [ "$ANALYZE" -eq 1 ] && [ "$EXECUTE" -eq 1 ]; then
        # Mode analyse + transcription du dossier
        process_folder "$FOLDER" 0 1
    elif [ "$EXECUTE" -eq 1 ]; then
        # Mode transcription seule du dossier
        process_folder "$FOLDER" 0 1
    else
        # Mode simulation
        echo "ℹ️  Mode simulation pour le dossier : $FOLDER"
        echo "Ajoutez --exec pour lancer le traitement réel"
        echo "Ajoutez --analyze pour analyser les fichiers audio"
        process_folder "$FOLDER" 1 0
    fi
    exit 0
fi

# Mode fichier unique (code existant adapté)
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
command -v ffmpeg >/dev/null 2>&1 || { echo "❌ Erreur : ffmpeg requis"; exit 1; }

if [ ! -x "$WHISPER_BIN" ]; then
    echo "❌ Erreur : binaire whisper-cli introuvable ($WHISPER_BIN)"
    echo "Lancez d'abord install_whisper.sh"
    exit 1
fi

# Vérification modèle
MODEL_FILE="$MODELS_DIR/ggml-${MODEL}.bin"
if [ ! -f "$MODEL_FILE" ]; then
    echo "❌ Erreur : modèle '$MODEL_FILE' introuvable"
    echo "Modèles disponibles dans $MODELS_DIR :"
    ls -1 "$MODELS_DIR"/*.bin 2>/dev/null || echo "Aucun modèle trouvé"
    exit 1
fi

log_action "Début transcription fichier '$FILE' avec modèle $MODEL, langue $LANG"

if [ "$EXECUTE" -eq 0 ]; then
    echo "ℹ️  Option --exec non fournie, simulation uniquement."
    echo "Commande qui serait exécutée :"
    echo "\"$WHISPER_BIN\" -m \"$MODEL_FILE\" -f \"<audio.wav>\" -l $LANG -otxt -osrt -ovtt"
    if [ -n "$THREADS" ]; then
        echo "  avec $THREADS threads"
    fi
    exit 0
fi

# Traitement du fichier unique
if process_single_file "$FILE"; then
    # Variables fichiers pour affichage final
    BASE_NAME="${FILE%.*}"

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
        echo "  - Audio WAV : ${BASE_NAME}.wav"
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
else
    echo "❌ Échec de la transcription"
    show_actions
    log_action "Échec de la transcription"
    exit 1
fi
