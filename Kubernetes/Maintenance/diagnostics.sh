#!/usr/bin/env bash
set -Eeuo pipefail

# Recherche en lecture seule les anomalies d'un cluster Kubernetes quelconque :
# nœuds non prêts, pods en attente ou en échec, workloads incomplets, événements
# Warning. Rien n'est corrigé, et aucun manifeste n'est relu en YAML ou en JSON,
# où étiquettes et annotations peuvent porter des valeurs sensibles. Le verdict
# est porté par le code de retour. kubectl seul : ni K3s, ni systemd.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5
ANOMALIES=0

usage() {
    cat <<'EOF'
diagnostics.sh — anomalies d'un cluster Kubernetes, en lecture seule.

Usage : diagnostics.sh [--help]

Recherche, sans jamais rien corriger :
  - les nœuds dont l'état n'est pas « Ready » ;
  - les pods Pending, CrashLoopBackOff, ImagePullBackOff, Error ou Failed ;
  - les Deployments, StatefulSets et DaemonSets dont les répliques prêtes sont
    inférieures aux désirées ;
  - les événements Warning, affichés mais sans effet sur le code de retour.

Un pod Succeeded ou Completed, Job terminé, n'est pas une anomalie. Le
kubeconfig est celui que kubectl résout lui-même : ce script ne le remplace pas
et ne l'affiche pas ; root n'est pas requis, et chaque appel est borné par
--request-timeout.

Codes de retour :
  0  aucune anomalie détectée
  1  au moins une anomalie, kubectl introuvable, ou apiserver injoignable
  2  option inconnue — seul cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Sans kubectl ni timeout, require_cmd sort en 1 en les nommant : la commande
# n'est jamais tentée, donc aucun « command not found » du shell ne filtre.
require_cmd kubectl timeout

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Renseigne REP — stdout de kubectl — et ERREUR — son stderr, tenu à part : un
# avertissement mêlé à un tableau serait lu comme une ligne de données.
REP=""; ERREUR=""
lire() {
    local code=0
    REP="$(timeout "$DELAI" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || code=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
    return "$code"
}
montrer_erreur() {
    [ -n "$ERREUR" ] || return 0
    printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
}
# Le verdict ne dépend que de ce compteur : une anomalie suffit à sortir en 1.
signaler() {
    warn "$1"
    ANOMALIES=$((ANOMALIES + 1))
}
# Rubrique relevée en tableau. Un appel qui échoue — droit RBAC manquant, par
# exemple — est compté comme anomalie sans interrompre le diagnostic : les
# rubriques suivantes restent instructives.
relever() {
    local titre="$1"; shift
    printf '\n%s\n' "$titre"
    if lire "$@"; then return 0; fi
    montrer_erreur
    signaler "Relevé impossible : $titre."
    return 1
}

# La première rubrique sert de sonde : apiserver injoignable, le diagnostic
# s'arrête là plutôt que d'enchaîner des appels voués à échouer pareillement.
printf '\nNœuds\n'
if ! lire get nodes --no-headers; then
    montrer_erreur
    error "L'apiserver ne répond pas : « kubectl get nodes » a échoué."
    exit 1
fi

# Colonnes : NAME STATUS ROLES AGE VERSION. Un nœud cordonné porte
# « Ready,SchedulingDisabled » : il est prêt, et n'est donc pas signalé.
while read -r nom etat _; do
    [ -n "$nom" ] || continue
    case "$etat" in Ready|Ready,*) ;; *) signaler "Nœud $nom non prêt : ${etat:-état inconnu}" ;; esac
done <<<"$REP"

# Colonnes : NAMESPACE NAME READY STATUS RESTARTS AGE. C'est la colonne STATUS
# qui porte la raison d'attente : CrashLoopBackOff n'est pas une phase mais une
# raison de conteneur, absente de .status.phase, qu'un conteneur d'init préfixe
# même de « Init: » — d'où les motifs à joker.
if relever "Pods (tous les namespaces)" get pods -A --no-headers; then
    examines=0
    while read -r ns nom _ etat _; do
        [ -n "$nom" ] || continue
        examines=$((examines + 1))
        case "$etat" in Pending|Failed|Error|*CrashLoopBackOff*|*ImagePullBackOff*) signaler "Pod $ns/$nom : $etat" ;; esac
    done <<<"$REP"
    info "$examines pod(s) examiné(s)."
fi

# La colonne « prêtes/désirées » change de place : un DaemonSet intercale
# DESIRED et CURRENT avant READY. Le premier champ en « x/y » est cherché.
for ressource in deployments statefulsets daemonsets; do
    relever "$ressource" get "$ressource" -A --no-headers || continue
    while read -r ns nom reste; do
        [ -n "$nom" ] || continue
        ratio=""
        for champ in $reste; do case "$champ" in */*) ratio="$champ"; break ;; esac; done
        case "$ratio" in ""|*[!0-9/]*) continue ;; esac
        pretes="${ratio%%/*}"; desirees="${ratio##*/}"
        if [ "$pretes" -lt "$desirees" ]; then signaler "$ns/$nom : $pretes/$desirees répliques prêtes"; fi
    done <<<"$REP"
done

# Les Warning d'un cluster sain sont anciens et sans gravité : affichés pour
# information, ils ne passent pas par signaler et ne changent pas le code de
# retour. Un relevé d'événements impossible non plus : signalé, jamais compté.
printf '\nÉvénements Warning\n'
if lire get events -A --field-selector type=Warning --no-headers; then
    if [ -n "$REP" ]; then
        printf '%s\n' "$REP" | sed 's/^/  /'
        info "Affichés pour information : un Warning ne change pas le code de retour."
    else
        info "Aucun événement Warning."
    fi
else
    montrer_erreur
    warn "Les événements Warning n'ont pas pu être listés — sans effet sur le verdict."
fi

printf '\n'
if [ "$ANOMALIES" -gt 0 ]; then error "$ANOMALIES anomalie(s) détectée(s). Rien n'a été modifié."; exit 1; fi
success "Aucune anomalie détectée. Rien n'a été modifié."
