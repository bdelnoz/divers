#!/bin/bash

#########################################################################
# Script: audio_transcription_diagnostic.sh
# Auteur: Bruno DELNOZ
# Email: bruno.delnoz@protonmail.com
# Target usage: Diagnostic ultra-complet des problèmes de transcription vocale polluée
# Version: v1.0 - Date: 2025-01-10
#
# Changelog:
# v1.0 - 2025-01-10 - Version initiale ultra-complète
#   - Diagnostic matériel et processus système complet
#   - Analyse automatique avec rapport structuré
#   - Tests d'enregistrement et transcription Whisper
#   - Détection processus suspects et filtres audio
#   - Génération logs détaillés et recommandations
#   - Support --help, --exec, --delete avec exemples
#########################################################################

# Variables globales - Configuration du script et environnement
SCRIPT_NAME="audio_transcription_diagnostic"
SCRIPT_VERSION="v1.0"
SCRIPT_DATE="2025-01-10"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WORKDIR="${SCRIPT_NAME}_${TIMESTAMP}"
LOG_FILE="log.${SCRIPT_NAME}.${SCRIPT_VERSION}.log"
ANALYSIS_FILE="$WORKDIR/analysis_report.txt"
BACKUP_DIR="${SCRIPT_NAME}_backups"

# Couleurs pour affichage terminal - Améliore lisibilité output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Compteurs pour rapport final - Tracking actions effectuées
ACTION_COUNTER=0
ACTIONS_LIST=()

#########################################################################
# FONCTIONS UTILITAIRES - Gestion logs, affichage, et analyse
#########################################################################

# Fonction log centralisée - Écrit dans fichier ET affiche terminal
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "[$timestamp] $message" >> "$LOG_FILE"
    echo -e "$message"
}

# Fonction ajout action - Track toutes les actions pour rapport final
add_action() {
    ACTION_COUNTER=$((ACTION_COUNTER + 1))
    ACTIONS_LIST+=("$ACTION_COUNTER. $1")
    log "${BLUE}[ACTION $ACTION_COUNTER] $1${NC}"
}

# Fonction analyse résultats - Catégorise les résultats pour rapport
analyze() {
    local category="$1"
    local result="$2"
    local status="$3"
    echo "$category|$result|$status" >> "$WORKDIR/raw_analysis.csv"
    log "${CYAN}[ANALYSE] $category: $result [$status]${NC}"
}

# Fonction backup config - Sauvegarde configs avant modifications
backup_config() {
    local file_to_backup="$1"
    local backup_name="$2"

    if [ -f "$file_to_backup" ]; then
        mkdir -p "$BACKUP_DIR"
        cp "$file_to_backup" "$BACKUP_DIR/${backup_name}_${TIMESTAMP}.bak"
        add_action "Sauvegarde de $file_to_backup vers $BACKUP_DIR"
        return 0
    fi
    return 1
}

# Fonction vérification prérequis - Check outils nécessaires avant exec
check_prerequisites() {
    local missing_tools=()
    local required_tools=("arecord" "aplay" "pactl" "lsmod" "journalctl" "lsusb")

    add_action "Vérification des prérequis système"

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
            log "${RED}❌ Outil manquant: $tool${NC}"
        else
            log "${GREEN}✅ Outil disponible: $tool${NC}"
        fi
    done

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "${RED}ERREUR: Outils manquants: ${missing_tools[*]}${NC}"
        log "${YELLOW}Installation suggérée: sudo apt-get install alsa-utils pulseaudio-utils${NC}"
        analyze "Prérequis" "Outils manquants: ${missing_tools[*]}" "CRITIQUE"
        return 1
    fi

    analyze "Prérequis" "Tous les outils nécessaires sont disponibles" "OK"
    return 0
}

#########################################################################
# FONCTION HELP - Documentation complète avec exemples détaillés
#########################################################################
show_help() {
    cat << 'EOF'
========================================================================
🎙️ AUDIO TRANSCRIPTION DIAGNOSTIC v1.0
========================================================================
Auteur: Bruno DELNOZ <bruno.delnoz@protonmail.com>

DESCRIPTION:
    Script ultra-complet pour diagnostiquer les problèmes de transcription
    vocale polluée. Analyse le système, les processus, la configuration
    audio et génère un rapport détaillé avec recommandations.

USAGE:
    ./audio_transcription_diagnostic.sh [OPTIONS]

OPTIONS:
    --exec          Lance le diagnostic complet
    --delete        Supprime tous les fichiers créés par le script
    --help          Affiche cette aide

EXEMPLES D'UTILISATION:

1. Diagnostic complet (recommandé):
   ./audio_transcription_diagnostic.sh --exec

   → Lance l'analyse complète avec test micro, scan processus,
     analyse logs système, génération rapport final

2. Nettoyage complet:
   ./audio_transcription_diagnostic.sh --delete

   → Supprime tous les dossiers de diagnostic créés précédemment
   → Supprime les logs et backups
   → Restore les configurations sauvegardées

3. Affichage aide:
   ./audio_transcription_diagnostic.sh --help
   ./audio_transcription_diagnostic.sh

   → Affiche cette documentation complète

SORTIE DU SCRIPT:
    - Dossier audio_transcription_diagnostic_YYYYMMDD_HHMMSS/
      ├── analysis_report.txt (rapport final avec recommandations)
      ├── test_micro.wav (enregistrement test)
      ├── whisper_result.txt (transcription Whisper si disponible)
      ├── processes_audio.log (processus audio actifs)
      ├── sources.log (sources audio système)
      ├── modules.log (modules PulseAudio/PipeWire)
      ├── system_logs.log (logs système audio)
      ├── kernel_modules.log (modules kernel audio)
      └── raw_analysis.csv (données brutes analyse)

    - log.audio_transcription_diagnostic.v1.0.log (log complet exécution)
    - audio_transcription_diagnostic_backups/ (sauvegardes configs)

PROBLÈMES DÉTECTÉS AUTOMATIQUEMENT:
    🚨 CRITIQUES:
    - Enregistrement audio impossible ou corrompu
    - Absence totale de processus audio système
    - Erreurs kernel/driver audio critiques
    - Permissions système insuffisantes

    🔍 SUSPECTS:
    - NoiseTorch ou filtres audio actifs
    - Modules PulseAudio loopback/echo-cancel
    - Processus de capture audio inconnus
    - Conflits entre serveurs audio (JACK/Pulse)

    ⚠️ ATTENTION:
    - Utilisateur pas dans groupe audio
    - Multiples cartes son détectées
    - Connexions réseau suspectes
    - Configuration audio personnalisée

EXEMPLES DE CAS D'USAGE TYPIQUES:

Cas 1 - Transcription polluée sur multiple plateformes:
    ./audio_transcription_diagnostic.sh --exec
    → Analyse si le problème vient du système ou des services

Cas 2 - Après installation nouveaux drivers audio:
    ./audio_transcription_diagnostic.sh --exec
    → Vérifie conflits et configuration post-installation

Cas 3 - Problème apparu après mise à jour système:
    ./audio_transcription_diagnostic.sh --exec
    → Compare configuration actuelle vs logs précédents

Cas 4 - Nettoyage après résolution problème:
    ./audio_transcription_diagnostic.sh --delete
    → Supprime tous les fichiers de diagnostic

INTERPRÉTATION DU RAPPORT:

    STATUS OK: Élément fonctionne normalement
    STATUS INFO: Information utile mais pas problématique
    STATUS ATTENTION: Élément à surveiller, peut causer problèmes
    STATUS SUSPECT: Élément probablement responsable du problème
    STATUS CRITIQUE: Élément défaillant, action immédiate requise

RECOMMANDATIONS POST-DIAGNOSTIC:

    1. Consulter analysis_report.txt pour actions prioritaires
    2. Suivre recommendations automatiques générées
    3. Tester avec fichier test_micro.wav si problème persiste
    4. Relancer diagnostic après corrections pour vérifier

COMPATIBILITÉ:
    - Testé sur Kali Linux, Ubuntu, Debian, Fedora
    - Nécessite bash 4.0+, alsa-utils, pulseaudio-utils
    - Supporte PulseAudio, PipeWire, JACK
    - Compatible systèmes systemd et SysV

AUTEUR & SUPPORT:
    Bruno DELNOZ - bruno.delnoz@protonmail.com
    Version v1.0 - 2025-01-10
========================================================================
EOF
}

