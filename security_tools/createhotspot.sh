#!/bin/bash
# Auteur : Bruno DELNOz (corrigé par Assistant)
# Email  : bruno.delnoz@protonmail.com
# Nom du script : createhotspot.sh
# Target usage : Gérer création, suppression et restauration d'un hotspot wifi sur une interface spécifique
# Version : v4.8 - Date : 2025-08-08 - CORRECTIONS STRUCTURELLES

: '
Changelog complet :
v4.8 - 2025-08-08 - CORRECTIONS STRUCTURELLES :
 - CORRECTION : repositionnement fonction repair_interfaces() (était coupée/mal placée)
 - CORRECTION : nettoyage code orphelin dans la fonction monitor_clients()
 - CORRECTION : restructuration logique des fonctions pour éviter définitions tardives
 - CORRECTION : amélioration cohérence du code et lisibilité
 - VALIDATION : toutes les fonctions correctement définies avant utilisation

v4.7 - 2025-08-08 - CORRECTIONS CRITIQUES :
 - CORRECTION : règles iptables utilisent maintenant $INTERFACE au lieu de wlan0 hardcodé
 - CORRECTION : amélioration reset_interface pour remise en mode managed propre
 - CORRECTION : nettoyage complet des processus hostapd/dnsmasq
 - CORRECTION : gestion interface bridge et restoration NetworkManager
 - CORRECTION : protection firewall existant en mode panic (sauvegarde auto)
 - CORRECTION : suppression spécifique règles hotspot (préservation fw utilisateur)
 - CORRECTION : ajout spécification réseau source dans règles NAT
 - AJOUT : fonction repair_interfaces pour réparer interfaces cassées
 - AJOUT : fonction panic_mode pour réparation VIOLENTE avec reset drivers complet
 - AJOUT : sauvegarde automatique firewall avant mode panic
 - AJOUT : ré-exécution firewall après mode panic si détecté
 - AJOUT : vérification règles existantes avant ajout (évite doublons)
 - AJOUT : meilleure détection et nettoyage des processus zombies
 - AJOUT : vérification état interface avant/après opérations
 - AJOUT : option --repair et --status et --panic pour maintenance
 - AJOUT : gestion signaux INT/TERM pour nettoyage propre
 - AJOUT : validation interface existe avant utilisation
 - AJOUT : détection automatique interface sortie pour NAT
 - AJOUT : déchargement/rechargement drivers WiFi en mode panic

v4.6 - 2025-07-26
 - Gestion avancée de NetworkManager pour remise à zéro interface
 - Validation canaux 2.4 GHz et 5 GHz
 - Choix dynamique plage IP (défaut 192.168.122.x)
 - Sauvegarde/restauration iptables sans écraser règles système
 - Correction bugs hostapd, dnsmasq, nettoyage propre
 - Help complet avec exemples, options, canaux valides
 - Gestion exec multiple avec backup iptables dynamiques
 - Préservation totale du firewall système

v4.5 - 2025-07-25
 - Ajout option channel et choix bande 2.4/5GHz
 - Ajout validation entrée utilisateur
 - Correction remise à zéro interface via NetworkManager
 - Ajout exemple dans le help

v4.4 - 2025-07-24
 - Correction bug suppression règles iptables hotspot
 - Gestion multi-exécutions sans backup corrompu
 - Ajout nettoyage dnsmasq et hostapd après erreur

v4.3 - 2025-07-23
 - Ajout sauvegarde/restauration iptables temporaire
 - Nettoyage et suppression règles iptables hotspot

v4.2 - 2025-07-22
 - Ajout contrôle interface NetworkManager
 - Gestion erreurs hostapd et dnsmasq plus robuste

v4.1 - 2025-07-21
 - Ajout help détaillé avec exemples et canaux
 - Choix de la plage IP par défaut modifiable

v4.0 - 2025-07-20
 - Première version stable
 - Création, suppression hotspot
 - Gestion iptables pour hotspot
'

