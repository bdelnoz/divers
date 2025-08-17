#!/bin/bash

IFACE="wlan0"

echo "[*] Tentative remise DOWN de $IFACE..."
sudo ip link set "$IFACE" down
sleep 2

echo "[*] Tentative remise UP de $IFACE..."
sudo ip link set "$IFACE" up
sleep 2

echo "[*] Etat interface :"
ip link show "$IFACE"

