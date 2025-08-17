#!/bin/bash
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : detect_processus_suspects.sh
# Target usage : Liste tous les processus avec un score de dangerosité 1-5, log + csv
# Version : v1.2 - Date : 2025-08-08
# Changelog :
#   v1.2 (2025-08-08) : Ajout export CSV pour lisibilité

LOG_FILE="$(dirname "$0")/detect_processus_suspects.log"
CSV_FILE="$(dirname "$0")/detect_processus_suspects.csv"

BLACKLIST=("nc" "netcat" "ncat" "wget" "curl" "tcpdump" "nmap" "metasploit" "msfconsole" "python" "perl")

function usage() {
  cat << EOF
Usage : $0 --exec | --remove | --help

Options :
  --exec    : Lance l'analyse des processus avec dangerosité et export CSV
  --remove  : Supprime les fichiers log et csv générés
  --help    : Affiche ce message d'aide

Exemple :
  $0 --exec

Version du script : v1.2
EOF
}

function remove_logs() {
  rm -f "$LOG_FILE" "$CSV_FILE"
  echo "Logs supprimés."
}

function is_blacklisted() {
  local pname="$1"
  for item in "${BLACKLIST[@]}"; do
    if [[ "$pname" == *"$item"* ]]; then
      return 0
    fi
  done
  return 1
}

function exec_analysis() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Début analyse processus avec dangerosité" | tee "$LOG_FILE"

  ps -eo pid,user,uid,cmd --sort=uid > /tmp/all_procs.$$
  ss -tulnp 2>/dev/null | awk '/pid=/ {match($0,/pid=([0-9]+)/,a); print a[1]}' | sort -u > /tmp/pids_listen.$$

  # Entêtes CSV
  echo -e "Niveau\tPID\tUser\tUID\tDangerosité\tCommande" > "$CSV_FILE"

  echo -e "Niv\tPID\tUser\tUID\tDangerosité\tCmd" | tee -a "$LOG_FILE"

  while read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    user=$(echo "$line" | awk '{print $2}')
    uid=$(echo "$line" | awk '{print $3}')
    cmd=$(echo "$line" | cut -d' ' -f4-)

    danger=1
    [[ "$uid" -ge 1000 && "$user" != "root" ]] && ((danger+=1))
    grep -qw "$pid" /tmp/pids_listen.$$ && ((danger+=2))
    is_blacklisted "$cmd" && ((danger+=2))
    (( danger > 5 )) && danger=5

    line_out="$danger\t$pid\t$user\t$uid\t$danger\t$cmd"
    echo -e "$line_out" | tee -a "$LOG_FILE"
    echo -e "$line_out" >> "$CSV_FILE"

  done < /tmp/all_procs.$$

  rm -f /tmp/all_procs.$$ /tmp/pids_listen.$$

  echo "Analyse terminée." | tee -a "$LOG_FILE"
}

case "$1" in
  --exec)
    exec_analysis
    ;;
  --remove)
    remove_logs
    ;;
  --help|*)
    usage
    ;;
esac

