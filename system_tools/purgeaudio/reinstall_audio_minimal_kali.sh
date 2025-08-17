#!/bin/bash
# reinstall_audio_minimal_kali.sh
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Version : v1.0 - Date : 2025-08-12
# Changelog :
#   v1.0 - 2025-08-12 - Version initiale conforme règles v38
#
# Usage :
#   ./reinstall_audio_minimal_kali.sh --help
#
# Description :
#   Script pour réinstaller minimalement les paquets audio de Kali Linux
#   avec purge préalable et logs détaillés.
#
# Arguments :
#   --help       Affiche ce message d'aide et quitte
#   --exec       Lance la réinstallation minimale audio
#   --delete     Supprime proprement les paquets audio et fichiers liés
#
# Exemple :
#   ./reinstall_audio_minimal_kali.sh --exec

LOGFILE="$(dirname "$0")/log.reinstall_audio_minimal_kali.v1.0.log"

function log {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

function show_help {
    cat <<EOF
Usage: $0 [OPTIONS]

Options :
  --help      Affiche ce message d'aide
  --exec      Purge puis réinstalle minimalement les paquets audio
  --delete    Supprime proprement tous paquets et fichiers audio liés

Exemple :
  $0 --exec

EOF
}

function purge_audio {
    log "Début purge paquets audio"
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
        mpg123 parole pavucontrol pipewire pipewire-bin pipewire-pulse portaudio19-dev pulseaudio \
        pulseaudio-utils python3-pyaudio qml6-module-org-kde-pipewire recordmydesktop speech-dispatcher-audio-plugins \
        totem wireplumber xfce4-pulseaudio-plugin xmms2-plugin-alsa || {
            log "Erreur lors de la purge audio"
            exit 1
        }
    log "Purge audio terminée"
}

function reinstall_audio_minimal {
    log "Début réinstallation minimale audio"
    sudo apt-get update && sudo apt-get install -y \
        pulseaudio pavucontrol pipewire pipewire-pulse wireplumber || {
            log "Erreur lors de la réinstallation minimale"
            exit 2
        }
    log "Réinstallation minimale terminée"
}

function delete_all {
    log "Suppression complète et nettoyage audio"
    purge_audio
    log "Suppression complète terminée"
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
        purge_audio
        reinstall_audio_minimal
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
