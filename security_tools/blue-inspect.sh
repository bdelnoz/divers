#!/bin/bash

usage() {
  echo "Usage: $0 [options]"
  echo "Options:"
  echo "  --help          Affiche ce message"
  echo "  --dry-run       Montre ce qui serait fait sans rien appliquer"
  echo "  --force         Applique sans confirmation"
  echo "  --clean         Supprime fichiers et caches Bluetooth"
  echo "  --block         Blackliste les modules Bluetooth"
  echo "  --stop          Stop et désactive les services Bluetooth"
  echo "  --remove        Désinstalle les paquets Bluetooth"
  echo "  --hold          Empêche la réinstallation par update"
  echo "  --all           Lance toutes les actions"
  echo ""
  echo "Exemple:"
  echo "  $0 --all --force"
}

DRY_RUN=0
FORCE=0
STOP=0
BLOCK=0
REMOVE=0
CLEAN=0
HOLD=0

if [ $# -eq 0 ]; then
  usage
  exit 1
fi

for arg in "$@"; do
  case $arg in
    --help) usage; exit 0 ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    --stop) STOP=1 ;;
    --block) BLOCK=1 ;;
    --remove) REMOVE=1 ;;
    --clean) CLEAN=1 ;;
    --hold) HOLD=1 ;;
    --all)
      STOP=1
      BLOCK=1
      REMOVE=1
      CLEAN=1
      HOLD=1
      ;;
    *) echo "Option inconnue: $arg"; usage; exit 1 ;;
  esac
done

confirm() {
  if [ $FORCE -eq 1 ]; then
    return 0
  fi
  read -p "$1 (y/N) " answer
  case "$answer" in
    [Yy]*) return 0 ;;
    *) echo "Annulé."; exit 1 ;;
  esac
}

run_cmd() {
  echo "+ $*"
  if [ $DRY_RUN -eq 0 ]; then
    eval "$@"
  fi
}

if [ $STOP -eq 1 ]; then
  confirm "Arrêter et désactiver les services Bluetooth ?"
  run_cmd "sudo systemctl stop bluetooth.service bluetooth.target"
  run_cmd "sudo systemctl disable bluetooth.service bluetooth.target"
fi

if [ $BLOCK -eq 1 ]; then
  confirm "Blacklister les modules Bluetooth ?"
  run_cmd "echo -e 'blacklist btusb\nblacklist bluetooth\nblacklist btrtl\nblacklist btintel\nblacklist btbcm\nblacklist hci_uart' | sudo tee /etc/modprobe.d/blacklist-bluetooth.conf"
  run_cmd "sudo update-initramfs -u"
fi

if [ $REMOVE -eq 1 ]; then
  confirm "Désinstaller les paquets Bluetooth ?"
  run_cmd "sudo apt-get purge -y bluez bluetooth"
fi

if [ $CLEAN -eq 1 ]; then
  confirm "Supprimer les fichiers et caches Bluetooth ?"
  run_cmd "sudo rm -rf /etc/bluetooth /var/lib/bluetooth /var/cache/bluetooth"
fi

if [ $HOLD -eq 1 ]; then
  confirm "Bloquer la réinstallation des paquets Bluetooth via mise à jour ?"
  run_cmd "sudo apt-mark hold bluez bluetooth"
fi

echo "Terminé."
