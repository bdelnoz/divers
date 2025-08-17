#!/bin/bash
# Auteur : Bruno DELNOZ (corrigé)
# Email  : bruno.delnoz@protonmail.com
# Nom du script : createhotspot.sh
# Target usage : Gérer création, suppression et restauration d'un hotspot wifi sur une interface spécifique
# Version : v3.6 - Date : 2025-07-21 - Corrections compatibilité fw.sh systemctl

LOGFILE="./createhotspot.log"
SCRIPTNAME=$(basename "$0")
DNSMASQ_PID_FILE="/tmp/dnsmasq_${IFACE}.pid"
IPTABLES_BACKUP="/tmp/iptables_backup_$(date +%s).rules"
FW_SERVICE_NAME="fw"  # Nom de votre service systemctl

log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOGFILE"
}

usage() {
cat <<EOF
Usage: $SCRIPTNAME [--exec | --delete] --interface=INTERFACE [--ssid=SSID] [--password=PASSWORD]

Options:
--exec           Exécute la création du hotspot sur l'interface spécifiée.
--delete         Supprime le hotspot et restaure l'interface en DHCP.
--interface=IF   Interface wifi à utiliser (ex: wlan1).
--ssid=SSID      SSID du hotspot (défaut: MyHotspot).
--password=PASS  Mot de passe du hotspot (défaut: 12345678, min 8 chars).
--help           Affiche cette aide.

Exemples:
$SCRIPTNAME --exec --interface=wlan1
$SCRIPTNAME --exec --interface=wlan1 --ssid=MonWifi --password=motdepasse123
$SCRIPTNAME --delete --interface=wlan1

EOF
}

check_fw_service() {
    log "[*] Vérification du service pare-feu"

    if systemctl is-active --quiet "$FW_SERVICE_NAME"; then
        log "✓ Service $FW_SERVICE_NAME actif détecté"
        return 0
    elif systemctl list-unit-files | grep -q "^$FW_SERVICE_NAME\.service"; then
        log "⚠ Service $FW_SERVICE_NAME installé mais inactif"
        return 1
    else
        log "Service $FW_SERVICE_NAME non détecté, utilisation iptables standard"
        return 2
    fi
}

backup_iptables() {
    log "[*] Sauvegarde des règles iptables actuelles"

    # Sauvegarder toutes les tables
    iptables-save > "$IPTABLES_BACKUP"

    if [ -f "$IPTABLES_BACKUP" ] && [ -s "$IPTABLES_BACKUP" ]; then
        log "✓ Règles iptables sauvegardées : $IPTABLES_BACKUP"
        return 0
    else
        log "⚠ Échec de la sauvegarde iptables"
        return 1
    fi
}

add_hotspot_rules() {
    local internet_iface="$1"
    log "[*] Ajout des règles hotspot (préservation fw.sh)"

    # Règles spécifiques hotspot SEULEMENT
    iptables -t nat -I POSTROUTING -s 10.42.0.0/24 -o "$internet_iface" -j MASQUERADE -m comment --comment "HOTSPOT_$IFACE"
    iptables -I FORWARD -i "$IFACE" -o "$internet_iface" -m state --state RELATED,ESTABLISHED -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"
    iptables -I FORWARD -i "$internet_iface" -o "$IFACE" -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"
    iptables -I INPUT -i "$IFACE" -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"
    iptables -I OUTPUT -o "$IFACE" -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"

    # Règles DNS pour le hotspot
    iptables -I INPUT -i "$IFACE" -p udp --dport 53 -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"
    iptables -I INPUT -i "$IFACE" -p tcp --dport 53 -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"

    # Règle DHCP pour le hotspot
    iptables -I INPUT -i "$IFACE" -p udp --dport 67 -j ACCEPT -m comment --comment "HOTSPOT_$IFACE"

    log "✓ Règles hotspot ajoutées avec marquage pour $IFACE"
}

