#!/bin/bash
# Auteur : Bruno DELNOZ
# Email : bruno.delnoz@protonmail.com
# Nom du script : create_repo.sh
# Target usage : Initialise un dépôt Git local, crée README.md, commit initial, crée repo GitHub avec visibilité publique/privée optionnelle, logs détaillés, gestion suppression propre
# Version : v2.2 - Date : 2025-07-19 - Corrections delete-all + fix permissions GitHub

LOG_FILE="${0%.*}.log"
CONFIG_FILE="$HOME/.create_repo_config"
DRY_RUN=false
REPO_CREATED=false
TEMPLATE=""

print_help() {
  echo "Usage: $0 --exec <repo-name> [OPTIONS] | --delete <repo-name> | --delete-force <repo-name> | --delete-all <repo-name>"
  echo "Options:"
  echo "  --exec         Crée et initialise un dépôt Git nommé <repo-name>"
  echo "  --public       Rend le dépôt GitHub public"
  echo "  --private      Rend le dépôt GitHub privé (défaut)"
  echo "  --template     Utilise un template (python|web|basic)"
  echo "  --dry-run      Mode simulation, aucune action réelle"
  echo "  --delete       Supprime proprement le dépôt <repo-name> avec sauvegarde"
  echo "  --delete-force Supprime définitivement le dépôt <repo-name> sans sauvegarde"
  echo "  --delete-all   Supprime tout ce que le script a créé pour <repo-name> avec sauvegarde"
  echo "  --config       Affiche la configuration actuelle"
  echo "Exemples:"
  echo "  $0 --exec MonDepot --public --template python"
  echo "  $0 --exec MonDepot --private --dry-run"
  echo "  $0 --delete MonDepot"
  echo "  $0 --config"
  exit 0
}

log() {
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local message="$timestamp - $1"
  echo "$message" | tee -a "$LOG_FILE"
}

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    log "Configuration chargée depuis $CONFIG_FILE"
  else
    # Détection automatique du nom d'utilisateur GitHub
    OWNER=$(gh api user --jq .login 2>/dev/null || echo "bdelnoz")
    DEFAULT_BRANCH="main"
    log "Configuration par défaut utilisée (owner: $OWNER)"
  fi
}

show_config() {
  load_config
  echo "Configuration actuelle :"
  echo "  Propriétaire GitHub : $OWNER"
  echo "  Branche par défaut : ${DEFAULT_BRANCH:-main}"
  echo "  Fichier de config : $CONFIG_FILE"
  echo "  Fichier de log : $LOG_FILE"
  exit 0
}

