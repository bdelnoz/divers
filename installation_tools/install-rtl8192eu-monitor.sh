#!/bin/bash

set -e

DRIVER_NAME="rtl8192eu"
DRIVER_VERSION="1.0"
ARCHIVE_NAME="rtl8192eu.tar.gz"
SRC_DIR="/usr/src/${DRIVER_NAME}-${DRIVER_VERSION}"
DL_URL="https://dl.dropboxusercontent.com/scl/fi/4m5vtyb8ljwipbn6kky5m/rtl8192eu.tar.gz?rlkey=dxxuz5r0v5zhr1rfdzfc4l4rb&dl=1"

echo "[1/6] Nettoyage ancien driver éventuel..."
sudo modprobe -r 8192eu || true
sudo dkms remove -m $DRIVER_NAME -v $DRIVER_VERSION --all || true
sudo rm -rf "$SRC_DIR" /tmp/$ARCHIVE_NAME

echo "[2/6] Installation des paquets requis..."
sudo apt update
sudo apt install -y dkms build-essential bc linux-headers-$(uname -r) wget tar

echo "[3/6] Téléchargement de l'archive prépackagée..."
wget -O /tmp/$ARCHIVE_NAME "$DL_URL"

echo "[4/6] Extraction dans /usr/src..."
sudo tar -xzf /tmp/$ARCHIVE_NAME -C /usr/src/
sudo mv /usr/src/rtl8192eu-master "$SRC_DIR"

echo "[5/6] Configuration DKMS..."
cd "$SRC_DIR"
cat <<EOF | sudo tee dkms.conf > /dev/null
PACKAGE_NAME="$DRIVER_NAME"
PACKAGE_VERSION="$DRIVER_VERSION"
BUILT_MODULE_NAME[0]="8192eu"
DEST_MODULE_LOCATION[0]="/updates/dkms"
AUTOINSTALL="yes"
MAKE[0]="make all"
CLEAN="make clean"
EOF

echo "[6/6] Compilation et activation..."
sudo dkms add -m $DRIVER_NAME -v $DRIVER_VERSION
sudo dkms build -m $DRIVER_NAME -v $DRIVER_VERSION
sudo dkms install -m $DRIVER_NAME -v $DRIVER_VERSION

sudo modprobe 8192eu
sudo ip link set wlan1 down
sudo iw dev wlan1 set type monitor
sudo ip link set wlan1 up

echo "[✔] Installation terminée. wlan1 est maintenant en mode monitor (si supporté par le chipset)."
