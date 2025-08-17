#!/bin/bash
# Auteur: Bruno Delnoz - bruno.delnoz@protonmail.com
# Version corrigée avec meilleure gestion d'erreurs

set -e

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Fonction d'affichage avec couleurs
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fonction de nettoyage en cas d'erreur
cleanup() {
    log_error "Une erreur s'est produite. Nettoyage..."
    if [ -n "$VIRTUAL_ENV" ]; then
        deactivate 2>/dev/null || true
    fi
    exit 1
}

trap cleanup ERR

log_info "=== INSTALLATION OVOS SUR KALI ==="

# Vérifier privilèges root
if [ "$EUID" -ne 0 ]; then
    log_error "Ce script doit être lancé en root."
    echo "Utilisation: sudo $0"
    exit 1
fi

# Détecter l'utilisateur réel (pas root)
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "nox")}
USER_HOME="/home/$REAL_USER"

log_info "Installation pour l'utilisateur: $REAL_USER"
log_info "Répertoire home: $USER_HOME"

# Vérifier que l'utilisateur existe
if ! id "$REAL_USER" &>/dev/null; then
    log_error "L'utilisateur '$REAL_USER' n'existe pas."
    read -p "Voulez-vous créer cet utilisateur ? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        adduser "$REAL_USER"
        USER_HOME="/home/$REAL_USER"
    else
        log_error "Installation annulée."
        exit 1
    fi
fi

# Vérifier que le répertoire home existe
if [ ! -d "$USER_HOME" ]; then
    log_error "Le répertoire home '$USER_HOME' n'existe pas."
    exit 1
fi

log_info "Mise à jour des paquets..."
apt update || {
    log_error "Échec de la mise à jour des paquets"
    exit 1
}

log_info "Installation des dépendances système..."
apt install -y \
    python3 \
    python3-venv \
    python3-pip \
    python3-dev \
    build-essential \
    swig \
    libfann-dev \
    portaudio19-dev \
    libpulse-dev \
    libffi-dev \
    libssl-dev \
    libasound2-dev \
    git \
    wget \
    cmake \
    pkg-config \
    libjpeg-dev \
    zlib1g-dev || {
    log_error "Échec de l'installation des dépendances système"
    exit 1
}

log_info "Création de l'environnement Python..."
cd "$USER_HOME" || {
    log_error "Impossible d'accéder au répertoire $USER_HOME"
    exit 1
}

# Supprimer l'ancien environnement s'il existe
if [ -d "ovos-env" ]; then
    log_warn "Suppression de l'ancien environnement..."
    rm -rf ovos-env
fi

# Créer l'environnement virtuel
sudo -u "$REAL_USER" python3 -m venv ovos-env || {
    log_error "Échec de la création de l'environnement virtuel"
    exit 1
}

# Activer l'environnement
source ovos-env/bin/activate || {
    log_error "Échec de l'activation de l'environnement virtuel"
    exit 1
}

log_info "Mise à jour de pip..."
pip install --upgrade pip setuptools wheel || {
    log_error "Échec de la mise à jour de pip"
    exit 1
}

log_info "Installation d'OVOS - Étape 1: Core packages..."
pip install ovos-core || {
    log_error "Échec de l'installation d'ovos-core"
    exit 1
}

log_info "Installation d'OVOS - Étape 2: Plugin manager..."
pip install ovos-plugin-manager || {
    log_error "Échec de l'installation d'ovos-plugin-manager"
    exit 1
}

log_info "Installation d'OVOS - Étape 3: Plugins essentiels..."
pip install \
    ovos-plugin-audio \
    ovos-plugin-tts \
    ovos-plugin-listener \
    ovos-plugin-skill || {
    log_warn "Certains plugins ont échoué, continuation..."
}

log_info "Installation d'OVOS - Étape 4: Configuration..."
pip install ovos-config || {
    log_error "Échec de l'installation d'ovos-config"
    exit 1
}

# Désactiver l'environnement temporairement
deactivate

log_info "Création du lanceur desktop..."
DESKTOP_DIR="$USER_HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/ovos.desktop" << EOF
[Desktop Entry]
Type=Application
Name=Lancer OVOS
Comment=Assistant vocal Open Voice Operating System
Exec=gnome-terminal -- bash -c "cd $USER_HOME && source ovos-env/bin/activate && ovos-listen; exec bash"
Icon=utilities-terminal
Terminal=false
Categories=Utility;Audio;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR/ovos.desktop"
chown "$REAL_USER:$REAL_USER" "$DESKTOP_DIR/ovos.desktop"

# Créer un script de lancement simple
cat > "$USER_HOME/start-ovos.sh" << EOF
#!/bin/bash
cd "$USER_HOME"
source ovos-env/bin/activate
ovos-listen
EOF

chmod +x "$USER_HOME/start-ovos.sh"
chown "$REAL_USER:$REAL_USER" "$USER_HOME/start-ovos.sh"

# Changer les permissions de l'environnement
chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/ovos-env"

log_info "Configuration initiale d'OVOS..."
sudo -u "$REAL_USER" bash -c "cd $USER_HOME && source ovos-env/bin/activate && ovos-config setup" || {
    log_warn "Configuration automatique échouée, vous devrez configurer manuellement"
}

log_info "Installation terminée avec succès !"
echo ""
log_info "Pour lancer OVOS:"
echo "  - Double-cliquez sur le lanceur: $DESKTOP_DIR/ovos.desktop"
echo "  - Ou utilisez le script: $USER_HOME/start-ovos.sh"
echo "  - Ou manuellement: cd $USER_HOME && source ovos-env/bin/activate && ovos-listen"
echo ""
log_info "Pour configurer OVOS:"
echo "  - Lancez: cd $USER_HOME && source ovos-env/bin/activate && ovos-config"
echo ""
log_warn "Note: Au premier lancement, OVOS pourrait télécharger des modèles supplémentaires."
