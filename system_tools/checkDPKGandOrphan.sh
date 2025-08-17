#!/bin/bash
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : checkDPKGandOrphan.sh
# Target usage : Vérifie paquets installés, orphelins, HI, analyse risques paquets HI, gestion backups, suppression propre
# Version : v29 - Date : 2025-07-17

# Variables globales
SCRIPT_NAME="checkDPKGandOrphan.sh"
BACKUP_DIR="./${SCRIPT_NAME}_backups"
LOG_FILE="${SCRIPT_NAME}.log"
ADV_LOG_FILE="${SCRIPT_NAME}_advanced.log"
MAX_BACKUPS=5
USER_OWNER=$(id -un)
DATE_NOW=$(date +%Y%m%d%H%M%S)

# Couleurs pour affichage avancé
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color
SEP_LINE="--------------------------------------------------"

# Fonction d'affichage usage
usage() {
  cat <<EOF
Usage: sudo ./$SCRIPT_NAME [--help] [--exec] [--advanced] [--delete] [--deletebck]

Options :
 --help       Affiche ce message
 --exec       Lance l'analyse basique et affiche résumé + logs
 --advanced   Analyse approfondie des paquets HI, évalue le risque, génère log détaillé
 --delete     Supprime proprement les paquets orphelins détectés
 --deletebck  Supprime proprement les backups créés par le script

Exemples :
  sudo ./$SCRIPT_NAME --exec
  sudo ./$SCRIPT_NAME --advanced
  sudo ./$SCRIPT_NAME --delete
  sudo ./$SCRIPT_NAME --deletebck
EOF
}

# Fonction création backup état actuel
backup_state() {
  mkdir -p "$BACKUP_DIR" || { echo "Erreur création backup dir"; exit 1; }
  BACKUP_FILE="${BACKUP_DIR}/${SCRIPT_NAME}_backup_${DATE_NOW}.txt"
  dpkg --get-selections > "$BACKUP_FILE" || { echo "Erreur backup dpkg selections"; exit 1; }
  prune_backups
}

# Fonction suppression backups anciens au-delà de MAX_BACKUPS
prune_backups() {
  local files=($(ls -1t "$BACKUP_DIR"/${SCRIPT_NAME}_backup_*.txt 2>/dev/null))
  local count=${#files[@]}
  if (( count > MAX_BACKUPS )); then
    for ((i=MAX_BACKUPS; i<count; i++)); do
      rm -f "${files[i]}"
    done
  fi
}

# Récupération paquets installés, orphelins, HI
get_packages() {
  dpkg --get-selections > installed.txt
  apt-get autoremove --dry-run | grep "^Remv" | awk '{print $2}' > orphan.txt
  dpkg -l | awk '/^hi/{print $2}' > hi.txt
}

# Analyse des paquets HI avec description et estimation risque
analyse_hi() {
  if [[ ! -s hi.txt ]]; then
    echo "Aucun paquet HI détecté."
    return 1
  fi

  declare -A PAQ_RISQUE=(
    ["bluez-firmware"]="MOYEN"
    ["bluez-hcidump"]="MOYEN"
    ["bluez-obexd"]="MOYEN"
    ["gir1.2-gnomebluetooth-3.0"]="ÉLEVÉ"
    ["gnome-bluetooth-3-common"]="ÉLEVÉ"
    ["kismet-capture-linux-bluetooth"]="ÉLEVÉ"
    ["libbluetooth3"]="ÉLEVÉ"
    ["libbtbb1"]="MOYEN"
    ["libgnome-bluetooth-3.0-13"]="ÉLEVÉ"
    ["libgnome-bluetooth-ui-3.0-13"]="ÉLEVÉ"
    ["libkf6bluezqt-data"]="MOYEN"
    ["libkf6bluezqt6"]="MOYEN"
    ["libldacbt-abr2"]="MOYEN"
    ["libldacbt-enc2"]="MOYEN"
    ["libqt6bluetooth6"]="ÉLEVÉ"
    ["libqt6bluetooth6-bin"]="ÉLEVÉ"
    ["libspa-0.2-bluetooth"]="ÉLEVÉ"
    ["libubertooth1"]="MOYEN"
    ["python3-bluepy"]="MOYEN"
    ["qml6-module-org-kde-bluezqt"]="MOYEN"
  )

  HI_PAQUETS=()
  for pkg in $(cat hi.txt); do
    HI_PAQUETS+=("$pkg")
  done

  declare -a RISQUE_ELEVE=()
  declare -a RISQUE_MOYEN=()
  declare -a RISQUE_FAIBLE=()

  for pkg in "${HI_PAQUETS[@]}"; do
    risque=${PAQ_RISQUE[$pkg]:-"FAIBLE"}
    case "$risque" in
      "ÉLEVÉ") RISQUE_ELEVE+=("$pkg") ;;
      "MOYEN") RISQUE_MOYEN+=("$pkg") ;;
      *) RISQUE_FAIBLE+=("$pkg") ;;
    esac
  done

  echo -e "${RED}${SEP_LINE}${NC}"
  echo -e "${RED}PAQUETS HI À RISQUE ÉLEVÉ${NC}"
  echo -e "${RED}${SEP_LINE}${NC}"
  for p in "${RISQUE_ELEVE[@]}"; do
    desc=$(apt-cache show "$p" 2>/dev/null | grep -m1 '^Description:' | cut -d' ' -f2-)
    echo -e "${RED}- $p : Description: $desc / Risque: ÉLEVÉ${NC}"
  done

  echo -e "\n${SEP_LINE}\n"

  echo -e "${YELLOW}${SEP_LINE}${NC}"
  echo -e "${YELLOW}PAQUETS HI À RISQUE MOYEN${NC}"
  echo -e "${YELLOW}${SEP_LINE}${NC}"
  for p in "${RISQUE_MOYEN[@]}"; do
    desc=$(apt-cache show "$p" 2>/dev/null | grep -m1 '^Description:' | cut -d' ' -f2-)
    echo -e "${YELLOW}- $p : Description: $desc / Risque: MOYEN${NC}"
  done

  echo -e "\n${SEP_LINE}\n"

  echo -e "PAQUETS HI À RISQUE FAIBLE"
  echo -e "${SEP_LINE}"
  for p in "${RISQUE_FAIBLE[@]}"; do
    desc=$(apt-cache show "$p" 2>/dev/null | grep -m1 '^Description:' | cut -d' ' -f2-)
    echo "- $p : Description: $desc / Risque: FAIBLE"
  done
}