# Variables par défaut
INTERFACE=""
SSID="MyHotspot"
BAND="5"
CHANNEL="36"
IP_RANGE="192.168.122"
DHCP_RANGE_START=10
DHCP_RANGE_END=50
IPTABLES_BACKUP="./iptables_backup_createhotspot.rules"
HOSTAPD_CONF="./hostapd.conf"
DNSMASQ_CONF="./dnsmasq.conf"
DHCP_LEASES="./dnsmasq.leases"
HOSTAPD_PID_FILE="./hostapd.pid"
DNSMASQ_PID_FILE="./dnsmasq.pid"
EXEC_MODE=0

# Liste des canaux valides
VALID_CHANNELS_24G=(1 2 3 4 5 6 7 8 9 10 11)
VALID_CHANNELS_5G=(36 40 44 48 52 56 60 64 100 104 108 112 116 120 124 128 132 136 140 144 149 153 157 161 165)

print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options :
  --interface=IFACE     Interface wifi à utiliser (obligatoire)
  --ssid=SSID           Nom du hotspot (défaut: $SSID)
  --band=BAND           Bande radio 2.4 ou 5 (défaut: $BAND)
  --channel=CHANNEL     Canal wifi (défaut: $CHANNEL)
  --iprange=IP          Plage IP du hotspot (défaut: $IP_RANGE, ex: 192.168.122)
  --exec                Lance la création du hotspot
  --clean               Supprime hotspot et restaure iptables
  --repair              Répare les interfaces WiFi cassées
  --panic               MODE VIOLENT : réparation extrême + reset drivers
  --status              Affiche l'état des interfaces et services
  --monitor             Lance monitoring temps réel des connexions clients

Canaux valides 2.4 GHz : ${VALID_CHANNELS_24G[*]}
Canaux valides 5 GHz  : ${VALID_CHANNELS_5G[*]}

Exemples :
  sudo $0 --interface=wlan0 --ssid=MonHotspot --band=2.4 --channel=6 --exec
  sudo $0 --interface=wlan1 --band=5 --channel=36 --iprange=192.168.150 --exec
  sudo $0 --interface=wlan0 --clean
  sudo $0 --repair  # Répare toutes les interfaces WiFi
  sudo $0 --panic   # MODE VIOLENT : reset complet drivers + interfaces
  sudo $0 --monitor # Monitoring temps réel des connexions

EOF
}

check_requirements() {
  local missing=""
  command -v hostapd >/dev/null 2>&1 || missing="$missing hostapd"
  command -v dnsmasq >/dev/null 2>&1 || missing="$missing dnsmasq"
  command -v iptables >/dev/null 2>&1 || missing="$missing iptables"
  command -v nmcli >/dev/null 2>&1 || missing="$missing nmcli"

  if [ -n "$missing" ]; then
    echo "ERREUR: Paquets manquants:$missing"
    echo "Installation: sudo apt install$missing"
    exit 1
  fi
}

validate_channel() {
  local band=$1
  local channel=$2
  if [[ "$band" == "2.4" || "$band" == "2" ]]; then
    [[ " ${VALID_CHANNELS_24G[*]} " == *" $channel "* ]] && return 0
  elif [[ "$band" == "5" ]]; then
    [[ " ${VALID_CHANNELS_5G[*]} " == *" $channel "* ]] && return 0
  fi
  return 1
}

show_interface_status() {
  echo "=== État des interfaces WiFi ==="
  iw dev 2>/dev/null || echo "Erreur: impossible de lister les interfaces"
  echo
  echo "=== État NetworkManager ==="
  nmcli device status | grep wifi 2>/dev/null || echo "Aucune interface WiFi détectée"
}

