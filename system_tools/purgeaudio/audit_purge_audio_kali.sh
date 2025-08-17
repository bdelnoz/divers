#!/bin/bash
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
# Nom du script : purge_audio_complet.sh
# Target usage : Purger totalement audio + modules kernel, avec backup pour restauration
# Version : v1.0 - Date : 2025-08-12
# Changelog :
# v1.0 - Purge totale audio, suppression modules kernel audio avec backup

set -e

LOGFILE="$(dirname "$0")/log.purge_audio_complet.v1.0.log"
BACKUPDIR="$(dirname "$0")/backup_audio_$(date +%Y%m%d_%H%M%S)"

print_help() {
  cat <<EOF
Usage : $0 [--exec | --restore | --help]

--exec    : Exécute la purge complète audio + modules kernel (avec confirmation)
--restore : Restaure paquets audio et modules kernel (après backup purge)
--help    : Affiche cette aide

Exemples :
  $0 --exec
  $0 --restore
EOF
}

backup_modules() {
  echo "Création du dossier de backup : $BACKUPDIR" | tee -a "$LOGFILE"
  mkdir -p "$BACKUPDIR"
  # Backup blacklist audio modules si existant
  if [ -f /etc/modprobe.d/blacklist-audio.conf ]; then
    cp /etc/modprobe.d/blacklist-audio.conf "$BACKUPDIR/"
    echo "Backup blacklist-audio.conf effectué." | tee -a "$LOGFILE"
  fi
  # Backup modules kernel audio existants (liste)
  echo "Backup des modules kernel audio existants dans $BACKUPDIR/modules_list.txt" | tee -a "$LOGFILE"
  lsmod | grep -iE 'snd|audio|pulse|alsa|jack|oss' > "$BACKUPDIR/modules_list.txt"
}

purge_audio() {
  echo "Purge des paquets audio..." | tee -a "$LOGFILE"
  packages=(
    alsa-tools alsa-topology-conf alsa-ucm-conf alsa-utils audacity audacity-data firmware-intel-sound
    firmware-realtek flac gir1.2-gst-plugins-base-1.0:amd64 gir1.2-gstreamer-1.0:amd64 gstreamer1.0-gl:amd64
    gstreamer1.0-gtk3:amd64 gstreamer1.0-libav:amd64 gstreamer1.0-pipewire gstreamer1.0-plugins-bad:amd64
    gstreamer1.0-plugins-base:amd64 gstreamer1.0-plugins-good:amd64 gstreamer1.0-plugins-ugly:amd64
    gstreamer1.0-x:amd64 libao-common libao4:amd64 libasound2-data libasound2-dev:amd64 libasound2-plugins:amd64
    libasound2-plugins:i386 libasound2t64:amd64 libasound2t64:i386 libaudio2:amd64 libavcodec61:amd64
    libcanberra-gtk3-0:amd64 libcanberra-pulse:amd64 libchromaprint1:amd64 libfaad2:amd64 libflac14:amd64
    libgstreamer-gl1.0-0:amd64 libgstreamer-plugins-bad1.0-0:amd64 libgstreamer-plugins-base1.0-0:amd64
    libgstreamer1.0-0:amd64 libjack-jackd2-0:amd64 libmad0:amd64 libmpg123-0t64:amd64 libopenal1:amd64
    libpulse-dev:amd64 libpulse-mainloop-glib0:amd64 libpulse0:amd64 pavucontrol pipewire pipewire-pulse
    pulseaudio pulseaudio-utils python3-pyaudio sound-theme-freedesktop xfce4-pulseaudio-plugin:amd64
  )
  sudo apt-get purge -y "${packages[@]}" | tee -a "$LOGFILE"
  sudo apt-get autoremove -y | tee -a "$LOGFILE"

  echo "Suppression des fichiers de configuration audio..." | tee -a "$LOGFILE"
  sudo find /etc -type f \( -iname '*pulse*' -o -iname '*alsa*' -o -iname '*audio*' \) -exec rm -f {} + | tee -a "$LOGFILE"
  sudo find "$HOME" -type f \( -iname '*pulse*' -o -iname '*alsa*' -o -iname '*audio*' \) -exec rm -f {} + | tee -a "$LOGFILE"
}