# Fonction nettoyage paquets orphelins --delete
clean_orphans() {
  if [[ -s orphan.txt ]]; then
    echo "Suppression des paquets orphelins listés dans orphan.txt..."
    xargs -a orphan.txt apt-get -y purge
  else
    echo "Aucun paquet orphelin détecté."
  fi
}

# Suppression propre des backups --deletebck
clean_backups() {
  if [[ -d "$BACKUP_DIR" ]]; then
    rm -rf "$BACKUP_DIR"
    echo "Backups supprimés dans $BACKUP_DIR"
  else
    echo "Aucun backup trouvé."
  fi
}

# Fonction d'exécution principale --exec
run_exec() {
  echo "Démarrage du script $SCRIPT_NAME"
  echo "Log principal: $LOG_FILE"
  echo "Log avancé: $ADV_LOG_FILE"
  echo

  backup_state
  echo "[1] Sauvegarde de l'état actuel effectuée." | tee -a "$LOG_FILE"

  get_packages
  echo "[2] Paquets installés, orphelins et HI listés." | tee -a "$LOG_FILE"

  INSTALLED_COUNT=$(wc -l < installed.txt)
  ORPHAN_COUNT=$(wc -l < orphan.txt)
  HI_COUNT=$(wc -l < hi.txt)

  echo -e "\nRésumé des paquets trouvés :"
  echo " - Paquets installés : $INSTALLED_COUNT"
  echo " - Paquets orphelins : $ORPHAN_COUNT"
  echo " - Paquets HI        : $HI_COUNT"
  echo "[3] Résumé affiché et log créé : $LOG_FILE" | tee -a "$LOG_FILE"

  echo "Fin du script."
}

# Fonction exécution avancée --advanced
run_advanced() {
  run_exec > /dev/null
  echo "[4] Analyse HI approfondie :" | tee -a "$ADV_LOG_FILE"
  analyse_hi | tee -a "$ADV_LOG_FILE"
}

# Gestion des arguments
case "$1" in
  --help|"")
    usage
    ;;
  --exec)
    run_exec
    ;;
  --advanced)
    run_advanced
    ;;
  --delete)
    get_packages
    clean_orphans
    ;;
  --deletebck)
    clean_backups
    ;;
  *)
    echo "Argument invalide."
    usage
    exit 1
    ;;
esac

# Forcer ownership final de tout le dossier
chown -R  nox:nox .

exit 0
