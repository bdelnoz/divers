#!/bin/bash

echo "=== Vérification des interfaces réseau ==="
ip link show

echo
echo "=== Recherche de l'interface 8192eu ==="
iw dev | grep Interface

echo
echo "=== Vérification des messages récents du noyau liés au wifi ==="
dmesg | tail -40 | grep -i -E "wifi|wlan|8192eu|usb"

echo
echo "=== Etat des interfaces sans-fil ==="
iwconfig

echo
read -p "Entrez le nom de l'interface wifi (ex: wlan0) à scanner : " IFACE

echo
echo "=== Scan des réseaux wifi visibles sur $IFACE ==="
sudo iw dev "$IFACE" scan | grep SSID