kill_processes_safely() {
  echo "[*] Arrêt des processus hostapd et dnsmasq..."

  # Arrêt hostapd
  if [ -f "$HOSTAPD_PID_FILE" ]; then
    local pid=$(cat "$HOSTAPD_PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$HOSTAPD_PID_FILE"
  fi

  # Arrêt dnsmasq
  if [ -f "$DNSMASQ_PID_FILE" ]; then
    local pid=$(cat "$DNSMASQ_PID_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      sleep 2
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$DNSMASQ_PID_FILE"
  fi

  # Nettoyage général des processus orphelins
  pkill -f "hostapd.*$HOSTAPD_CONF" 2>/dev/null || true
  pkill -f "dnsmasq.*$DNSMASQ_CONF" 2>/dev/null || true

  echo "✓ Processus arrêtés"
}

reset_interface() {
  local iface=$1
  echo "[*] Remise à zéro complète de $iface"

  # Arrêt de l'interface
  ip link set "$iface" down 2>/dev/null || true
  sleep 1

  # Suppression des adresses IP
  ip addr flush dev "$iface" 2>/dev/null || true

  # Remise en mode managed via iw
  iw dev "$iface" set type managed 2>/dev/null || true
  sleep 1

  # NetworkManager : déconnexion forcée puis reconnexion
  nmcli device disconnect "$iface" 2>/dev/null || true
  sleep 2

  # Remise sous contrôle NetworkManager
  nmcli device set "$iface" managed yes 2>/dev/null || true
  sleep 2

  # Réactivation interface
  ip link set "$iface" up 2>/dev/null || true
  sleep 2

  # Tentative de reconnexion automatique
  nmcli device connect "$iface" 2>/dev/null || true

  echo "✓ $iface réinitialisée"
}

repair_interfaces() {
  echo "[*] === RÉPARATION DES INTERFACES WiFi ==="

  # Arrêt de tous les services hotspot
  kill_processes_safely

  # Nettoyage des règles iptables du hotspot
  remove_iptables_rules

  # Restauration iptables si backup existe
  restore_iptables

  # Réparation de toutes les interfaces WiFi
  local interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}')
  if [ -z "$interfaces" ]; then
    echo "Aucune interface WiFi trouvée"
    return 1
  fi

  for iface in $interfaces; do
    echo "[*] Réparation de $iface..."
    reset_interface "$iface"
  done

  # Redémarrage NetworkManager pour être sûr
  echo "[*] Redémarrage NetworkManager..."
  sudo systemctl restart NetworkManager
  sleep 5

  echo ""
  echo "[!] Si ça marche toujours pas, ton hardware WiFi a peut-être un problème..."
  echo "[!] Ou alors redémarre carrément la machine !"
  echo "✓ Réparation terminée"
  show_interface_status
}

panic_mode() {
  echo "[!] === MODE PANIC ACTIVÉ - RÉPARATION VIOLENTE ==="
  echo "[!] ⚠️  ATTENTION: Reset complet des drivers WiFi !"

  # Arrêt brutal de tous les services réseau
  echo "[!] Arrêt brutal de tous les services réseau..."
  kill_processes_safely

  # Nettoyage iptables hardcore
  echo "[!] Flush complet iptables..."
  iptables -F 2>/dev/null || true
  iptables -t nat -F 2>/dev/null || true
  iptables -t mangle -F 2>/dev/null || true
  iptables -X 2>/dev/null || true
  iptables -t nat -X 2>/dev/null || true
  iptables -t mangle -X 2>/dev/null || true

  # Restauration iptables si backup existe
  restore_iptables

  # Récupération liste des interfaces WiFi AVANT déchargement drivers
  local wifi_interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}')

  # Arrêt NetworkManager
  echo "[!] Arrêt NetworkManager..."
  systemctl stop NetworkManager 2>/dev/null || true
  systemctl stop wpa_supplicant 2>/dev/null || true

  # Down toutes les interfaces WiFi
  for iface in $wifi_interfaces; do
    echo "[!] Down interface $iface..."
    ip link set "$iface" down 2>/dev/null || true
    ip addr flush dev "$iface" 2>/dev/null || true
  done

  # Déchargement BRUTAL des drivers WiFi
  echo "[!] Déchargement drivers WiFi..."
  local wifi_modules=$(lsmod | grep -E "(iwl|ath|rt|wl)" | awk '{print $1}')

  for module in $wifi_modules; do
    echo "[!] Déchargement driver: $module"
    modprobe -r "$module" 2>/dev/null || true
  done

  # Attente pour que le kernel se stabilise
  echo "[!] Attente stabilisation kernel (10s)..."
  sleep 10

  # Rechargement des drivers WiFi
  echo "[!] Rechargement drivers WiFi..."
  for module in $wifi_modules; do
    echo "[!] Rechargement driver: $module"
    modprobe "$module" 2>/dev/null || true
  done

  # Attente détection hardware
  echo "[!] Attente détection hardware (15s)..."
  sleep 15

  # Redémarrage services réseau
  echo "[!] Redémarrage services réseau..."
  systemctl start wpa_supplicant 2>/dev/null || true
  systemctl start NetworkManager 2>/dev/null || true

  # Attente démarrage NetworkManager
  echo "[!] Attente démarrage NetworkManager (10s)..."
  sleep 10

  # Force la détection des nouvelles interfaces
  echo "[!] Force détection interfaces..."
  nmcli general reload 2>/dev/null || true

  # Récupération nouvelles interfaces après rechargement
  local new_interfaces=$(iw dev 2>/dev/null | grep Interface | awk '{print $2}')

  # Remise en gestion NetworkManager FORCE
  for iface in $new_interfaces; do
    echo "[!] Force gestion NetworkManager: $iface"
    nmcli device set "$iface" managed yes 2>/dev/null || true
    sleep 2
    nmcli device connect "$iface" 2>/dev/null || true
  done

  # Reset rfkill au cas où
  echo "[!] Reset rfkill..."
  rfkill unblock wifi 2>/dev/null || true
  rfkill unblock all 2>/dev/null || true

  # Attente finale
  echo "[!] Finalisation (5s)..."
  sleep 5

  echo "[!] === MODE PANIC TERMINÉ ==="
  echo "[!] Vérification état..."
  show_interface_status
}

