#!/bin/bash
# Nom du script : setup_virtual_mic.sh
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Version : v1.0 - Date : 2025-08-20
# Changelog :
#   v1.0 (2025-08-20) : Création du script pour micro virtuel temps réel.

# Target usage : Création d'un micro virtuel PulseAudio pour capture audio temps réel.

# Fonction HELP
function show_help {
    echo "Usage : $0 [--exec|--delete|--help]"
    echo ""
    echo "Options :"
    echo "  --exec     : Crée et active le micro virtuel pour le flux temps réel."
    echo "  --delete   : Supprime le micro virtuel et nettoie les modules."
    echo "  --help     : Affiche ce message."
    echo ""
    echo "Exemple :"
    echo "  $0 --exec   # Crée le micro virtuel"
    echo "  $0 --delete # Supprime le micro virtuel"
    exit 0
}

# Vérification arguments
if [[ $# -eq 0 ]]; then
    show_help
fi

# Nom micro physique (à adapter : pactl list sources short)
PHYSICAL_MIC=$(pactl list sources short | grep -v monitor | head -n1 | awk '{print $2}')
VIRTUAL_MIC="VirtualVoiceMic"

# Execution
case "$1" in
    --exec)
        # Supprime existants
        pactl unload-module module-null-sink 2>/dev/null
        pactl unload-module module-loopback 2>/dev/null

        # Crée micro virtuel
        pactl load-module module-null-sink sink_name=$VIRTUAL_MIC

        # Loopback micro physique -> virtuel
        pactl load-module module-loopback source=$PHYSICAL_MIC sink=$VIRTUAL_MIC latency_msec=1

        echo "1. Micro physique : $PHYSICAL_MIC capté"
        echo "2. Micro virtuel : $VIRTUAL_MIC créé et actif"
        echo "3. Redirection flux audio : terminée"
        echo "4. Sélectionner '$VIRTUAL_MIC' dans le logiciel vocal"
        echo "Sortie conforme aux règles de contextualisation v41."
        ;;
    --delete)
        pactl unload-module module-loopback 2>/dev/null
        pactl unload-module module-null-sink 2>/dev/null
        echo "1. Micro virtuel et loopback supprimés"
        echo "Sortie conforme aux règles de contextualisation v41."
        ;;
    --help)
        show_help
        ;;
    *)
        echo "Option invalide"
        show_help
        ;;
esac
