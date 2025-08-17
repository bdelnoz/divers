#!/bin/bash
#
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : extract_chrome_extensions.sh
# Target usage : Extraction des extensions Chrome/Brave/Chromium avec détection d'extensions potentiellement intrusives
# Version : v1.5 - Date : 2025-08-08
# Changelog :
#   v1.0 - Extraction multi-extensions + noms traduits depuis _locales, logs, options, path dynamique utilisateur
#   v1.1 - Ajout détection simple d'extensions potentiellement intrusives / bugs vocaux, log clair du statut
#   v1.2 - Correction bug recherche dossier version (listait fichiers au lieu de dossiers)
#   v1.3 - Fiabilisation liste dossiers version avec boucle fiable + logs précis
#   v1.4 - Correction incrémentation version suite demande utilisateur
#   v1.5 - Correction EOF prématurée, ajout versionning strict dans changelog

set -euo pipefail

SCRIPT_NAME=$(basename "$0")
LOG_FILE="./${SCRIPT_NAME%.sh}.log"

print_help() {
  cat <<EOF
Usage : $SCRIPT_NAME --exec | --remove | --help

Options :
  --exec    : Exécute l'extraction des extensions et génère un log
  --remove  : Supprime le fichier log généré
  --help    : Affiche ce message d'aide

Exemple :
  $SCRIPT_NAME --exec
EOF
}

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

get_translation() {
  local locale_dir="$1"
  local message_key="$2"
  local default_name="$3"
  local messages_json

  if [[ -f "$locale_dir/messages.json" ]]; then
    messages_json=$(cat "$locale_dir/messages.json")
    local regex="\"$message_key\"[[:space:]]*:[[:space:]]*\"([^\"]+)\""
    if [[ $messages_json =~ $regex ]]; then
      echo "${BASH_REMATCH[1]}"
      return
    fi
  fi
  echo "$default_name"
}

declare -A BLACKLIST_EXTENSIONS=(
  [bhchdcejhohfmigjafbampogmaanbfkg]="Potentiellement intrusive"
  [somebadextensionid]="Potentiellement responsable bug vocal"
  [anotherbadid]="Potentiellement intrusive et bug vocal"
)

if [[ $# -eq 0 || "$1" == "--help" ]]; then
  print_help
  exit 0
fi

if [[ "$1" == "--remove" ]]; then
  if [[ -f "$LOG_FILE" ]]; then
    rm -f "$LOG_FILE"
    echo "Log supprimé : $LOG_FILE"
  else
    echo "Aucun log à supprimer."
  fi
  exit 0
fi

if [[ "$1" != "--exec" ]]; then
  echo "Option invalide."
  print_help
  exit 1
fi

USER_CONFIG_PATHS=(
  "$HOME/.config/BraveSoftware/Brave-Browser/Default"
  "$HOME/.config/google-chrome/Default"
  "$HOME/.config/chromium/Default"
)

PROFILE_PATH=""
for path in "${USER_CONFIG_PATHS[@]}"; do
  if [[ -d "$path" ]]; then
    PROFILE_PATH="$path"
    break
  fi
done

if [[ -z "$PROFILE_PATH" ]]; then
  echo "Aucun dossier d'extensions Chrome/Chromium/Brave trouvé."
  exit 1
fi

log "Début extraction des extensions Chrome/Chromium/Brave"
log "Profil détecté : $PROFILE_PATH"

EXTENSIONS_DIR="$PROFILE_PATH/Extensions"
if [[ ! -d "$EXTENSIONS_DIR" ]]; then
  log "Dossier Extensions introuvable dans le profil."
  exit 1
fi

count=0
for ext_id_dir in "$EXTENSIONS_DIR"/*; do
  if [[ -d "$ext_id_dir" ]]; then
    ext_id_name=$(basename "$ext_id_dir")

    # Lister uniquement dossiers version
    version_dirs=()
    while IFS= read -r -d $'\0' dir; do
      version_dirs+=("$dir")
    done < <(find "$ext_id_dir" -mindepth 1 -maxdepth 1 -type d -print0)

    if [[ ${#version_dirs[@]} -eq 0 ]]; then
      log "Aucun dossier version trouvé pour l'extension $ext_id_name"
      continue
    fi

    # Trier versions et prendre la plus récente (ordre lexicographique suffisant ici)
    IFS=$'\n' sorted_versions=($(printf '%s\n' "${version_dirs[@]}" | sort -V))
    unset IFS
    latest_version_dir="${sorted_versions[-1]}"
    manifest_file="$latest_version_dir/manifest.json"

    if [[ ! -f "$manifest_file" ]]; then
      log "Manifest non trouvé pour l'extension $ext_id_name"
      continue
    fi

    ext_version=$(jq -r '.version' "$manifest_file" 2>/dev/null || echo "unknown")
    ext_name=$(jq -r '.name' "$manifest_file" 2>/dev/null || echo "unknown")

    if [[ "$ext_name" =~ ^__MSG_(.*)__$ ]]; then
      msg_key="${BASH_REMATCH[1]}"
      locale=$(echo "${LANG:-en}" | cut -d. -f1 | cut -d_ -f1)
      [[ -z "$locale" ]] && locale="en"
      locale_dir="$latest_version_dir/_locales/$locale"
      [[ ! -d "$locale_dir" ]] && locale_dir="$latest_version_dir/_locales/en"
      ext_name=$(get_translation "$locale_dir" "$msg_key" "$ext_name")
    fi

    status="OK"
    if [[ -n "${BLACKLIST_EXTENSIONS[$ext_id_name]:-}" ]]; then
      status="${BLACKLIST_EXTENSIONS[$ext_id_name]}"
    fi

    log "Extension ID: $ext_id_name"
    log "  Nom       : $ext_name"
    log "  Version   : $ext_version"
    log "  Statut    : $status"
    count=$((count+1))
  fi
done

log "Extraction terminée, $count extensions trouvées."

exit 0
