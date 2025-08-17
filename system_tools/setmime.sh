#!/bin/bash
# setmime.sh - Bruno Delnoz <bruno.delnoz@protonmail.com>
# Script complet pour gérer les associations MIME et raccourci Windows+E
# Usage: setmime.sh [thunar|nemo|dolphin]

help() {
  cat << EOF
Usage: $0 [thunar|nemo|dolphin]

Arguments :
  thunar   - Configure Thunar (par défaut)
  nemo     - Configure Nemo
  dolphin  - Configure Dolphin

Exemples :
  $0
  $0 nemo
  $0 dolphin
EOF
}

FILEMANAGER=${1:-thunar}
case $FILEMANAGER in
  thunar|nemo|dolphin) ;;
  *) echo "Gestionnaire inconnu : $FILEMANAGER" >&2; help; exit 1 ;;
esac

set_default_app() {
  local mime=$1
  local desktop=$2
  xdg-mime default "$desktop" "$mime"
}

restart_filemanager() {
  case $FILEMANAGER in
    thunar)
      pkill thunar >/dev/null 2>&1 || true
      nohup thunar >/dev/null 2>&1 &
      ;;
    nemo)
      pkill nemo >/dev/null 2>&1 || true
      nohup nemo >/dev/null 2>&1 &
      ;;
    dolphin)
      pkill dolphin >/dev/null 2>&1 || true
      nohup dolphin >/dev/null 2>&1 &
      ;;
  esac
}

update_kde_cache() {
  [[ $FILEMANAGER == "dolphin" ]] && kbuildsycoca5 --noincremental >/dev/null 2>&1
}

apply_associations() {
  case $FILEMANAGER in
    thunar)
      set_default_app text/csv libreoffice.desktop
      set_default_app application/vnd.oasis.opendocument.spreadsheet libreoffice.desktop
      set_default_app video/mp4 kdenlive.desktop
      set_default_app application/zip org.gnome.FileRoller.desktop
      set_default_app application/x-rar org.gnome.FileRoller.desktop
      set_default_app inode/directory thunar.desktop
      ;;
    nemo)
      set_default_app text/csv libreoffice.desktop
      set_default_app application/vnd.oasis.opendocument.spreadsheet libreoffice.desktop
      set_default_app video/mp4 kdenlive.desktop
      set_default_app application/zip org.gnome.FileRoller.desktop
      set_default_app application/x-rar org.gnome.FileRoller.desktop
      set_default_app inode/directory nemo.desktop
      ;;
    dolphin)
      set_default_app text/csv libreoffice.desktop
      set_default_app application/vnd.oasis.opendocument.spreadsheet libreoffice.desktop
      set_default_app video/mp4 kdenlive.desktop
      set_default_app application/zip org.kde.ark.desktop
      set_default_app application/x-rar org.kde.ark.desktop
      set_default_app inode/directory org.kde.dolphin.desktop
      update_kde_cache
      ;;
  esac
}

check_dependencies() {
  local deps=("xdg-mime")
  [[ $FILEMANAGER == "dolphin" ]] && deps+=("kbuildsycoca5")
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      echo "Dépendance manquante : $dep" >&2
      exit 1
    fi
  done
}

set_windows_e_shortcut() {
  case $FILEMANAGER in
    thunar)
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>e" -s "thunar" 2>/dev/null || \
      xfconf-query -c xfce4-keyboard-shortcuts -n -t string -p "/commands/custom/<Super>e" -s "thunar"
      ;;
    nemo)
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>e" -s "nemo" 2>/dev/null || \
      xfconf-query -c xfce4-keyboard-shortcuts -n -t string -p "/commands/custom/<Super>e" -s "nemo"
      ;;
    dolphin)
      xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Super>e" -s "dolphin" 2>/dev/null || \
      xfconf-query -c xfce4-keyboard-shortcuts -n -t string -p "/commands/custom/<Super>e" -s "dolphin"
      ;;
  esac
}

main() {
  check_dependencies
  echo "Configuration des associations MIME pour $FILEMANAGER..."
  apply_associations
  echo "Configuration du raccourci Windows+E pour ouvrir $FILEMANAGER..."
  set_windows_e_shortcut
  restart_filemanager
  echo "Terminé. Testez avec un fichier CSV et la touche Windows+E."
}

main "$@"
