#!/bin/bash
# Auteur : Bruno DELNOz
# Email  : bruno.delnoz@protonmail.com
# Nom du script : diag_audio_voix.sh
# Target usage : Diagnostiquer anomalies audio / périphériques / logs / connexions réseau pouvant impacter la transcription vocale
# Version : v1.1 - Date : 2025-08-09
#
# Changelog :
# v1.1 - 2025-08-09
#   - Ajout d'arguments --exec et --delete, sauvegarde des rapports supprimés dans ./backups
#   - Mode help obligatoire si aucun argument
#   - Rapport numéroté post-exécution
# v1.0 - 2025-08-08
#   - Script initial : inventaire processus audio, périphériques ALSA, journalctl, connexions réseau, CPU/mémoire
#
# HELP :
#   Usage :
#     ./diag_audio_voix.sh --help        Affiche ce bloc d'aide (s'affiche aussi si aucun argument)
#     ./diag_audio_voix.sh --exec        Lance le diagnostic et génère un rapport .log dans le même dossier
#     ./diag_audio_voix.sh --delete      Supprime les rapports générés (déplace dans ./backups), demande confirmation implicite
#     ./diag_audio_voix.sh --dry-run     Montre les actions sans exécuter (utile pour vérifier)
#
#   Exemples :
#     ./diag_audio_voix.sh --exec
#     ./diag_audio_voix.sh --exec --dry-run
#     ./diag_audio_voix.sh --delete
#
# Notes de conception :
#   - Ne requiert pas sudo ; si besoin d'accès root, l'élévation doit être fournie par l'utilisateur.
#   - Tous les fichiers générés (logs, backups) sont dans le même dossier que le script.
#   - Logs détaillés nommés diag_audio_YYYY-MM-DD_HH-MM-SS.log
#   - Affichage post-exécution numéroté des actions faites.
#   - Vérification des prérequis (arecord, aplay, ss, journalctl, pkill).
#   - Argument --exec exécute le diagnostic réel.
#
################################################################################
# Vérification des prérequis
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%F_%H-%M-%S)"
LOGFILE="$SCRIPT_DIR/diag_audio_${TIMESTAMP}.log"
BACKUP_DIR="$SCRIPT_DIR/backups"

REQ_CMDS=(arecord aplay ss journalctl pkill ps grep awk head)

missing=()
for cmd in "${REQ_CMDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing+=("$cmd")
    fi
done

if [ "${#missing[@]}" -gt 0 ]; then
    echo "⚠️  Prérequis manquants : ${missing[*]}" >&2
    echo "⚠️  Installer les paquets requis (ex: alsa-utils, iproute2) puis relancer." >&2
    # Ne sort pas si l'utilisateur a demandé --help : help gère déjà l'affichage
fi

# Si aucun argument : afficher help (règle --help obligatoire)
if [ "$#" -eq 0 ]; then
    set +x
    sed -n '1,160p' "$0"
    exit 0
fi

# Parse args
DRY_RUN=0
DO_EXEC=0
DO_DELETE=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --help|-h)
            sed -n '1,160p' "$0"
            exit 0
            ;;
        --exec)
            DO_EXEC=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --delete)
            DO_DELETE=1
            shift
            ;;
        *)
            echo "Argument inconnu : $1" >&2
            exit 2
            ;;
    esac
done

# Helper: write to logfile (ou simuler)
log() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] $*"
    else
        echo "$*" | tee -a "$LOGFILE"
    fi
}

# Actions list for post-exec summary
declare -a ACTIONS

