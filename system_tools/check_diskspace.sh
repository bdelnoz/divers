#!/bin/bash
# Auteur : Bruno Delnoz
# Email : bruno.delnoz@protonmail.com
#
# Description :
# Ce script vérifie l'utilisation du disque sur la partition racine (/).
# Il envoie une alerte dans le syslog et une notification desktop si l'utilisation dépasse certains seuils :
# - 80% : alerte standard
# - 90% : alerte critique
#
# Usage :
#   ./check_disk.sh [--help] [--test]
#
# Options :
#   --help    Affiche ce message d'aide et quitte.
#   --test    Envoie des notifications de test simulant les alertes à 80% et 90%.

# Fonction affichant l'aide
function help() {
  echo "Usage : $0 [--help] [--test]"
  echo "Ce script vérifie l'espace disque sur / et alerte selon seuils."
  echo "Options :"
  echo "  --help    Affiche cette aide"
  echo "  --test    Envoie des alertes de test"
  echo "Auteur : Bruno Delnoz (bruno.delnoz@protonmail.com)"
}

# Fonction pour envoyer une notification desktop urgente
function send_notification() {
  notify-send -u critical -t 10000 "Check Disk" "$1"
}

# Fonction test envoyant deux alertes simulées
function test_log() {
  local msg80="Attention : espace disque à 80% (test)"
  local msg90="Attention critique : espace disque à 90% (test)"
  logger -p user.info "$msg80"
  send_notification "$msg80"
  logger -p user.warning "$msg90"
  send_notification "$msg90"
  echo "Test exécuté : alertes 80% et 90% simulées envoyées."
}

# Gestion des arguments
if [[ "$#" -eq 0 ]]; then
  help
  exit 0
fi

case "$1" in
  --help)
    help
    exit 0
    ;;
  --test)
    test_log
    exit 0
    ;;
esac

# Récupération de l'utilisation disque sur /
USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')

# Vérification et alertes selon seuils
if [ "$USAGE" -ge 90 ]; then
  MSG="Alerte critique : utilisation disque à ${USAGE}% sur /"
  logger -p user.alert "$MSG"
  send_notification "$MSG"
elif [ "$USAGE" -ge 80 ]; then
  MSG="Alerte : utilisation disque à ${USAGE}% sur /"
  logger -p user.warning "$MSG"
  send_notification "$MSG"
fi