disable_modules() {
  echo "Désactivation des modules kernel audio..." | tee -a "$LOGFILE"
  backup_modules

  blacklist_file="/etc/modprobe.d/blacklist-audio.conf"
  echo -e "# Blacklist audio kernel modules - généré par purge_audio_complet.sh\nblacklist snd\nblacklist snd_pcm\nblacklist snd_timer\nblacklist snd_seq\nblacklist snd_hwdep\nblacklist snd_seq_device\nblacklist snd_seq_midi\nblacklist snd_seq_midi_event\nblacklist snd_usb_audio\nblacklist snd_hda_intel\nblacklist snd_hda_codec\nblacklist snd_soc_core\nblacklist snd_soc_skl\nblacklist snd_soc_skl_ipc\nblacklist snd_soc_sst_ipc\nblacklist snd_sof_pci\nblacklist snd_sof_intel_byt\nblacklist snd_sof_intel_hda_common\nblacklist snd_sof_intel_ipc\nblacklist snd_sof_xtensa\nblacklist snd_sof\nblacklist snd_aloop\nblacklist snd_virmidi\nblacklist snd_mixer_oss\nblacklist snd_pcm_oss\nblacklist snd_seq_oss\nblacklist snd_timer\nblacklist soundcore" | sudo tee "$blacklist_file" > /dev/null

  echo "Suppression des modules kernel audio présents..." | tee -a "$LOGFILE"
  for mod in snd snd_pcm snd_timer snd_seq snd_hwdep snd_seq_device snd_seq_midi snd_seq_midi_event snd_usb_audio snd_hda_intel snd_hda_codec; do
    sudo modprobe -r "$mod" 2>/dev/null || true
  done
}

main() {
  if [ $# -eq 0 ]; then
    print_help
    exit 0
  fi

  case "$1" in
    --exec)
      echo "CONFIRMATION : Cette action va supprimer TOUT ce qui concerne l'audio, y compris modules kernel."
      read -rp "Êtes-vous sûr de vouloir continuer ? (oui/non) : " conf
      if [[ "$conf" != "oui" ]]; then
        echo "Abandon."
        exit 0
      fi
      purge_audio
      disable_modules
      echo "Purge complète terminée. Veuillez redémarrer votre système."
      ;;
    --restore)
      echo "Restauration des paquets audio et modules kernel audio."
      sudo apt-get update
      sudo apt-get install -y alsa-tools alsa-topology-conf alsa-ucm-conf alsa-utils audacity audacity-data firmware-intel-sound firmware-realtek flac gir1.2-gst-plugins-base-1.0 gstreamer1.0-gl gstreamer1.0-gtk3 gstreamer1.0-libav gstreamer1.0-pipewire gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly gstreamer1.0-x libao-common libao4 libasound2-data libasound2-dev libasound2-plugins libaudio2 libavcodec61 libcanberra-gtk3-0 libcanberra-pulse libchromaprint1 libfaad2 libflac14 libgstreamer-gl1.0-0 libgstreamer-plugins-bad1.0-0 libgstreamer-plugins-base1.0-0 libgstreamer1.0-0 libjack-jackd2-0 libmad0 libmpg123-0t64 libopenal1 libpulse-dev libpulse-mainloop-glib0 libpulse0 pavucontrol pipewire pipewire-pulse pulseaudio pulseaudio-utils python3-pyaudio sound-theme-freedesktop xfce4-pulseaudio-plugin
      if [ -f "$BACKUPDIR/blacklist-audio.conf" ]; then
        sudo cp "$BACKUPDIR/blacklist-audio.conf" /etc/modprobe.d/
        echo "Blacklist restaurée depuis backup." | tee -a "$LOGFILE"
      else
        sudo rm -f /etc/modprobe.d/blacklist-audio.conf
        echo "Blacklist supprimée (pas de backup trouvé)." | tee -a "$LOGFILE"
      fi
      echo "Modules kernel audio réactivés (redémarrez)."
      ;;
    --help)
      print_help
      ;;
    *)
      echo "Argument inconnu : $1"
      print_help
      exit 1
      ;;
  esac
}

main "$@"

exit 0