remove_hotspot_rules() {
    log "[*] Suppression UNIQUEMENT des règles hotspot marquées"

    # Supprimer toutes les règles marquées HOTSPOT_$IFACE
    local rules_found=false

    # Nettoyer NAT
    while iptables -t nat -D POSTROUTING -m comment --comment "HOTSPOT_$IFACE" 2>/dev/null; do
        rules_found=true
    done

    # Nettoyer FORWARD
    while iptables -D FORWARD -m comment --comment "HOTSPOT_$IFACE" 2>/dev/null; do
        rules_found=true
    done

    # Nettoyer INPUT
    while iptables -D INPUT -m comment --comment "HOTSPOT_$IFACE" 2>/dev/null; do
        rules_found=true
    done

    # Nettoyer OUTPUT
    while iptables -D OUTPUT -m comment --comment "HOTSPOT_$IFACE" 2>/dev/null; do
        rules_found=true
    done

    if [ "$rules_found" = true ]; then
        log "✓ Règles hotspot supprimées, règles fw.sh préservées"
    else
        log "Aucune règle hotspot trouvée à supprimer"
    fi
}

check_prereqs() {
    local missing_tools=()

    command -v nmcli >/dev/null 2>&1 || missing_tools+=("nmcli (NetworkManager)")
    command -v iptables >/dev/null 2>&1 || missing_tools+=("iptables")
    command -v iptables-save >/dev/null 2>&1 || missing_tools+=("iptables-save")
    command -v dnsmasq >/dev/null 2>&1 || missing_tools+=("dnsmasq")
    command -v hostapd >/dev/null 2>&1 || missing_tools+=("hostapd")

    if [ ${#missing_tools[@]} -gt 0 ]; then
        log "ERREUR : Outils manquants : ${missing_tools[*]}"
        log "Installez avec : apt install network-manager iptables-persistent dnsmasq hostapd"
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        log "ERREUR : Ce script doit être exécuté en tant que root"
        exit 1
    fi

    # Vérifier le service fw.sh
    check_fw_service

    log "Prérequis vérifiés"
}

verify_interface() {
    local iface="$1"
    if ! ip link show "$iface" >/dev/null 2>&1; then
        log "ERREUR : Interface $iface non trouvée"
        exit 1
    fi

    # Vérifier que c'est une interface WiFi
    if ! iw dev "$iface" info >/dev/null 2>&1; then
        log "ERREUR : $iface n'est pas une interface WiFi valide"
        exit 1
    fi

    # Vérifier support AP mode
    if ! iw list | grep -A 10 "Supported interface modes:" | grep -q "AP"; then
        log "ATTENTION : Le hardware WiFi pourrait ne pas supporter le mode AP"
    fi

    log "Interface $iface vérifiée"
}

get_interface_management_state() {
    local iface="$1"
    nmcli device show "$iface" 2>/dev/null | grep "GENERAL.STATE" | grep -q "unmanaged" && echo "unmanaged" || echo "managed"
}

set_interface_managed() {
    local iface="$1"
    log "[*] Configuration de l'interface $iface en mode 'managed'"

    local current_state=$(get_interface_management_state "$iface")
    log "État actuel de $iface: $current_state"

    if [ "$current_state" = "unmanaged" ]; then
        # Supprimer les fichiers de configuration unmanaged
        local nm_config_dir="/etc/NetworkManager/conf.d"
        local config_file="$nm_config_dir/99-unmanage-$iface.conf"

        if [ -f "$config_file" ]; then
            log "Suppression de la configuration unmanaged : $config_file"
            rm -f "$config_file"
        fi

        # Recharger NetworkManager
        systemctl reload NetworkManager
        sleep 3

        # Forcer managed
        nmcli device set "$iface" managed yes 2>/dev/null
        sleep 2

        local final_state=$(get_interface_management_state "$iface")
        if [ "$final_state" = "managed" ]; then
            log "✓ Interface $iface maintenant en mode 'managed'"
        else
            log "⚠ ATTENTION: Interface $iface toujours en mode '$final_state'"
            return 1
        fi
    else
        log "✓ Interface $iface déjà en mode 'managed'"
    fi
    return 0
}

cleanup_hotspot() {
    log "[1] Suppression du hotspot pour $IFACE (préservation fw.sh)"

    # Arrêter hostapd s'il tourne
    pkill -f "hostapd.*$IFACE" 2>/dev/null && log "hostapd arrêté"

    # Arrêter dnsmasq spécifique à l'interface
    if [ -f "/tmp/dnsmasq_$IFACE.pid" ]; then
        local pid=$(cat "/tmp/dnsmasq_$IFACE.pid")
        if kill "$pid" 2>/dev/null; then
            log "dnsmasq arrêté (PID: $pid)"
        fi
        rm -f "/tmp/dnsmasq_$IFACE.pid"
    fi

    # Nettoyer dnsmasq par nom de processus
    local dnsmasq_pids=$(pgrep -f "dnsmasq.*$IFACE")
    if [ -n "$dnsmasq_pids" ]; then
        echo "$dnsmasq_pids" | xargs kill -TERM 2>/dev/null
        log "Processus dnsmasq spécifiques à $IFACE arrêtés"
    fi

    # Supprimer UNIQUEMENT les règles hotspot (préserve fw.sh)
    remove_hotspot_rules

    # Nettoyer IP statique
    ip addr flush dev "$IFACE" 2>/dev/null
    log "IP statique sur $IFACE supprimée"

    # Nettoyer les fichiers temporaires
    rm -f "/tmp/hostapd_$IFACE.conf" "/tmp/dnsmasq_$IFACE.conf" "/tmp/hostapd_$IFACE.pid"
}

get_internet_interface() {
    local hotspot_iface="$1"

    # Priorité 1: Interface avec route par défaut active (excluant le hotspot)
    local default_iface=$(ip route | grep '^default' | grep -v "$hotspot_iface" | awk '{print $5}' | head -n1)

    if [ -n "$default_iface" ]; then
        log "Interface internet détectée via route par défaut : $default_iface"
        echo "$default_iface"
        return
    fi

    # Priorité 2: Autre interface WiFi connectée
    local other_wifi=$(nmcli device status | grep wifi | grep connected | grep -v "^$hotspot_iface" | awk '{print $1}' | head -n1)

    if [ -n "$other_wifi" ]; then
        log "Interface WiFi connectée détectée : $other_wifi"
        echo "$other_wifi"
        return
    fi

    # Priorité 3: Interface Ethernet active
    local eth_iface=$(nmcli device status | grep ethernet | grep connected | awk '{print $1}' | head -n1)

    if [ -n "$eth_iface" ]; then
        log "Interface Ethernet connectée détectée : $eth_iface"
        echo "$eth_iface"
        return
    fi

    # Fallback
    log "⚠ Aucune interface internet claire détectée, utilisation de eth0 par défaut"
    echo "eth0"
}

cleanup_nm_connections() {
    log "[2] Nettoyage des connexions NetworkManager pour $IFACE UNIQUEMENT"

    # Déconnecter UNIQUEMENT l'interface hotspot
    nmcli device disconnect "$IFACE" 2>/dev/null

    # Supprimer UNIQUEMENT les connexions hotspot/AP temporaires
    local connections=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE$" | cut -d: -f1)

    if [ -n "$connections" ]; then
        while IFS= read -r conn; do
            # Ne supprimer que les connexions hotspot/AP, pas les connexions WiFi normales
            if echo "$conn" | grep -qi "hotspot\|ap\|temp"; then
                log "Suppression de la connexion hotspot : $conn"
                nmcli connection delete "$conn" 2>/dev/null
            else
                log "Conservation de la connexion normale : $conn"
            fi
        done <<< "$connections"
    fi

    # Vérifier que les autres interfaces WiFi ne sont PAS affectées
    check_other_interfaces
}

check_other_interfaces() {
    log "[*] Vérification protection des autres interfaces WiFi"

    # Lister toutes les interfaces WiFi sauf celle du hotspot
    local other_wifi=$(ls /sys/class/net/ | grep -E '^wlan[0-9]+

check_hotspot_running() {
    # Vérifier NetworkManager AP mode
    if nmcli device status | grep "^$IFACE" | grep -qi "ap\|hotspot"; then
        return 0
    fi

    # Vérifier hostapd
    if pgrep -f "hostapd.*$IFACE" >/dev/null; then
        return 0
    fi

    # Vérifier dnsmasq
    if pgrep -f "dnsmasq.*$IFACE" >/dev/null; then
        return 0
    fi

    return 1
}

start_hotspot() {
    log "[0] Démarrage hotspot sur $IFACE avec SSID '$SSID'"

    if check_hotspot_running; then
        log "ERREUR: Hotspot déjà actif sur $IFACE. Utilisez --delete d'abord."
        exit 1
    fi

    # Déconnecter l'interface des réseaux existants
    nmcli device disconnect "$IFACE" 2>/dev/null

    # Méthode 1: Essayer avec NetworkManager (plus propre)
        log '[1] Tentative création hotspot via NetworkManager (préserve autres interfaces)'

    if nmcli device wifi hotspot ifname "$IFACE" ssid "$SSID" password "$PASSWORD" 2>/dev/null; then
        log "✓ Hotspot créé via NetworkManager sur $IFACE"

        # Vérifier que les autres interfaces WiFi sont toujours OK
        check_other_interfaces

        sleep 5

        # Configurer le routage
        setup_routing
        return 0
    fi

    log "Échec NetworkManager, passage en mode manuel"

    # Méthode 2: Configuration manuelle avec hostapd
    setup_manual_hotspot
}

setup_manual_hotspot() {
    log "[2] Configuration manuelle du hotspot"

    # Configurer l'interface en mode unmanaged
    nmcli device set "$IFACE" managed no 2>/dev/null

    # Assigner une IP statique
    ip addr flush dev "$IFACE"
    ip addr add 10.42.0.1/24 dev "$IFACE"
    ip link set "$IFACE" up

    if [ $? -ne 0 ]; then
        log "ERREUR: Impossible de configurer l'IP sur $IFACE"
        exit 1
    fi

    # Créer configuration hostapd
    local hostapd_conf="/tmp/hostapd_$IFACE.conf"
    cat > "$hostapd_conf" <<EOF
interface=$IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    # Lancer hostapd
    hostapd "$hostapd_conf" -B -P "/tmp/hostapd_$IFACE.pid"
    if [ $? -ne 0 ]; then
        log "ERREUR: Impossible de lancer hostapd"
        rm -f "$hostapd_conf"
        exit 1
    fi

    log "✓ hostapd lancé avec succès"

    # Lancer dnsmasq
    setup_dnsmasq

    # Configurer le routage
    setup_routing
}

setup_dnsmasq() {
    log "[3] Configuration DHCP avec dnsmasq"

    local dnsmasq_conf="/tmp/dnsmasq_$IFACE.conf"
    cat > "$dnsmasq_conf" <<EOF
interface=$IFACE
bind-interfaces
dhcp-range=10.42.0.10,10.42.0.50,24h
dhcp-option=3,10.42.0.1
dhcp-option=6,10.42.0.1
server=8.8.8.8
server=8.8.4.4
EOF

    dnsmasq --conf-file="$dnsmasq_conf" --pid-file="/tmp/dnsmasq_$IFACE.pid"

    if [ $? -eq 0 ]; then
        log "✓ dnsmasq lancé avec succès"
    else
        log "ERREUR: Impossible de lancer dnsmasq"
        exit 1
    fi
}

setup_routing() {
    log "[4] Configuration du routage NAT (compatible fw.sh)"

    local internet_iface=$(get_internet_interface "$IFACE")
    log "Interface internet détectée : $internet_iface"

    # Sauvegarder les règles actuelles avant modification
    backup_iptables

    # Activer IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Ajouter UNIQUEMENT les règles hotspot (avec marquage)
    add_hotspot_rules "$internet_iface"

    log "✓ Routage NAT configuré (règles fw.sh préservées)"
    log "✓ Hotspot actif - SSID: $SSID"
}

delete_hotspot() {
    log "[0] Suppression complète du hotspot pour $IFACE (préservation fw.sh)"

    cleanup_hotspot
    cleanup_nm_connections

    # Plus besoin de toucher /etc/network/interfaces ni de redémarrer les services
    # NetworkManager gère tout automatiquement

    # Remettre l'interface en mode managed (NetworkManager gère le reste)
    restore_interface_nm

    # Redémarrer le service fw.sh pour réappliquer les règles complètes
    restart_fw_service

    # Vérifier que les autres interfaces ne sont pas affectées
    check_other_interfaces

    log "✓ Hotspot supprimé pour $IFACE - fw.sh restauré - autres interfaces WiFi préservées"
}

### MAIN ###

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

MODE=""
IFACE=""
SSID="MyHotspot"
PASSWORD="12345678"

for arg in "$@"; do
    case "$arg" in
        --exec) MODE="exec" ;;
        --delete) MODE="delete" ;;
        --interface=*) IFACE="${arg#*=}" ;;
        --ssid=*) SSID="${arg#*=}" ;;
        --password=*) PASSWORD="${arg#*=}" ;;
        --help) usage; exit 0 ;;
        *) log "Argument inconnu: $arg" ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$IFACE" ]; then
    log "ERREUR: Mode et interface obligatoires"
    usage
    exit 1
