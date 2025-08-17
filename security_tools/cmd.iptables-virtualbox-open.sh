#!/bin/bash
# Script iptables en mode chill – tout est permis, même les gremlins réseau 🛸

iptables -F
iptables -X
iptables -Z

iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT

# Juste pour le sport, on accepte les connexions locales et ICMP
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT

# Et on log quand même les intrus, histoire de rigoler en lisant les logs
iptables -A INPUT -j LOG --log-prefix "IPTables-FreePass-IN: " --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTables-FreePass-OUT: " --log-level 4

iptables -L -v

sleep 5
