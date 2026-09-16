#!/usr/bin/env bash
set -Eeuo pipefail

# Affiche en lecture seule la consommation CPU et mémoire du cluster. L'API
# metrics décide du mode : présente, « kubectl top » ; absente, la capacité et
# l'allocatable des nœuds prennent le relais et le relevé le dit. Rien n'est
# créé, redémarré ni modifié ; kubectl seul : ni K3s, ni systemd.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5                 # --request-timeout demandé à kubectl, en secondes
REVEIL=$((DELAI + 2))   # timeout qui l'entoure : lui laisser le temps d'écrire

usage() {
    cat <<'EOF'
resource-usage.sh — CPU et mémoire des nœuds et des pods, en lecture seule.

Usage : resource-usage.sh [--namespace <ns>] [--help]

  --namespace <ns>   ne relever les pods que de ce namespace
  --help             afficher cette aide

Deux modes, selon ce que le cluster expose : l'API metrics répond, et
« kubectl top nodes » puis « kubectl top pods » rendent la consommation ; ou
elle est absente — [WARN] le dit, et la capacité et l'allocatable des nœuds
sont relevés à sa place par « kubectl describe nodes ». K3s embarque
metrics-server, un cluster managé pas toujours : cette absence n'est pas une
panne, le relevé est rendu et vaut 0. Le kubeconfig est celui que kubectl
résout seul (KUBECONFIG, sinon ~/.kube/config) ; root n'est pas requis, rien
n'est écrit sur le cluster, chaque appel est borné par --request-timeout.

Codes de retour :
  0  relevé affiché — métriques du cluster, ou capacité des nœuds à défaut
  1  kubectl introuvable, apiserver injoignable, droits insuffisants, ou une
     rubrique du relevé illisible
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
            # « --namespace -A » relèverait tout le cluster.
            case "$NS" in -*) die "Nom de namespace invalide : $NS" 2 ;; esac
            shift
            ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# require_cmd sort en 1 en nommant ce qui manque : la commande n'est jamais
# tentée, donc aucun « command not found » du shell ne filtre.
require_cmd kubectl timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Renseigne REP — stdout de kubectl — et ERREUR — son stderr, tenu à part : un
# avertissement mêlé au tableau serait compté comme une ligne de données. La
# sortie d'erreur n'est montrée qu'en cas d'échec.
REP=""; ERREUR=""
lire() {
    local code=0
    REP="$(timeout "$REVEIL" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || code=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
    return "$code"
}
montrer_erreur() {
    [ -n "$ERREUR" ] || return 0
    printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
}

# La sonde précède tout : « kubectl top » échoue pareillement si l'API metrics
# manque ou si l'apiserver est muet.
if ! lire get nodes --no-headers; then
    montrer_erreur
    case "$ERREUR" in
        *Forbidden*) error "Droits insuffisants pour lire les nœuds : « kubectl get nodes » a été refusé." ;;
        *) error "L'apiserver ne répond pas : « kubectl get nodes » a échoué." ;;
    esac
    exit 1
fi

printf '\nCPU et mémoire des nœuds\n'
if lire top nodes --no-headers && [ -n "$REP" ]; then
    printf '%s\n' "$REP" | sed 's/^/  /'
else
    # Seule cette réponse dit l'API metrics absente ; toute autre est un échec
    # de plus, que le repli sur la capacité ne répare pas — donc pas de repli.
    case "$ERREUR" in
        *"Metrics API not available"*)
            warn "API metrics absente : ni CPU ni mémoire ne peuvent être relevés." ;;
        *)
            montrer_erreur
            case "$ERREUR" in
                *Forbidden*) die "Droits insuffisants pour lire les métriques des nœuds." ;;
                *) die "Métriques des nœuds illisibles." ;;
            esac ;;
    esac

    printf '\nCapacité et allocatable des nœuds\n'
    if ! lire describe nodes; then
        montrer_erreur
        case "$ERREUR" in
            *Forbidden*) die "Droits insuffisants pour décrire les nœuds." ;;
            *NotFound*) die "L'apiserver ne connaît pas la ressource « nodes »." ;;
            *) die "L'apiserver n'a pas rendu la description des nœuds." ;;
        esac
    fi
    # Par nœud, le décrivant rend un bloc « Capacity: » puis un bloc
    # « Allocatable: », faits de lignes «   cpu: 4 ». Seuls ces deux blocs sont
    # retenus : conditions, adresses et pods occupent le reste.
    printf '  %-20s %-12s %-14s %-12s %s\n' "Nœud" "CPU" "CPU allouable" "Mémoire" "Mémoire allouable"
    printf '%s\n' "$REP" | awk '
        function emettre() {
            if (nom != "") printf "  %-20s %-12s %-14s %-12s %s\n", nom, cap["cpu"], all["cpu"], cap["memory"], all["memory"]
            delete cap; delete all; bloc = ""
        }
        /^Name:/        { emettre(); nom = $2; next }
        /^Capacity:/    { bloc = "cap"; next }
        /^Allocatable:/ { bloc = "all"; next }
        /^  [a-z-]+:/   { cle = $1; sub(/:$/, "", cle)
                          if (cle != "cpu" && cle != "memory") next
                          if (bloc == "cap") cap[cle] = $2; else if (bloc == "all") all[cle] = $2 }
        END             { emettre() }
    '
    success "Relevé terminé : capacité des nœuds, API metrics absente. Rien n'a été modifié."
    exit 0
fi

portee="tous les namespaces"; appel=(pods -A)
if [ -n "$NS" ]; then portee="namespace $NS"; appel=(pods -n "$NS"); fi

printf '\nCPU et mémoire des pods (%s)\n' "$portee"
if lire top "${appel[@]}" --no-headers; then
    if [ -n "$REP" ]; then printf '%s\n' "$REP" | sed 's/^/  /'
    else info "Aucun pod dans $portee."; fi
else
    montrer_erreur
    die "Relevé impossible : CPU et mémoire des pods. Rien n'a été modifié."
fi
success "Relevé terminé : métriques du cluster. Rien n'a été modifié."
