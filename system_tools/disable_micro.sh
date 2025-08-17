@ disable_micro.sh

#!/bin/bash

# Chercher le périphérique audio d'enregistrement (micro)
micro_device=$(arecord -l | grep -i "device" | awk -F'[ :]+' '{print $2}')

# Vérifier si un périphérique a été trouvé
if [ -z "$micro_device" ]; then
    echo "Aucun périphérique audio de type micro trouvé."
    exit 1
fi

# Désactiver le périphérique en utilisant alsa
echo "Désactivation du périphérique $micro_device"
sudo amixer -c $micro_device sset 'Capture' nocap

# Optionnel : Désactiver le module du noyau associé à ce périphérique
# Vous pouvez ici utiliser modprobe pour désactiver le module
# module_name=$(lsmod | grep snd | awk '{print $1}' | head -n 1)
# sudo modprobe -r $module_name
