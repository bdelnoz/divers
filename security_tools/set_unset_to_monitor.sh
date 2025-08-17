#!/bin/bash

show_help() {
  cat << EOF
Usage: $0 [interface] [action]

Arguments :
  interface  Interface réseau sans fil (par défaut wlan0). Doit être de la forme wlanX.
  action     set   : passer l'interface en mode monitor (exclure de NetworkManager)
             unset : remettre l'interface en mode managed (réintégrer dans NetworkManager)
  -h, --help Affiche ce message d'aide.

Exemples :
  $0                 # remet wlan0 en mode managed (unset)
  $0 wlan1 set       # passe wlan1 en mode monitor
  $0 wlan2 unset     # remet wlan2 en mode managed
EOF
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  show_help
  exit 0
fi

IFACE=${1:-wlan0}
ACTION=${2:-unset}

if [[ ! $IFACE =~ ^wlan[0-9]+$ ]]; then
  echo "[!] Interface invalide : $IFACE (doit être wlanX)"
  exit 1
fi

if [[ "$ACTION" != "set" && "$ACTION" != "unset" ]]; then
  echo "[!] Action invalide : $ACTION (doit être 'set' ou 'unset')"
  exit 1
fi

if [ "$ACTION" == "set" ]; then
  echo "[*] Exclusion de $IFACE de NetworkManager..."
  sudo nmcli device set $IFACE managed no || { echo "[!] Impossible d'exclure $IFACE de NetworkManager"; exit 1; }

  echo "[*] Passage de $IFACE en mode monitor..."
  sudo ip link set $IFACE down || { echo "[!] Impossible de mettre $IFACE down"; exit 1; }
  sudo iw dev $IFACE set type monitor || { echo "[!] Échec du passage en mode monitor"; exit 1; }
  sudo ip link set $IFACE up || { echo "[!] Impossible de remettre $IFACE up"; exit 1; }
  echo "[*] Interface $IFACE en mode monitor et up."

elif [ "$ACTION" == "unset" ]; then
  echo "[*] Remise de $IFACE en mode managed..."
  sudo ip link set $IFACE down || { echo "[!] Impossible de mettre $IFACE down"; exit 1; }
  sudo iw dev $IFACE set type managed || { echo "[!] Échec du passage en mode managed"; exit 1; }
  sudo ip link set $IFACE up || { echo "[!] Impossible de remettre $IFACE up"; exit 1; }

  echo "[*] Réintégration de $IFACE dans NetworkManager..."
  sudo nmcli device set $IFACE managed yes || echo "[!] nmcli device set managed yes a échoué"
  sleep 5
  sudo nmcli device reapply $IFACE || echo "[!] nmcli device reapply a échoué"

  echo "[*] Redémarrage de NetworkManager pour forcer la détection..."
  sudo systemctl restart NetworkManager || { echo "[!] Impossible de redémarrer NetworkManager"; exit 1; }

  echo "[*] Interface $IFACE en mode managed et gérée par NetworkManager."
fi

