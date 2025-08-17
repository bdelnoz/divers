# enable_micro.sh

#!/bin/bash

# Chercher le périphérique audio d'enregistrement (micro)
micro_device=$(arecord -l | grep -i "device" | awk -F'[ :]+' '{print $2}')

# Vérifier si un périphérique a été trouvé
if [ -z "$micro_device" ]; then
    echo "Aucun périphérique audio de type micro trouvé."
    exit 1
fi

# Activer le périphérique en utilisant alsa
echo "Activation du périphérique $micro_device"
sudo amixer -c $micro_device sset 'Capture' cap

# Optionnel : Activer le module du noyau associé à ce périphérique
# module_name=$(lsmod | grep snd | awk '{print $1}' | head -n 1)
# sudo modprobe $module_name
