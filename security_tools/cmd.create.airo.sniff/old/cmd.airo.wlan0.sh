#!/bin/bash

iface="wlan0"
dir="./"
prefix="capture-"

# Passer en monitor et retirer NetworkManager proprement
sudo systemctl stop NetworkManager
sudo ip link set $iface down
sudo iw dev $iface set type monitor
sudo ip link set $iface up

# Lancer airodump-ng en arrière-plan
sudo airodump-ng --showack --real-time --manufacturer --uptime -c 1-165 \
  --write "$dir$prefix" --output-format csv,pcap $iface &

pid=$!

# Attendre durée souhaitée
sleep 60

# Arrêter airodump-ng proprement
sudo kill $pid

# Remettre propriétaire
sudo chown nox:nox "$dir"/*

# Remettre interface en managed + relancer NetworkManager
sudo ip link set $iface down
sudo iw dev $iface set type managed
sudo ip link set $iface up
sudo systemctl start NetworkManager
