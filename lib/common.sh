#!/usr/bin/env bash
# lib/common.sh — fonctions partagées par tous les scripts du dépôt.
#
# Chargement, depuis n'importe quel script et n'importe quelle profondeur :
#
#   _dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
#   source "$_dir/lib/common.sh"
#
# Ce fichier assure la journalisation et les vérifications, rien d'autre : il ne
# charge aucune configuration de lui-même. Un script qui a besoin d'une
# configuration de contexte appelle load_config <contexte> (voir plus bas).

# --- Garde contre un double chargement ------------------------------------
if [ -n "${_COMMON_SH_CHARGE:-}" ]; then
    return 0
fi
_COMMON_SH_CHARGE=1

# --- Racine du projet ------------------------------------------------------
SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SCRIPTS_ROOT

# --- Répertoire de logs ----------------------------------------------------
# Aucun fichier de configuration n'est lu ici : la journalisation est
# indépendante des configurations de contexte (voir load_config plus bas).
LOG_DIR="${SCRIPTS_LOG_DIR:-}"
if [ -z "$LOG_DIR" ]; then
    if [ "$(id -u)" -eq 0 ]; then
        LOG_DIR="/var/log/mgnetworking"
    else
        LOG_DIR="$SCRIPTS_ROOT/logs"
    fi
fi

# Un log par script : install-k3s.sh -> install-k3s.log
LOG_FILE=""
if mkdir -p "$LOG_DIR" 2>/dev/null; then
    LOG_FILE="$LOG_DIR/$(basename "${0%.sh}").log"
fi

# --- Couleurs : uniquement si la sortie est un terminal --------------------
if [ -t 2 ]; then
    _C_INFO=''; _C_WARN='\033[0;33m'; _C_ERROR='\033[0;31m'
    _C_SUCCESS='\033[0;32m'; _C_RESET='\033[0m'
else
    _C_INFO=''; _C_WARN=''; _C_ERROR=''; _C_SUCCESS=''; _C_RESET=''
fi

# --- Journalisation --------------------------------------------------------
_log() {
    local niveau="$1"; shift
    local couleur
    case "$niveau" in
        INFO)    couleur="$_C_INFO"    ;;
        WARN)    couleur="$_C_WARN"    ;;
        ERROR)   couleur="$_C_ERROR"   ;;
        SUCCESS) couleur="$_C_SUCCESS" ;;
        *)       couleur=''            ;;
    esac

    printf '%b[%s]%b %s\n' "$couleur" "$niveau" "$_C_RESET" "$*" >&2

    if [ -n "$LOG_FILE" ]; then
        printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$niveau" "$*" >> "$LOG_FILE"
    fi
}

info()    { _log INFO    "$@"; }
warn()    { _log WARN    "$@"; }
error()   { _log ERROR   "$@"; }
success() { _log SUCCESS "$@"; }

# Message d'erreur puis sortie. Usage : die "message" [code]
die() {
    error "$1"
    exit "${2:-1}"
}

# --- Capture de la sortie des commandes externes ---------------------------

# Exécute une commande en enregistrant sa sortie dans le log.
# Usage : run_logged apt-get upgrade -y
run_logged() {
    info "Exécution : $*"
    if [ -n "$LOG_FILE" ]; then
        "$@" 2>&1 | tee -a "$LOG_FILE"
        return "${PIPESTATUS[0]}"
    fi
    "$@"
}

# Redirige TOUTE la sortie du script courant vers le log, en plus de l'écran.
# À appeler une fois, juste après le source, dans les scripts d'installation.
# Note : la sortie n'étant plus un terminal, les couleurs se désactivent.
enable_full_logging() {
    if [ -z "$LOG_FILE" ] || [ -n "${_FULL_LOGGING:-}" ]; then
        return 0
    fi
    _FULL_LOGGING=1
    exec > >(tee -a "$LOG_FILE") 2>&1
    _C_INFO=''; _C_WARN=''; _C_ERROR=''; _C_SUCCESS=''; _C_RESET=''
    info "Journalisation complète activée : $LOG_FILE"
}

# --- Vérifications ---------------------------------------------------------
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Ce script doit être exécuté en root (ou via sudo)."
    fi
}

# Usage : require_cmd kubectl helm
require_cmd() {
    local manquantes=()
    local cmd
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            manquantes+=("$cmd")
        fi
    done
    if [ "${#manquantes[@]}" -gt 0 ]; then
        die "Commande(s) requise(s) introuvable(s) : ${manquantes[*]}"
    fi
}

# Renseigne OS_ID, OS_VERSION et OS_ARCH
detect_os() {
    if [ ! -r /etc/os-release ]; then
        die "/etc/os-release illisible : distribution non identifiable."
    fi
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-inconnu}"
    OS_VERSION="${VERSION_ID:-inconnue}"
    OS_ARCH="$(uname -m)"
    export OS_ID OS_VERSION OS_ARCH
}

# Usage : require_os debian ubuntu
require_os() {
    if [ -z "${OS_ID:-}" ]; then
        detect_os
    fi
    local attendu
    for attendu in "$@"; do
        if [ "$OS_ID" = "$attendu" ]; then
            return 0
        fi
    done
    die "Distribution non supportée : $OS_ID (attendu : $*)"
}

# --- Configuration de contexte ---------------------------------------------

# Charge un fichier de configuration depuis config/, par son nom court.
# C'est le script appelant qui décide quoi charger et quand : common.sh ne
# charge jamais de configuration de lui-même.
#
# Usage : load_config docker      -> config/docker.env
#         load_config k3s         -> config/k3s.env
#
# Un fichier demandé mais introuvable arrête le script : poursuivre sans la
# configuration attendue serait plus dangereux que s'arrêter.
load_config() {
    local nom="${1:?load_config : nom de configuration manquant}"
    local fichier="$SCRIPTS_ROOT/config/$nom.env"

    if [ ! -f "$fichier" ]; then
        die "Configuration introuvable : config/$nom.env (modèle : config/$nom.env.example)"
    fi
    # shellcheck source=/dev/null
    . "$fichier"
    info "Configuration chargée : config/$nom.env"
}

# --- Interaction -----------------------------------------------------------

# Demande confirmation. Contournable par --yes via la variable ASSUME_YES.
# Usage : confirm "Supprimer les volumes inutilisés ?" || exit 0
confirm() {
    if [ "${ASSUME_YES:-false}" = "true" ]; then
        info "Confirmation automatique : $1"
        return 0
    fi
    local reponse
    printf '%s [o/N] ' "$1" >&2
    read -r reponse
    case "$reponse" in
        [oO]|[oO][uU][iI]|[yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Gestion des erreurs ---------------------------------------------------
_on_error() {
    local code="$1" ligne="$2"
    error "Échec (code $code) à la ligne $ligne de $(basename "$0")."
}
trap '_on_error "$?" "$LINENO"' ERR
