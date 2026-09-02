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

# --- Contexte du serveur ---------------------------------------------------
# config/server.env décrit LA MACHINE : emplacement des journaux, nom d'hôte,
# fuseau horaire, taille du fichier d'échange… Il est le seul fichier que
# common.sh charge de lui-même. Les configurations applicatives (docker.env,
# k3s.env…) restent à la charge des scripts, via load_config.
#
# Les valeurs de la ligne de commande priment toujours sur celles d'ici : un
# script lit son argument en premier et ne retombe sur la variable qu'à défaut.
if [ -f "$SCRIPTS_ROOT/config/server.env" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPTS_ROOT/config/server.env"
fi

# --- Répertoire de logs ----------------------------------------------------
# Deux niveaux : LOG_DIR issu de config/server.env s'il y est défini, sinon la
# valeur par défaut ci-dessous, écrite en dur. Le dépôt reste ainsi fonctionnel
# sans aucune configuration.
if [ -z "${LOG_DIR:-}" ]; then
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

# Neutralise le journal après un échec d'écriture, et n'avertit qu'une fois.
#
# LOG_FILE est vidé : c'est déjà la convention du socle pour « pas de journal »
# — celle retenue plus haut lorsque mkdir échoue. run_logged et
# enable_full_logging la respectent, aucun des deux ne tentera donc d'écrire
# dans un fichier hors service.
#
# L'avertissement passe par warn, dont l'écriture fichier est désormais sans
# objet puisque LOG_FILE vient d'être vidé : aucune récursion possible.
_journal_hors_service() {
    local fichier="$LOG_FILE"
    LOG_FILE=""
    if [ -n "${_JOURNAL_AVERTI:-}" ]; then
        return 0
    fi
    _JOURNAL_AVERTI=1
    warn "Journal inaccessible : $fichier — poursuite sans journalisation."
}

# Ajoute une ligne horodatée au fichier de journal, s'il y en a un.
#
# Un journal devenu inécrivable en cours d'exécution — répertoire disparu,
# disque plein, droits modifiés — n'interrompt pas le script (ADR-0003,
# décision 8). L'écriture est enveloppée pour deux raisons :
#
#   - le « if » place l'écriture dans un contexte de condition, ce qui neutralise
#     set -e : sans lui, l'échec de la redirection tue le script ;
#   - la redirection porte sur le groupe, et non sur le printf, afin que la
#     stderr soit déjà détournée quand bash tente d'ouvrir LOG_FILE. C'est ce qui
#     étouffe son message brut (« … : No such file or directory »), remplacé par
#     un avertissement lisible.
_journaliser() {
    local niveau="$1"; shift
    if [ -z "$LOG_FILE" ]; then
        return 0
    fi
    if { printf '%s [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$niveau" "$*" \
            >> "$LOG_FILE"; } 2>/dev/null; then
        return 0
    fi
    _journal_hors_service
}

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

    _journaliser "$niveau" "$@"
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
#
# La sortie de la commande part sur stderr, comme les messages de _log : deux
# flux distincts se mélangeraient à l'affichage, chacun ayant son propre tampon.
# stdout reste ainsi réservé aux données que le script produit réellement.
run_logged() {
    # L'annonce sert aussi de sonde : si le journal est devenu inécrivable, info
    # le constate et vide LOG_FILE. Le test qui suit bascule alors de lui-même
    # sur la branche sans tee, plutôt que de relancer tee sur un fichier mort.
    info "Exécution : $*"
    if [ -n "$LOG_FILE" ]; then
        "$@" 2>&1 | tee -a "$LOG_FILE" >&2
        return "${PIPESTATUS[0]}"
    fi
    "$@" >&2
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
#
# Les variables chargées sont exportées, donc visibles des processus fils
# (ADR-0003, décision 7). Les fichiers .env continuent de s'écrire en
# affectations nues : c'est set -a qui se charge de l'exportation, pas eux.
load_config() {
    local nom="${1:?load_config : nom de configuration manquant}"
    local fichier="$SCRIPTS_ROOT/config/$nom.env"

    if [ ! -f "$fichier" ]; then
        die "Configuration introuvable : config/$nom.env (modèle : config/$nom.env.example)"
    fi

    # État antérieur de allexport : le rétablir tel quel, plutôt que de le forcer
    # à « off », au cas où l'appelant l'aurait lui-même activé.
    local allexport_actif="non"
    case "$-" in *a*) allexport_actif="oui" ;; esac

    # « || code=$? » place le source dans un contexte de condition : son échec ne
    # tue plus le script sur-le-champ, et set +a est donc toujours atteint. Sans
    # cette précaution, tout ce que le script déclare ensuite serait exporté à
    # son insu.
    #
    # Contrepartie à connaître : ce contexte de condition suspend errexit
    # *pendant* l'exécution du fichier. Une commande en échec au milieu du .env
    # n'interrompt donc plus rien — le source va jusqu'au bout et rend le code de
    # sa dernière commande, le plus souvent 0. Le die ci-dessous ne se déclenche
    # que sur une erreur de syntaxe. Le risque reste théorique : config/README.md
    # prescrit des fichiers faits d'affectations, jamais de commandes.
    local code=0
    set -a
    # shellcheck source=/dev/null
    . "$fichier" || code=$?
    if [ "$allexport_actif" = "non" ]; then
        set +a
    fi

    if [ "$code" -ne 0 ]; then
        die "Configuration illisible : config/$nom.env (code $code)"
    fi
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

# Le fichier est transmis par le trap, jamais déduit ici : à l'intérieur de
# _on_error, BASH_SOURCE désignerait common.sh, où la fonction est définie.
# Évalué dans la chaîne du trap, ${BASH_SOURCE[0]} désigne au contraire le
# fichier où l'échec s'est produit — le script appelant, ou common.sh lui-même
# quand la faute vient du socle. $LINENO y renvoie à la même unité, les deux
# valeurs sont donc cohérentes entre elles (ADR-0003, décision 9).
_on_error() {
    local code="$1" ligne="$2" fichier="${3:-$0}"
    error "Échec (code $code) à la ligne $ligne de $(basename "$fichier")."
}
trap '_on_error "$?" "$LINENO" "${BASH_SOURCE[0]:-$0}"' ERR
