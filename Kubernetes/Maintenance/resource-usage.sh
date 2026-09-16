#!/usr/bin/env bash
set -Eeuo pipefail

# Affiche en lecture seule la consommation CPU et mémoire du cluster. L'API
# metrics décide du mode : elle répond, « kubectl top » ; absente ou en panne, la
# capacité des nœuds prend le relais. Rien n'est modifié ; kubectl seul.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5          # --request-timeout des relevés courants, en secondes
DELAI_NOEUDS=30  # « describe nodes » : un nœud après l'autre, donc plus long
MARGE=2          # le timeout qui entoure kubectl le laisse écrire son message

usage() {
    cat <<'EOF'
resource-usage.sh — CPU et mémoire des nœuds et des pods, en lecture seule.

Usage : resource-usage.sh [--namespace <ns>] [--help]

  --namespace <ns>   ne relever les pods que de ce namespace
  --help             afficher cette aide

L'API metrics répond : « kubectl top nodes » puis « kubectl top pods », avec
leurs intitulés de colonnes. Elle manque, ou elle est installée mais en panne :
[WARN] en nomme la cause, puis la capacité et l'allocatable des nœuds sont
rendues par « kubectl describe nodes ». K3s embarque metrics-server, un cluster
managé pas toujours : cette absence n'est pas une panne, le relevé vaut 0.

Avec --namespace, un nom inconnu est refusé avant le relevé. Le kubeconfig est
celui que kubectl résout seul ; root n'est pas requis.

Codes de retour :
  0  relevé affiché — métriques du cluster, ou capacité des nœuds à défaut
  1  kubectl introuvable, apiserver injoignable, droits insuffisants,
     namespace inconnu, délai dépassé, ou une rubrique vide
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

require_cmd kubectl timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Renseigne REP — stdout de kubectl —, ERREUR — son stderr, tenu à part, car un
# avertissement mêlé au tableau serait compté comme une ligne de données — CODE.
REP=""; ERREUR=""; CODE=0; DELAI_UTILISE=0
lire() {
    local delai="$1"; shift
    DELAI_UTILISE="$delai"; CODE=0
    REP="$(timeout "$((delai + MARGE))" kubectl "$@" --request-timeout="${delai}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# L'erreur de kubectl n'est montrée qu'en cas d'échec : sur un code 0, elle porte
# « No resources found », qui n'est pas une ligne du tableau.
montrer_erreur() { [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2; }

# Traduit l'échec d'un appel kubectl. Le 124 vient de « timeout », pas de
# kubectl : le dire « apiserver injoignable » accuserait le cluster à tort.
# « cause » remplace le message des rubriques qui ont leur propre mot à dire.
echec() {
    local appel="$1" cause="${2:-}"
    montrer_erreur
    case "$CODE:$ERREUR" in
        124:*)       die "L'appel $appel a été interrompu : délai dépassé (${DELAI_UTILISE} s)." ;;
        *Forbidden*) die "Droits insuffisants : $appel a été refusé." ;;
        *NotFound*)  die "L'apiserver ne connaît pas la ressource demandée par $appel." ;;
    esac
    # Posé hors de l'expansion : une apostrophe dans ${cause:-…} vaut SC1011.
    [ -n "$cause" ] || cause="L'apiserver n'a pas répondu : $appel a échoué."
    die "$cause"
}

# La sonde précède tout : « kubectl top » échoue pareil si l'API metrics manque
# ou si l'apiserver est muet.
lire "$DELAI" get nodes
[ "$CODE" = 0 ] || echec "« kubectl get nodes »"

# « top pods -n inconnu » rend 0 sur « No resources found » : le namespace se
# vérifie donc à part, sans quoi une faute de frappe passerait pour un vide.
if [ -n "$NS" ]; then
    lire "$DELAI" get namespace "$NS"
    if [ "$CODE" != 0 ]; then
        case "$ERREUR" in *NotFound*) montrer_erreur; die "Namespace inconnu : $NS" ;; esac
        echec "« kubectl get namespace $NS »" \
            "L'apiserver n'a pas répondu : le namespace $NS n'a pas pu être vérifié."
    fi
