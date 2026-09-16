#!/usr/bin/env bash
set -Eeuo pipefail

# Supprime les objets Kubernetes nommés un à un en argument. Le script ne cherche
# aucun candidat — pods Failed, Jobs terminés, ReplicaSets à zéro : ce qui n'est
# pas nommé reste — et ne supprime jamais par label, par motif, --all, ni un
# namespace entier.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=30
# Surcharge de test : dans un conteneur seul, le délai peut être raccourci.
if [ -e /.dockerenv ] && [ -n "${DELAI_TEST:-}" ]; then DELAI="$DELAI_TEST"; fi
PROTEGES=" kube-system kube-public kube-node-lease "
TYPES="pods jobs cronjobs deployments replicasets statefulsets daemonsets services configmaps ingresses"

usage() {
    cat <<'EOF'
cleanup-resources.sh — supprime les objets Kubernetes nommés un à un.

Usage : cleanup-resources.sh [-n <namespace> <type>/<nom>] ... [--dry-run] [-y|--yes]

  -n <ns>     namespace de l'objet qui suit ; un -n par objet
  --dry-run   affiche ce qui serait supprimé, sans appeler kubectl
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Une cible s'écrit « <type>/<nom> » et suit son propre -n : aucune autre forme
n'est acceptée. Types acceptés, sous leur nom, leur pluriel ou leur abréviation
kubectl : pods po, jobs, cronjobs cj, deployments deploy, replicasets rs,
statefulsets sts, daemonsets ds, services svc, configmaps cm, ingresses ing.
Tout autre type — secrets, pvc, namespaces, nœuds, PV, CRD — est refusé en 2,
et les objets de kube-system, kube-public et kube-node-lease en 1.

Codes de retour :
  0  suppression terminée, chaque cible relue absente ; ou --dry-run
  1  cible inexistante ou protégée, kubectl ou timeout introuvable, apiserver
     injoignable, confirmation refusée, ou cible encore présente après delete
  2  option inconnue, cible mal formée, type hors liste, nom ou namespace
     invalide, ou aucune cible
EOF
}

# Forme canonique plurielle d'un type, ou 1 s'il n'est pas dans la liste blanche.
# Liste blanche et non liste noire : kubectl supprimerait volontiers un nœud, un
# PV ou un namespace, et aucun des trois n'a de raison de passer.
canonique() {
    case "$1" in
        pods|pod|po)                   printf 'pods' ;;
        jobs|job)                      printf 'jobs' ;;
        cronjobs|cronjob|cj)           printf 'cronjobs' ;;
        deployments|deployment|deploy) printf 'deployments' ;;
        replicasets|replicaset|rs)     printf 'replicasets' ;;
        statefulsets|statefulset|sts)  printf 'statefulsets' ;;
        daemonsets|daemonset|ds)       printf 'daemonsets' ;;
        services|service|svc)          printf 'services' ;;
        configmaps|configmap|cm)       printf 'configmaps' ;;
        ingresses|ingress|ing)         printf 'ingresses' ;;
        *) return 1 ;;
    esac
}

# DNS-1123 : minuscules, chiffres, « - » et « . », extrémités alphanumériques.
# Hors de cette forme, un composant serait lu par kubectl comme une option ou un
# sélecteur. dns_ns refuse en outre le point, absent des namespaces.
dns_nom() { case "$1" in ""|*[!a-z0-9.-]*) return 1 ;; [!a-z0-9]*|*[!a-z0-9]) return 1 ;; esac; }
dns_ns()  { case "$1" in ""|*[!a-z0-9-]*)  return 1 ;; [!a-z0-9]*|*[!a-z0-9]) return 1 ;; esac; }

# Décision 45 : un ASSUME_YES hérité du parent ne confirme pas ce script.
export ASSUME_YES="false"
CIBLES=(); DRY_RUN="false"; OUI="false"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        -n)
            if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then die "L'option -n attend un namespace et une cible « <type>/<nom> »." 2; fi
            CIBLES+=("$2|$3"); shift 3 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done
[ "${#CIBLES[@]}" -gt 0 ] || die "Aucune cible : nommer un objet, « -n <namespace> <type>/<nom> »." 2