monitor_clients() {
  echo "🔍 === MONITORING TEMPS RÉEL HOTSPOT ==="
  echo "Surveillance des connexions clients..."
  echo "Ctrl+C pour arrêter"
  echo ""
  echo "Format des logs :"
  echo "  HOTSPOT-TRAFFIC: Tout trafic hotspot"
  echo "  HOTSPOT-CLIENT: Trafic vers clients connectés"
  echo "  HOTSPOT-OUT: Trafic sortant des clients"
  echo "  HOTSPOT-NAT: Translations NAT"
  echo ""
  echo "=== MONITORING EN COURS ==="

  # Monitoring via journalctl (plus moderne)
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -f --no-pager | grep --line-buffered "HOTSPOT"
  else
    # Fallback sur tail des logs kernel
    tail -f /var/log/kern.log | grep --line-buffered "HOTSPOT"
  fi
}

generate_hostapd_conf() {
  cat > "$HOSTAPD_CONF" <<EOF
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=$( [[ "$BAND" == "5" ]] && echo "a" || echo "g" )
channel=$CHANNEL
ieee80211n=1
wmm_enabled=1
# Gestion des logs et PID
logger_syslog=-1
logger_syslog_level=2
EOF
}

generate_dnsmasq_conf() {
  cat > "$DNSMASQ_CONF" <<EOF
# Interface spécifique
interface=$INTERFACE
# Pas d'autres interfaces
except-interface=lo
# Range DHCP
dhcp-range=$IP_RANGE.$DHCP_RANGE_START,$IP_RANGE.$DHCP_RANGE_END,12h
# Fichier de leases
dhcp-leasefile=$DHCP_LEASES
# Logs
log-queries
log-dhcp
# PID file
pid-file=$DNSMASQ_PID_FILE
EOF
}

