#!/bin/bash
# ==============================================
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : check_brave_selenium.sh
# Target usage : Vérifie, teste, installe Selenium dans un virtualenv local et chromedriver pour Brave dans le répertoire courant
# Version : v9.5 - Date : 2025-07-18
# ==============================================

LOGFILE="check_brave_selenium.log"
TMPDIR="./tmp_test_install"
CURDIR="$(pwd)"
VENV_DIR="$CURDIR/.venv_selenium"
BRAVE_USER_PROFILE="$HOME/.config/BraveSoftware/Brave-Browser/Default"
SELENIUM_PROFILE_TMP="$CURDIR/tmp_brave_profile"

show_help() {
  echo "Usage : ./check_brave_selenium.sh --exec | --delete | --install | --test | --delete-profile | --help"
  echo ""
  echo "Exemples :"
  echo "  ./check_brave_selenium.sh --test           # Simulation installation et profil"
  echo "  ./check_brave_selenium.sh --exec           # Vérification complète"
  echo "  ./check_brave_selenium.sh --install        # Installation virtuelle selenium et chromedriver"
  echo "  ./check_brave_selenium.sh --delete          # Nettoyage venv, logs, chromedriver"
  echo "  ./check_brave_selenium.sh --delete-profile  # Supprime uniquement le profil Selenium temporaire"
  echo "  ./check_brave_selenium.sh --help           # Aide"
  echo ""
  echo "Ordre conseillé d'utilisation : --test, --exec, --install"
}

delete_all() {
  echo "Suppression de $LOGFILE, $TMPDIR, chromedriver, venv $VENV_DIR (le profil temporaire n'est PAS supprimé)" | tee -a "$LOGFILE"
  rm -f "$LOGFILE"
  rm -rf "$TMPDIR"
  rm -f "$CURDIR/chromedriver"
  rm -rf "$VENV_DIR"
  echo "Suppression terminée." | tee -a "$LOGFILE"
}

delete_profile() {
  if [ -d "$SELENIUM_PROFILE_TMP" ]; then
    echo "Suppression du profil Selenium temporaire $SELENIUM_PROFILE_TMP" | tee -a "$LOGFILE"
    rm -rf "$SELENIUM_PROFILE_TMP"
    echo "Profil temporaire supprimé." | tee -a "$LOGFILE"
  else
    echo "Profil temporaire inexistant, rien à supprimer." | tee -a "$LOGFILE"
  fi
}

check_venv_exists() {
  [ -d "$VENV_DIR" ] && [ -x "$VENV_DIR/bin/python3" ]
}

check_selenium_installed() {
  if check_venv_exists; then
    "$VENV_DIR/bin/python3" -c "import selenium" >/dev/null 2>&1
  else
    return 1
  fi
}

check_chromedriver_present() {
  [ -f "$CURDIR/chromedriver" ] && [ -x "$CURDIR/chromedriver" ]
}

ensure_venv_and_install() {
  if ! check_venv_exists; then
    echo "Création virtualenv local dans $VENV_DIR..." | tee -a "$LOGFILE"
    python3 -m venv "$VENV_DIR" | tee -a "$LOGFILE"
  fi
  echo "Installation selenium et psutil dans virtualenv (sans sudo) avec pip..." | tee -a "$LOGFILE"
  "$VENV_DIR/bin/pip" install --upgrade pip selenium webdriver-manager psutil | tee -a "$LOGFILE"
}

download_chromedriver() {
  BRAVE_VERSION=$(brave-browser --version | grep -oP '\d+\.\d+\.\d+\.\d+')
  if [ -z "$BRAVE_VERSION" ]; then
    echo "Erreur : Impossible de détecter la version de Brave." | tee -a "$LOGFILE"
    return 1
  fi
  CHROME_MAJOR=$(echo "$BRAVE_VERSION" | cut -d'.' -f1)
  LATEST=$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_$CHROME_MAJOR")
  if [ -z "$LATEST" ]; then
    echo "Aucune version spécifique trouvée, fallback LATEST_RELEASE global" | tee -a "$LOGFILE"
    LATEST=$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE")
  fi
  echo "Téléchargement chromedriver version $LATEST dans $CURDIR" | tee -a "$LOGFILE"
  wget -q "https://chromedriver.storage.googleapis.com/$LATEST/chromedriver_linux64.zip" -O "$CURDIR/chromedriver_linux64.zip"
  unzip -o "$CURDIR/chromedriver_linux64.zip" -d "$CURDIR" | tee -a "$LOGFILE"
  chmod +x "$CURDIR/chromedriver"
  rm -f "$CURDIR/chromedriver_linux64.zip"
}