fi

if [ ${#PASSWORD} -lt 8 ]; then
    log "ERREUR: Mot de passe trop court (8 caractères minimum)"
    exit 1
fi

check_prereqs
verify_interface "$IFACE"

case "$MODE" in
    "exec") start_hotspot ;;
    "delete") delete_hotspot ;;
    *) usage; exit 1 ;;
esac

log "✓ Script terminé avec succès" | grep -v "^$IFACE$")

    if [ -n "$other_wifi" ]; then
        for iface in $other_wifi; do
            local status=$(nmcli device status | grep "^$iface" | awk '{print $3}')
            log "Interface $iface : statut '$status' (préservé)"

            # Vérifier que l'interface n'est pas disconnectée par erreur
            if [ "$status" = "disconnected" ] || [ "$status" = "unmanaged" ]; then
                log "⚠ Interface $iface semble déconnectée - vérifiez manuellement"
            fi
        done
    else
        log "Aucune autre interface WiFi détectée"
    fi
}

check_hotspot_running() {
    # Vérifier NetworkManager AP mode
    if nmcli device status | grep "^$IFACE" | grep -qi "ap\|hotspot"; then
        return 0
    fi

    # Vérifier hostapd
    if pgrep -f "hostapd.*$IFACE" >/dev/null; then
        return 0
    fi

    # Vérifier dnsmasq
    if pgrep -f "dnsmasq.*$IFACE" >/dev/null; then
        return 0
    fi

    return 1
}

