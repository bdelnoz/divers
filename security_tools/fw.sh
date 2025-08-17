#!/bin/bash
set -e

# Supprimer les règles ACCEPT all parasites si présentes
iptables -D INPUT -j ACCEPT 2>/dev/null || true
iptables -D OUTPUT -j ACCEPT 2>/dev/null || true

# Politique par défaut : tout bloquer
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Vider toutes les règles existantes
iptables -F
iptables -X
iptables -Z

# Supprimer les règles ACCEPT all sur INPUT et OUTPUT si elles réapparaissent
while iptables -D INPUT -j ACCEPT 2>/dev/null; do :; done
while iptables -D OUTPUT -j ACCEPT 2>/dev/null; do :; done

iptables -L -n -v --line-numbers

# Autoriser le loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Autoriser les connexions déjà établies ou liées
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Autoriser le ping
iptables -A OUTPUT -p icmp --icmp-type echo-request -j ACCEPT
iptables -A INPUT -p icmp --icmp-type echo-reply -j ACCEPT

# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT

# DHCP
iptables -A OUTPUT -p udp --dport 67:68 --sport 67:68 -j ACCEPT

# HTTP / HTTPS
iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT

# regles pour adb
iptables -I OUTPUT 1 -o lo -p tcp --dport 5555 -j ACCEPT
iptables -I INPUT 1 -i lo -p tcp --dport 5555 -j ACCEPT
iptables -I INPUT 1 -i lo -p tcp --dport 5556 -j ACCEPT
iptables -I OUTPUT 1 -o lo -p tcp --dport 5556 -j ACCEPT

# timeserver
for ip in $(dig +short ntp.ubuntu.com); do
  iptables -A OUTPUT -p udp -d "$ip" --dport 123 -j ACCEPT
  iptables -A INPUT -p udp -s "$ip" --sport 123 -j ACCEPT
done

# === Intégration complète Docker ===

# Créer les chaînes Docker si elles n'existent pas
iptables -L DOCKER-USER -n >/dev/null 2>&1 || iptables -N DOCKER-USER
iptables -L DOCKER-ISOLATION-STAGE-1 -n >/dev/null 2>&1 || iptables -N DOCKER-ISOLATION-STAGE-1
iptables -L DOCKER-ISOLATION-STAGE-2 -n >/dev/null 2>&1 || iptables -N DOCKER-ISOLATION-STAGE-2

# Vider les chaînes
iptables -F DOCKER-USER
iptables -F DOCKER-ISOLATION-STAGE-1
iptables -F DOCKER-ISOLATION-STAGE-2

# Réinjecter les règles
iptables -A DOCKER-USER -j RETURN
iptables -A DOCKER-ISOLATION-STAGE-2 -j DROP
iptables -A DOCKER-ISOLATION-STAGE-2 -j RETURN
iptables -A DOCKER-ISOLATION-STAGE-1 -j DOCKER-ISOLATION-STAGE-2
iptables -A DOCKER-ISOLATION-STAGE-1 -j RETURN

# Appels dans FORWARD
iptables -A FORWARD -j DOCKER-USER
iptables -A FORWARD -j DOCKER-ISOLATION-STAGE-1
iptables -L DOCKER -n >/dev/null 2>&1 && iptables -A FORWARD -j DOCKER || true

# Log des paquets bloqués
iptables -A INPUT -j LOG --log-prefix "IPTables-Blocked-IN: " --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTables-Blocked-OUT: " --log-level 4

# Supprimer les règles ACCEPT all sur INPUT et OUTPUT si elles existent en 1ère position (sécuriser)
iptables -D INPUT 1 2>/dev/null || true
iptables -D OUTPUT 1 2>/dev/null || true

# Sauvegarde des règles
iptables-save > /etc/iptables/rules.v4

# Journaliser les règles appliquées
{
  echo "=== Règles iptables appliquées ==="
  iptables -L -v
} | systemd-cat -t iptables-fw || true

# Vérifier si la dernière commande a échoué
if [ $? -ne 0 ]; then
  echo "Erreur lors de l'application des règles iptables !" | systemd-cat -t iptables-fw -p err
fi

# Afficher règles ACCEPT all restantes sur INPUT et OUTPUT (debug)
iptables -S | grep '^-A INPUT -j ACCEPT' || true
iptables -S | grep '^-A OUTPUT -j ACCEPT' || true

# afficher les regles en place
clear
iptables -L -v -n