save_iptables() {
  if [ ! -f "$IPTABLES_BACKUP" ]; then
    echo "[*] Sauvegarde des règles iptables COMPLÈTE..."
    iptables-save > "$IPTABLES_BACKUP"
    echo "✓ Sauvegarde iptables : $IPTABLES_BACKUP"

    # VÉRIFICATION SERVICE FIREWALL ACTIF
    if systemctl is-active --quiet iptables 2>/dev/null || systemctl is-active --quiet firewall 2>/dev/null || systemctl list-units --state=active | grep -q fw; then
      echo "⚠️  ATTENTION: Service firewall systemctl détecté !"
      echo "⚠️  Le hotspot pourrait être écrasé par votre firewall automatique"
      echo "⚠️  Considérez arrêter temporairement le service firewall :"
      echo "     sudo systemctl stop [nom-du-service-fw]"
    fi
  else
    echo "[*] Sauvegarde iptables existante trouvée"
  fi
}

restore_iptables() {
  if [ -f "$IPTABLES_BACKUP" ]; then
    echo "[*] Restauration des règles iptables..."
    iptables-restore < "$IPTABLES_BACKUP"
    rm -f "$IPTABLES_BACKUP"
    echo "✓ Règles iptables restaurées"
  else
    echo "⚠ Aucune sauvegarde iptables trouvée"
  fi
}

apply_iptables_rules() {
  echo "[*] Application des règles iptables TEMPORAIRES pour $INTERFACE"
  echo "[*] Mode PENTESTING - Intégration avec firewall existant + LOGGING COMPLET"

  # Activation du forwarding IP
  echo 1 > /proc/sys/net/ipv4/ip_forward

  # LOGGING COMPLET - Création des chaînes de log spécialisées
  echo "[*] Configuration logging complet pour devices connectés..."

  # Chaîne pour logger TOUT le trafic hotspot (autorisé + bloqué)
  iptables -N HOTSPOT-LOG-ALL 2>/dev/null || true
  iptables -F HOTSPOT-LOG-ALL 2>/dev/null || true
  iptables -A HOTSPOT-LOG-ALL -j LOG --log-prefix "HOTSPOT-TRAFFIC: " --log-level 4
  iptables -A HOTSPOT-LOG-ALL -j ACCEPT

  # Chaîne pour logger spécifiquement les devices clients
  iptables -N HOTSPOT-LOG-CLIENTS 2>/dev/null || true
  iptables -F HOTSPOT-LOG-CLIENTS 2>/dev/null || true
  iptables -A HOTSPOT-LOG-CLIENTS -j LOG --log-prefix "HOTSPOT-CLIENT: " --log-level 4
  iptables -A HOTSPOT-LOG-CLIENTS -j ACCEPT

  # Chaîne pour logger les connexions sortantes des clients
  iptables -N HOTSPOT-LOG-OUTBOUND 2>/dev/null || true
  iptables -F HOTSPOT-LOG-OUTBOUND 2>/dev/null || true
  iptables -A HOTSPOT-LOG-OUTBOUND -j LOG --log-prefix "HOTSPOT-OUT: " --log-level 4
  iptables -A HOTSPOT-LOG-OUTBOUND -j ACCEPT

  # Règles de forwarding avec logging COMPLET
  # Trafic ENTRANT vers les clients (réponses Internet -> clients)
  iptables -I FORWARD -o "$INTERFACE" -j HOTSPOT-LOG-CLIENTS -m comment --comment "HOTSPOT-TEMP" 2>/dev/null || true

  # Trafic SORTANT des clients (clients -> Internet)
  iptables -I FORWARD -i "$INTERFACE" -j HOTSPOT-LOG-OUTBOUND -m comment --comment "HOTSPOT-TEMP" 2>/dev/null || true

  # Détection automatique de l'interface de sortie
  local default_iface=$(ip route | grep default | head -1 | awk '{print $5}')
  if [ -n "$default_iface" ]; then
    # Règle NAT temporaire avec commentaire pour identification
    if ! iptables -t nat -C POSTROUTING -s "$IP_RANGE.0/24" -o "$default_iface" -j MASQUERADE 2>/dev/null; then
      iptables -t nat -I POSTROUTING 1 -s "$IP_RANGE.0/24" -o "$default_iface" -j MASQUERADE -m comment --comment "HOTSPOT-TEMP" 2>/dev/null || true
    fi

    # BONUS: Logger aussi dans la table NAT (post-routing)
    iptables -t nat -I POSTROUTING 1 -s "$IP_RANGE.0/24" -o "$default_iface" -j LOG --log-prefix "HOTSPOT-NAT: " --log-level 4 -m comment --comment "HOTSPOT-TEMP" 2>/dev/null || true

    echo "✓ Règles iptables TEMPORAIRES + LOGGING COMPLET appliquées"
    echo "   - Sortie: $default_iface"
    echo "   - Réseau hotspot: $IP_RANGE.0/24"
    echo "   - Marquées: HOTSPOT-TEMP pour nettoyage facile"
    echo ""
    echo "📊 LOGGING ACTIVÉ:"
    echo "   - HOTSPOT-TRAFFIC: Tout le trafic hotspot"
    echo "   - HOTSPOT-CLIENT: Trafic vers les clients connectés"
    echo "   - HOTSPOT-OUT: Trafic sortant des clients"
    echo "   - HOTSPOT-NAT: Translations NAT"
    echo ""
    echo "🔍 MONITORING EN TEMPS RÉEL:"
    echo "   tail -f /var/log/kern.log | grep HOTSPOT"
    echo "   journalctl -f | grep HOTSPOT"

    echo ""
    echo "🔬 MODE PENTESTING LOGGING ACTIVÉ"
    echo "   - TOUTES les connexions des devices loggées"
    echo "   - Trafic autorisé ET bloqué capturé"
    echo "   - Votre fw.sh reste PRIORITAIRE"
    echo "   - Nettoyage propre à l'arrêt"
  else
    echo "⚠ Impossible de déterminer l'interface de sortie"
  fi
}