start_hotspot() {
    log "[0] Démarrage hotspot sur $IFACE avec SSID '$SSID'"

    if check_hotspot_running; then
        log "ERREUR: Hotspot déjà actif sur $IFACE. Utilisez --delete d'abord."
        exit 1
    fi

    # Déconnecter l'interface des réseaux existants
    nmcli device disconnect "$IFACE" 2>/dev/null

    # Méthode 1: Essayer avec NetworkManager (plus propre)
    log "[1] Tentative création hotspot via NetworkManager"

    if nmcli device wifi hotspot ifname "$IFACE" ssid "$SSID" password "$PASSWORD" 2>/dev/null; then
        log "✓ Hotspot créé via NetworkManager"
        sleep 5

        # Configurer le routage
        setup_routing
        return 0
    fi

    log "Échec NetworkManager, passage en mode manuel"

    # Méthode 2: Configuration manuelle avec hostapd
    setup_manual_hotspot
}

setup_manual_hotspot() {
    log "[2] Configuration manuelle du hotspot"

    # Configurer l'interface en mode unmanaged
    nmcli device set "$IFACE" managed no 2>/dev/null

    # Assigner une IP statique
    ip addr flush dev "$IFACE"
    ip addr add 10.42.0.1/24 dev "$IFACE"
    ip link set "$IFACE" up

    if [ $? -ne 0 ]; then
        log "ERREUR: Impossible de configurer l'IP sur $IFACE"
        exit 1
    fi

    # Créer configuration hostapd
    local hostapd_conf="/tmp/hostapd_$IFACE.conf"
    cat > "$hostapd_conf" <<EOF
interface=$IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=7
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF

    # Lancer hostapd
    hostapd "$hostapd_conf" -B -P "/tmp/hostapd_$IFACE.pid"
    if [ $? -ne 0 ]; then
        log "ERREUR: Impossible de lancer hostapd"
        rm -f "$hostapd_conf"
        exit 1
    fi

    log "✓ hostapd lancé avec succès"

    # Lancer dnsmasq
    setup_dnsmasq

    # Configurer le routage
    setup_routing
}

