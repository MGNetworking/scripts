#!/usr/bin/env bash
set -Eeuo pipefail

# Vérifie, en lecture seule, la solution de métriques de K3s : le déploiement
# metrics-server de kube-system, l'APIService v1beta1.metrics.k8s.io et un relevé
# « kubectl top nodes ». Rien n'est installé ni reconfiguré.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5             # --request-timeout de chaque appel kubectl, en secondes
MARGE=2             # « timeout » qui l'entoure : le laisser écrire son message
NS="kube-system"    # namespace où K3s pose metrics-server
DEPLOIEMENT="metrics-server"
APISERVICE="v1beta1.metrics.k8s.io"
ATTENTE="~1 minute" # délai que met l'API metrics à servir après un démarrage

usage() {
    cat <<'EOF'
install-metrics.sh — vérifie metrics-server et l'API metrics, en lecture seule.

Usage : install-metrics.sh [--help]

Rien n'est installé : K3s fournit metrics-server, sauf --disable metrics-server.
Sont constatés le déploiement metrics-server de kube-system, l'APIService
v1beta1.metrics.k8s.io et sa condition Available, puis un relevé
« kubectl top nodes ». Chacun en échec interdit le verdict final et rend 1.

kubectl résout seul son kubeconfig — KUBECONFIG, sinon ~/.kube/config ; root
n'est pas requis, et chaque appel est borné par --request-timeout (5 s).

Codes de retour :
  0  metrics-server répond : déploiement disponible, APIService Available,
     relevé rendu
  1  kubectl ou timeout absent, cluster injoignable, kubeconfig invalide, droits
     insuffisants, déploiement ou APIService absent ou non disponible, relevé
     vide ou refusé, délai dépassé
  2  option inconnue — seul cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

require_cmd kubectl timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé au
# relevé serait lu comme une ligne de métriques.
REP=""; ERREUR=""; CODE=0
lire() {
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Traduit l'échec du dernier appel : le 124 vient de « timeout », pas du cluster.
# « cause » remplace le message des rubriques qui ont leur propre mot à dire.
echec() {
    local appel="$1" cause="${2:-}"
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel $appel a été interrompu : délai dépassé (${DELAI} s)." ;;
        *Forbidden*) die "Droits insuffisants : $appel a été refusé par le cluster." ;;
        *Unauthorized*|*x509*|*"error loading config file"*) die "Kubeconfig invalide ou périmé : $appel a été refusé." ;;
        *"could not find the requested resource"*|*"doesn't have a resource type"*) die "Ressource inconnue de l'API : $appel a échoué — l'apiserver répond, mais ne connaît pas cette ressource." ;;
    esac
    # Posé hors de l'expansion : une apostrophe dans ${cause:-…} vaut SC1011.
    [ -n "$cause" ] || cause="L'apiserver est injoignable : $appel a échoué. Vérifier l'accès par install-kubectl.sh."
    die "$cause"
}

printf '\nDéploiement %s (%s)\n' "$DEPLOIEMENT" "$NS"
lire get deployment "$DEPLOIEMENT" -n "$NS" --no-headers \
    -o 'custom-columns=IMAGE:.spec.template.spec.containers[0].image,DISPONIBLES:.status.availableReplicas,DESIREES:.spec.replicas'
case "$ERREUR" in *NotFound*) die "Déploiement $DEPLOIEMENT absent du namespace $NS : metrics-server n'est pas posé. Rien n'a été installé." ;; esac
[ "$CODE" = 0 ] || echec "« kubectl get deployment $DEPLOIEMENT -n $NS »"
[ -n "$REP" ] || die "Le déploiement $DEPLOIEMENT de $NS n'a rendu aucune ligne."
read -r IMAGE DISPONIBLES DESIREES <<<"$REP"
# Un champ absent s'affiche « <none> » et vaut zéro : aucune réplique disponible.
case "$DISPONIBLES" in ""|*[!0-9]*) DISPONIBLES=0 ;; esac
case "$DESIREES" in ""|*[!0-9]*) DESIREES=0 ;; esac
printf '  Image        %s\n  Disponibles  %s/%s\n' "$IMAGE" "$DISPONIBLES" "$DESIREES"
[ "$DISPONIBLES" -ge 1 ] || die "Déploiement $DEPLOIEMENT non disponible dans $NS : $DISPONIBLES/$DESIREES répliques disponibles. Rien n'a été modifié."

# Trois champs nommés, jamais une position : la raison de la condition est ce qui
# apprend pourquoi l'API metrics ne répond pas.
printf '\nAPIService %s\n' "$APISERVICE"
lire get apiservice "$APISERVICE" \
    -o 'jsonpath={.status.conditions[?(@.type=="Available")].status}{"|"}{.status.conditions[?(@.type=="Available")].reason}{"|"}{.status.conditions[?(@.type=="Available")].message}'
case "$ERREUR" in *NotFound*) die "APIService $APISERVICE absente du cluster : l'API metrics n'est pas enregistrée. Rien n'a été installé." ;; esac
[ "$CODE" = 0 ] || echec "« kubectl get apiservice $APISERVICE »"
IFS='|' read -r STATUT RAISON MESSAGE <<<"$REP"
printf '  Available    %s\n' "${STATUT:-absente}"
[ "$STATUT" = "True" ] || die "APIService $APISERVICE non Available (${RAISON:-raison non donnée}) : ${MESSAGE:-aucun message}. Rien n'a été installé."

printf '\nRelevé « kubectl top nodes »\n'
lire top nodes
if [ "$CODE" != 0 ]; then
    # Deux refus disent l'API metrics hors d'usage, et se distinguent : absente du
    # cluster, ou enregistrée mais pas encore en mesure de servir. Le second est le
    # cas normal juste après un démarrage, d'où le [WARN] plutôt qu'un silence.
    case "$ERREUR" in
        *"Metrics API not available"*)          warn "L'API metrics n'est pas enregistrée dans le cluster : metrics-server est absent ou désactivé." ;;
        *ServiceUnavailable*|*"not available yet"*) warn "L'API metrics est enregistrée mais ne sert pas encore de métriques : c'est le cas ${ATTENTE} après un démarrage de metrics-server." ;;
    esac
    echec "« kubectl top nodes »" "Relevé impossible : ni CPU ni mémoire n'ont pu être lus. Rien n'a été modifié."
fi
[ -n "$REP" ] || { warn "Le relevé est vide : metrics-server vient peut-être de démarrer, l'API met ${ATTENTE} à publier ses premières métriques."; die "Aucune métrique de nœud n'a été rendue : relevé incomplet. Rien n'a été modifié."; }
printf '%s\n' "$REP" | sed 's/^/  /'
success "metrics-server répond : déploiement $NS/$DEPLOIEMENT disponible ($IMAGE), APIService $APISERVICE Available, relevé rendu. Rien n'a été installé ni modifié."