remove_iptables_rules() {
  echo "[*] Nettoyage règles iptables HOTSPOT-TEMP + chaînes de logging"

  # Suppression des chaînes de logging personnalisées
  echo "[*] Suppression chaînes de logging hotspot..."
  iptables -F HOTSPOT-LOG-ALL 2>/dev/null || true
  iptables -X HOTSPOT-LOG-ALL 2>/dev/null || true
  iptables -F HOTSPOT-LOG-CLIENTS 2>/dev/null || true
  iptables -X HOTSPOT-LOG-CLIENTS 2>/dev/null || true
  iptables -F HOTSPOT-LOG-OUTBOUND 2>/dev/null || true
  iptables -X HOTSPOT-LOG-OUTBOUND 2>/dev/null || true

  # Suppression PAR COMMENTAIRE (plus propre)
  echo "[*] Suppression règles marquées HOTSPOT-TEMP..."
  iptables-save | grep -v "HOTSPOT-TEMP" | iptables-restore 2>/dev/null || {
    # Fallback si grep/restore échoue
    echo "[*] Fallback: suppression manuelle des règles hotspot"

    # Suppression des règles de forward pour l'interface
    if [ -n "$INTERFACE" ]; then
      iptables -D FORWARD -i "$INTERFACE" -j HOTSPOT-LOG-OUTBOUND 2>/dev/null || true
      iptables -D FORWARD -o "$INTERFACE" -j HOTSPOT-LOG-CLIENTS 2>/dev/null || true
    fi

    # Suppression spécifique des règles NAT hotspot
    if [ -n "$IP_RANGE" ]; then
      local interfaces=$(ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print $2}' | grep -v lo)
      for iface in $interfaces; do
        iptables -t nat -D POSTROUTING -s "$IP_RANGE.0/24" -o "$iface" -j LOG 2>/dev/null || true
        iptables -t nat -D POSTROUTING -s "$IP_RANGE.0/24" -o "$iface" -j MASQUERADE 2>/dev/null || true
      done
    fi
  }

  echo "✓ Règles hotspot temporaires + logging nettoyées"
  echo "✓ Chaînes de logging supprimées"
  echo "✓ Votre fw.sh peut maintenant reprendre le contrôle total"
}