prepare_selenium_profile() {
  rm -rf "$SELENIUM_PROFILE_TMP"
  echo "Clonage du profil Brave utilisateur depuis $BRAVE_USER_PROFILE vers $SELENIUM_PROFILE_TMP" | tee -a "$LOGFILE"
  cp -r "$BRAVE_USER_PROFILE" "$SELENIUM_PROFILE_TMP"
  if [ $? -ne 0 ]; then
    echo "Erreur lors du clonage du profil utilisateur Brave." | tee -a "$LOGFILE"
    return 1
  fi
  return 0
}

run_test_install() {
  echo "=== Test simulation installation avec virtualenv dans $CURDIR ===" | tee -a "$LOGFILE"
  mkdir -p "$TMPDIR"
  TEST_OK=true

  if check_venv_exists; then
    if check_selenium_installed; then
      echo "OK Selenium déjà installé dans virtualenv." | tee -a "$LOGFILE"
    else
      echo "KO Selenium absent dans virtualenv." | tee -a "$LOGFILE"
      echo "Selenium et psutil installables via pip dans virtualenv (sans sudo)." | tee -a "$LOGFILE"
      TEST_OK=false
    fi
  else
    echo "KO virtualenv local absent." | tee -a "$LOGFILE"
    echo "Virtualenv + selenium + psutil installables via python3 -m venv + pip." | tee -a "$LOGFILE"
    TEST_OK=false
  fi

  BRAVE_VERSION=$(brave-browser --version | grep -oP '\d+\.\d+\.\d+\.\d+')
  if [ -z "$BRAVE_VERSION" ]; then
    echo "KO Brave non détecté" | tee -a "$LOGFILE"
    TEST_OK=false
  else
    echo "Brave version : $BRAVE_VERSION" | tee -a "$LOGFILE"
    CHROME_MAJOR=$(echo "$BRAVE_VERSION" | cut -d'.' -f1)
    LATEST=$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_$CHROME_MAJOR")
    if [ -z "$LATEST" ]; then
      echo "Aucune version spécifique trouvée, fallback LATEST_RELEASE global" | tee -a "$LOGFILE"
      LATEST=$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE")
    fi

    if [ -z "$LATEST" ]; then
      echo "KO : Aucun chromedriver disponible" | tee -a "$LOGFILE"
      TEST_OK=false
    else
      echo "Chromedriver version à installer : $LATEST" | tee -a "$LOGFILE"
      if check_chromedriver_present; then
        echo "OK chromedriver déjà présent dans $CURDIR" | tee -a "$LOGFILE"
      else
        echo "KO chromedriver absent dans $CURDIR, installable via téléchargement." | tee -a "$LOGFILE"
        TEST_OK=false
      fi
    fi
  fi

  if prepare_selenium_profile; then
    echo "OK Profil Selenium cloné prêt." | tee -a "$LOGFILE"
  else
    echo "KO Profil Selenium cloné impossible." | tee -a "$LOGFILE"
    TEST_OK=false
  fi

  echo "=== Résultat test simulation ===" | tee -a "$LOGFILE"
  if [ "$TEST_OK" = true ]; then
    echo "TEST OK : tout est installable et profil utilisateur prêt." | tee -a "$LOGFILE"
  else
    echo "TEST KO : blocage détecté." | tee -a "$LOGFILE"
  fi
}