# Tout est jugé ici, sur la chaîne seule : aucun appel kubectl n'a encore eu lieu.
LISTE=()
for cible in "${CIBLES[@]}"; do
    ns="${cible%%|*}"; objet="${cible#*|}"
    case "$objet" in ?*/*) ;; *) die "Cible mal formée : « $objet » — attendu « <type>/<nom> »." 2 ;; esac
    genre="${objet%%/*}"; nom="${objet#*/}"
    case "$nom" in ""|*/*) die "Cible mal formée : « $objet » — attendu « <type>/<nom> »." 2 ;; esac
    canon="$(canonique "$genre")" || die "Type hors périmètre : « $genre » — types acceptés : $TYPES." 2
    dns_ns "$ns" || die "Namespace invalide : « $ns » — minuscules, chiffres et « - » attendus." 2
    dns_nom "$nom" || die "Nom invalide : « $nom » — minuscules, chiffres, « - » et « . » attendus." 2
    case "$PROTEGES" in *" $ns "*) die "Namespace protégé : $ns — rien n'a été supprimé." ;; esac
    LISTE+=("$ns|$canon|$nom")
done

info "Objets visés (${#LISTE[@]}) :"
for cible in "${LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"$cible"
    info "  namespace $ns — $genre/$nom"
done

if [ "$DRY_RUN" = "true" ]; then
    success "--dry-run : rien n'a été supprimé."
    exit 0
fi

require_cmd kubectl timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Raison courte d'un échec. Délai dépassé et type inconnu ne sont pas des
# apiservers injoignables : les confondre enverrait chercher la panne à côté.
raison() {   # <code> <erreur>
    case "$1" in 124) printf 'Délai dépassé (%s s)' "$DELAI"; return ;; esac
    case "$2" in
        *NotFound*)                       printf 'Cible inexistante' ;;
        *Forbidden*)                      printf "Droits insuffisants : l'apiserver a refusé" ;;
        *"doesn't have a resource type"*) printf 'Type inconnu de cet apiserver' ;;
        *refused*|*"no such host"*)       printf 'Apiserver injoignable' ;;
        *)                                printf 'Échec de kubectl (code %s)' "$1" ;;
    esac
}

# Un appel kubectl borné par « timeout » ; le message d'erreur est consigné, le
# code rendu dans CODE. Aucun appel ne part d'ailleurs.
appel() {   # <verbe> <ns> <type> <nom> [option...]
    local verbe="$1" ns="$2" genre="$3" nom="$4"; shift 4
    CODE=0
    timeout "$((DELAI + 2))" kubectl "$verbe" "$genre" "$nom" -n "$ns" \
        --request-timeout="${DELAI}s" "$@" >/dev/null 2>"$TEMPORAIRE/err" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/err")"
}

# Chaque cible est relue AVANT la première suppression : un refus ne laisse
# jamais un nettoyage à moitié fait.
for cible in "${LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"$cible"
    appel get "$ns" "$genre" "$nom"
    if [ "$CODE" != 0 ]; then
        [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
        die "$(raison "$CODE" "$ERREUR") : $genre/$nom dans $ns. Rien n'a été supprimé."
    fi
done

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Suppression à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Supprimer ces ${#LISTE[@]} objet(s) ?" || die "Nettoyage abandonné : rien n'a été supprimé." 1

# État par cible : « ? » jamais tentée, « » supprimée, sinon la raison de l'échec.
ETATS=()
for i in "${!LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"${LISTE[i]}"
    # --wait=false : un finalizer retiendrait autrement l'appel jusqu'au délai
    # dépassé. La disparition se juge à la relecture finale, et un échec ne
    # dispense pas de tenter les cibles suivantes.
    ETATS[i]="?"
    appel delete "$ns" "$genre" "$nom" --wait=false
    if [ "$CODE" != 0 ]; then
        ETATS[i]="$(raison "$CODE" "$ERREUR")"
        warn "Échec : $genre/$nom dans $ns — ${ETATS[i]}."
    else
        ETATS[i]=""
        info "Supprimé : $genre/$nom (namespace $ns)"
    fi
done

# Relecture : elle seule juge de la disparition. Chaque cible y reçoit son état
# définitif, dont le bilan qui suit est tiré.
FAITES=(); ECHECS=(); NON_TENTEES=()
for i in "${!LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"${LISTE[i]}"
    if [ -z "${ETATS[i]}" ]; then
        appel get "$ns" "$genre" "$nom"
        if [ "$CODE" = 0 ]; then
            ETATS[i]="encore présent après delete"
        elif [[ "$ERREUR" != *NotFound* ]]; then
            ETATS[i]="relecture impossible : $(raison "$CODE" "$ERREUR")"
        fi
    fi
    case "${ETATS[i]}" in
        "")  FAITES+=("$ns $genre/$nom") ;;
        "?") NON_TENTEES+=("$ns $genre/$nom") ;;
        *)   ECHECS+=("$ns $genre/$nom — ${ETATS[i]}") ;;
    esac
done

if [ "${#ECHECS[@]}" -gt 0 ] || [ "${#NON_TENTEES[@]}" -gt 0 ]; then
    printf '  %s\n' "Supprimées : ${FAITES[*]:-aucune}" >&2
    [ "${#ECHECS[@]}" -eq 0 ] || printf '  %s\n' "En échec :" "${ECHECS[@]}" >&2
    [ "${#NON_TENTEES[@]}" -eq 0 ] || printf '  %s\n' "Non tentées :" "${NON_TENTEES[@]}" >&2
    die "Nettoyage inachevé : ${#FAITES[@]} supprimée(s), ${#ECHECS[@]} en échec, ${#NON_TENTEES[@]} non tentée(s) sur ${#LISTE[@]}." 1
fi

success "Nettoyage terminé : ${#LISTE[@]} objet(s) supprimé(s), chacun relu absent."