validate_repo_name() {
  if [ -z "$REPO_NAME" ]; then
    log "Erreur : nom du dépôt manquant."
    exit 1
  fi

  if [[ ! "$REPO_NAME" =~ ^[a-zA-Z0-9._-]+$ ]] || [ ${#REPO_NAME} -gt 100 ]; then
    log "Erreur : Nom invalide. Max 100 caractères, lettres/chiffres/points/tirets/underscores uniquement"
    exit 1
  fi
}

check_prerequisites() {
  if ! command -v git &>/dev/null; then
    log "Erreur : Git non installé. Installer Git avant d'exécuter ce script."
    exit 1
  fi
  if ! command -v gh &>/dev/null; then
    log "Erreur : GitHub CLI (gh) non installé. Installer gh avant d'exécuter ce script."
    exit 1
  fi
  if ! gh auth status &>/dev/null; then
    log "Erreur : Vous n'êtes pas connecté à GitHub CLI (gh). Veuillez vous connecter avec 'gh auth login'."
    exit 1
  fi
}

safe_git_command() {
  local cmd="$1"
  local error_msg="$2"

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Commande : $cmd"
    return 0
  fi

  if ! eval "$cmd" >> "../$LOG_FILE" 2>&1; then
    log "ERREUR: $error_msg"
    log "Commande échouée: $cmd"
    exit 1
  fi
}

cleanup_on_failure() {
  if [ "$REPO_CREATED" = true ] && [ "$DRY_RUN" = false ]; then
    log "Nettoyage suite à l'échec..."
    if [ -d "$HOME/git/$REPO_NAME" ]; then
      rm -rf "$HOME/git/$REPO_NAME"
    fi
    gh repo delete "$OWNER/$REPO_NAME" --yes 2>/dev/null || true
    log "Nettoyage terminé"
  fi
}

create_from_template() {
  local template="$1"
  local readme_content=""

  case $template in
    "python")
      readme_content="# $REPO_NAME

## Description
Projet Python

## Installation
\`\`\`bash
pip install -r requirements.txt
\`\`\`

## Usage
\`\`\`bash
python main.py
\`\`\`

## Tests
\`\`\`bash
pytest
\`\`\`"

      # Création du .gitignore Python
      cat > .gitignore << 'EOF'
# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
venv/
.venv
.env
pip-log.txt
pip-delete-this-directory.txt
.coverage
.pytest_cache/
dist/
build/
*.egg-info/
EOF
      log "Template Python appliqué avec .gitignore"
      ;;
    "web")
      readme_content="# $REPO_NAME

## Demo
[Voir la démo](https://github.com/$OWNER/$REPO_NAME)

## Installation
\`\`\`bash
npm install
\`\`\`

## Développement
\`\`\`bash
npm run dev
\`\`\`

## Build
\`\`\`bash
npm run build
\`\`\`"

      # Création du .gitignore Web/Node.js
      cat > .gitignore << 'EOF'
# Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
.npm
.eslintcache

# Build outputs
dist/
build/
*.tgz
*.tar.gz

# Environment
.env
.env.local
.env.development.local
.env.test.local
.env.production.local
EOF
      log "Template Web appliqué avec .gitignore"
      ;;
    "basic"|*)
      readme_content="# $REPO_NAME

## Description
Description du projet

## Installation
Instructions d'installation

## Usage
Instructions d'utilisation"
      ;;
  esac

  echo "$readme_content" > README.md
  log "Template '$template' appliqué au README.md"
}

confirm_deletion() {
  echo "ATTENTION: Suppression de '$REPO_NAME'. Tapez 'oui' pour confirmer:"
  read -r response
  if [ "$response" != "oui" ]; then
    log "Suppression annulée par l'utilisateur"
    exit 0
  fi
}

ensure_delete_permissions() {
  # Vérifie si les permissions delete_repo sont disponibles
  # Pour les tokens, vérifie les scopes du token
  local auth_status
  auth_status=$(gh auth status 2>&1)

  if echo "$auth_status" | grep -q "Token:"; then
    # Utilisation d'un token - vérification des scopes
    echo "🔑 Détection d'un token GitHub. Vérification des permissions..."

    # Test direct de suppression pour vérifier les permissions
    local temp_test_result
    temp_test_result=$(gh api "/user" 2>&1)

    if [ $? -eq 0 ]; then
      echo "✅ Token GitHub valide détecté"
      return 0
    else
      echo "❌ Problème avec le token GitHub"
      echo "Vérifiez que votre token a les scopes suivants :"
      echo "  - repo (accès complet aux dépôts)"
      echo "  - delete_repo (suppression de dépôts)"
      echo ""
      echo "Pour mettre à jour votre token :"
      echo "1. Allez sur GitHub.com > Settings > Developer settings > Personal access tokens"
      echo "2. Modifiez votre token pour inclure les scopes 'repo' et 'delete_repo'"
      echo "3. Mettez à jour votre token avec : gh auth login --with-token"
      return 1
    fi
  else
    # Authentification interactive - tentative de refresh
    if ! echo "$auth_status" | grep -q "delete_repo"; then
      echo "⚠️  Permissions 'delete_repo' manquantes. Tentative d'obtention automatique..."
      if gh auth refresh -h github.com -s delete_repo; then
        echo "✅ Permissions 'delete_repo' obtenues avec succès"
        return 0
      else
        echo "❌ Échec de l'obtention automatique des permissions"
        echo "Veuillez exécuter manuellement : gh auth refresh -h github.com -s delete_repo"
        return 1
      fi
    fi
  fi
  return 0
}

create_repo() {
  validate_repo_name

  if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Mode simulation - aucune action réelle effectuée"
  fi

  log "1. Création du répertoire '$REPO_NAME'"
  if [ "$DRY_RUN" = false ]; then
    mkdir -p "$HOME/git/$REPO_NAME"
  fi

  log "2. Accès au répertoire '$HOME/git/$REPO_NAME'"
  if [ "$DRY_RUN" = false ]; then
    cd "$HOME/git/$REPO_NAME" || { log "Erreur : Impossible d'entrer dans $HOME/git/$REPO_NAME"; exit 1; }
  fi

  log "3. Vérification/Initialisation du dépôt Git local"
  if [ "$DRY_RUN" = false ]; then
    if [ -d ".git" ]; then
      log "Dépôt Git existant détecté - conservation des branches existantes"
      git status >> "../$LOG_FILE" 2>&1
    else
      log "Initialisation d'un nouveau dépôt Git"
      git init >> "../$LOG_FILE" 2>&1
      REPO_CREATED=true
    fi
  fi

  log "4. Gestion du fichier README.md"
  if [ "$DRY_RUN" = false ]; then
    if [ ! -f "README.md" ]; then
      log "README.md n'existe pas, création..."
      if [ -n "$TEMPLATE" ]; then
        create_from_template "$TEMPLATE"
      else
        echo "# $REPO_NAME" > README.md
      fi

      log "5. Ajout des fichiers au suivi Git"
      safe_git_command "git add ." "Impossible d'ajouter les fichiers"

      log "6. Commit initial"
      safe_git_command "git commit -m 'Initial commit'" "Échec du commit initial"
    else
      log "README.md existe déjà, pas de modification"
    fi
  fi

  # Configuration de la branche principale
  local default_branch="${DEFAULT_BRANCH:-main}"
  if [ "$default_branch" = "main" ] && [ "$DRY_RUN" = false ]; then
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    if [ "$current_branch" != "main" ] && ! git show-ref --verify --quiet refs/heads/main; then
      log "7. Renommage de la branche en 'main'"
      safe_git_command "git branch -M main" "Impossible de renommer la branche"
    fi
  fi

  log "8. Configuration du dépôt distant GitHub"
  if [ "$DRY_RUN" = false ]; then
    if ! git remote -v | grep -q "origin"; then
      log "Ajout du dépôt distant origin."
      git remote add origin "https://github.com/$OWNER/$REPO_NAME.git" >> "../$LOG_FILE" 2>&1
    fi
  fi

  local visibility_arg="private"
  if [ "$VISIBILITY" == "public" ]; then
    visibility_arg="public"
  fi

  log "9. Création repo distant GitHub avec visibilité : $visibility_arg"
  if [ "$DRY_RUN" = false ]; then
    if gh repo view "$OWNER/$REPO_NAME" &>/dev/null; then
      log "Le repo distant '$OWNER/$REPO_NAME' existe déjà. Vérification visibilité..."
      current_visibility=$(gh repo view "$OWNER/$REPO_NAME" --json visibility -q .visibility)
      if [ "$current_visibility" != "$visibility_arg" ]; then
        log "Changement de visibilité de $current_visibility à $visibility_arg"
        gh repo edit "$OWNER/$REPO_NAME" --visibility "$visibility_arg" >> "../$LOG_FILE" 2>&1
      else
        log "Visibilité déjà $visibility_arg, aucun changement nécessaire."
      fi
    else
      gh repo create "$OWNER/$REPO_NAME" --"$visibility_arg" --source=. --remote=origin --push >> "../$LOG_FILE" 2>&1
    fi
  fi

  log "10. Création branche 'Working' et configuration"
  if [ "$DRY_RUN" = false ]; then
    if gh repo view "$OWNER/$REPO_NAME" &>/dev/null; then
      log "Récupération des branches distantes existantes..."
      git fetch origin >> "../$LOG_FILE" 2>&1 || true
    fi

    if git show-ref --verify --quiet refs/heads/Working; then
      log "La branche 'Working' existe déjà"
    else
      git branch Working
      log "Branche 'Working' créée"
    fi
    git checkout Working >> "../$LOG_FILE" 2>&1
    git push --set-upstream origin Working >> "../$LOG_FILE" 2>&1
  fi

  log "11. Dépôt '$REPO_NAME' prêt (local + distant) dans ~/git/"
  if [ "$DRY_RUN" = false ]; then
    cd "$HOME" || exit 1
  fi
}

delete_repo() {
  validate_repo_name
  confirm_deletion

  if [ ! -d "$HOME/git/$REPO_NAME" ]; then
    log "Erreur : Le répertoire '$HOME/git/$REPO_NAME' n'existe pas."
    exit 1
  fi

  BACKUP_NAME="${REPO_NAME}_backup_$(date +%Y%m%d%H%M%S).tar.gz"
  log "1. Sauvegarde du répertoire '$HOME/git/$REPO_NAME' dans $BACKUP_NAME"
  tar -czf "$BACKUP_NAME" -C "$HOME/git" "$REPO_NAME"

  log "2. Suppression du répertoire '$HOME/git/$REPO_NAME'"
  rm -rf "$HOME/git/$REPO_NAME"

  log "3. Suppression terminée, sauvegarde disponible : $BACKUP_NAME"
}

delete_force() {
  validate_repo_name
  confirm_deletion

  if [ ! -d "$HOME/git/$REPO_NAME" ]; then
    log "Erreur : Le répertoire '$HOME/git/$REPO_NAME' n'existe pas."
    exit 1
  fi

  log "Suppression définitive sans sauvegarde du répertoire '$HOME/git/$REPO_NAME'"
  rm -rf "$HOME/git/$REPO_NAME"
  log "Suppression forcée terminée."
}

delete_all() {
  validate_repo_name
  confirm_deletion

  if [ ! -d "$HOME/git/$REPO_NAME" ]; then
    echo "Erreur : Le répertoire '$HOME/git/$REPO_NAME' n'existe pas."
    exit 1
  fi

  BACKUP_NAME="${REPO_NAME}_full_backup_$(date +%Y%m%d%H%M%S).tar.gz"
  echo "1. Sauvegarde complète du répertoire '$HOME/git/$REPO_NAME' dans $BACKUP_NAME"
  tar -czf "$BACKUP_NAME" -C "$HOME/git" "$REPO_NAME"

  echo "2. Suppression du repo distant GitHub"
  if gh repo view "$OWNER/$REPO_NAME" &>/dev/null; then
    echo "Repo distant '$OWNER/$REPO_NAME' trouvé, suppression en cours..."

    # Vérification et gestion des permissions delete_repo
    local delete_error
    delete_error=$(gh repo delete "$OWNER/$REPO_NAME" --yes 2>&1)

    if [ $? -eq 0 ]; then
      echo "✅ Repo distant supprimé avec succès"
    else
      if echo "$delete_error" | grep -q "403\|Must have admin rights\|delete_repo"; then
        echo "❌ Permissions insuffisantes détectées"

        if ensure_delete_permissions; then
          echo "✅ Tentative de nouvelle suppression..."
          if gh repo delete "$OWNER/$REPO_NAME" --yes; then
            echo "✅ Repo distant supprimé avec succès"
          else
            echo "❌ Échec de la suppression après vérification des permissions"
            echo "Problème possible :"
            echo "  - Token sans les scopes 'repo' et 'delete_repo'"
            echo "  - Pas de droits admin sur le dépôt"
            echo "Suppression manuelle nécessaire : https://github.com/$OWNER/$REPO_NAME"
          fi
        else
          echo "❌ Impossible de résoudre le problème de permissions"
          echo "Suppression manuelle nécessaire : https://github.com/$OWNER/$REPO_NAME"
        fi
      else
        echo "❌ Erreur lors de la suppression : $delete_error"
        echo "Suppression manuelle nécessaire : https://github.com/$OWNER/$REPO_NAME"
      fi
    fi
  else
    echo "ℹ️  Repo distant '$OWNER/$REPO_NAME' n'existe pas ou déjà supprimé"
  fi

  echo "3. Suppression complète du répertoire local '$HOME/git/$REPO_NAME'"
  rm -rf "$HOME/git/$REPO_NAME"

  echo "4. Suppression du fichier log '$LOG_FILE'"
  if [ -f "$LOG_FILE" ]; then
    rm -f "$LOG_FILE"
  fi

  echo ""
  echo "📋 Résumé de l'opération delete-all :"
  echo "  ✅ Répertoire local supprimé : $HOME/git/$REPO_NAME"
  echo "  ✅ Repo GitHub distant traité : $OWNER/$REPO_NAME"
  echo "  ✅ Sauvegarde créée : $BACKUP_NAME"
  echo "  ✅ Fichier log supprimé"
  echo ""
  echo "✅ Suppression complète terminée pour '$REPO_NAME'"
}

# Configuration du trap pour nettoyage en cas d'erreur
trap cleanup_on_failure ERR

# MAIN

if [ $# -eq 0 ] || [ "$1" == "--help" ]; then
  print_help
fi

# Chargement de la configuration
load_config

ACTION=$1
REPO_NAME=$2
VISIBILITY="private"

# Parse des options
for arg in "$@"; do
  case $arg in
    --public)
      VISIBILITY="public"
      ;;
    --private)
      VISIBILITY="private"
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --template)
      shift 2
      TEMPLATE="$1"
      ;;
    --config)
      show_config
      ;;
  esac
done

# Traitement des templates spécifiques
if [ "$#" -gt 2 ]; then
  for ((i=3; i<=$#; i++)); do
    arg=${!i}
    if [ "$arg" = "--template" ]; then
      next_i=$((i+1))
      if [ $next_i -le $# ]; then
        TEMPLATE=${!next_i}
        break
      fi
    fi
  done
fi

# Validation des prérequis sauf pour --config
if [ "$ACTION" != "--config" ]; then
  check_prerequisites
fi

case $ACTION in
  --exec)
    create_repo
    ;;
  --delete)
    delete_repo
    ;;
  --delete-force)
    delete_force
    ;;
  --delete-all)
    delete_all
    ;;
  --config)
    show_config
    ;;
  *)
    log "Erreur : Action inconnue '$ACTION'."
    print_help
    ;;
esac