run_checks() {
  echo "=== Vérification Selenium Brave dans $CURDIR ===" | tee "$LOGFILE"
  OPS=()
  if check_venv_exists && check_selenium_installed; then
    echo "OK Selenium dans virtualenv" | tee -a "$LOGFILE"
    OPS+=("Selenium dans virtualenv: OK")
  else
    echo "KO Selenium dans virtualenv" | tee -a "$LOGFILE"
    OPS+=("Selenium dans virtualenv: KO")
  fi

  BRAVE_VER=$(brave-browser --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+')
  if [ -n "$BRAVE_VER" ]; then
    echo "Brave Browser version : $BRAVE_VER" | tee -a "$LOGFILE"
    OPS+=("Brave Browser détecté version $BRAVE_VER")
  else
    echo "KO Brave Browser non détecté" | tee -a "$LOGFILE"
    OPS+=("Brave Browser non détecté")
  fi

  if check_chromedriver_present; then
    echo "OK chromedriver dans $CURDIR" | tee -a "$LOGFILE"
    OPS+=("Chromedriver présent dans $CURDIR")
  else
    echo "KO chromedriver dans $CURDIR" | tee -a "$LOGFILE"
    OPS+=("Chromedriver absent dans $CURDIR")
  fi

  if [ -x /usr/bin/brave-browser ]; then
    echo "OK chemin Brave" | tee -a "$LOGFILE"
    OPS+=("Chemin /usr/bin/brave-browser OK")
  else
    echo "KO chemin Brave" | tee -a "$LOGFILE"
    OPS+=("Chemin /usr/bin/brave-browser KO")
  fi

  if prepare_selenium_profile; then
    echo "OK Profil Selenium cloné prêt." | tee -a "$LOGFILE"
    OPS+=("Profil Selenium cloné OK")
  else
    echo "KO Profil Selenium cloné impossible." | tee -a "$LOGFILE"
    OPS+=("Profil Selenium cloné KO")
  fi

  echo "=== Fin vérification ===" | tee -a "$LOGFILE"
  echo ""
  echo "Résumé des opérations :" | tee -a "$LOGFILE"
  local i=1
  for op in "${OPS[@]}"; do
    echo "  $i) $op" | tee -a "$LOGFILE"
    ((i++))
  done

  echo ""
  echo "Statut final :"
  if [[ " ${OPS[*]} " == *"KO"* ]]; then
    echo "  Des éléments sont manquants ou mal configurés."
  else
    echo "  Tout est correctement installé et configuré."
  fi | tee -a "$LOGFILE"
}

run_install() {
  OPS=()
  if ! check_venv_exists; then
    echo "Création du virtualenv local..." | tee -a "$LOGFILE"
    python3 -m venv "$VENV_DIR" | tee -a "$LOGFILE"
    OPS+=("Virtualenv créé")
  else
    echo "Virtualenv local déjà existant." | tee -a "$LOGFILE"
    OPS+=("Virtualenv existant")
  fi

  echo "Installation / mise à jour de selenium et psutil dans virtualenv (sans sudo) avec pip..." | tee -a "$LOGFILE"
  "$VENV_DIR/bin/pip" install --upgrade pip selenium webdriver-manager psutil | tee -a "$LOGFILE"
  OPS+=("Selenium, webdriver-manager et psutil installé/mis à jour")

  if ! check_chromedriver_present; then
    download_chromedriver && OPS+=("Chromedriver téléchargé et installé") || OPS+=("Erreur téléchargement chromedriver")
  else
    echo "chromedriver déjà présent dans $CURDIR." | tee -a "$LOGFILE"
    OPS+=("Chromedriver existant")
  fi

  echo ""
  echo "Résumé des opérations effectuées :" | tee -a "$LOGFILE"
  local i=1
  for op in "${OPS[@]}"; do
    echo "  $i) $op" | tee -a "$LOGFILE"
    ((i++))
  done

  echo ""
  echo "Statut final :"
  if [[ " ${OPS[*]} " == *"Erreur"* ]]; then
    echo "  Des erreurs sont survenues lors de l'installation."
  else
    echo "  Installation complétée avec succès."
  fi | tee -a "$LOGFILE"
}

case "$1" in
  --exec) run_checks ;;
  --delete) delete_all ;;
  --install) run_install ;;
  --test) run_test_install ;;
  --delete-profile) delete_profile ;;
  --help|*) show_help ;;
esac

exit 0