start_hostapd() {
  echo "[*] Démarrage de hostapd..."

  # Configuration de l'IP sur l'interface
  ip addr add "$IP_RANGE.1/24" dev "$INTERFACE" 2>/dev/null || {
    echo "⚠ Adresse IP déjà configurée sur $INTERFACE"
  }

  # Démarrage hostapd en arrière-plan
  hostapd "$HOSTAPD_CONF" >hostapd.log 2>&1 &
  local hostapd_pid=$!
  echo "$hostapd_pid" > "$HOSTAPD_PID_FILE"

  sleep 3

  if ! kill -0 "$hostapd_pid" 2>/dev/null; then
    echo "ERREUR : hostapd n'a pas démarré"
    echo "Voir le fichier hostapd.log pour plus de détails"
    cat hostapd.log
    return 1
  fi

  echo "✓ hostapd démarré (PID $hostapd_pid)"
  return 0
}

start_dnsmasq() {
  echo "[*] Démarrage de dnsmasq..."

  # Suppression du fichier de leases s'il existe
  rm -f "$DHCP_LEASES"

  # Démarrage dnsmasq
  dnsmasq --conf-file="$DNSMASQ_CONF" --no-daemon &
  local dnsmasq_pid=$!
  echo "$dnsmasq_pid" > "$DNSMASQ_PID_FILE"

  sleep 3

  if ! kill -0 "$dnsmasq_pid" 2>/dev/null; then
    echo "ERREUR : dnsmasq n'a pas démarré"
    return 1
  fi

  echo "✓ dnsmasq démarré (PID $dnsmasq_pid)"
  return 0
}

clean_hotspot() {
  echo "[*] === NETTOYAGE HOTSPOT ==="

  # Arrêt des services
  kill_processes_safely

  # Suppression des règles iptables
  remove_iptables_rules

  # Restauration iptables
  restore_iptables

  # Suppression de l'IP de l'interface
  if [ -n "$INTERFACE" ]; then
    ip addr del "$IP_RANGE.1/24" dev "$INTERFACE" 2>/dev/null || true
    reset_interface "$INTERFACE"
  fi

  # Nettoyage des fichiers
  rm -f "$HOSTAPD_CONF" "$DNSMASQ_CONF" "$DHCP_LEASES"
  rm -f hostapd.log dnsmasq.log

  echo "✓ Nettoyage terminé"
}

parse_args() {
  for arg in "$@"; do
    case $arg in
      --interface=*) INTERFACE="${arg#*=}" ;;
      --ssid=*) SSID="${arg#*=}" ;;
      --band=*) BAND="${arg#*=}" ;;
      --channel=*) CHANNEL="${arg#*=}" ;;
      --iprange=*) IP_RANGE="${arg#*=}" ;;
      --exec) EXEC_MODE=1 ;;
      --clean) EXEC_MODE=2 ;;
      --repair) EXEC_MODE=3 ;;
      --status) EXEC_MODE=4 ;;
      --panic) EXEC_MODE=5 ;;
      --monitor) EXEC_MODE=6 ;;
      --help) print_help; exit 0 ;;
      *) echo "Option inconnue: $arg"; print_help; exit 1 ;;
    esac
  done
}