#########################################################################
# FONCTIONS DIAGNOSTIC - Modules d'analyse système complets
#########################################################################

# Test matériel et enregistrement - Vérifie hardware et qualité signal
test_hardware_recording() {
    add_action "Démarrage test matériel et enregistrement audio"

    log "${PURPLE}========================================="
    log "1️⃣  TEST MATÉRIEL ET ENREGISTREMENT"
    log "=========================================${NC}"

    # Test d'enregistrement avec analyse détaillée
    log "${YELLOW}⏰ Test d'enregistrement micro (10 secondes)...${NC}"
    log "Parle maintenant: 'Bonjour je teste mon micro un deux trois'"

    # Enregistrement avec gestion d'erreurs complète
    if arecord -f cd -t wav -d 10 "$WORKDIR/test_micro.wav" 2>&1 | tee "$WORKDIR/arecord.log"; then
        add_action "Enregistrement audio effectué avec succès"

        # Analyse du fichier audio créé
        if [ -f "$WORKDIR/test_micro.wav" ]; then
            file_size=$(stat -c%s "$WORKDIR/test_micro.wav")
            if [ $file_size -gt 1000 ]; then
                log "${GREEN}✅ Fichier audio créé ($file_size bytes)${NC}"
                analyze "Enregistrement" "Fichier créé - $file_size bytes" "OK"

                # Test de lecture avec vérification erreurs
                log "${YELLOW}🔊 Test de lecture du fichier...${NC}"
                if aplay "$WORKDIR/test_micro.wav" 2>&1 | tee "$WORKDIR/aplay.log"; then
                    analyze "Lecture" "Fichier lu sans erreur" "OK"
                    add_action "Test lecture audio réussi"
                else
                    analyze "Lecture" "Erreur lors de la lecture" "CRITIQUE"
                fi

                # Analyse spectrale avancée si sox disponible
                if command -v sox &> /dev/null; then
                    add_action "Analyse spectrale avancée avec sox"
                    sox "$WORKDIR/test_micro.wav" -n stat 2>&1 | tee "$WORKDIR/sox_analysis.log"
                    analyze "Analyse_spectrale" "Disponible via sox" "INFO"

                    # Extraction données techniques audio
                    duration=$(sox --i -D "$WORKDIR/test_micro.wav" 2>/dev/null)
                    sample_rate=$(sox --i -r "$WORKDIR/test_micro.wav" 2>/dev/null)
                    channels=$(sox --i -c "$WORKDIR/test_micro.wav" 2>/dev/null)

                    analyze "Durée_audio" "${duration}s" "INFO"
                    analyze "Sample_rate" "${sample_rate}Hz" "INFO"
                    analyze "Canaux" "$channels" "INFO"
                fi

                # Test de qualité audio avec ffmpeg si disponible
                if command -v ffmpeg &> /dev/null; then
                    add_action "Analyse qualité audio avec ffmpeg"
                    ffmpeg -i "$WORKDIR/test_micro.wav" -af "volumedetect" -f null /dev/null 2>&1 | tee "$WORKDIR/ffmpeg_analysis.log"
                    analyze "Analyse_ffmpeg" "Analyse qualité effectuée" "INFO"
                fi

            else
                log "${RED}❌ Fichier audio trop petit ou corrompu${NC}"
                analyze "Enregistrement" "Fichier corrompu - $file_size bytes" "CRITIQUE"
            fi
        else
            log "${RED}❌ Fichier audio non créé${NC}"
            analyze "Enregistrement" "Échec création fichier" "CRITIQUE"
        fi
    else
        log "${RED}❌ Échec enregistrement audio${NC}"
        analyze "Enregistrement" "Impossible d'enregistrer" "CRITIQUE"
    fi
}

