#!/bin/bash
# Auteur : Bruno DELNOZ
# Email  : bruno.delnoz@protonmail.com
# Nom du script : createhotspot.sh
# Target usage : Gérer création, suppression et restauration d'un hotspot wifi sur une interface spécifique
# Version : v3.3 - Date : 2025-07-20 - Corrections et améliorations isolation interfaces

LOGFILE="./createhotspot.log"
SCRIPTNAME=$(basename "$0")

# Fonction log pour consigner actions et résultats dans LOGFILE
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOGFILE"
}

# Affichage aide
usage() {
cat <<EOF
Usage: $SCRIPTNAME [--exec | --delete] --interface=INTERFACE [--ssid=SSID] [--password=PASSWORD]

Options:
--exec           Exécute la création du hotspot sur l'interface spécifiée.
                 L'interface sera automatiquement passée en mode 'managed'.
--delete         Supprime le hotspot et restaure l'interface en DHCP.
                 L'interface sera automatiquement passée en mode 'unmanaged'.
--interface=IF   Interface wifi à utiliser (ex: wlan1).
--ssid=SSID      SSID du hotspot (défaut: MyHotspot).
--password=PASS  Mot de passe du hotspot (défaut: 12345678, min 8 chars).
--help           Affiche cette aide.

Exemples:
$SCRIPTNAME --exec --interface=wlan1
$SCRIPTNAME --exec --interface=wlan1 --ssid=MonWifi --password=motdepasse123
$SCRIPTNAME --delete --interface=wlan1

Note: Le script gère automatiquement les modes managed/unmanaged de NetworkManager.

EOF
}

# Vérifications prérequis (ex: NetworkManager, iptables, dnsmasq)
check_prereqs() {
    command -v nmcli >/dev/null 2>&1 || { log "ERREUR : nmcli absent."; exit 1; }
    command -v iptables >/dev/null 2>&1 || { log "ERREUR : iptables absent."; exit 1; }
    command -v dnsmasq >/dev/null 2>&1 || { log "ERREUR : dnsmasq absent."; exit 1; }
    log "Prérequis vérifiés"
}

# Obtenir l'état de gestion actuel d'une interface
get_interface_management_state() {
    local iface="$1"
    local state=$(nmcli device show "$iface" 2>/dev/null | grep "GENERAL.STATE" | awk '{print $2}')
    local managed=$(nmcli device show "$iface" 2>/dev/null | grep "GENERAL.STATE" | grep -q "unmanaged" && echo "unmanaged" || echo "managed")
    echo "$managed"
}