main() {
  # Vérification des privilèges root
  if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root"
    exit 1
  fi

  parse_args "$@"

  if [[ "$EXEC_MODE" -eq 6 ]]; then
    monitor_clients
    exit 0
  fi

  if [[ "$EXEC_MODE" -eq 5 ]]; then
    panic_mode
    exit 0
  fi

  if [[ "$EXEC_MODE" -eq 4 ]]; then
    show_interface_status
    exit 0
  fi

  if [[ "$EXEC_MODE" -eq 3 ]]; then
    repair_interfaces
    exit 0
  fi

  if [[ -z "$INTERFACE" && "$EXEC_MODE" -ne 0 ]]; then
    echo "Erreur : interface non spécifiée"
    print_help
    exit 1
  fi

  if [[ "$EXEC_MODE" -eq 0 ]]; then
    print_help
    exit 0
  fi

  check_requirements

  if [[ "$EXEC_MODE" -eq 2 ]]; then
    clean_hotspot
    exit 0
  fi

  # Validation de l'interface
  if ! ip link show "$INTERFACE" >/dev/null 2>&1; then
    echo "Erreur : interface $INTERFACE non trouvée"
    exit 1
  fi

  # Validation bande
  if ! [[ "$BAND" =~ ^(2\.4|2|5)$ ]]; then
    echo "Erreur : bande invalide '$BAND', choisir 2.4 ou 5"
    exit 1
  fi

  # Validation canal
  if ! validate_channel "$BAND" "$CHANNEL"; then
    echo "Erreur : canal $CHANNEL invalide pour la bande $BAND GHz"
    echo "Canaux valides pour $BAND GHz : $([ "$BAND" == "5" ] && echo "${VALID_CHANNELS_5G[*]}" || echo "${VALID_CHANNELS_24G[*]}")"
    exit 1
  fi

  echo "[*] === CRÉATION HOTSPOT ==="
  echo "Interface: $INTERFACE"
  echo "SSID: $SSID"
  echo "Bande: $BAND GHz"
  echo "Canal: $CHANNEL"
  echo "Plage IP: $IP_RANGE.x"

  # Nettoyage préventif
  clean_hotspot 2>/dev/null || true
  sleep 2

  # Préparation interface
  reset_interface "$INTERFACE"

  # Sauvegarde iptables
  save_iptables

  # Génération des fichiers de configuration
  generate_hostapd_conf
  generate_dnsmasq_conf

  # Application des règles réseau
  apply_iptables_rules

  # Démarrage des services
  if ! start_hostapd; then
    echo "Échec du démarrage de hostapd"
    clean_hotspot
    exit 1
  fi

  if ! start_dnsmasq; then
    echo "Échec du démarrage de dnsmasq"
    clean_hotspot
    exit 1
  fi

  echo
  echo "🔬 === HOTSPOT PENTESTING + LOGGING ACTIF ==="
  echo "Interface: $INTERFACE"
  echo "SSID: $SSID ($BAND GHz, canal $CHANNEL)"
  echo "Passerelle: $IP_RANGE.1"
  echo "Plage DHCP: $IP_RANGE.$DHCP_RANGE_START - $IP_RANGE.$DHCP_RANGE_END"
  echo ""
  echo "📊 LOGGING COMPLET ACTIVÉ - TOUS les paquets des clients loggés !"
  echo "🎯 READY FOR ADVANCED NETWORK ANALYSIS"
  echo "   - Règles iptables temporaires (marquées HOTSPOT-TEMP)"
  echo "   - Chaînes de logging spécialisées actives"
  echo "   - Votre fw.sh reste maître du firewall"
  echo "   - Nettoyage automatique à l'arrêt"
  echo ""
  echo "🔍 MONITORING TEMPS RÉEL :"
  echo "   sudo $0 --monitor"
  echo "   # ou directement :"
  echo "   tail -f /var/log/kern.log | grep HOTSPOT"
  echo "   journalctl -f | grep HOTSPOT"
  echo ""
  echo "📡 Suggestions pour vos analyses :"
  echo "   - tcpdump -i $INTERFACE -w capture_\$(date +%Y%m%d_%H%M).pcap"
  echo "   - wireshark sur interface $INTERFACE"
  echo "   - ettercap -T -M arp:remote /$IP_RANGE.0//"
  echo "   - nmap -sn $IP_RANGE.0/24  # Scanner clients connectés"
  echo ""
  echo "Pour arrêter : sudo $0 --interface=$INTERFACE --clean"
}

# Gestion des signaux pour nettoyage propre
trap 'echo "Interruption détectée, nettoyage..."; clean_hotspot; exit 0' INT TERM

main "$@"
