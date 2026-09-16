#!/usr/bin/env bash
set -Eeuo pipefail

# Affiche en lecture seule les événements du cluster, du plus ancien au plus
# récent. Rien n'est créé, purgé ni modifié ; le script ne juge pas ce qu'il
# affiche — un Warning ne change pas le code de retour, le verdict relève de
# diagnostics.sh (TASK-058). kubectl seul : ni K3s, ni systemd.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5

usage() {
    cat <<'EOF'
events.sh — événements du cluster, du plus ancien au plus récent.

Usage : events.sh [--namespace <ns>] [--warnings]

  --namespace <ns>   ne garder que les événements de ce namespace
  --warnings         ne garder que les événements de type Warning
  --help             afficher cette aide

Sans option, les événements de TOUS les namespaces sont listés, par
« kubectl get events -A ». L'ordre croissant est demandé à kubectl par
--sort-by=.lastTimestamp : le plus ancien en tête, le plus récent en bas.

--warnings ajoute --field-selector type=Warning, appliqué par l'apiserver :
les événements Normal ne quittent pas le serveur. Les deux options se
combinent.

Avec --namespace, l'existence du namespace est vérifiée avant la liste :
kubectl ne signale pas un namespace inconnu sur « get events », qui rend
alors 0 avec « No resources found » — une faute de frappe passerait pour un
namespace vide.

Le kubeconfig est celui que kubectl résout lui-même ; ce script ne le
remplace pas et ne l'affiche pas. Root n'est pas requis, et chaque appel est
borné par --request-timeout. Une liste vide n'est pas une panne : les
événements expirent — une heure par défaut côté apiserver.

Codes de retour :
  0  liste affichée — vide comprise, et quel que soit le type des événements
  1  kubectl introuvable, apiserver injoignable, ou namespace inconnu
  2  option inconnue, ou --namespace sans valeur ou sans nom valable
EOF
}

NS=""
WARNINGS="non"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --namespace)
            shift
            NS="${1:-}"
            [ -n "$NS" ] || die "L'option --namespace attend un nom de namespace." 2
            # Une valeur en tiret serait prise par kubectl pour une option :
            # « --namespace -A » listerait tout le cluster.
            case "$NS" in -*) die "Nom de namespace invalide : $NS" 2 ;; esac
            shift
            ;;
        --warnings) WARNINGS="oui"; shift ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Sans kubectl ni timeout, require_cmd sort en 1 en les nommant : la commande
# n'est jamais tentée, donc aucun « command not found » du shell ne filtre.
require_cmd kubectl timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Renseigne REP — stdout de kubectl — et ERREUR — son stderr, tenu à part : un
# avertissement mêlé à la liste serait compté comme un événement. Rend le code.
REP=""; ERREUR=""
lire() {
    local code=0
    REP="$(timeout "$DELAI" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || code=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
    return "$code"
}

# La sortie d'erreur de kubectl n'est montrée qu'en cas d'échec.
montrer_erreur() {
    [ -n "$ERREUR" ] || return 0
    printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
}

# L'existence du namespace se vérifie à part : « kubectl get events -n inconnu »
# rend 0 avec « No resources found », sans distinguer la faute de frappe du
# namespace réellement vide. L'échec de cette vérification a deux causes, que
# seul le message de kubectl sépare : namespace absent, ou apiserver muet.
if [ -n "$NS" ] && ! lire get namespace "$NS" --no-headers; then
    montrer_erreur
    case "$ERREUR" in
        *NotFound*) die "Namespace inconnu : $NS" ;;
        *) die "L'apiserver n'a pas répondu : le namespace $NS n'a pas pu être vérifié." ;;
    esac
fi

portee="tous les namespaces"
appel=(get events -A --sort-by=.lastTimestamp)
if [ -n "$NS" ]; then
    portee="namespace $NS"
    appel=(get events -n "$NS" --sort-by=.lastTimestamp)
fi
if [ "$WARNINGS" = "oui" ]; then
    appel+=(--field-selector type=Warning)
fi

if ! lire "${appel[@]}"; then
    montrer_erreur
    die "L'apiserver n'a pas rendu la liste des événements ($portee)."
fi

printf '\nÉvénements (%s)\n' "$portee"
if [ "$WARNINGS" = "oui" ]; then
    printf 'Filtre : type=Warning\n'
fi

# kubectl annonce une liste vide sur stderr, avec un code 0 : stdout est alors
# vide. « No resources found… » n'est pas une ligne à compter.
if [ -z "$REP" ]; then
    info "Aucun événement dans $portee."
    exit 0
fi

printf '%s\n' "$REP" | sed 's/^/  /'
# kubectl rend une ligne d'en-tête : elle s'affiche, mais n'est pas un événement.
lignes="$(printf '%s\n' "$REP" | wc -l)"
success "$((lignes - 1)) événement(s) — $portee."
