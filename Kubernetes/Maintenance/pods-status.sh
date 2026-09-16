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

Sans option, les pods de TOUS les namespaces sont listés (kubectl get pods -A
-o wide). Avec --namespace, le namespace est vérifié avant la liste : kubectl
ne signale pas un namespace inconnu sur « get pods », qui rend alors 0 avec
« No resources found » — une faute de frappe passerait pour un namespace vide.

Le kubeconfig est celui que kubectl résout lui-même ; ce script ne le remplace
pas et ne l'affiche pas. Root n'est pas requis, et chaque appel est borné par
--request-timeout.

Codes de retour :
  0  liste affichée — vide comprise, et quel que soit l'état des pods
  1  kubectl introuvable, apiserver injoignable, ou namespace inconnu
  2  option inconnue, ou --namespace sans valeur — seuls cas de 2
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
            shift
            ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Sans kubectl, require_cmd sort en 1 en le nommant : la commande n'est jamais
# tentée, donc aucun « command not found » du shell ne filtre.
require_cmd kubectl

# Renseigne REP avec la sortie de kubectl, erreur comprise, et rend son code.
REP=""
lire() {
    local code=0
    REP="$(timeout "$DELAI" kubectl "$@" --request-timeout="${DELAI}s" 2>&1)" || code=$?
    return "$code"
}

# L'existence du namespace se vérifie à part : « kubectl get pods -n inconnu »
# rend 0 avec « No resources found », sans distinguer la faute de frappe du
# namespace réellement vide.
if [ -n "$NS" ] && ! lire get namespace "$NS" --no-headers; then
    if [ -n "$REP" ]; then printf '%s\n' "$REP" | sed 's/^/  /' >&2; fi
    die "Namespace inconnu, ou apiserver injoignable : $NS"
fi

portee="tous les namespaces"
appel=(get pods -A -o wide --no-headers)
if [ -n "$NS" ]; then
    portee="namespace $NS"
    appel=(get pods -n "$NS" -o wide --no-headers)
fi

if ! lire "${appel[@]}"; then
    if [ -n "$REP" ]; then printf '%s\n' "$REP" | sed 's/^/  /' >&2; fi
    die "L'apiserver n'a pas rendu la liste des pods ($portee)."
fi

printf '\nPods (%s)\n' "$portee"

# kubectl annonce une liste vide sur stderr, avec un code 0 : « No resources
# found… » n'est pas un pod et ne doit pas passer pour une liste.
case "$REP" in ""|"No resources found"*) info "Aucun pod dans $portee."; exit 0 ;; esac

printf '%s\n' "$REP" | sed 's/^/  /'
success "$(printf '%s\n' "$REP" | wc -l) pod(s) listé(s) — $portee."