# Forcer une interface en mode managed
set_interface_managed() {
    local iface="$1"
    log "[*] Configuration de l'interface $iface en mode 'managed'"

    local current_state=$(get_interface_management_state "$iface")
    log "État actuel de $iface: $current_state"

    if [ "$current_state" = "unmanaged" ]; then
        log "Passage de $iface en mode 'managed'"

        nmcli device set "$iface" managed yes 2>/dev/null

        if [ "$(get_interface_management_state "$iface")" = "unmanaged" ]; then
            log "Tentative via modification de la configuration NetworkManager"

            local nm_config_dir="/etc/NetworkManager/conf.d"
            local config_file="$nm_config_dir/99-unmanage-$iface.conf"

            if [ -f "$config_file" ]; then
                log "Suppression de la configuration unmanaged existante: $config_file"
                rm -f "$config_file"
            fi

            if [ -d "$nm_config_dir" ]; then
                grep -l "interface-name=$iface" "$nm_config_dir"/*.conf 2>/dev/null | while read -r conf_file; do
                    if grep -q "managed=false" "$conf_file" 2>/dev/null; then
                        log "Suppression de la configuration dans: $conf_file"
                        sed -i "/interface-name=$iface/,/managed=false/d" "$conf_file"
                    fi
                done
            fi

            systemctl reload NetworkManager
            sleep 3

            nmcli device set "$iface" managed yes 2>/dev/null
        fi

        sleep 2
        local final_state=$(get_interface_management_state "$iface")
        if [ "$final_state" = "managed" ]; then
            log "✓ Interface $iface maintenant en mode 'managed'"
        else
            log "⚠ ATTENTION: Interface $iface toujours en mode '$final_state'"
            log "Tentative de forçage manuel..."

            ip link set "$iface" down
            sleep 1
            ip link set "$iface" up
            sleep 2
            nmcli device set "$iface" managed yes
            sleep 2

            final_state=$(get_interface_management_state "$iface")
            log "État final après forçage: $final_state"
        fi
    else
        log "✓ Interface $iface déjà en mode 'managed'"
    fi
}

# Forcer une interface en mode unmanaged
set_interface_unmanaged() {
    local iface="$1"
    log "[*] Configuration de l'interface $iface en mode 'unmanaged'"

    local current_state=$(get_interface_management_state "$iface")
    log "État actuel de $iface: $current_state"

    if [ "$current_state" = "managed" ]; then
        log "Passage de $iface en mode 'unmanaged'"

        nmcli device disconnect "$iface" 2>/dev/null
        nmcli device set "$iface" managed no 2>/dev/null

        local nm_config_dir="/etc/NetworkManager/conf.d"
        local config_file="$nm_config_dir/99-unmanage-$iface.conf"

        mkdir -p "$nm_config_dir"

        cat > "$config_file" << EOF
[keyfile]
unmanaged-devices=interface-name:$iface

[device]
wifi.scan-rand-mac-address=no
EOF

        log "Configuration permanente créée: $config_file"

        systemctl reload NetworkManager
        sleep 2

        local final_state=$(get_interface_management_state "$iface")
        if [ "$final_state" = "unmanaged" ]; then
            log "✓ Interface $iface maintenant en mode 'unmanaged'"
        else
            log "⚠ ATTENTION: Interface $iface toujours en mode '$final_state'"
        fi
    else
        log "✓ Interface $iface déjà en mode 'unmanaged'"
    fi
}

get_interface_network() {
    local iface="$1"
    local current_ip=$(ip addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -n1)
    if [ -n "$current_ip" ]; then
        local network=$(ip route | grep "$iface" | grep -oP '\d+\.\d+\.\d+\.0/\d+' | head -n1)
        echo "$network"
    else
        echo "10.42.0.0/24"
    fi
}

get_internet_interface() {
    local hotspot_iface="$1"
    local default_iface=$(ip route | grep '^default' | grep -v "$hotspot_iface" | awk '{print $5}' | head -n1)
    if [ -n "$default_iface" ]; then
        echo "$default_iface"
    else
        echo "eth0"
    fi
}

cleanup_hotspot() {
    log "[1] Suppression du hotspot et désactivation du NAT pour $IFACE UNIQUEMENT"

    local interface_network=$(get_interface_network "$IFACE")
    local internet_iface=$(get_internet_interface "$IFACE")

    log "Suppression des règles pour réseau: $interface_network via $internet_iface"

    iptables -t nat -D POSTROUTING -s "$interface_network" -o "$internet_iface" -j MASQUERADE 2>/dev/null && \
        log "Règle NAT supprimée: $interface_network -> $internet_iface"

    iptables -D FORWARD -i "$IFACE" -o "$internet_iface" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && \
        log "Règle FORWARD supprimée: $IFACE -> $internet_iface"

    iptables -D FORWARD -i "$internet_iface" -o "$IFACE" -j ACCEPT 2>/dev/null && \
        log "Règle FORWARD supprimée: $internet_iface -> $IFACE"

    iptables -D INPUT -i "$IFACE" -j ACCEPT 2>/dev/null
    iptables -D OUTPUT -o "$IFACE" -j ACCEPT 2>/dev/null

    local dnsmasq_pids=$(pgrep -f "dnsmasq.*$IFACE")
    if [ -n "$dnsmasq_pids" ]; then
        echo "$dnsmasq_pids" | xargs kill -TERM 2>/dev/null
        log "Processus dnsmasq spécifiques à $IFACE arrêtés"
    fi

    log "Suppression des règles iptables UNIQUEMENT pour $IFACE terminée"
}

clean_interfaces_file() {
    log "[2] Nettoyage /etc/network/interfaces pour $IFACE UNIQUEMENT"

    if [ ! -f /etc/network/interfaces ]; then
        log "Fichier /etc/network/interfaces non trouvé, création d'un fichier minimal"
        echo "# interfaces(5) file used by ifup(8) and ifdown(8)" > /etc/network/interfaces
        echo "auto lo" >> /etc/network/interfaces
        echo "iface lo inet loopback" >> /etc/network/interfaces
        return
    fi

    local backup_file="/etc/network/interfaces.bak_$(date +%s)"
    cp /etc/network/interfaces "$backup_file"
    log "Sauvegarde créée : $backup_file"

    local temp_file=$(mktemp)
    local in_iface_block=false
    local iface_found=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug)[[:space:]]+$IFACE([[:space:]]|$) ]]; then
            in_iface_block=true
            iface_found=true
            log "Suppression du bloc auto/allow-hotplug pour $IFACE"
            continue
        elif [[ "$line" =~ ^[[:space:]]*iface[[:space:]]+$IFACE[[:space:]] ]]; then
            in_iface_block=true
            iface_found=true
            log "Suppression du bloc iface pour $IFACE"
            continue
        elif [ "$in_iface_block" = true ]; then
            if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]] ]]; then
                in_iface_block=false
                if [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]] ]]; then
                    echo "$line" >> "$temp_file"
                fi
                continue
            else
                continue
            fi
        fi
        if [ "$in_iface_block" = false ]; then
            echo "$line" >> "$temp_file"
        fi
    done < /etc/network/interfaces

    mv "$temp_file" /etc/network/interfaces

    if [ "$iface_found" = true ]; then
        log "Configuration statique supprimée pour $IFACE UNIQUEMENT dans /etc/network/interfaces"
    else
        log "Aucune configuration trouvée pour $IFACE dans /etc/network/interfaces"
    fi
}

force_dhcp_interfaces() {
    log "[3] Forçage DHCP dans /etc/network/interfaces pour $IFACE UNIQUEMENT"

    echo "" >> /etc/network/interfaces
    echo "auto $IFACE" >> /etc/network/interfaces
    echo "iface $IFACE inet dhcp" >> /etc/network/interfaces
    echo "" >> /etc/network/interfaces

    log "Configuration DHCP ajoutée dans /etc/network/interfaces pour $IFACE UNIQUEMENT"
}

cleanup_nm_connections() {
    log "[4] Nettoyage des connexions NetworkManager pour $IFACE UNIQUEMENT"

    local connections=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE$" | cut -d: -f1)

    if [ -n "$connections" ]; then
        while IFS= read -r conn; do
            log "Suppression de la connexion NetworkManager : $conn (interface: $IFACE)"
            nmcli connection delete "$conn" 2>/dev/null || log "Impossible de supprimer la connexion $conn"
        done <<< "$connections"
    else
        log "Aucune connexion NetworkManager active trouvée pour $IFACE"
    fi

    nmcli device disconnect "$IFACE" 2>/dev/null || log "Interface $IFACE déjà déconnectée"
    nmcli device set "$IFACE" managed yes 2>/dev/null || log "Impossible de définir $IFACE comme géré par NetworkManager"

    log "Autres interfaces WiFi non impactées par le nettoyage"
}

restore_dhcp_nm() {
    log "[5] Remise en DHCP de l'interface $IFACE UNIQUEMENT via NetworkManager"

    sleep 2

    local conn_name="DHCP_$IFACE"
    nmcli connection add type wifi ifname "$IFACE" con-name "$conn_name" autoconnect yes ipv4.method auto 2>/dev/null

    if [ $? -eq 0 ]; then
        log "Connexion DHCP '$conn_name' créée pour l'interface $IFACE UNIQUEMENT"
    else
        log "Échec de la création de la connexion DHCP, tentative de connexion directe sur $IFACE"
        nmcli device connect "$IFACE" 2>/dev/null || log "Impossible de connecter $IFACE"
    fi
}

restart_network_services() {
    log "[6] Redémarrage des services réseau (impact global mais nécessaire)"
    log "ATTENTION: Cette étape peut temporairement affecter toutes les interfaces"

    systemctl stop NetworkManager
    if [ $? -eq 0 ]; then
        log "NetworkManager arrêté"
        sleep 3
    else
        log "ATTENTION : Échec de l'arrêt de NetworkManager"
    fi

    systemctl stop networking
    if [ $? -eq 0 ]; then
        log "Service networking arrêté"
        sleep 2
    else
        log "ATTENTION : Échec de l'arrêt du service networking"
    fi

    log "[7] Redémarrage du service networking"
    systemctl start networking
    if [ $? -eq 0 ]; then
        log "Service networking redémarré avec succès"
        sleep 3
    else
        log "ERREUR : Échec du redémarrage du service networking"
    fi

    log "[8] Redémarrage du service NetworkManager"
    systemctl start NetworkManager
    if [ $? -eq 0 ]; then
        log "NetworkManager redémarré avec succès"
        sleep 5
    else
        log "ERREUR : Échec du redémarrage de NetworkManager"
    fi

    if systemctl is-active --quiet networking; then
        log "Service networking actif"
    else
        log "ATTENTION : Service networking non actif"
    fi

    if systemctl is-active --quiet NetworkManager; then
        log "NetworkManager actif - toutes les interfaces devraient se reconnecter automatiquement"
    else
        log "ATTENTION : NetworkManager non actif"
    fi
}

check_interface_status() {
    log "[9] Vérification de l'état final de l'interface $IFACE UNIQUEMENT"

    local retries=10
    while [ $retries -gt 0 ]; do
        if ip link show "$IFACE" >/dev/null 2>&1; then
            local ip_addr=$(ip addr show "$IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+')
            if [ -n "$ip_addr" ]; then
                log "Interface $IFACE active avec l'adresse IP : $ip_addr"
                check_other_interfaces_status
                return 0
            fi
        fi
        log "Attente de l'activation de l'interface $IFACE... (tentatives restantes: $retries)"
        sleep 3
        retries=$((retries - 1))
    done

    log "ATTENTION : Interface $IFACE ne semble pas avoir obtenu d'adresse IP via DHCP"
    check_other_interfaces_status
    return 1
}

check_other_interfaces_status() {
    log "[*] Vérification que les autres interfaces WiFi ne sont pas impactées"

    local other_wifi_interfaces=$(ip link show | grep -E '^[0-9]+: wl' | cut -d: -f2 | tr -d ' ' | grep -v "^$IFACE$")

    if [ -n "$other_wifi_interfaces" ]; then
        while IFS= read -r other_iface; do
            if [ -n "$other_iface" ]; then
                local other_ip=$(ip addr show "$other_iface" 2>/dev/null | grep -oP 'inet \K[\d.]+')
                if [ -n "$other_ip" ]; then
                    log "✓ Interface $other_iface non impactée - IP: $other_ip"
                else
                    log "⚠ Interface $other_iface sans IP (peut être normale si non utilisée)"
                fi
            fi
        done <<< "$other_wifi_interfaces"
    else
        log "Aucune autre interface WiFi détectée"
    fi
}

delete_all() {
    log "[0] Début de la suppression complète du hotspot pour $IFACE UNIQUEMENT"
    log "Les autres interfaces WiFi ne seront PAS impactées sauf durant le redémarrage des services"

    cleanup_hotspot
    cleanup_nm_connections
    clean_interfaces_file
    force_dhcp_interfaces
    restart_network_services
    restore_dhcp_nm
    check_interface_status

    log "[10] Passage de l'interface $IFACE en mode 'unmanaged'"
    set_interface_unmanaged "$IFACE"

    log "[FINI] Hotspot supprimé, interface $IFACE restaurée en DHCP et passée en mode 'unmanaged' - Autres interfaces préservées"
}

# Configuration par défaut du hotspot
HOTSPOT_SSID="${HOTSPOT_SSID:-MyHotspot}"
HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD:-12345678}"

create_hotspot() {
    log "[0] Début de la création du hotspot sur $IFACE UNIQUEMENT"
    log "Les autres interfaces WiFi ne seront PAS impactées"

    if ! iw list | grep -A 20 "wiphy" | grep -q "AP"; then
        log "Erreur : Le matériel ne supporte pas le mode AP"
        exit 1
    fi

    set_interface_managed "$IFACE"

    # Désactivation des connexions NetworkManager sur IFACE
    cleanup_nm_connections

    # Configuration IP statique
    local hotspot_ip="10.42.0.1"
    local netmask="255.255.255.0"
    ip addr flush dev "$IFACE"
    ip addr add "$hotspot_ip"/24 dev "$IFACE"
    ip link set "$IFACE" up

    # Configuration iptables pour NAT
    local internet_iface=$(get_internet_interface "$IFACE")
    iptables -t nat -A POSTROUTING -s 10.42.0.0/24 -o "$internet_iface" -j MASQUERADE
    iptables -A FORWARD -i "$IFACE" -o "$internet_iface" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i "$internet_iface" -o "$IFACE" -j ACCEPT

    # Lancement de dnsmasq pour DHCP et DNS
    dnsmasq --interface="$IFACE" --dhcp-range=10.42.0.10,10.42.0.50,12h --no-resolv --except-interface=lo --bind-interfaces

    # Lancement hostapd
    cat > /tmp/hostapd.conf << EOF
interface=$IFACE
driver=nl80211
ssid=$HOTSPOT_SSID
hw_mode=g
channel=6
wmm_enabled=1
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$HOTSPOT_PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

    hostapd /tmp/hostapd.conf &

    log "Hotspot créé avec succès sur $IFACE (SSID: $HOTSPOT_SSID)"
}

main() {
    if [ $# -eq 0 ]; then
        usage
        exit 1
    fi

    ACTION=""
    IFACE=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --exec)
                ACTION="exec"
                shift
                ;;
            --delete)
                ACTION="delete"
                shift
                ;;
            --interface=*)
                IFACE="${1#*=}"
                shift
                ;;
            --ssid=*)
                HOTSPOT_SSID="${1#*=}"
                shift
                ;;
            --password=*)
                HOTSPOT_PASSWORD="${1#*=}"
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                log "Option inconnue : $1"
                usage
                exit 1
                ;;
        esac
    done

    if [ -z "$IFACE" ]; then
        log "ERREUR : Interface wifi non spécifiée"
        usage
        exit 1
    fi

    check_prereqs

    if [ "$ACTION" = "exec" ]; then
        create_hotspot
    elif [ "$ACTION" = "delete" ]; then
        delete_all
    else
        log "ERREUR : Action non définie. Utilisez --exec ou --delete"
        usage
        exit 1
    fi
}

main "$@"