setup_dnsmasq() {
    log "[3] Configuration DHCP avec dnsmasq"

    local dnsmasq_conf="/tmp/dnsmasq_$IFACE.conf"
    cat > "$dnsmasq_conf" <<EOF
interface=$IFACE
bind-interfaces
dhcp-range=10.42.0.10,10.42.0.50,24h
dhcp-option=3,10.42.0.1
dhcp-option=6,10.42.0.1
server=8.8.8.8
server=8.8.4.4
EOF

    dnsmasq --conf-file="$dnsmasq_conf" --pid-file="/tmp/dnsmasq_$IFACE.pid"

    if [ $? -eq 0 ]; then
        log "✓ dnsmasq lancé avec succès"
    else
        log "ERREUR: Impossible de lancer dnsmasq"
        exit 1
    fi
}

setup_routing() {
    log "[4] Configuration du routage NAT"

    local internet_iface=$(get_internet_interface "$IFACE")
    log "Interface internet détectée : $internet_iface"

    # Activer IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Configurer iptables
    iptables -t nat -A POSTROUTING -s 10.42.0.0/24 -o "$internet_iface" -j MASQUERADE
    iptables -A FORWARD -i "$IFACE" -o "$internet_iface" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i "$internet_iface" -o "$IFACE" -j ACCEPT
    iptables -A INPUT -i "$IFACE" -j ACCEPT
    iptables -A OUTPUT -o "$IFACE" -j ACCEPT

    log "✓ Routage NAT configuré"
    log "✓ Hotspot actif - SSID: $SSID"
}

