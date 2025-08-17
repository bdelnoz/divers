#!/bin/bash

# Valeurs par défaut
DEFAULT_MAC="48:22:54:1C:3B:AF"
DEFAULT_IP="192.168.5.159"

MAC="${1:-$DEFAULT_MAC}"
IP="${2:-$DEFAULT_IP}"

# Nettoyage MAC pour nom fichier
MAC_CLEAN=$(echo "$MAC" | tr '[:lower:]' '[:upper:]' | tr ':' '-')

# Timestamp
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# Log
LOGDIR="$HOME/Security/Logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/investigate-${MAC_CLEAN}-$TIMESTAMP.log"

# Lancement journalisation
{
echo "=== Investigation sur le MAC : $MAC ==="
echo "IP associée : $IP"
echo "Horodatage : $TIMESTAMP"
echo "---------------------------------------"

# 0. iptables avant scan (silencieux)
echo "[0] Activation des règles IPtables (pré-scan)"
/home/nox/Security/cmd.iptables-scan.sh >/dev/null 2>&1 && echo "→ OK"
echo ""

# 1. Lookup fabricant
echo "[1] Recherche fabricant via macvendors.com"
curl -s "https://api.macvendors.com/$MAC" || echo "Erreur requête"
echo ""

# 2. Lookup local
echo "[2] Recherche locale dans oui.txt"
if [ -f oui.txt ]; then
  grep -i "${MAC:0:8}" oui.txt || echo "Non trouvé"
else
  echo "Fichier oui.txt absent"
fi
echo ""

# 3. Nmap
if [[ "$IP" =~ ^192\. ]]; then
  echo "[3] Scan Nmap de $IP"
  sudo nmap -A "$IP"
else
  echo "[3] IP invalide – scan ignoré"
fi
echo ""

# 4. Sniffing Wi-Fi
echo "[4] Sniff Wi-Fi manuel suggéré :"
echo "   sudo airmon-ng start wlan0"
echo "   sudo airodump-ng --bssid $MAC wlan0mon"
echo ""

# 5. Vérification routeur
echo "[5] Vérifie les clients connectés (interface routeur)"
echo ""

# 6. iptables post scan (silencieux)
echo "[6] Restauration des règles IPtables"
/home/nox/Security/cmd.iptables-afterscan.sh >/dev/null 2>&1 && echo "→ OK"
echo ""

echo "=== FIN ==="
echo "Log texte : $LOGFILE"

} | tee "$LOGFILE"

# Compression automatique
gzip -f "$LOGFILE" && echo "→ Log compressé : $LOGFILE.gz"

