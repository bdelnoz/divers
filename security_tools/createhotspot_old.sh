        #!/bin/bash
        # Auteur : Bruno DELNOZ
        # Email  : bruno.delnoz@protonmail.com
        # Nom du script : createhotspot.sh
        # Target usage : Gérer création, suppression et restauration d'un hotspot wifi sur une interface spécifique
        # Version : v3.2 - Date : 2025-07-20 - Améliorations isolation interfaces

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

            # Vérifier l'état actuel
            local current_state=$(get_interface_management_state "$iface")
            log "État actuel de $iface: $current_state"

            if [ "$current_state" = "unmanaged" ]; then
                log "Passage de $iface en mode 'managed'"

                # Méthode 1: Via nmcli
                nmcli device set "$iface" managed yes 2>/dev/null

                # Méthode 2: Si la première ne fonctionne pas, modifier la config NetworkManager
                if [ "$(get_interface_management_state "$iface")" = "unmanaged" ]; then
                    log "Tentative via modification de la configuration NetworkManager"

                    # Créer ou modifier le fichier de configuration pour cette interface
                    local nm_config_dir="/etc/NetworkManager/conf.d"
                    local config_file="$nm_config_dir/99-unmanage-$iface.conf"

                    # Supprimer toute configuration qui rendrait cette interface unmanaged
                    if [ -f "$config_file" ]; then
                        log "Suppression de la configuration unmanaged existante: $config_file"
                        rm -f "$config_file"
                    fi

                    # Chercher et supprimer d'autres configurations qui pourraient affecter cette interface
                    if [ -d "$nm_config_dir" ]; then
                        grep -l "interface-name=$iface" "$nm_config_dir"/*.conf 2>/dev/null | while read -r conf_file; do
                            if grep -q "managed=false" "$conf_file" 2>/dev/null; then
                                log "Suppression de la configuration dans: $conf_file"
                                sed -i "/interface-name=$iface/,/managed=false/d" "$conf_file"
                            fi
                        done
                    fi

                    # Redémarrer NetworkManager pour prendre en compte les changements
                    log "Redémarrage de NetworkManager pour appliquer les changements"
                    systemctl reload NetworkManager
                    sleep 3

                    # Forcer le mode managed
                    nmcli device set "$iface" managed yes 2>/dev/null
                fi

                # Vérification finale
                sleep 2
                local final_state=$(get_interface_management_state "$iface")
                if [ "$final_state" = "managed" ]; then
                    log "✓ Interface $iface maintenant en mode 'managed'"
                else
                    log "⚠ ATTENTION: Interface $iface toujours en mode '$final_state'"
                    log "Tentative de forçage manuel..."

                    # Dernière tentative: down/up de l'interface
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

            # Vérifier l'état actuel
            local current_state=$(get_interface_management_state "$iface")
            log "État actuel de $iface: $current_state"

            if [ "$current_state" = "managed" ]; then
                log "Passage de $iface en mode 'unmanaged'"

                # Déconnecter d'abord toute connexion active
                nmcli device disconnect "$iface" 2>/dev/null

                # Passer en mode unmanaged
                nmcli device set "$iface" managed no 2>/dev/null

                # Créer une configuration permanente pour que l'interface reste unmanaged
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

                # Recharger NetworkManager
                systemctl reload NetworkManager
                sleep 2

                # Vérification finale
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
            # NetworkManager utilise généralement 10.42.X.0/24 où X dépend de l'interface
            # Essayer de détecter le réseau actuel de l'interface
            local current_ip=$(ip addr show "$iface" 2>/dev/null | grep -oP 'inet \K[\d.]+/\d+' | head -n1)
            if [ -n "$current_ip" ]; then
                # Extraire le réseau de l'IP actuelle
                local network=$(ip route | grep "$iface" | grep -oP '\d+\.\d+\.\d+\.0/\d+' | head -n1)
                echo "$network"
            else
                # Par défaut, utiliser un réseau basé sur l'interface
                echo "10.42.0.0/24"  # Réseau par défaut NetworkManager
            fi
        }

        # Obtenir l'interface internet (celle qui n'est pas notre interface hotspot)
        get_internet_interface() {
            local hotspot_iface="$1"
            # Trouver l'interface avec la route par défaut qui n'est pas notre interface hotspot
            local default_iface=$(ip route | grep '^default' | grep -v "$hotspot_iface" | awk '{print $5}' | head -n1)
            if [ -n "$default_iface" ]; then
                echo "$default_iface"
            else
                # Fallback vers eth0 si aucune route par défaut trouvée
                echo "eth0"
            fi
        }

        # Nettoyage règles iptables SEULEMENT pour l'interface spécifiée
        cleanup_hotspot() {
            log "[1] Suppression du hotspot et désactivation du NAT pour $IFACE UNIQUEMENT"

            # Obtenir le réseau spécifique à cette interface
            local interface_network=$(get_interface_network "$IFACE")
            local internet_iface=$(get_internet_interface "$IFACE")

            log "Suppression des règles pour réseau: $interface_network via $internet_iface"

            # Supprimer UNIQUEMENT les règles spécifiques à cette interface et son réseau
            iptables -t nat -D POSTROUTING -s "$interface_network" -o "$internet_iface" -j MASQUERADE 2>/dev/null && \
                log "Règle NAT supprimée: $interface_network -> $internet_iface"

            iptables -D FORWARD -i "$IFACE" -o "$internet_iface" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && \
                log "Règle FORWARD supprimée: $IFACE -> $internet_iface"

            iptables -D FORWARD -i "$internet_iface" -o "$IFACE" -j ACCEPT 2>/dev/null && \
                log "Règle FORWARD supprimée: $internet_iface -> $IFACE"

            # Supprimer les règles INPUT/OUTPUT spécifiques à cette interface si elles existent
            iptables -D INPUT -i "$IFACE" -j ACCEPT 2>/dev/null
            iptables -D OUTPUT -o "$IFACE" -j ACCEPT 2>/dev/null

            # Arrêter seulement les processus dnsmasq liés à cette interface spécifique
            local dnsmasq_pids=$(pgrep -f "dnsmasq.*$IFACE")
            if [ -n "$dnsmasq_pids" ]; then
                echo "$dnsmasq_pids" | xargs kill -TERM 2>/dev/null
                log "Processus dnsmasq spécifiques à $IFACE arrêtés"
            fi

            log "Suppression des règles iptables UNIQUEMENT pour $IFACE terminée"
        }

        # Nettoyage config statique dans /etc/network/interfaces pour l'interface UNIQUEMENT
        clean_interfaces_file() {
            log "[2] Nettoyage /etc/network/interfaces pour $IFACE UNIQUEMENT"

            # Vérifier si le fichier existe
            if [ ! -f /etc/network/interfaces ]; then
                log "Fichier /etc/network/interfaces non trouvé, création d'un fichier minimal"
                echo "# interfaces(5) file used by ifup(8) and ifdown(8)" > /etc/network/interfaces
                echo "auto lo" >> /etc/network/interfaces
                echo "iface lo inet loopback" >> /etc/network/interfaces
                return
            fi

            # Sauvegarde du fichier original avant modification
            local backup_file="/etc/network/interfaces.bak_$(date +%s)"
            cp /etc/network/interfaces "$backup_file"
            log "Sauvegarde créée : $backup_file"

            # Création d'un fichier temporaire pour la nouvelle configuration
            local temp_file=$(mktemp)
            local in_iface_block=false
            local iface_found=false

            while IFS= read -r line; do
                # Détecter le début d'un bloc pour notre interface SEULEMENT
                if [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug)[[:space:]]+.*$IFACE([[:space:]]|$) ]]; then
                    # Vérifier que c'est bien NOTRE interface et pas une autre qui contiendrait le nom
                    if [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug)[[:space:]]+$IFACE([[:space:]]|$) ]] ||
                    [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug)[[:space:]]+.*[[:space:]]$IFACE([[:space:]]|$) ]]; then
                        in_iface_block=true
                        iface_found=true
                        log "Suppression du bloc auto/allow-hotplug pour $IFACE"
                        continue
                    fi
                elif [[ "$line" =~ ^[[:space:]]*iface[[:space:]]+$IFACE[[:space:]] ]]; then
                    in_iface_block=true
                    iface_found=true
                    log "Suppression du bloc iface pour $IFACE"
                    continue
                # Détecter la fin du bloc (ligne vide ou nouveau bloc iface/auto)
                elif [ "$in_iface_block" = true ]; then
                    if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]] ]]; then
                        in_iface_block=false
                        # Si c'est une nouvelle déclaration, on la garde
                        if [[ "$line" =~ ^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]] ]]; then
                            echo "$line" >> "$temp_file"
                        fi
                        continue
                    else
                        # On est dans le bloc de l'interface, on ignore la ligne
                        continue
                    fi
                fi

                # Si on n'est pas dans le bloc de l'interface, on garde la ligne
                if [ "$in_iface_block" = false ]; then
                    echo "$line" >> "$temp_file"
                fi
            done < /etc/network/interfaces

            # Remplacer le fichier original par le nouveau
            mv "$temp_file" /etc/network/interfaces

            if [ "$iface_found" = true ]; then
                log "Configuration statique supprimée pour $IFACE UNIQUEMENT dans /etc/network/interfaces"
            else
                log "Aucune configuration trouvée pour $IFACE dans /etc/network/interfaces"
            fi
        }

        # Forçage DHCP dans /etc/network/interfaces pour l'interface UNIQUEMENT
        force_dhcp_interfaces() {
            log "[3] Forçage DHCP dans /etc/network/interfaces pour $IFACE UNIQUEMENT"

            # Vérifier si une configuration pour cette interface existe déjà
            if grep -q "^[[:space:]]*iface[[:space:]]\+$IFACE[[:space:]]" /etc/network/interfaces; then
                log "Configuration existante trouvée pour $IFACE, elle a été nettoyée précédemment"
            fi

            # Ajouter la configuration DHCP SEULEMENT pour notre interface
            echo "" >> /etc/network/interfaces
            echo "auto $IFACE" >> /etc/network/interfaces
            echo "iface $IFACE inet dhcp" >> /etc/network/interfaces
            echo "" >> /etc/network/interfaces

            log "Configuration DHCP ajoutée dans /etc/network/interfaces pour $IFACE UNIQUEMENT"
        }

        # Nettoyage des connexions NetworkManager pour l'interface UNIQUEMENT
        cleanup_nm_connections() {
            log "[4] Nettoyage des connexions NetworkManager pour $IFACE UNIQUEMENT"

            # Lister SEULEMENT les connexions liées à notre interface spécifique
            local connections=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE$" | cut -d: -f1)

            if [ -n "$connections" ]; then
                while IFS= read -r conn; do
                    log "Suppression de la connexion NetworkManager : $conn (interface: $IFACE)"
                    nmcli connection delete "$conn" 2>/dev/null || log "Impossible de supprimer la connexion $conn"
                done <<< "$connections"
            else
                log "Aucune connexion NetworkManager active trouvée pour $IFACE"
            fi

            # Forcer la déconnexion SEULEMENT de notre interface
            nmcli device disconnect "$IFACE" 2>/dev/null || log "Interface $IFACE déjà déconnectée"

            # S'assurer que SEULEMENT notre interface est gérée par NetworkManager
            nmcli device set "$IFACE" managed yes 2>/dev/null || log "Impossible de définir $IFACE comme géré par NetworkManager"

            log "Autres interfaces WiFi non impactées par le nettoyage"
        }

        # Remise en DHCP via NetworkManager SEULEMENT pour notre interface
        restore_dhcp_nm() {
            log "[5] Remise en DHCP de l'interface $IFACE UNIQUEMENT via NetworkManager"

            # Attendre un peu pour que les changements précédents prennent effet
            sleep 2

            # Créer une nouvelle connexion DHCP SEULEMENT pour notre interface
            local conn_name="DHCP_$IFACE"
            nmcli connection add type wifi ifname "$IFACE" con-name "$conn_name" autoconnect yes ipv4.method auto 2>/dev/null

            if [ $? -eq 0 ]; then
                log "Connexion DHCP '$conn_name' créée pour l'interface $IFACE UNIQUEMENT"
            else
                log "Échec de la création de la connexion DHCP, tentative de connexion directe sur $IFACE"
                nmcli device connect "$IFACE" 2>/dev/null || log "Impossible de connecter $IFACE"
            fi
        }

        # Redémarrage services réseau avec vérifications
        restart_network_services() {
            log "[6] Redémarrage des services réseau (impact global mais nécessaire)"
            log "ATTENTION: Cette étape peut temporairement affecter toutes les interfaces"

            # Arrêter NetworkManager d'abord
            systemctl stop NetworkManager
            if [ $? -eq 0 ]; then
                log "NetworkManager arrêté"
                sleep 3
            else
                log "ATTENTION : Échec de l'arrêt de NetworkManager"
            fi

            # Arrêter networking
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
                sleep 5  # Attendre que NetworkManager initialise TOUTES les interfaces
            else
                log "ERREUR : Échec du redémarrage de NetworkManager"
            fi

            # Vérifier l'état des services
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

        # Vérification finale de l'état de l'interface UNIQUEMENT
        check_interface_status() {
            log "[9] Vérification de l'état final de l'interface $IFACE UNIQUEMENT"

            # Attendre que l'interface soit prête
            local retries=10
            while [ $retries -gt 0 ]; do
                if ip link show "$IFACE" >/dev/null 2>&1; then
                    local ip_addr=$(ip addr show "$IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+')
                    if [ -n "$ip_addr" ]; then
                        log "Interface $IFACE active avec l'adresse IP : $ip_addr"

                        # Vérifier que les autres interfaces WiFi sont toujours actives
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

        # Vérification que les autres interfaces ne sont pas impactées
        check_other_interfaces_status() {
            log "[*] Vérification que les autres interfaces WiFi ne sont pas impactées"

            # Lister toutes les interfaces WiFi sauf celle qu'on traite
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

        # Suppression propre complète SEULEMENT pour l'interface spécifiée
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

            # Passer l'interface en mode unmanaged après suppression
            log "[10] Passage de l'interface $IFACE en mode 'unmanaged'"
            set_interface_unmanaged "$IFACE"

            log "[FINI] Hotspot supprimé, interface $IFACE restaurée en DHCP et passée en mode 'unmanaged' - Autres interfaces préservées"
        }

        # Configuration par défaut du hotspot
        HOTSPOT_SSID="${HOTSPOT_SSID:-MyHotspot}"
        HOTSPOT_PASSWORD="${HOTSPOT_PASSWORD:-12345678}"

        # Création hotspot SEULEMENT sur l'interface spécifiée
        create_hotspot() {
            log "[0] Début de la création du hotspot sur $IFACE UNIQUEMENT"
            log "Les autres interfaces WiFi ne seront PAS impactées"

            # Vérifier que l'interface supporte le mode AP
            if ! iw list | grep -A 20 "wiphy" | grep -q "AP"; then
                log "ATTENTION : La carte WiFi pourrait ne pas supporter le mode Access Point"
            fi

            # ÉTAPE CRITIQUE: Passer l'interface en mode managed AVANT tout autre action
            log "[0.1] Passage de l'interface $IFACE en mode 'managed'"
            set_interface_managed "$IFACE"

            # Attendre que les changements prennent effet
            sleep 3

            # Nettoyer SEULEMENT les connexions existantes pour cette interface
            cleanup_existing_connections

            # Créer la connexion hotspot
            log "[1] Création de la connexion hotspot '$HOTSPOT_CONNECTION_NAME' sur $IFACE"
            nmcli connection add type wifi ifname "$IFACE" con-name "$HOTSPOT_CONNECTION_NAME" \
                autoconnect no ssid "$HOTSPOT_SSID" \
                wifi.mode ap wifi.band bg ipv4.method shared \
                wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$HOTSPOT_PASSWORD"

            if [ $? -ne 0 ]; then
                log "ERREUR : Échec de la création de la connexion hotspot sur $IFACE"
                return 1
            fi

            # Assurer que SEULEMENT notre interface est bien gérée et disponible
            log "[2] Préparation de l'interface $IFACE UNIQUEMENT"
            nmcli device set "$IFACE" managed yes
            nmcli device disconnect "$IFACE" 2>/dev/null

            # Attendre que l'interface soit disponible
            sleep 3

            # Vérifier que l'interface est visible et managée par NetworkManager
            if ! nmcli device status | grep -q "^$IFACE"; then
                log "ERREUR : Interface $IFACE non visible par NetworkManager"
                nmcli connection delete "$HOTSPOT_CONNECTION_NAME" 2>/dev/null
                return 1
            fi

            # Vérifier le statut de gestion
            local mgmt_state=$(get_interface_management_state "$IFACE")
            if [ "$mgmt_state" = "unmanaged" ]; then
                log "ERREUR : Interface $IFACE toujours en mode 'unmanaged' malgré la configuration"
                log "Tentative de correction..."
                set_interface_managed "$IFACE"
                sleep 3
                mgmt_state=$(get_interface_management_state "$IFACE")
                if [ "$mgmt_state" = "unmanaged" ]; then
                    log "ERREUR CRITIQUE : Impossible de passer $IFACE en mode 'managed'"
                    nmcli connection delete "$HOTSPOT_CONNECTION_NAME" 2>/dev/null
                    return 1
                fi
            fi

            # Activer le hotspot en spécifiant explicitement l'interface
            log "[3] Activation du hotspot sur l'interface $IFACE UNIQUEMENT (état: $mgmt_state)"
            nmcli connection up "$HOTSPOT_CONNECTION_NAME" ifname "$IFACE"

            if [ $? -eq 0 ]; then
                log "[4] Hotspot '$HOTSPOT_SSID' créé avec succès sur $IFACE UNIQUEMENT"
                log "    SSID: $HOTSPOT_SSID"
                log "    Mot de passe: $HOTSPOT_PASSWORD"
                log "    Interface: $IFACE (mode: managed)"

                # Vérifier l'état de l'interface
                sleep 3
                local hotspot_ip=$(ip addr show "$IFACE" 2>/dev/null | grep -oP 'inet \K[\d.]+')
                if [ -n "$hotspot_ip" ]; then
                    log "    IP du hotspot: $hotspot_ip"
                fi

                # Configurer le forwarding IP SEULEMENT pour cette interface
                setup_ip_forwarding

                # Vérifier que les autres interfaces ne sont pas impactées
                check_other_interfaces_status

                return 0
            else
                log "ERREUR : Échec de l'activation du hotspot sur $IFACE"
                log "Vérification du statut de l'interface..."
                nmcli device status | grep "$IFACE"
                # Nettoyer en cas d'échec
                nmcli connection delete "$HOTSPOT_CONNECTION_NAME" 2>/dev/null
                return 1
            fi
        }

        # Nettoyage des connexions existantes SEULEMENT pour l'interface cible
        cleanup_existing_connections() {
            log "[*] Nettoyage des connexions existantes pour $IFACE UNIQUEMENT"

            # Supprimer toute connexion hotspot existante SEULEMENT pour cette interface
            local existing_hotspot=$(nmcli -t -f NAME,DEVICE connection show | grep ":$IFACE$" | grep -i hotspot | cut -d: -f1)
            if [ -n "$existing_hotspot" ]; then
                log "Suppression de la connexion hotspot existante sur $IFACE: $existing_hotspot"
                nmcli connection delete "$existing_hotspot" 2>/dev/null
            fi

            # Supprimer spécifiquement notre connexion si elle existe
            nmcli connection delete "$HOTSPOT_CONNECTION_NAME" 2>/dev/null

            # Déconnecter SEULEMENT les connexions actives sur cette interface spécifique
            local active_conn=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":$IFACE$" | cut -d: -f1)
            if [ -n "$active_conn" ]; then
                log "Déconnexion de la connexion active sur $IFACE UNIQUEMENT: $active_conn"
                nmcli connection down "$active_conn" 2>/dev/null
            fi

            log "Nettoyage terminé pour $IFACE - autres interfaces WiFi non impactées"
        }

        # Configuration du forwarding IP SEULEMENT pour l'interface spécifiée
        setup_ip_forwarding() {
            log "[5] Configuration du partage de connexion pour $IFACE UNIQUEMENT"

            # NetworkManager avec ipv4.method=shared gère automatiquement pour notre interface:
            # - La création d'un sous-réseau (généralement 10.42.X.0/24)
            # - Les règles iptables NAT nécessaires pour CETTE interface
            # - Le serveur DHCP pour les clients de CETTE interface
            # - L'IP forwarding

            # Activer le forwarding IP global (nécessaire pour le NAT de toutes les interfaces)
            echo 1 > /proc/sys/net/ipv4/ip_forward

            # Les règles iptables sont gérées automatiquement par NetworkManager
            # SEULEMENT pour l'interface configurée en mode 'shared'
            log "Vérification des règles NetworkManager pour le partage de connexion sur $IFACE"

            # NetworkManager créera automatiquement les règles suivantes SEULEMENT pour notre interface :
            # - NAT pour le sous-réseau de cette interface spécifique
            # - FORWARD rules pour cette interface spécifique
            # - Ces règles n'affectent PAS les autres interfaces

            log "Configuration du partage de connexion terminée pour $IFACE UNIQUEMENT (géré par NetworkManager)"
            log "Les autres interfaces WiFi conservent leur configuration iptables existante"
        }

        # Main
        if [ $# -eq 0 ] || [[ "$1" == "--help" ]]; then
            usage
            exit 0
        fi

        # Vérifier les privilèges root
        if [ "$EUID" -ne 0 ]; then
            log "ERREUR : Ce script doit être exécuté en tant que root"
            exit 1
        fi

        # Analyse arguments
        for arg in "$@"; do
            case $arg in
                --exec) ACTION="exec" ;;
                --delete) ACTION="delete" ;;
                --interface=*) IFACE="${arg#*=}" ;;
                --ssid=*) HOTSPOT_SSID="${arg#*=}" ;;
                --password=*) HOTSPOT_PASSWORD="${arg#*=}" ;;
                *) ;;
            esac
        done

        # Vérifications des paramètres
        if [ -z "$IFACE" ]; then
            log "ERREUR : Interface non spécifiée."
            usage
            exit 1
        fi

        # Définir le nom de connexion après avoir récupéré l'interface
        HOTSPOT_CONNECTION_NAME="Hotspot-$IFACE"

        if [ "$ACTION" == "exec" ]; then
            if [ -z "$HOTSPOT_PASSWORD" ] || [ ${#HOTSPOT_PASSWORD} -lt 8 ]; then
                log "ERREUR : Le mot de passe doit contenir au moins 8 caractères."
                usage
                exit 1
            fi

            if [ -z "$HOTSPOT_SSID" ]; then
                HOTSPOT_SSID="MyHotspot"
                log "Utilisation du SSID par défaut: $HOTSPOT_SSID"
            fi
        fi

        # Vérifier que l'interface existe et afficher son état de gestion
        if ! ip link show "$IFACE" >/dev/null 2>&1; then
            log "ERREUR : Interface $IFACE non trouvée"
            exit 1
        fi

        # Afficher l'état de gestion actuel de l'interface
        current_mgmt_state=$(get_interface_management_state "$IFACE")
        log "État de gestion actuel de $IFACE: $current_mgmt_state"

        # Afficher les autres interfaces WiFi détectées pour information
        log "Interface cible: $IFACE"
        other_wifi=$(ip link show | grep -E '^[0-9]+: wl' | cut -d: -f2 | tr -d ' ' | grep -v "^$IFACE$" | tr '\n' ' ')
        if [ -n "$other_wifi" ]; then
            log "Autres interfaces WiFi détectées (ne seront PAS impactées): $other_wifi"
        fi

        check_prereqs

        case $ACTION in
            exec)
                if create_hotspot; then
                    echo -e "\n✓ Hotspot créé avec succès sur $IFACE UNIQUEMENT !"
                    echo "  SSID: $HOTSPOT_SSID"
                    echo "  Mot de passe: $HOTSPOT_PASSWORD"
                    echo "  Interface: $IFACE (passée en mode 'managed')"
                    if [ -n "$other_wifi" ]; then
                        echo "  Autres interfaces WiFi préservées: $other_wifi"
                    fi
                else
                    echo -e "\n✗ Échec de la création du hotspot sur $IFACE"
                    exit 1
                fi
                ;;
            delete)
                delete_all
                if [ -n "$other_wifi" ]; then
                    echo -e "\n✓ Hotspot supprimé sur $IFACE (passée en mode 'unmanaged') - Autres interfaces WiFi préservées: $other_wifi"
                else
                    echo -e "\n✓ Hotspot supprimé sur $IFACE (passée en mode 'unmanaged')"
                fi
                ;;
            *)
                usage
                exit 1
                ;;
        esac

        # Affichage résumé actions
        echo -e "\nActions réalisées POUR L'INTERFACE $IFACE UNIQUEMENT :"
        echo "1) Prérequis vérifiés"
        if [ "$ACTION" == "exec" ]; then
            echo "2) Interface $IFACE passée en mode 'managed'"
            echo "3) Connexions existantes nettoyées sur $IFACE uniquement"
            echo "4) Hotspot '$HOTSPOT_SSID' créé sur interface $IFACE uniquement"
            echo "5) Partage de connexion configuré pour $IFACE uniquement"
            echo "6) Autres interfaces WiFi non impactées"
        elif [ "$ACTION" == "delete" ]; then
            echo "2) Hotspot supprimé et NAT désactivé pour $IFACE uniquement"
            echo "3) Connexions NetworkManager nettoyées pour $IFACE uniquement"
            echo "4) Configuration statique supprimée de /etc/network/interfaces pour $IFACE"
            echo "5) Configuration DHCP ajoutée pour $IFACE uniquement"
            echo "6) Services networking et NetworkManager redémarrés (impact temporaire global)"
            echo "7) Interface $IFACE reconfigurée en DHCP via NetworkManager"
            echo "8) État final de $IFACE vérifié + vérification autres interfaces"
            echo "9) Interface $IFACE passée en mode 'unmanaged'"
            echo "10) Autres interfaces WiFi préservées et vérifiées"
        fi

        exit 0
