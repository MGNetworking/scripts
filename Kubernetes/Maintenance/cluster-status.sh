#!/usr/bin/env bash
set -Eeuo pipefail

# Relève l'état d'un cluster Kubernetes quelconque, en lecture seule : aucune
# commande de ce script ne modifie le cluster. Il ne connaît que kubectl — ni
# K3s, ni systemd — et survit donc au remplacement de K3s par un cluster managé.
# Le verdict ne juge pas la santé du cluster : cela relève de diagnostics.sh.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5

usage() {
    cat <<'EOF'
cluster-status.sh — état d'un cluster Kubernetes, en lecture seule.

Usage : cluster-status.sh [--help]

Rubriques, dans cet ordre : nœuds (-o wide), versions client et serveur,
namespaces, pods, deployments et services de tous les namespaces.

Le kubeconfig est celui que kubectl résout lui-même : KUBECONFIG s'il est
défini dans l'environnement, sinon ~/.kube/config. Ce script ne le remplace
pas et ne l'affiche pas. Root n'est pas requis. Chaque appel est borné par
--request-timeout : un apiserver muet ne fige pas le relevé.

Codes de retour :
  0  cluster joignable, quel que soit l'état des pods
  1  kubectl introuvable, ou apiserver injoignable
  2  option inconnue — seul cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
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

afficher() {
    if [ -n "$REP" ]; then printf '%s\n' "$REP" | sed 's/^/  /'; else printf '  aucun élément\n'; fi
}

# Une rubrique dont l'appel échoue n'interrompt pas le relevé — un droit RBAC
# manquant sur une ressource ne doit pas taire les cinq autres —, mais son
# message d'erreur s'affiche tel quel plutôt que d'être tu.
rubrique() {
    local titre="$1"; shift
    printf '\n%s\n' "$titre"
    if lire "$@"; then
        afficher
    elif [ -n "$REP" ]; then
        printf '%s\n' "$REP" | sed 's/^/  /'
    else
        printf '  non disponible\n'
    fi
}

# La première rubrique sert de sonde : apiserver injoignable, le relevé s'arrête
# là au lieu d'enchaîner six appels voués à échouer de la même façon.
printf '\nNœuds\n'
if ! lire get nodes -o wide --no-headers; then
    if [ -n "$REP" ]; then printf '%s\n' "$REP" | sed 's/^/  /' >&2; fi
    error "L'apiserver ne répond pas : « kubectl get nodes » a échoué."
    exit 1
fi
afficher

rubrique "Versions client et serveur" version
rubrique "Namespaces" get namespaces --no-headers
rubrique "Pods (tous les namespaces)" get pods -A --no-headers
rubrique "Deployments (tous les namespaces)" get deployments -A --no-headers
rubrique "Services (tous les namespaces)" get services -A --no-headers

success "Relevé terminé : l'apiserver a répondu."
