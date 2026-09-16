#!/usr/bin/env bash
set -Eeuo pipefail

# Affiche en lecture seule les pods d'un cluster Kubernetes, par kubectl seul.
# Rien n'est redémarré, supprimé ni évincé ; ni K3s ni systemd n'entrent en jeu.
# Le script ne juge pas ce qu'il affiche : un pod en échec est montré tel quel
# et ne change pas le code de retour — le verdict relève de diagnostics.sh.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5

usage() {
    cat <<'EOF'
pods-status.sh — état des pods, en lecture seule.

Usage : pods-status.sh [--namespace <ns>]

  --namespace <ns>   ne lister que les pods de ce namespace
  --help             afficher cette aide

Sans option, les pods de TOUS les namespaces sont listés, par
« kubectl get pods -A -o wide ». Avec --namespace, le namespace est vérifié
avant la liste : kubectl ne signale pas un namespace inconnu sur « get pods »,
qui rend alors 0 avec « No resources found » — une faute de frappe passerait
alors pour un namespace vide.

Le kubeconfig est celui que kubectl résout lui-même ; ce script ne le remplace
pas et ne l'affiche pas. Root n'est pas requis, et chaque appel est borné par
--request-timeout.

Codes de retour :
  0  liste affichée — vide comprise, et quel que soit l'état des pods
  1  kubectl introuvable, apiserver injoignable, ou namespace inconnu
  2  option inconnue, ou --namespace sans valeur ou sans nom valable
EOF
}

NS=""
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
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Sans kubectl ni timeout, require_cmd sort en 1 en les nommant : la commande
# n'est jamais tentée, donc aucun « command not found » du shell ne filtre.
require_cmd kubectl timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Renseigne REP — stdout de kubectl — et ERREUR — son stderr, tenu à part : un
# avertissement mêlé à la liste serait compté comme un pod. Rend le code.
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

# L'existence du namespace se vérifie à part : « kubectl get pods -n inconnu »
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
appel=(get pods -A -o wide)
if [ -n "$NS" ]; then
    portee="namespace $NS"
    appel=(get pods -n "$NS" -o wide)
fi

if ! lire "${appel[@]}"; then
    montrer_erreur
    die "L'apiserver n'a pas rendu la liste des pods ($portee)."
fi

printf '\nPods (%s)\n' "$portee"

# kubectl annonce une liste vide sur stderr, avec un code 0 : stdout est alors
# vide. « No resources found… » n'est pas une ligne à compter.
if [ -z "$REP" ]; then
    info "Aucun pod dans $portee."
    exit 0
fi

printf '%s\n' "$REP" | sed 's/^/  /'
# -o wide rend une ligne d'en-tête : elle s'affiche, mais n'est pas un pod.
lignes="$(printf '%s\n' "$REP" | wc -l)"
success "$((lignes - 1)) pod(s) listé(s) — $portee."
