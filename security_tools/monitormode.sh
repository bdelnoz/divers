#!/bin/bash
set -e

if [ $# -ne 2 ]; then
  echo "Usage: $0 {setmon|unsetmon} interface"
  exit 1
fi

action=$1
iface=$2

if ! ip link show "$iface" &>/dev/null; then
  echo "Erreur : interface '$iface' inexistante."
  exit 2
fi

case $action in
  setmon)
    echo "[*] Passage de $iface en mode monitor"
    sudo ip link set "$iface" down
    sudo iw "$iface" set monitor control
    sudo ip link set "$iface" up
    ;;
  unsetmon)
    echo "[*] Retour de $iface en mode managed"
    sudo ip link set "$iface" down
    sudo iw "$iface" set type managed
    sudo ip link set "$iface" up
    ;;
  *)
    echo "Usage: $0 {setmon|unsetmon} interface"
    exit 3
    ;;
esac

echo "[*] Opération terminée sur $iface"

