#!/bin/bash
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Version : v1.1 - Date : 2025-07-16

LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/ovos_$(date +%Y%m%d_%H%M%S).log"

OVOS_ENV_DIR="./ovos-env"
OVOS_CORE="$OVOS_ENV_DIR/bin/ovos-core"
OVOS_LISTEN="$OVOS_ENV_DIR/bin/ovos-listen"
PORT=8181

usage() {
  cat << EOF
Usage: $0 {start|stop|status|delete|--help}

Actions :
  start   - Démarre ovos-core et ovos-listen
  stop    - Arrête ovos-core et ovos-listen
  status  - Vérifie si ovos-core et ovos-listen tournent
  delete  - Supprime proprement les logs et arrête les services

Options :
  --help  - Affiche ce message d'aide

Exemple :
  $0 start
EOF
}

check_prereq() {
  if [ ! -x "$OVOS_CORE" ] || [ ! -x "$OVOS_LISTEN" ]; then
    echo "[!] Fichiers exécutables manquants ou non accessibles." | tee -a "$LOG_FILE"
    exit 1
  fi
}

check_port() {
  if ss -tln | grep -q ":$PORT "; then
    echo "[+] Port $PORT OK." | tee -a "$LOG_FILE"
    return 0
  else
    echo "[!] Port $PORT KO." | tee -a "$LOG_FILE"
    return 1
  fi
}

start_services() {
  echo "[+] Démarrage d'OVOS..." | tee -a "$LOG_FILE"
  check_port
  if [ $? -ne 0 ]; then
    echo "[!] Port $PORT occupé, impossible de démarrer." | tee -a "$LOG_FILE"
    exit 1
  fi

  nohup "$OVOS_CORE" > "$LOG_DIR/ovos-core.log" 2>&1 &
  sleep 1
  echo "[+] ovos-core démarré." | tee -a "$LOG_FILE"

  nohup "$OVOS_LISTEN" > "$LOG_DIR/ovos-listen.log" 2>&1 &
  sleep 1
  echo "[+] ovos-listen démarré." | tee -a "$LOG_FILE"

  echo -e "Actions effectuées :\n1. Vérification port $PORT\n2. Démarrage ovos-core\n3. Démarrage ovos-listen" | tee -a "$LOG_FILE"
}

stop_services() {
  echo "[+] Arrêt d'OVOS..." | tee -a "$LOG_FILE"
  pkill -f "$OVOS_CORE"
  pkill -f "$OVOS_LISTEN"
  echo "[+] Services arrêtés." | tee -a "$LOG_FILE"
  echo "Actions effectuées : 1. Arrêt ovos-core et ovos-listen" | tee -a "$LOG_FILE"
}

status_services() {
  echo "[+] Vérification du statut d'OVOS..." | tee -a "$LOG_FILE"
  pgrep -f "$OVOS_CORE" >/dev/null && echo "[+] ovos-core est en cours d'exécution." | tee -a "$LOG_FILE" || echo "[!] ovos-core n'est pas lancé." | tee -a "$LOG_FILE"
  pgrep -f "$OVOS_LISTEN" >/dev/null && echo "[+] ovos-listen est en cours d'exécution." | tee -a "$LOG_FILE" || echo "[!] ovos-listen n'est pas lancé." | tee -a "$LOG_FILE"
  echo "Actions effectuées : 1. Vérification du statut ovos-core et ovos-listen" | tee -a "$LOG_FILE"
}

delete_services() {
  stop_services
  echo "[+] Suppression des logs..." | tee -a "$LOG_FILE"
  rm -f "$LOG_DIR"/ovos-*.log
  echo "[+] Logs supprimés." | tee -a "$LOG_FILE"
  echo "Actions effectuées : 1. Arrêt services 2. Suppression logs" | tee -a "$LOG_FILE"
}

# Création dossier logs si absent
mkdir -p "$LOG_DIR"

if [ $# -eq 0 ]; then
  usage
  exit 0
fi

case "$1" in
  start)
    check_prereq
    start_services
    ;;
  stop)
    stop_services
    ;;
  status)
    status_services
    ;;
  delete)
    delete_services
    ;;
  --help)
    usage
    ;;
  *)
    echo "[!] Option invalide : $1"
    usage
    exit 1
    ;;
esac