# --delete : déplacer les rapports existants vers backup (avec sauvegarde horodatée)
if [ "$DO_DELETE" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Création dossier de backup : $BACKUP_DIR"
        echo "[DRY-RUN] Déplacement des fichiers diag_audio_*.log vers $BACKUP_DIR/"
    else
        mkdir -p "$BACKUP_DIR"
        shopt -s nullglob
        moved=0
        for f in "$SCRIPT_DIR"/diag_audio_*.log; do
            mv "$f" "$BACKUP_DIR/$(basename "$f" .log)_deleted_${TIMESTAMP}.log"
            moved=$((moved+1))
        done
        shopt -u nullglob
        echo "✅ $moved fichier(s) déplacé(s) vers $BACKUP_DIR"
        ACTIONS+=("Déplacement de $moved rapport(s) vers backups")
    fi
    [ "$DO_EXEC" -eq 0 ] && { [ "$DRY_RUN" -eq 1 ] && echo "[DRY-RUN] Fin --delete" || echo "Terminé --delete"; exit 0; }
fi

# Exécution réelle du diagnostic
if [ "$DO_EXEC" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] Génération du rapport : $LOGFILE"
    else
        echo "🔍 Démarrage du diagnostic audio..." | tee "$LOGFILE"
    fi

    # 1) Stopper (simuler) recherche de processus voice2cmd.py (ne tue pas automatiquement sauf --exec réel)
    log ""
    log "=== 1) Processus audio en cours (filtrage pulse/pipewire/alsa/voice2cmd/python) ==="
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] ps aux | grep -E 'pulse|pipewire|alsa|jackd|voice2cmd|python' | grep -v grep"
    else
        ps aux | grep -E "pulse|pipewire|alsa|jackd|voice2cmd|python" | grep -v grep | tee -a "$LOGFILE"
        ACTIONS+=("Liste des processus audio collectée")
    fi

    # 2) Périphériques audio (entrée/sortie)
    log ""
    log "=== 2) Périphériques audio (entrée) : arecord -l ==="
    if command -v arecord >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[DRY-RUN] arecord -l"
        else
            arecord -l 2>&1 | tee -a "$LOGFILE"
            ACTIONS+=("Périphériques d'entrée listés")
        fi
    else
        log "arecord non disponible"
    fi

    log ""
    log "=== 2b) Périphériques audio (sortie) : aplay -l ==="
    if command -v aplay >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[DRY-RUN] aplay -l"
        else
            aplay -l 2>&1 | tee -a "$LOGFILE"
            ACTIONS+=("Périphériques de sortie listés")
        fi
    else
        log "aplay non disponible"
    fi

    # 3) Logs système pertinents
    log ""
    log "=== 3) Logs système (journalctl récents filtrés) ==="
    if command -v journalctl >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[DRY-RUN] journalctl -n 200 | grep -iE 'alsa|pulse|pipewire|audio|mic|vosk|voice2cmd|sounddevice'"
        else
            journalctl -n 200 | grep -iE "alsa|pulse|pipewire|audio|mic|vosk|voice2cmd|sounddevice" | tee -a "$LOGFILE" || true
            ACTIONS+=("Journal système filtré et ajouté au rapport")
        fi
    else
        log "journalctl non disponible"
    fi

    # 4) Connexions réseau ouvertes
    log ""
    log "=== 4) Connexions réseau (ss -tulpn) ==="
    if command -v ss >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[DRY-RUN] ss -tulpn"
        else
            ss -tulpn 2>&1 | tee -a "$LOGFILE"
            ACTIONS+=("Connexions réseau listées")
        fi
    else
        log "ss non disponible"
    fi

    # 5) Utilisation CPU/Mémoire des top processus
    log ""
    log "=== 5) Top CPU/Mémoire (ps) ==="
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 15"
    else
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -n 15 | tee -a "$LOGFILE"
        ACTIONS+=("Usage CPU/mémoire collecté")
    fi

    # 6) Espace disque
    log ""
    log "=== 6) Espace disque (df -h .) ==="
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] df -h ."
    else
        df -h . 2>&1 | tee -a "$LOGFILE"
        ACTIONS+=("Espace disque vérifié")
    fi

    # 7) Permissions / accès aux fichiers du projet (ex : ~/venv-voix-joplin, ~/Security/scripts)
    log ""
    log "=== 7) Vérification arborescence projet (existence des chemins usuels) ==="
    PROJECT_PATHS=( "~/venv-voix-joplin" "~/Security/scripts/divers/py" "~/vosk-model-fr-0.22" "~/vosk-model-small-fr-0.22" )
    for p in "${PROJECT_PATHS[@]}"; do
        expanded="$(eval echo $p)"
        if [ "$DRY_RUN" -eq 1 ]; then
            log "[DRY-RUN] test -e $expanded"
        else
            if [ -e "$expanded" ]; then
                ls -ld "$expanded" 2>&1 | tee -a "$LOGFILE"
            else
                echo "ABSENT: $expanded" | tee -a "$LOGFILE"
            fi
        fi
    done
    ACTIONS+=("Vérification arborescence projet effectuée")

    # 8) Résumé minimal d'anomalies potentielles (heuristique simple)
    log ""
    log "=== 8) Résumé heuristique (détection rapide d'éléments suspects) ==="
    if [ "$DRY_RUN" -eq 1 ]; then
        log "[DRY-RUN] Analyse heuristique simulée"
    else
        # Exemple d'heuristiques : processus voice2cmd présent, PipeWire/Pulse inactifs, utilisation CPU > 70% sur un processus audio
        if ps aux | grep -q "[v]oice2cmd.py"; then
            echo "POTENTIEL: process voice2cmd.py en cours — vérifier comportements d'enregistrement." | tee -a "$LOGFILE"
        fi
        if ss -tulpn 2>/dev/null | grep -qiE "python|voice2cmd"; then
            ss -tulpn 2>/dev/null | grep -iE "python|voice2cmd" | tee -a "$LOGFILE"
        fi
        if ps -eo comm,%cpu --sort=-%cpu | awk 'NR==2{if($2+0>70) exit 1; else exit 0}'; then
            echo "OK: Aucun processus unique >70% CPU détecté (contrôle heuristique basique)." | tee -a "$LOGFILE"
        else
            echo "POTENTIEL: Processus consommant >70% CPU détecté — voir section Top CPU." | tee -a "$LOGFILE"
        fi
        ACTIONS+=("Analyse heuristique basique effectuée")
    fi

    # Post-exec: afficher numérotation des actions réalisées
    if [ "$DRY_RUN" -eq 1 ]; then
        echo ""
        echo "[DRY-RUN] Actions simulées :"
        i=1
        for a in "${ACTIONS[@]}"; do
            echo "  $i) $a"
            i=$((i+1))
        done
    else
        echo ""
        echo "✅ Diagnostic terminé. Rapport : $LOGFILE"
        echo "Résumé des actions :"
        i=1
        for a in "${ACTIONS[@]}"; do
            echo "  $i) $a"
            i=$((i+1))
        done
    fi
fi

exit 0
