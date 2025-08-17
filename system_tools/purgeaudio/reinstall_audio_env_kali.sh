#!/bin/bash
# reinstall_audio_env_kali.sh
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Version : v1.2 - Date : 2025-08-12
# Changelog :
#   v1.0 - Version initiale
#   v1.1 - Installation paquet par paquet + vérification paquets cassés
#   v1.2 - Purge audio sélective pour éviter les conflits de dépendances

LOGFILE="$(dirname "$0")/log.reinstall_audio_env_kali.v1.2.log"

function log {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

function show_help {
    cat <<EOF
Usage: $0 [OPTIONS]

Options :
  --help      Affiche ce message d'aide
  --exec      Purge sélective puis réinstalle l'environnement audio
  --delete    Supprime proprement les paquets audio non critiques

Exemple :
  $0 --exec

EOF
}

function purge_audio_safe {
    log "Début purge audio sélective (sans dépendances critiques)"
    sudo apt-get purge -y \
        libcdparanoia0 libchromaprint1 libecore-audio1 libfaad2 libflac++11 libflac14 \
        libgavl2 libges-1.0-0 libgstreamer-gl1.0-0 libgstreamer-plugins-bad1.0-0 \
        libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libgtk-4-media-gstreamer \
        libgupnp-av-1.0-3 libjack-jackd2-0 libjack-jackd2-dev libkf6pulseaudioqt5 \
        libkpipewire-data libkpipewire6 libkpipewiredmabuf6 libkpipewirerecord6 libmad0 \
        libmatroska7 libmpg123-0t64 libopenal1 libopusfile0 libout123-0t64 libpcaudio0 \
        libpipewire-0.3-0t64 libpipewire-0.3-common libpipewire-0.3-modules libportaudio2 \
        libportaudiocpp0 libpulse-dev libpulse-mainloop-glib0 libpulse0 libpulsedsp \
        libqt5multimediagsttools5 libroc0.4 librtaudio7 librubberband2 libsamplerate0 \
        libsndfile1 libsndio7.0 libsox-fmt-alsa libsox-fmt-base libsox3 libsoxr0 \
        libspatialaudio0t64 libswresample5 libsyn123-0t64 libtag-c2 libtag2 libtwolame0 \
        libvisual-0.4-0 libvorbis0a libvorbisenc2 libvorbisfile3 libwavpack1 libwebrtc-audio-processing-1-3 \
        mpg123 python3-pyaudio qml6-module-org-kde-pipewire speech-dispatcher-audio-plugins \
        xmms2-plugin-alsa || {
            log "Erreur lors de la purge audio sélective"
            exit 1
        }
    log "Purge audio sélective terminée"
}

function reinstall_audio_env {
    log "Vérification des paquets cassés"
    if ! sudo apt-get check; then
        log "Des paquets cassés ont été détectés. Veuillez corriger avant de poursuivre."
        exit 3
    fi

    log "Début réinstallation complète audio"

    PACKAGES=(
        kali-desktop-xfce
        pavucontrol
        pulseaudio
        pipewire
        pipewire-pulse
        wireplumber
        parole
        totem
        recordmydesktop
    )

    FAILED_PKGS=()

    for pkg in "${PACKAGES[@]}"; do
        log "Installation de $pkg"
        if sudo apt-get install -y "$pkg"; then
            log "✅ Installation réussie : $pkg"
        else
            log "❌ Échec de l'installation : $pkg"
            FAILED_PKGS+=("$pkg")
        fi
    done

    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        log "⚠️ Les paquets suivants n'ont pas pu être installés : ${FAILED_PKGS[*]}"
        exit 4
    fi

    log "Réinstallation complète terminée"
}

function delete_all {
    log "Suppression audio non critique"
    purge_audio_safe
    log "Suppression terminée"
}

if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

case "$1" in
    --help)
        show_help
        ;;
    --exec)
        purge_audio_safe
        reinstall_audio_env
        ;;
    --delete)
        delete_all
        ;;
    *)
        echo "Option inconnue: $1"
        show_help
        exit 1
        ;;
esac

log "Script terminé"
exit 0