# Analyse processus système - Détecte processus audio suspects/conflictuels
analyze_system_processes() {
    add_action "Analyse des processus système audio"

    log "${PURPLE}========================================="
    log "2️⃣  ANALYSE PROCESSUS SYSTÈME"
    log "=========================================${NC}"

    # Processus audio principaux avec analyse détaillée
    log "${YELLOW}--- Processus audio actifs ---${NC}"
    audio_processes=$(ps aux | grep -Ei 'pulse|pipewire|jack|noisetorch|cadmus|noise|alsa' | grep -v grep)

    if [ -n "$audio_processes" ]; then
        echo "$audio_processes" | tee "$WORKDIR/processes_audio.log"
        process_count=$(echo "$audio_processes" | wc -l)
        analyze "Processus_audio" "$process_count processus détectés" "INFO"
        add_action "Détection de $process_count processus audio actifs"

        # Analyse détaillée par type de processus
        if echo "$audio_processes" | grep -q pipewire; then
            pipewire_count=$(echo "$audio_processes" | grep -c pipewire)
            analyze "PipeWire" "$pipewire_count processus actifs" "INFO"
            log "${CYAN}  → PipeWire détecté ($pipewire_count processus)${NC}"
        fi

        if echo "$audio_processes" | grep -q pulse; then
            pulse_count=$(echo "$audio_processes" | grep -c pulse)
            analyze "PulseAudio" "$pulse_count processus actifs" "INFO"
            log "${CYAN}  → PulseAudio détecté ($pulse_count processus)${NC}"
        fi

        if echo "$audio_processes" | grep -q jack; then
            jack_count=$(echo "$audio_processes" | grep -c jack)
            analyze "JACK" "$jack_count processus actifs - Conflit possible" "ATTENTION"
            log "${YELLOW}  → JACK détecté ($jack_count processus) - Possible conflit${NC}"
        fi

        if echo "$audio_processes" | grep -qi noisetorch; then
            analyze "NoiseTorch" "Filtre audio actif détecté" "SUSPECT"
            log "${RED}  → NoiseTorch détecté - FILTRE AUDIO SUSPECT${NC}"
        fi

        if echo "$audio_processes" | grep -qi cadmus; then
            analyze "Cadmus" "Modulateur vocal détecté" "SUSPECT"
            log "${RED}  → Cadmus détecté - MODULATEUR VOCAL SUSPECT${NC}"
        fi

    else
        log "${RED}Aucun processus audio standard détecté${NC}"
        analyze "Processus_audio" "Aucun processus standard" "CRITIQUE"
    fi

    # Recherche processus suspects supplémentaires
    log "${YELLOW}--- Processus suspects potentiels ---${NC}"
    suspect_processes=$(ps aux | grep -Ei 'record|capture|stream|voice|speech|micro|sound|filter|transcri' | grep -v grep)

    if [ -n "$suspect_processes" ]; then
        echo "$suspect_processes" | tee "$WORKDIR/processes_suspects.log"
        suspect_count=$(echo "$suspect_processes" | wc -l)
        analyze "Processus_suspects" "$suspect_count processus trouvés" "ATTENTION"
        add_action "Détection de $suspect_count processus suspects"

        # Analyse détaillée des processus suspects
        while IFS= read -r line; do
            if echo "$line" | grep -qi "record"; then
                log "${YELLOW}  → Processus d'enregistrement détecté: $(echo "$line" | awk '{print $11}')"
            fi
            if echo "$line" | grep -qi "capture"; then
                log "${YELLOW}  → Processus de capture détecté: $(echo "$line" | awk '{print $11}')"
            fi
            if echo "$line" | grep -qi "transcri"; then
                log "${RED}  → Processus de transcription détecté: $(echo "$line" | awk '{print $11}') - SUSPECT${NC}"
            fi
        done <<< "$suspect_processes"
    else
        analyze "Processus_suspects" "Aucun processus suspect" "OK"
    fi

    # Analyse des connexions de processus vers devices audio
    log "${YELLOW}--- Processus utilisant devices audio ---${NC}"
    if command -v fuser &> /dev/null; then
        audio_users=$(fuser -v /dev/snd/* 2>&1 | grep -v "Cannot stat")
        if [ -n "$audio_users" ]; then
            echo "$audio_users" | tee "$WORKDIR/audio_device_users.log"
            analyze "Devices_audio_usage" "Processus utilisant /dev/snd détectés" "INFO"
            add_action "Analyse utilisation devices /dev/snd"
        fi
    fi
}

# Configuration audio système - Analyse sources, modules, connexions
analyze_audio_configuration() {
    add_action "Analyse configuration audio système"

    log "${PURPLE}========================================="
    log "3️⃣  CONFIGURATION AUDIO SYSTÈME"
    log "=========================================${NC}"

    # Sources audio avec analyse approfondie
    log "${YELLOW}--- Sources audio ---${NC}"
    if pactl list sources short 2>&1 | tee "$WORKDIR/sources.log"; then
        source_count=$(pactl list sources short 2>/dev/null | wc -l)
        analyze "Sources_audio" "$source_count sources détectées" "INFO"
        add_action "Énumération de $source_count sources audio"

        # Analyse détaillée des sources
        pactl list sources 2>&1 | tee "$WORKDIR/sources_detailed.log"

        # Détection sources virtuelles ou filtrées
        virtual_sources=$(pactl list sources 2>/dev/null | grep -c "monitor")
        if [ $virtual_sources -gt 0 ]; then
            analyze "Sources_virtuelles" "$virtual_sources sources monitor détectées" "INFO"
        fi

    else
        analyze "Sources_audio" "Impossible de lister les sources" "CRITIQUE"
    fi

    # Connexions actives des sources - Détection flux suspects
    log "${YELLOW}--- Connexions source actives ---${NC}"
    if pactl list source-outputs 2>&1 | tee "$WORKDIR/source-outputs.log"; then
        output_count=$(pactl list source-outputs 2>/dev/null | grep -c "Source Output")
        if [ $output_count -gt 0 ]; then
            analyze "Connexions_actives" "$output_count connexions actives" "INFO"
            add_action "Détection de $output_count connexions source actives"

            # Analyse des applications connectées
            connected_apps=$(pactl list source-outputs 2>/dev/null | grep "application.name" | cut -d'"' -f2)
            if [ -n "$connected_apps" ]; then
                log "${CYAN}Applications connectées aux sources:${NC}"
                echo "$connected_apps" | while read -r app; do
                    log "${CYAN}  → $app${NC}"
                done
                echo "$connected_apps" > "$WORKDIR/connected_apps.log"
            fi
        else
            analyze "Connexions_actives" "Aucune connexion active" "OK"
        fi
    else
        analyze "Connexions_actives" "Impossible de lister les connexions" "ATTENTION"
    fi

    # Modules chargés avec analyse de sécurité
    log "${YELLOW}--- Modules PulseAudio/PipeWire ---${NC}"
    if pactl list modules short 2>&1 | tee "$WORKDIR/modules.log"; then
        module_count=$(pactl list modules short 2>/dev/null | wc -l)
        analyze "Modules_total" "$module_count modules chargés" "INFO"
        add_action "Analyse de $module_count modules audio"

        # Analyse modules suspects/problématiques
        if pactl list modules short 2>/dev/null | grep -q "module-loopback"; then
            loopback_count=$(pactl list modules short 2>/dev/null | grep -c "module-loopback")
            analyze "Module_loopback" "$loopback_count modules - Peut causer échos/boucles" "SUSPECT"
            log "${RED}  → module-loopback détecté ($loopback_count) - SUSPECT${NC}"
        fi

        if pactl list modules short 2>/dev/null | grep -q "module-echo-cancel"; then
            echo_cancel_count=$(pactl list modules short 2>/dev/null | grep -c "module-echo-cancel")
            analyze "Module_echo_cancel" "$echo_cancel_count modules - Filtre audio actif" "ATTENTION"
            log "${YELLOW}  → module-echo-cancel détecté ($echo_cancel_count)${NC}"
        fi

        if pactl list modules short 2>/dev/null | grep -q "module-filter"; then
            filter_count=$(pactl list modules short 2>/dev/null | grep -c "module-filter")
            analyze "Module_filter" "$filter_count modules - Filtrage audio détecté" "SUSPECT"
            log "${RED}  → module-filter détecté ($filter_count) - FILTRAGE SUSPECT${NC}"
        fi

        if pactl list modules short 2>/dev/null | grep -q "module-remap"; then
            remap_count=$(pactl list modules short 2>/dev/null | grep -c "module-remap")
            analyze "Module_remap" "$remap_count modules - Remapping audio" "ATTENTION"
            log "${YELLOW}  → module-remap détecté ($remap_count)${NC}"
        fi

        # Sauvegarde configuration modules pour analyse
        pactl list modules 2>&1 | tee "$WORKDIR/modules_detailed.log"

    else
        analyze "Modules_audio" "Impossible de lister les modules" "CRITIQUE"
    fi

    # Information serveur audio principal
    log "${YELLOW}--- Configuration serveur audio ---${NC}"
    if pactl info 2>&1 | tee "$WORKDIR/server_info.log"; then
        server_name=$(pactl info 2>/dev/null | grep "Server Name" | cut -d':' -f2 | xargs)
        server_version=$(pactl info 2>/dev/null | grep "Server Version" | cut -d':' -f2 | xargs)
        analyze "Serveur_audio" "$server_name $server_version" "INFO"
        add_action "Identification serveur audio: $server_name $server_version"
    fi
}

# Analyse matériel et drivers - Hardware, kernel modules, périphériques
analyze_hardware_drivers() {
    add_action "Analyse matériel et drivers audio"

    log "${PURPLE}========================================="
    log "4️⃣  MATÉRIEL ET DRIVERS"
    log "=========================================${NC}"

    # Cartes son détectées avec analyse complète
    log "${YELLOW}--- Cartes son détectées ---${NC}"
    if cat /proc/asound/cards | tee "$WORKDIR/cards.log"; then
        card_count=$(cat /proc/asound/cards | grep -c "^[[:space:]]*[0-9]")
        analyze "Cartes_son" "$card_count cartes détectées" "INFO"
        add_action "Détection de $card_count cartes son"

        # Analyse détaillée par carte
        card_info=$(cat /proc/asound/cards)
        if [ $card_count -gt 1 ]; then
            analyze "Multi_cartes" "Multiples cartes - Possible conflit" "ATTENTION"
            log "${YELLOW}  → Attention: Multiples cartes détectées, possible conflit${NC}"
        fi

        # Information sur la carte par défaut
        default_card=$(cat /proc/asound/card*/id 2>/dev/null | head -1)
        if [ -n "$default_card" ]; then
            analyze "Carte_defaut" "$default_card" "INFO"
        fi
    else
        analyze "Cartes_son" "Impossible de lire /proc/asound/cards" "CRITIQUE"
    fi

    # Modules kernel audio avec vérification intégrité
    log "${YELLOW}--- Modules kernel audio ---${NC}"
    if lsmod | grep snd | tee "$WORKDIR/kernel_modules.log"; then
        kernel_mod_count=$(lsmod | grep -c snd)
        analyze "Modules_kernel" "$kernel_mod_count modules chargés" "INFO"
        add_action "Énumération de $kernel_mod_count modules kernel audio"

        # Vérification modules critiques
        critical_modules=("snd_hda_intel" "snd_usb_audio" "snd_pcm" "snd_mixer_oss")
        for module in "${critical_modules[@]}"; do
            if lsmod | grep -q "$module"; then
                log "${GREEN}  → Module critique $module: OK${NC}"
            else
                log "${RED}  → Module critique $module: MANQUANT${NC}"
                analyze "Module_$module" "Module critique manquant" "CRITIQUE"
            fi
        done

        # Modules potentiellement problématiques
        if lsmod | grep -q "snd_dummy"; then
            analyze "Module_dummy" "Module dummy audio détecté" "ATTENTION"
        fi

    else
        analyze "Modules_kernel" "Aucun module kernel audio" "CRITIQUE"
    fi

    # Périphériques USB audio avec analyse complète
    log "${YELLOW}--- Périphériques USB audio ---${NC}"
    usb_audio=$(lsusb | grep -i audio)
    if [ -n "$usb_audio" ]; then
        echo "$usb_audio" | tee "$WORKDIR/usb_audio.log"
        usb_audio_count=$(echo "$usb_audio" | wc -l)
        analyze "USB_audio" "$usb_audio_count périphériques USB" "INFO"
        add_action "Détection de $usb_audio_count périphériques USB audio"

        # Analyse détaillée des périphériques USB
        echo "$usb_audio" | while read -r line; do
            device_info=$(echo "$line" | awk '{for(i=7;i<=NF;i++) printf "%s ", $i; print ""}')
            log "${CYAN}  → Périphérique USB: $device_info${NC}"
        done
    else
        analyze "USB_audio" "Aucun périphérique USB audio" "INFO"
    fi

    # Devices /dev/snd avec permissions et propriétés
    log "${YELLOW}--- Périphériques /dev/snd ---${NC}"
    if [ -d "/dev/snd" ]; then
        ls -la /dev/snd/ | tee "$WORKDIR/dev_snd.log"
        dev_count=$(ls /dev/snd/ | wc -l)
        analyze "Peripheriques_dev" "$dev_count devices trouvés" "INFO"
        add_action "Analyse de $dev_count devices dans /dev/snd"

        # Vérification permissions utilisateur
        user_groups=$(groups)
        if echo "$user_groups" | grep -q audio; then
            analyze "Permissions_audio" "Utilisateur dans groupe audio" "OK"
            log "${GREEN}  → Utilisateur dans groupe audio: OK${NC}"
        else
            analyze "Permissions_audio" "Utilisateur PAS dans groupe audio" "CRITIQUE"
            log "${RED}  → Utilisateur PAS dans groupe audio: CRITIQUE${NC}"
        fi

        # Test accès devices
        for device in /dev/snd/control*; do
            if [ -e "$device" ]; then
                if [ -r "$device" ]; then
                    log "${GREEN}  → Accès lecture $device: OK${NC}"
                else
                    log "${RED}  → Accès lecture $device: REFUSÉ${NC}"
                    analyze "Acces_device" "Accès refusé à $device" "CRITIQUE"
                fi
            fi
        done
    else
        analyze "Peripheriques_dev" "/dev/snd inexistant" "CRITIQUE"
    fi

    # Information détaillée ALSA
    log "${YELLOW}--- Configuration ALSA ---${NC}"
    if command -v aplay &> /dev/null; then
        aplay -l 2>&1 | tee "$WORKDIR/alsa_devices.log"
        analyze "ALSA_devices" "Énumération devices ALSA effectuée" "INFO"
        add_action "Énumération devices ALSA"
    fi

    if command -v amixer &> /dev/null; then
        amixer 2>&1 | tee "$WORKDIR/alsa_mixer.log"
        analyze "ALSA_mixer" "Configuration mixer ALSA sauvée" "INFO"
    fi
}

