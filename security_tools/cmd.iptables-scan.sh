#!/bin/bash
# Script iptables pour autoriser uniquement trafic Nmap/Zenmap sortant avec DNS complet et ICMP

iptables -F
iptables -X
iptables -Z

iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP

# Loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Connexions établies/relatives
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Trafic sortant TCP/UDP (Nmap scans)
iptables -A OUTPUT -p tcp -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p udp -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# Réponses entrantes TCP/UDP (établi)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT

# DNS TCP et UDP
iptables -A OUTPUT -p udp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p udp --sport 53 -m conntrack --ctstate ESTABLISHED -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -m conntrack --ctstate ESTABLISHED -j ACCEPT

# ICMP
iptables -A INPUT -p icmp -j ACCEPT
iptables -A OUTPUT -p icmp -j ACCEPT

# Optionnel : logger les paquets bloqués
iptables -A INPUT -j LOG --log-prefix "IPTables-Blocked-IN: " --log-level 4
iptables -A OUTPUT -j LOG --log-prefix "IPTables-Blocked-OUT: " --log-level 4

iptables -L -v

sleep 5