fi

printf '\nCPU et mémoire des nœuds\n'
lire "$DELAI" top nodes
if [ "$CODE" = 0 ]; then
    # Un code 0 sans tableau est une liste vide : la rubrique n'a rien rendu, le
    # relevé est amputé, et une rubrique vide interdit le [SUCCESS] final (A78).
    [ -n "$REP" ] || { montrer_erreur; die "Aucune métrique de nœud n'a été rendue : relevé incomplet. Rien n'a été modifié."; }
    printf '%s\n' "$REP" | sed 's/^/  /'
else
    # Deux réponses disent l'API metrics hors d'usage — absente du cluster, ou
    # installée mais en panne. Toute autre est un échec de plus, que le repli ne
    # répare pas : il n'y a donc pas de repli.
    case "$ERREUR" in
        *"Metrics API not available"*) METRIQUES="absente" ;;
        *ServiceUnavailable*)          METRIQUES="indisponible" ;;
        *) echec "« kubectl top nodes »" ;;
    esac

    warn "API metrics $METRIQUES : ni CPU ni mémoire ne peuvent être relevés."
    printf '\nCapacité et allocatable des nœuds\n'
    lire "$DELAI_NOEUDS" describe nodes
    [ "$CODE" = 0 ] || echec "« kubectl describe nodes »"

    # Par nœud, le décrivant rend un bloc « Capacity: » puis un bloc
    # « Allocatable: », faits de lignes «   cpu: 4 ». Seuls ces deux blocs sont
    # retenus — ni labels, ni System Info, ni « Allocated resources ».
    printf '%s\n' "$REP" | awk '
        BEGIN { printf "  %-20s %-12s %-14s %-12s %s\n", "Nœud", "CPU", "CPU allouable", "Mémoire", "Mémoire allouable" }
        function emettre() {
            if (nom != "") printf "  %-20s %-12s %-14s %-12s %s\n", nom, cap["cpu"], all["cpu"], cap["memory"], all["memory"]
            delete cap; delete all; nom = ""
        }
        /^Name:/        { emettre(); nom = $2; next }
        /^Capacity:/    { bloc = "cap"; next }
        /^Allocatable:/ { bloc = "all"; next }
        /^[^ ]/         { bloc = ""; next }
        /^  [a-z0-9-]+:/ { cle = $1; sub(/:$/, "", cle)
                           if ((cle == "cpu" || cle == "memory") && (bloc == "cap" || bloc == "all")) {
                               if (bloc == "cap") cap[cle] = $2; else all[cle] = $2 } }
        END             { emettre() }
    '
    success "Relevé terminé : capacité des nœuds, API metrics $METRIQUES. Rien n'a été modifié."
    exit 0
fi

portee="tous les namespaces"; appel=(pods -A)
if [ -n "$NS" ]; then portee="namespace $NS"; appel=(pods -n "$NS"); fi

printf '\nCPU et mémoire des pods (%s)\n' "$portee"
lire "$DELAI" top "${appel[@]}"
[ "$CODE" = 0 ] || echec "« kubectl top ${appel[*]} »" \
    "Relevé impossible : CPU et mémoire des pods. Rien n'a été modifié."

# Sans objet à relever, kubectl n'écrit rien sur stdout — pas même les intitulés
# — et annonce l'absence sur stderr avec le code 0 : une sortie vide dit
# l'absence de données, pas une panne ; un namespace vide n'est pas un échec.
if [ -z "$REP" ]; then info "Aucun pod dans $portee."
else printf '%s\n' "$REP" | sed 's/^/  /'; fi
success "Relevé terminé : métriques du cluster. Rien n'a été modifié."