delete_hotspot() {
    log "[0] Suppression complète du hotspot pour $IFACE"

    cleanup_hotspot
    cleanup_nm_connections

    # Remettre l'interface en mode managed
    if set_interface_managed "$IFACE"; then
        restore_dhcp_nm
        log "✓ Interface $IFACE restaurée en DHCP"
    else
        log "⚠ Problème lors de la restauration de $IFACE"
    fi

    log "✓ Hotspot supprimé pour $IFACE"
}

### MAIN ###

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

MODE=""
IFACE=""
SSID="MyHotspot"
PASSWORD="12345678"

for arg in "$@"; do
    case "$arg" in
        --exec) MODE="exec" ;;
        --delete) MODE="delete" ;;
        --interface=*) IFACE="${arg#*=}" ;;
        --ssid=*) SSID="${arg#*=}" ;;
        --password=*) PASSWORD="${arg#*=}" ;;
        --help) usage; exit 0 ;;
        *) log "Argument inconnu: $arg" ;;
    esac
done

if [ -z "$MODE" ] || [ -z "$IFACE" ]; then
    log "ERREUR: Mode et interface obligatoires"
    usage
    exit 1
fi

if [ ${#PASSWORD} -lt 8 ]; then
    log "ERREUR: Mot de passe trop court (8 caractères minimum)"
    exit 1
fi

check_prereqs
verify_interface "$IFACE"

case "$MODE" in
    "exec") start_hotspot ;;
    "delete") delete_hotspot ;;
    *) usage; exit 1 ;;
esac

log "✓ Script terminé avec succès"
