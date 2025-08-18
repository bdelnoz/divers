#!/bin/bash
#
# install_whisper.sh
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Target usage : Installation complète OpenAI Whisper (pip) + whisper.cpp avec compilation
# Version : v1.5 - Date : 2025-08-12
# Changelog :
#  v1.0 - 2025-08-10 - Version initiale
#  v1.1 - 2025-08-11 - Ajout vérification python et pip
#  v1.2 - 2025-08-11 - Installation openai-whisper via pip dans virtualenv
#  v1.3 - 2025-08-11 - Clonage et compilation whisper.cpp avec détection erreurs
#  v1.4 - 2025-08-12 - Gestion correcte dossier build, création si absent, build complet
#  v1.5 - 2025-08-12 - Correction nom binaire (whisper-cli au lieu de whisper)

set -e

# Variables globales
WHISPER_CPP_DIR="whisper.cpp"
BUILD_DIR="$WHISPER_CPP_DIR/build"
BIN_PATH="$BUILD_DIR/bin/whisper-cli"
VENV_DIR="whisper_env"
LOG_FILE="log.install_whisper.v1.5.log"
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
USAGE: $0 [OPTIONS]

OPTIONS:
  --help          Affiche cette aide
  --clean         Nettoie complètement l'installation (virtualenv + whisper.cpp)
  --reinstall     Supprime et réinstalle tout
  --test          Test l'installation avec un fichier audio

EXEMPLES:
  $0                    # Installation complète
  $0 --clean            # Nettoyage complet
  $0 --reinstall        # Réinstallation complète
  $0 --test audio.wav   # Test avec fichier audio

DESCRIPTION:
Script d'installation automatique de OpenAI Whisper (Python) et whisper.cpp.
Crée un environnement virtuel Python et compile les binaires C++ optimisés.

Le binaire compilé sera disponible : $BIN_PATH
Le virtualenv Python sera : $VENV_DIR

EOF
}

# Fonction de nettoyage
clean_installation() {
    log_action "Début nettoyage installation"

    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
        log_action "Suppression virtualenv $VENV_DIR"
    fi

    if [ -d "$WHISPER_CPP_DIR" ]; then
        rm -rf "$WHISPER_CPP_DIR"
        log_action "Suppression dossier whisper.cpp"
    fi

    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        log_action "Suppression ancien log"
    fi

    echo "Nettoyage terminé."
    show_actions
}

# Fonction de test
test_installation() {
    local audio_file="$1"

    if [ -z "$audio_file" ]; then
        echo "Erreur : fichier audio requis pour test"
        echo "Usage : $0 --test <fichier_audio>"
        exit 1
    fi

    if [ ! -f "$audio_file" ]; then
        echo "Erreur : fichier audio '$audio_file' introuvable"
        exit 1
    fi

    if [ ! -x "$BIN_PATH" ]; then
        echo "Erreur : binaire whisper-cli non trouvé. Lancez d'abord l'installation."
        exit 1
    fi

    echo "Test transcription avec whisper.cpp..."
    "$BIN_PATH" -f "$audio_file" -m models/ggml-base.bin

    echo ""
    echo "Test transcription avec Python whisper..."
    source "$VENV_DIR/bin/activate"
    whisper "$audio_file" --model base
    deactivate

    log_action "Test réussi avec fichier $audio_file"
}

# Parse arguments
case "${1:-}" in
    --help)
        show_help
        exit 0
        ;;
    --clean)
        clean_installation
        exit 0
        ;;
    --reinstall)
        clean_installation
        # Continue vers installation
        ;;
    --test)
        test_installation "$2"
        exit 0
        ;;
    "")
        # Installation normale
        ;;
    *)
        echo "Option inconnue : $1"
        show_help
        exit 1
        ;;
esac

# Début installation
log_action "Début installation whisper v1.5"

echo "1. Vérification prérequis système..."
command -v python3 >/dev/null 2>&1 || { echo "Erreur : python3 requis"; exit 1; }
command -v pip3 >/dev/null 2>&1 || { echo "Erreur : pip3 requis"; exit 1; }
command -v git >/dev/null 2>&1 || { echo "Erreur : git requis"; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "Erreur : cmake requis"; exit 1; }
command -v make >/dev/null 2>&1 || { echo "Erreur : make requis"; exit 1; }
log_action "Vérification prérequis terminée"

echo "2. Installation openai-whisper dans virtualenv..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    log_action "Création virtualenv $VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install openai-whisper
deactivate
log_action "Installation openai-whisper terminée"

echo "3. Clonage ou mise à jour whisper.cpp..."
if [ ! -d "$WHISPER_CPP_DIR" ]; then
    git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_CPP_DIR"
    log_action "Clonage whisper.cpp depuis GitHub"
else
    cd "$WHISPER_CPP_DIR"
    git pull --rebase
    cd -
    log_action "Mise à jour whisper.cpp"
fi

echo "4. Préparation dossier build..."
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
    log_action "Nettoyage ancien build"
fi
mkdir -p "$BUILD_DIR"
log_action "Création nouveau dossier build"

echo "5. Compilation whisper.cpp..."
cd "$BUILD_DIR"
cmake ..
make -j$(nproc)
cd -
log_action "Compilation whisper.cpp terminée"

echo "6. Vérification binaire whisper-cli..."
if [ ! -x "$BIN_PATH" ]; then
    echo "Erreur : binaire whisper-cli introuvable ($BIN_PATH)"
    exit 1
fi
log_action "Vérification binaire whisper-cli réussie"

echo "7. Téléchargement modèles de base..."
cd "$WHISPER_CPP_DIR"
if [ ! -d "models" ]; then
    mkdir models
fi
if [ ! -f "models/ggml-base.bin" ]; then
    bash models/download-ggml-model.sh base
    log_action "Téléchargement modèle base"
fi
cd -

echo ""
echo "=== INSTALLATION TERMINEE ==="
echo "Binaire whisper.cpp : $BIN_PATH"
echo "Virtualenv Python : $VENV_DIR"
echo "Modèles : $WHISPER_CPP_DIR/models/"
echo ""
echo "USAGE:"
echo "  Whisper.cpp : $BIN_PATH -f audio.wav -m $WHISPER_CPP_DIR/models/ggml-base.bin"
echo "  Python : source $VENV_DIR/bin/activate && whisper audio.wav"

show_actions
log_action "Installation complète terminée avec succès"

exit 0