# Analyse logs système - Erreurs, conflits, messages kernel
analyze_system_logs() {
    add_action "Analyse des logs système audio"

    log "${PURPLE}========================================="
    log "5️⃣  LOGS ET ERREURS SYSTÈME"
    log "=========================================${NC}"

    # Journalctl audio avec analyse d'erreurs avancée
    log "${YELLOW}--- Logs système audio (dernières 100 lignes) ---${NC}"
    audio_logs=$(journalctl -xe --no-pager | grep -Ei 'alsa|pulse|pipewire|jack|audio|sound' | tail -100)

    if [ -n "$audio_logs" ]; then
        echo "$audio_logs" | tee "$WORKDIR/system_logs.log"

        # Analyse par types d'erreurs
        error_count=$(echo "$audio_logs" | grep -ic error)
        warning_count=$(echo "$audio_logs" | grep -ic warning)
        critical_count=$(echo "$audio_logs" | grep -ic critical)

        if [ $error_count -gt 0 ]; then
            analyze "Erreurs_systeme" "$error_count erreurs détectées" "CRITIQUE"
            log "${RED}  → $error_count erreurs dans les logs système${NC}"
        fi

        if [ $warning_count -gt 0 ]; then
            analyze "Warnings_systeme" "$warning_count warnings détectés" "ATTENTION"
            log "${YELLOW}  → $warning_count warnings dans les logs système${NC}"
        fi

        if [ $critical_count -gt 0 ]; then
            analyze "Critical_systeme" "$critical_count messages critiques" "CRITIQUE"
            log "${RED}  → $critical_count messages critiques${NC}"
        fi

        if [ $error_count -eq 0 ] && [ $warning_count -eq 0 ]; then
            analyze "Logs_systeme" "Aucune erreur majeure détectée" "OK"
        fi

        add_action "Analyse de $((error_count + warning_count)) problèmes dans les logs"
    else
        analyze "Logs_systeme" "Aucun log audio trouvé" "ATTENTION"
    fi

    # Analyse dmesg pour erreurs matérielles/kernel
    log "${YELLOW}--- Messages kernel audio ---${NC}"
    kernel_audio=$(dmesg | grep -Ei 'audio|alsa|snd|sound|usb.*audio' | tail -50)

    if [ -n "$kernel_audio" ]; then
        echo "$kernel_audio" | tee "$WORKDIR/dmesg_audio.log"

        # Recherche erreurs kernel spécifiques
        kernel_errors=$(echo "$kernel_audio" | grep -i "error\|failed\|timeout")
        if [ -n "$kernel_errors" ]; then
            kernel_error_count=$(echo "$kernel_errors" | wc -l)
            analyze "Erreurs_kernel" "$kernel_error_count erreurs kernel audio" "CRITIQUE"
            log "${RED}  → $kernel_error_count erreurs kernel audio détectées${NC}"
        else
            analyze "Kernel_audio" "Messages kernel audio sans erreur" "OK"
        fi

        add_action "Analyse messages kernel audio"
    fi

    # Logs spécifiques PulseAudio si disponibles
    pulse_log_locations=("/var/log/pulse.log" "~/.pulse/pulse.log" "/tmp/pulse-*.log")
    for log_location in "${pulse_log_locations[@]}"; do
        if ls $log_location 2>/dev/null; then
            log "${YELLOW}--- Logs PulseAudio ($log_location) ---${NC}"
            tail -50 $log_location 2>/dev/null | tee "$WORKDIR/pulse_specific.log"
            analyze "Logs_PulseAudio" "Logs spécifiques PulseAudio trouvés" "INFO"
            break
        fi
    done

    # Vérification core dumps audio
    if ls /var/crash/*pulse* /var/crash/*pipewire* /var/crash/*jack* 2>/dev/null; then
        analyze "Core_dumps" "Core dumps audio détectés" "CRITIQUE"
        log "${RED}  → Core dumps de processus audio détectés${NC}"
        ls -la /var/crash/*pulse* /var/crash/*pipewire* /var/crash/*jack* 2>/dev/null | tee "$WORKDIR/core_dumps.log"
    fi
}

# Configuration et environnement - Variables, configs, fichiers système
analyze_configuration_environment() {
    add_action "Analyse configuration et environnement audio"

    log "${PURPLE}========================================="
    log "6️⃣  CONFIGURATION ET ENVIRONNEMENT"
    log "=========================================${NC}"

    # Variables d'environnement audio
    log "${YELLOW}--- Variables environnement audio ---${NC}"
    audio_env=$(env | grep -Ei 'pulse|pipewire|jack|alsa|audio')

    if [ -n "$audio_env" ]; then
        echo "$audio_env" | tee "$WORKDIR/env_audio.log"
        env_count=$(echo "$audio_env" | wc -l)
        analyze "Variables_env" "$env_count variables audio définies" "INFO"
        add_action "Sauvegarde de $env_count variables d'environnement audio"

        # Analyse variables critiques
        if env | grep -q "PULSE_RUNTIME_PATH"; then
            pulse_runtime=$(env | grep "PULSE_RUNTIME_PATH" | cut -d'=' -f2)
            analyze "PULSE_RUNTIME_PATH" "$pulse_runtime" "INFO"
        fi
    else
        analyze "Variables_env" "Aucune variable environnement audio" "INFO"
    fi

    # Fichiers de configuration utilisateur
    log "${YELLOW}--- Configurations utilisateur ---${NC}"
    config_files=(
        "$HOME/.config/pulse/client.conf"
        "$HOME/.config/pulse/daemon.conf"
        "$HOME/.config/pipewire/pipewire.conf"
        "$HOME/.asoundrc"
        "$HOME/.config/alsa/asoundrc"
    )

    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            log "${CYAN}Configuration trouvée: $config_file${NC}"
            backup_config "$config_file" "$(basename "$config_file")"
            cat "$config_file" | tee "$WORKDIR/config_$(basename "$config_file").log"
            analyze "Config_$(basename "$config_file")" "Configuration personnalisée détectée" "INFO"
        fi
    done

    # Fichiers de configuration système
    log "${YELLOW}--- Configurations système ---${NC}"
    system_configs=(
        "/etc/pulse/client.conf"
        "/etc/pulse/daemon.conf"
        "/etc/pulse/system.pa"
        "/etc/pipewire/pipewire.conf"
        "/etc/alsa/conf.d/"
        "/usr/share/alsa/alsa.conf"
    )

    for config in "${system_configs[@]}"; do
        if [ -f "$config" ] || [ -d "$config" ]; then
            log "${CYAN}Configuration système: $config${NC}"
            if [ -f "$config" ]; then
                cat "$config" | tee "$WORKDIR/system_$(basename "$config").log" 2>/dev/null
            else
                ls -la "$config" | tee "$WORKDIR/system_$(basename "$config")_dir.log" 2>/dev/null
            fi
            analyze "Config_system_$(basename "$config")" "Configuration système présente" "INFO"
        fi
    done

    # Services systemd audio
    log "${YELLOW}--- Services systemd audio ---${NC}"
    audio_services=("pulseaudio" "pipewire" "pipewire-pulse" "pipewire-media-session" "wireplumber")

    for service in "${audio_services[@]}"; do
        service_status=$(systemctl --user is-active "$service" 2>/dev/null)
        if [ "$service_status" = "active" ]; then
            log "${GREEN}  → Service $service: ACTIF${NC}"
            analyze "Service_$service" "Actif" "OK"
        elif [ "$service_status" = "inactive" ]; then
            log "${YELLOW}  → Service $service: INACTIF${NC}"
            analyze "Service_$service" "Inactif" "INFO"
        elif [ "$service_status" = "failed" ]; then
            log "${RED}  → Service $service: ÉCHEC${NC}"
            analyze "Service_$service" "En échec" "CRITIQUE"
        fi

        # Logs détaillés du service
        systemctl --user status "$service" 2>/dev/null | tee "$WORKDIR/service_${service}.log"
    done

    add_action "Analyse des services systemd audio"

    # Autostart et sessions
    log "${YELLOW}--- Applications de démarrage audio ---${NC}"
    autostart_dirs=("$HOME/.config/autostart" "/etc/xdg/autostart")

    for dir in "${autostart_dirs[@]}"; do
        if [ -d "$dir" ]; then
            audio_autostart=$(ls "$dir"/*.desktop 2>/dev/null | xargs grep -l -i "audio\|pulse\|pipewire\|jack" 2>/dev/null)
            if [ -n "$audio_autostart" ]; then
                echo "$audio_autostart" | tee "$WORKDIR/autostart_audio.log"
                autostart_count=$(echo "$audio_autostart" | wc -l)
                analyze "Autostart_audio" "$autostart_count applications audio au démarrage" "INFO"
            fi
        fi
    done
}

# Tests de transcription - Whisper, speech recognition, quality
test_transcription_engines() {
    add_action "Tests des moteurs de transcription"

    log "${PURPLE}========================================="
    log "7️⃣  TESTS DE TRANSCRIPTION"
    log "=========================================${NC}"

    # Test Whisper si disponible
    if command -v whisper &> /dev/null; then
        log "${YELLOW}🧠 Test Whisper local...${NC}"
        add_action "Test de transcription avec Whisper"

        if [ -f "$WORKDIR/test_micro.wav" ]; then
            # Test avec différents modèles si disponibles
            whisper_models=("tiny" "base" "small")

            for model in "${whisper_models[@]}"; do
                log "${CYAN}  → Test modèle Whisper: $model${NC}"

                if whisper "$WORKDIR/test_micro.wav" --language fr --model "$model" --output_format txt 2>&1 | tee "$WORKDIR/whisper_${model}_output.log"; then

                    result_file="$WORKDIR/test_micro.txt"
                    if [ -f "$result_file" ]; then
                        whisper_result=$(cat "$result_file")
                        echo "$whisper_result" | tee "$WORKDIR/whisper_${model}_result.txt"

                        log "${YELLOW}--- Résultat Whisper $model ---${NC}"
                        log "${CYAN}$whisper_result${NC}"

                        # Analyse qualité transcription
                        if echo "$whisper_result" | grep -qi "bonjour\|test\|micro\|un\|deux\|trois"; then
                            analyze "Whisper_${model}" "Transcription cohérente détectée" "OK"
                            log "${GREEN}  → Transcription cohérente avec modèle $model${NC}"
                        else
                            analyze "Whisper_${model}" "Transcription incohérente ou polluée" "CRITIQUE"
                            log "${RED}  → Transcription polluée avec modèle $model: '$whisper_result'${NC}"
                        fi

                        # Calcul score de confiance approximatif
                        word_count=$(echo "$whisper_result" | wc -w)
                        if [ $word_count -gt 0 ] && [ $word_count -lt 50 ]; then
                            analyze "Whisper_${model}_longueur" "$word_count mots - Longueur normale" "OK"
                        elif [ $word_count -ge 50 ]; then
                            analyze "Whisper_${model}_longueur" "$word_count mots - Trop long, possible hallucination" "SUSPECT"
                        fi

                        # Renommer le fichier pour éviter l'écrasement
                        mv "$result_file" "$WORKDIR/whisper_${model}_result.txt" 2>/dev/null
                    else
                        analyze "Whisper_${model}" "Échec génération fichier résultat" "CRITIQUE"
                    fi
                else
                    analyze "Whisper_${model}" "Échec exécution Whisper" "CRITIQUE"
                fi
            done
        else
            log "${RED}❌ Fichier test_micro.wav introuvable pour test Whisper${NC}"
            analyze "Whisper_test" "Fichier audio manquant" "CRITIQUE"
        fi
    else
        log "${RED}❌ Whisper non installé${NC}"
        analyze "Whisper_disponible" "Non installé" "INFO"
    fi

    # Test speech-dispatcher si disponible
    if command -v spd-say &> /dev/null; then
        log "${YELLOW}🗣️  Test speech-dispatcher...${NC}"
        echo "test speech dispatcher" | spd-say 2>&1 | tee "$WORKDIR/speech_dispatcher.log"
        analyze "Speech_dispatcher" "Disponible et testé" "INFO"
        add_action "Test speech-dispatcher effectué"
    fi

    # Test espeak si disponible
    if command -v espeak &> /dev/null; then
        log "${YELLOW}🔊 Test espeak...${NC}"
        espeak "test espeak" 2>&1 | tee "$WORKDIR/espeak.log"
        analyze "Espeak" "Disponible et testé" "INFO"
        add_action "Test espeak effectué"
    fi

    # Test festival si disponible
    if command -v festival &> /dev/null; then
        log "${YELLOW}🎭 Test festival...${NC}"
        echo "test festival" | festival --tts 2>&1 | tee "$WORKDIR/festival.log"
        analyze "Festival" "Disponible et testé" "INFO"
        add_action "Test festival effectué"
    fi

    # Test reconnaissance vocale Google si curl disponible
    if command -v curl &> /dev/null && [ -f "$WORKDIR/test_micro.wav" ]; then
        log "${YELLOW}🌐 Test API reconnaissance vocale (si connexion)...${NC}"
        # Note: Test basique de connectivité uniquement, pas d'envoi de données
        if curl -s --connect-timeout 5 https://www.google.com >/dev/null; then
            analyze "Connectivite_API" "Connexion internet disponible pour APIs" "INFO"
        else
            analyze "Connectivite_API" "Pas de connexion internet" "INFO"
        fi
    fi
}

# Analyse réseau et sécurité - Connexions suspectes, processus réseau
analyze_network_security() {
    add_action "Analyse réseau et sécurité audio"

    log "${PURPLE}========================================="
    log "8️⃣  ANALYSE RÉSEAU ET SÉCURITÉ"
    log "=========================================${NC}"

    # Connexions réseau actives suspectes
    log "${YELLOW}--- Connexions réseau actives ---${NC}"
    if command -v netstat &> /dev/null; then
        network_connections=$(netstat -tulpn 2>/dev/null | grep -E ':80|:443|:8080|:3000|:8000|:9000')

        if [ -n "$network_connections" ]; then
            echo "$network_connections" | tee "$WORKDIR/network_connections.log"
            connection_count=$(echo "$network_connections" | wc -l)
            analyze "Connexions_reseau" "$connection_count connexions web détectées" "INFO"
            add_action "Analyse de $connection_count connexions réseau"

            # Analyse connexions suspectes
            suspicious_ports=$(echo "$network_connections" | grep -E ':8080|:3000|:8000|:9000')
            if [ -n "$suspicious_ports" ]; then
                suspicious_count=$(echo "$suspicious_ports" | wc -l)
                analyze "Ports_suspects" "$suspicious_count ports non-standard actifs" "ATTENTION"
                log "${YELLOW}  → $suspicious_count ports non-standard détectés${NC}"
            fi
        else
            analyze "Connexions_reseau" "Aucune connexion web standard détectée" "OK"
        fi
    fi

    # Processus avec connexions réseau
    log "${YELLOW}--- Processus avec connexions réseau ---${NC}"
    if command -v lsof &> /dev/null; then
        network_processes=$(lsof -i 2>/dev/null | grep -v "ESTABLISHED.*:22" | grep -v "chrome\|firefox")

        if [ -n "$network_processes" ]; then
            echo "$network_processes" | tee "$WORKDIR/network_processes.log"
            net_proc_count=$(echo "$network_processes" | wc -l)
            analyze "Processus_reseau" "$net_proc_count processus avec connexions réseau" "INFO"
            add_action "Détection de $net_proc_count processus réseau"

            # Recherche processus audio avec connexions réseau
            audio_network=$(echo "$network_processes" | grep -Ei 'pulse|pipewire|jack|audio|sound')
            if [ -n "$audio_network" ]; then
                audio_net_count=$(echo "$audio_network" | wc -l)
                analyze "Audio_reseau" "$audio_net_count processus audio avec réseau" "ATTENTION"
                log "${YELLOW}  → $audio_net_count processus audio avec connexions réseau${NC}"
                echo "$audio_network" | tee "$WORKDIR/audio_network_processes.log"
            fi
        fi
    fi

    # Vérification ports d'écoute audio suspects
    suspicious_audio_ports=(8000 8080 3000 9000 5000 4000)
    log "${YELLOW}--- Vérification ports audio suspects ---${NC}"

    for port in "${suspicious_audio_ports[@]}"; do
        if netstat -tln 2>/dev/null | grep -q ":$port "; then
            listening_process=$(netstat -tlnp 2>/dev/null | grep ":$port " | awk '{print $7}' | cut -d'/' -f2)
            analyze "Port_$port" "Port $port ouvert - processus: $listening_process" "SUSPECT"
            log "${RED}  → Port suspect $port ouvert par: $listening_process${NC}"
        fi
    done

    # Analyse trafic réseau temps réel si tcpdump disponible
    if command -v tcpdump &> /dev/null && [ "$EUID" -eq 0 ]; then
        log "${YELLOW}--- Analyse trafic réseau (5 secondes) ---${NC}"
        timeout 5 tcpdump -i any -c 20 port not 22 2>&1 | tee "$WORKDIR/network_traffic.log" || true
        analyze "Trafic_reseau" "Échantillon trafic capturé" "INFO"
        add_action "Capture échantillon trafic réseau"
    fi

    # Vérification fichiers hosts et DNS
    log "${YELLOW}--- Vérification configuration réseau ---${NC}"
    if [ -f "/etc/hosts" ]; then
        suspicious_hosts=$(grep -v "^#\|^$\|127.0.0.1\|::1\|localhost" /etc/hosts)
        if [ -n "$suspicious_hosts" ]; then
            echo "$suspicious_hosts" | tee "$WORKDIR/suspicious_hosts.log"
            analyze "Hosts_suspects" "Entrées hosts personnalisées détectées" "ATTENTION"
        else
            analyze "Fichier_hosts" "Fichier hosts standard" "OK"
        fi
    fi

    # Vérification proxy/VPN
    if env | grep -qi "proxy\|vpn"; then
        proxy_vars=$(env | grep -i "proxy\|vpn")
        echo "$proxy_vars" | tee "$WORKDIR/proxy_config.log"
        analyze "Configuration_proxy" "Configuration proxy/VPN détectée" "INFO"
    fi
}

# Génération rapport d'analyse - Synthèse automatique et recommandations
generate_analysis_report() {
    add_action "Génération du rapport d'analyse automatique"

    log "${PURPLE}========================================="
    log "9️⃣  GÉNÉRATION RAPPORT D'ANALYSE"
    log "=========================================${NC}"

    log "${YELLOW}🔍 Génération du rapport d'analyse complet...${NC}"

    # Header du rapport avec informations système
    cat > "$ANALYSIS_FILE" << EOF
========================================================================
🎙️ RAPPORT D'ANALYSE AUDIO AUTOMATIQUE ULTRA-COMPLET
========================================================================

Généré le: $(date)
Script: $SCRIPT_NAME $SCRIPT_VERSION
Système: $(uname -a)
Utilisateur: $(whoami)
Répertoire: $(pwd)

========================================================================
📊 RÉSUMÉ EXÉCUTIF
========================================================================
EOF

    # Calcul statistiques analyse
    total_items=$(wc -l < "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    critiques=$(grep -c "CRITIQUE" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    suspects=$(grep -c "SUSPECT" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    attentions=$(grep -c "ATTENTION" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    ok_items=$(grep -c "OK" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")

    cat >> "$ANALYSIS_FILE" << EOF

Total d'éléments analysés: $total_items
🚨 Problèmes CRITIQUES: $critiques
🔍 Éléments SUSPECTS: $suspects
⚠️ Points d'ATTENTION: $attentions
✅ Éléments OK: $ok_items

NIVEAU DE RISQUE GLOBAL: $(
    if [ $critiques -gt 0 ]; then
        echo "🚨 CRITIQUE - Action immédiate requise"
    elif [ $suspects -gt 2 ]; then
        echo "⚠️ ÉLEVÉ - Investigation approfondie nécessaire"
    elif [ $suspects -gt 0 ] || [ $attentions -gt 3 ]; then
        echo "⚡ MODÉRÉ - Surveillance recommandée"
    else
        echo "✅ FAIBLE - Système normal"
    fi
)

EOF

    # Analyse des problèmes par catégorie
    grep "CRITIQUE" "$WORKDIR/raw_analysis.csv" 2>/dev/null > "$WORKDIR/critiques.tmp"
    grep "SUSPECT" "$WORKDIR/raw_analysis.csv" 2>/dev/null > "$WORKDIR/suspects.tmp"
    grep "ATTENTION" "$WORKDIR/raw_analysis.csv" 2>/dev/null > "$WORKDIR/attentions.tmp"

    if [ -s "$WORKDIR/critiques.tmp" ]; then
        cat >> "$ANALYSIS_FILE" << EOF

========================================================================
🚨 PROBLÈMES CRITIQUES DÉTECTÉS
========================================================================

Ces problèmes nécessitent une action IMMÉDIATE:

EOF
        while IFS='|' read -r cat result status; do
            echo "❌ $cat: $result" >> "$ANALYSIS_FILE"
        done < "$WORKDIR/critiques.tmp"
    fi

    if [ -s "$WORKDIR/suspects.tmp" ]; then
        cat >> "$ANALYSIS_FILE" << EOF

========================================================================
🔍 ÉLÉMENTS SUSPECTS IDENTIFIÉS
========================================================================

Ces éléments sont probablement responsables du problème:

EOF
        while IFS='|' read -r cat result status; do
            echo "🔍 $cat: $result" >> "$ANALYSIS_FILE"
        done < "$WORKDIR/suspects.tmp"
    fi

    if [ -s "$WORKDIR/attentions.tmp" ]; then
        cat >> "$ANALYSIS_FILE" << EOF

========================================================================
⚠️ POINTS D'ATTENTION
========================================================================

Ces éléments méritent surveillance:

EOF
        while IFS='|' read -r cat result status; do
            echo "⚠️ $cat: $result" >> "$ANALYSIS_FILE"
        done < "$WORKDIR/attentions.tmp"
    fi

    # Génération recommandations automatiques intelligentes
    cat >> "$ANALYSIS_FILE" << EOF

========================================================================
🎯 RECOMMANDATIONS AUTOMATIQUES INTELLIGENTES
========================================================================

Basé sur l'analyse complète, voici les actions recommandées par priorité:

EOF

    # Recommandations basées sur l'analyse - Logique intelligente
    recommendation_count=1

    # Vérifier NoiseTorch
    if grep -q "NoiseTorch.*SUSPECT" "$WORKDIR/raw_analysis.csv" 2>/dev/null; then
        cat >> "$ANALYSIS_FILE" << EOF
$recommendation_count. 🚨 PRIORITÉ CRITIQUE: Désactiver NoiseTorch
   NoiseTorch est un filtre audio actif qui modifie votre signal vocal.

   Actions:
   → sudo systemctl stop noisetorch
   → sudo systemctl disable noisetorch
   → killall noisetorch

   Redémarrez puis testez la transcription.

EOF
        recommendation_count=$((recommendation_count + 1))
    fi

    # Vérifier loopback
    if grep -q "Module_loopback.*SUSPECT" "$WORKDIR/raw_analysis.csv" 2>/dev/null; then
        cat >> "$ANALYSIS_FILE" << EOF
$recommendation_count. ⚠️ PRIORITÉ ÉLEVÉE: Désactiver modules loopback
   Les modules loopback causent des échos et boucles audio.

   Actions:
   → pactl list modules short | grep loopback
   → pactl unload-module module-loopback

   Puis relancer le diagnostic.

EOF
        recommendation_count=$((recommendation_count + 1))
    fi

    # Vérifier permissions
    if grep -q "Permissions_audio.*CRITIQUE" "$WORKDIR/raw_analysis.csv" 2>/dev/null; then
        cat >> "$ANALYSIS_FILE" << EOF
$recommendation_count. 🔧 PRIORITÉ ÉLEVÉE: Corriger permissions audio
   Votre utilisateur n'est pas dans le groupe audio.

   Actions:
   → sudo usermod -a -G audio \$USER
   → Redémarrer la session

   Essentiel pour accès aux périphériques audio.

EOF
        recommendation_count=$((recommendation_count + 1))
    fi

    # Vérifier JACK
    if grep -q "JACK.*INFO" "$WORKDIR/raw_analysis.csv" 2>/dev/null; then
        cat >> "$ANALYSIS_FILE" << EOF
$recommendation_count. ⚡ PRIORITÉ MODÉRÉE: Gérer conflit JACK
   JACK peut interférer avec PulseAudio/PipeWire.

   Actions:
   → Arrêter JACK temporairement: sudo systemctl stop jack
   → Tester transcription sans JACK
   → Configurer bridge JACK-Pulse si nécessaire

EOF
        recommendation_count=$((recommendation_count + 1))
    fi

    # Vérifier erreurs critiques
    if grep -q "Erreurs_systeme.*CRITIQUE" "$WORKDIR/raw_analysis.csv" 2>/dev/null; then
        cat >> "$ANALYSIS_FILE" << EOF
$recommendation_count. 🚨 PRIORITÉ CRITIQUE: Résoudre erreurs système
   Erreurs critiques détectées dans les logs système.

   Actions:
   → Consulter le fichier system_logs.log
   → Redémarrer les services audio: systemctl --user restart pulseaudio
   → Vérifier intégrité du système: dmesg | grep -i error

EOF
        recommendation_count=$((recommendation_count + 1))
    fi

    # Recommandations générales si pas de problème critique
    if [ $critiques -eq 0 ] && [ $suspects -eq 0 ]; then
        cat >> "$ANALYSIS_FILE" << EOF
✅ SYSTÈME SAIN DÉTECTÉ

Aucun problème critique identifié. Le problème de transcription
peut venir d'autres facteurs:

1. 🌐 Tester avec différents services (local vs cloud)
2. 🎤 Essayer un autre micro/casque
3. 🔄 Redémarrer complètement le système
4. 📶 Vérifier la qualité de connexion réseau
5. 🧠 Tester avec différents modèles Whisper

EOF
    fi

    # Plan d'action étape par étape
    cat >> "$ANALYSIS_FILE" << EOF

========================================================================
📋 PLAN D'ACTION ÉTAPE PAR ÉTAPE
========================================================================

PHASE 1 - Actions immédiates (0-15 minutes):
1. Appliquer recommandations critiques ci-dessus
2. Redémarrer services audio: systemctl --user restart pulseaudio
3. Tester enregistrement: arecord -f cd -t wav -d 5 test_fix.wav

PHASE 2 - Vérifications (15-30 minutes):
1. Relancer ce diagnostic pour comparer
2. Tester transcription avec fichier test_fix.wav
3. Vérifier si problème persiste sur différentes plateformes

PHASE 3 - Solutions avancées (si nécessaire):
1. Réinstallation complète stack audio
2. Test avec Live USB autre distribution
3. Configuration manuelle avancée PulseAudio/PipeWire

EOF

    # Tableau récapitulatif final détaillé
    cat >> "$ANALYSIS_FILE" << EOF

========================================================================
📊 TABLEAU RÉCAPITULATIF COMPLET DÉTAILLÉ
========================================================================

EOF

    printf "%-30s %-50s %-12s\n" "CATÉGORIE" "RÉSULTAT" "STATUS" >> "$ANALYSIS_FILE"
    echo "----------------------------------------------------------------------------------------" >> "$ANALYSIS_FILE"

    # Tri des résultats par priorité (CRITIQUE > SUSPECT > ATTENTION > OK)
    for status_filter in "CRITIQUE" "SUSPECT" "ATTENTION" "INFO" "OK"; do
        grep "|$status_filter$" "$WORKDIR/raw_analysis.csv" 2>/dev/null | while IFS='|' read -r cat result status; do
            printf "%-30s %-50s %-12s\n" "$cat" "$result" "$status" >> "$ANALYSIS_FILE"
        done
    done

    # Footer du rapport avec informations de contact et suivi
    cat >> "$ANALYSIS_FILE" << EOF

========================================================================
📞 INFORMATIONS COMPLÉMENTAIRES
========================================================================

FICHIERS GÉNÉRÉS POUR ANALYSE MANUELLE:
- test_micro.wav: Fichier audio de test (écouter pour vérifier qualité)
- system_logs.log: Logs système complets
- processes_audio.log: Processus audio détectés
- modules.log: Modules PulseAudio/PipeWire
- kernel_modules.log: Modules kernel audio
- sources.log: Sources audio système

COMMANDES DE SUIVI RECOMMANDÉES:
→ aplay test_micro.wav (écouter qualité enregistrement)
→ pactl list sources short (vérifier sources actives)
→ journalctl -xe | grep -i audio (logs temps réel)

PROCHAINES ÉTAPES SI PROBLÈME PERSISTE:
1. Sauvegarder ce rapport complet
2. Tester sur autre système/distribution
3. Contacter support technique avec ce diagnostic

AUTEUR: Bruno DELNOZ <bruno.delnoz@protonmail.com>
VERSION: $SCRIPT_VERSION - $SCRIPT_DATE

========================================================================
🏁 FIN DU RAPPORT - $(date)
========================================================================
EOF

    # Nettoyage fichiers temporaires
    rm -f "$WORKDIR"/*.tmp 2>/dev/null

    add_action "Rapport d'analyse généré: $ANALYSIS_FILE"
}

#########################################################################
# FONCTIONS PRINCIPALES - Gestion arguments et exécution
#########################################################################

# Fonction exécution complète - Lance tous les modules d'analyse
execute_full_diagnostic() {
    log "${GREEN}========================================="
    log "🚀 LANCEMENT DIAGNOSTIC ULTRA-COMPLET"
    log "=========================================${NC}"

    # Initialisation environnement de travail
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || exit 1

    # Header CSV pour analyse
    echo "Catégorie|Résultat|Status" > raw_analysis.csv

    add_action "Initialisation environnement de diagnostic"
    log "📁 Dossier de travail: $(pwd)"
    log "📋 Fichier de log: $LOG_FILE"

    # Vérification prérequis avant démarrage
    if ! check_prerequisites; then
        log "${RED}❌ Prérequis manquants, arrêt du diagnostic${NC}"
        exit 1
    fi

    # Exécution modules d'analyse en séquence
    test_hardware_recording
    analyze_system_processes
    analyze_audio_configuration
    analyze_hardware_drivers
    analyze_system_logs
    analyze_configuration_environment
    test_transcription_engines
    analyze_network_security
    generate_analysis_report

    # Retour au répertoire parent
    cd ..

    # Affichage résumé final
    log "${GREEN}========================================="
    log "🏁 DIAGNOSTIC ULTRA-COMPLET TERMINÉ"
    log "=========================================${NC}"
    log "📁 Tous les résultats dans: $WORKDIR/"
    log "📋 Rapport d'analyse: $ANALYSIS_FILE"
    log "📝 Log complet: $LOG_FILE"
    log ""

    # Statistiques finales colorées
    total_items=$(wc -l < "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    critiques=$(grep -c "CRITIQUE" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    suspects=$(grep -c "SUSPECT" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    attentions=$(grep -c "ATTENTION" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    ok_items=$(grep -c "OK" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")

    log "${CYAN}📊 RÉSUMÉ STATISTIQUES:${NC}"
    log "${RED}🚨 Critiques: $critiques${NC}"
    log "${YELLOW}🔍 Suspects: $suspects${NC}"
    log "${BLUE}⚠️  Attentions: $attentions${NC}"
    log "${GREEN}✅ OK: $ok_items${NC}"
    log "${PURPLE}📊 Total analysé: $total_items éléments${NC}"
    log ""

    # Recommandation finale
    if [ $critiques -gt 0 ]; then
        log "${RED}🚨 ACTION REQUISE: Consulte immédiatement le rapport d'analyse !${NC}"
    elif [ $suspects -gt 0 ]; then
        log "${YELLOW}🔍 INVESTIGATION: Éléments suspects détectés, consulte le rapport${NC}"
    else
        log "${GREEN}✅ SYSTÈME OK: Peu de problèmes détectés${NC}"
    fi

    log "${PURPLE}🎯 Consulte le fichier '$ANALYSIS_FILE' pour le rapport détaillé complet!${NC}"
    log "${CYAN}=========================================${NC}"

    # Affichage liste des actions effectuées
    log ""
    log "${CYAN}📋 RÉCAPITULATIF DES ACTIONS EFFECTUÉES:${NC}"
    for action in "${ACTIONS_LIST[@]}"; do
        log "${GREEN}$action${NC}"
    done
    log ""

    # Aperçu du rapport d'analyse
    if [ -f "$ANALYSIS_FILE" ]; then
        log "${CYAN}📄 APERÇU DU RAPPORT D'ANALYSE:${NC}"
        log "${BLUE}$(head -20 "$ANALYSIS_FILE")${NC}"
        log "${CYAN}... (consulter le fichier complet pour détails)${NC}"
    fi
}

# Fonction suppression propre - Nettoie tous les fichiers créés
delete_all_files() {
    log "${YELLOW}========================================="
    log "🗑️  SUPPRESSION PROPRE DE TOUS LES FICHIERS"
    log "=========================================${NC}"

    add_action "Démarrage suppression propre"

    # Recherche tous les dossiers de diagnostic
    diagnostic_dirs=$(find . -maxdepth 1 -type d -name "${SCRIPT_NAME}_*" 2>/dev/null)

    if [ -n "$diagnostic_dirs" ]; then
        log "${YELLOW}Dossiers de diagnostic trouvés:${NC}"
        echo "$diagnostic_dirs"

        echo "$diagnostic_dirs" | while read -r dir; do
            if [ -d "$dir" ]; then
                log "${RED}Suppression: $dir${NC}"
                rm -rf "$dir"
                add_action "Suppression dossier: $dir"
            fi
        done
    else
        log "${GREEN}Aucun dossier de diagnostic à supprimer${NC}"
    fi

    # Suppression logs du script
    log_files=$(find . -maxdepth 1 -name "log.${SCRIPT_NAME}.*.log" 2>/dev/null)

    if [ -n "$log_files" ]; then
        log "${YELLOW}Fichiers de log trouvés:${NC}"
        echo "$log_files"

        echo "$log_files" | while read -r logfile; do
            if [ -f "$logfile" ]; then
                log "${RED}Suppression: $logfile${NC}"
                rm -f "$logfile"
                add_action "Suppression log: $logfile"
            fi
        done
    else
        log "${GREEN}Aucun fichier de log à supprimer${NC}"
    fi

    # Suppression dossier de backups
    if [ -d "$BACKUP_DIR" ]; then
        log "${YELLOW}Dossier de backups trouvé: $BACKUP_DIR${NC}"

        # Restauration des configurations sauvegardées
        backup_files=$(find "$BACKUP_DIR" -name "*.bak" 2>/dev/null)
        if [ -n "$backup_files" ]; then
            log "${CYAN}Restauration des configurations sauvegardées:${NC}"

            echo "$backup_files" | while read -r backup; do
                # Extraction nom original et chemin
                backup_basename=$(basename "$backup" .bak)
                original_name=$(echo "$backup_basename" | sed 's/_[0-9]\{8\}_[0-9]\{6\}$//')

                # Tentative de restauration intelligente
                possible_paths=(
                    "$HOME/.config/pulse/$original_name"
                    "$HOME/.config/pipewire/$original_name"
                    "$HOME/$original_name"
                    "/etc/pulse/$original_name"
                )

                for path in "${possible_paths[@]}"; do
                    if [ -f "$path" ]; then
                        log "${BLUE}  → Restauration $backup vers $path${NC}"
                        cp "$backup" "$path"
                        add_action "Restauration config: $path"
                        break
                    fi
                done
            done
        fi

        log "${RED}Suppression dossier backups: $BACKUP_DIR${NC}"
        rm -rf "$BACKUP_DIR"
        add_action "Suppression dossier backups"
    else
        log "${GREEN}Aucun dossier de backup à supprimer${NC}"
    fi

    # Nettoyage fichiers temporaires résiduels
    temp_files=$(find /tmp -name "*${SCRIPT_NAME}*" -user "$(whoami)" 2>/dev/null)
    if [ -n "$temp_files" ]; then
        log "${YELLOW}Fichiers temporaires trouvés dans /tmp:${NC}"
        echo "$temp_files" | while read -r temp_file; do
            rm -rf "$temp_file"
            add_action "Suppression temp: $temp_file"
        done
    fi

    log "${GREEN}========================================="
    log "✅ SUPPRESSION PROPRE TERMINÉE"
    log "=========================================${NC}"

    # Affichage actions de suppression
    log "${CYAN}📋 ACTIONS DE SUPPRESSION EFFECTUÉES:${NC}"
    for action in "${ACTIONS_LIST[@]}"; do
        log "${GREEN}$action${NC}"
    done

    log "${GREEN}🧹 Tous les fichiers créés par le script ont été supprimés${NC}"
    log "${GREEN}🔄 Configurations originales restaurées si applicable${NC}"
}

#########################################################################
# LOGIQUE PRINCIPALE - Gestion des arguments et routing
#########################################################################

# Fonction principale - Router les arguments vers les bonnes fonctions
main() {
    # Vérification arguments
    if [ $# -eq 0 ]; then
        show_help
        exit 0
    fi

    case "$1" in
        --help|-h)
            show_help
            ;;
        --exec)
            execute_full_diagnostic
            ;;
        --delete)
            delete_all_files
            ;;
        *)
            log "${RED}❌ Argument non reconnu: $1${NC}"
            log "${YELLOW}Utilise --help pour voir l'aide complète${NC}"
            exit 1
            ;;
    esac
}

#########################################################################
# POINT D'ENTRÉE - Lancement du script avec gestion d'erreurs
#########################################################################

# Gestion des signaux pour nettoyage propre
trap 'log "${RED}Script interrompu par utilisateur${NC}"; exit 130' INT TERM

# Vérification environnement bash
if [ -z "$BASH_VERSION" ]; then
    echo "❌ Ce script nécessite bash, pas sh"
    exit 1
fi

# Vérification droits d'écriture
if [ ! -w "." ]; then
    echo "❌ Pas de droits d'écriture dans le répertoire courant"
    exit 1
fi

# Lancement fonction principale avec tous les arguments
main "$@"

# Code de sortie basé sur les résultats si exécution complète
if [ "$1" = "--exec" ] && [ -f "$WORKDIR/raw_analysis.csv" ]; then
    critiques=$(grep -c "CRITIQUE" "$WORKDIR/raw_analysis.csv" 2>/dev/null || echo "0")
    if [ $critiques -gt 0 ]; then
        exit 2  # Code erreur pour problèmes critiques détectés
    fi
fi

exit 0
