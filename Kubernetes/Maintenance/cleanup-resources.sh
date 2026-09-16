#!/usr/bin/env bash
set -Eeuo pipefail

# Supprime les objets Kubernetes nommés un à un en argument. Le script ne cherche
# aucun candidat — pods Failed, Jobs terminés, ReplicaSets à zéro : ce qui n'est
# pas nommé reste — et ne supprime jamais par label, par motif, --all, ni un
# namespace entier.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=30   # --request-timeout de chaque appel ; « timeout » l'entoure avec 2 s de marge
PROTEGES=" kube-system kube-public kube-node-lease "
# Types hors périmètre : cluster-scoped (nœud, PV, CRD) ou sensibles (Secret).
INTERDITS=" namespace namespaces node nodes persistentvolume persistentvolumes pv crd customresourcedefinition customresourcedefinitions secret secrets "

usage() {
    cat <<'EOF'
cleanup-resources.sh — supprime les objets Kubernetes nommés un à un.

Usage : cleanup-resources.sh [-n <namespace> <type>/<nom>] ... [--dry-run] [-y|--yes]

  -n <ns>     namespace de l'objet qui suit ; un -n par objet
  --dry-run   affiche ce qui serait supprimé, sans appeler kubectl delete
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Une cible s'écrit « <type>/<nom> » et suit son propre -n : aucune autre forme
n'est acceptée. La liste exacte est affichée avant toute suppression, puis chaque
cible est relue absente. Aucun objet n'est cherché ni supprimé en masse : ni par
label, ni par motif, ni --all, ni un namespace entier.

Refusés : namespaces kube-system, kube-public, kube-node-lease ; nœuds, PV, CRD ; Secrets.

Codes de retour :
  0  suppression terminée, chaque cible relue absente ; ou --dry-run
  1  cible inexistante ou protégée, kubectl ou timeout introuvable, apiserver
     injoignable, confirmation refusée, ou cible encore présente après delete
  2  option inconnue, cible mal formée, ou aucune cible
EOF
}

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

LISTE=()
for cible in "${CIBLES[@]}"; do
    ns="${cible%%|*}"; objet="${cible#*|}"
    case "$objet" in ?*/*) ;; *) die "Cible mal formée : « $objet » — attendu « <type>/<nom> »." 2 ;; esac
    genre="${objet%%/*}"; nom="${objet#*/}"
    case "$nom" in ""|*/*) die "Cible mal formée : « $objet » — attendu « <type>/<nom> »." 2 ;; esac
    # Un composant commençant par « - » serait lu par kubectl comme une option :
    # « delete deployment -l x » emporterait tout un sélecteur.
    case "$ns $genre $nom" in -*|*" -"*) die "Cible invalide : « $ns », « $genre », « $nom »." 2 ;; esac
    case "$PROTEGES" in *" $ns "*) die "Namespace protégé : $ns — rien n'a été supprimé." ;; esac
    case "$INTERDITS" in *" $genre "*) die "Type hors périmètre : $genre — rien n'a été supprimé." ;; esac
    LISTE+=("$ns|$genre|$nom")
done

require_cmd kubectl timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Traduit l'échec d'un appel portant sur une cible ; « fin » complète le message.
# Le 124 vient de « timeout » : l'appeler « injoignable » accuserait le cluster.
echec() {   # <ns> <genre> <nom> [fin]
    local ns="$1" genre="$2" nom="$3" fin="${4:-}"
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel a été interrompu : délai dépassé (${DELAI} s) — $genre/$nom dans $ns.$fin" ;;
    esac
    case "$ERREUR" in
        *NotFound*) die "Cible inexistante : $genre/$nom dans $ns.$fin" ;;
        *Forbidden*) die "Droits insuffisants : $genre/$nom dans $ns a été refusé.$fin" ;;
    esac
    die "L'apiserver n'a pas répondu : $genre/$nom dans $ns.$fin"
}

info "Objets visés (${#LISTE[@]}) :"
for cible in "${LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"$cible"
    info "  namespace $ns — $genre/$nom"
done

if [ "$DRY_RUN" = "true" ]; then
    success "--dry-run : rien n'a été supprimé."
    exit 0
fi

# Chaque cible est relue AVANT la première suppression : un refus ne laisse
# jamais un nettoyage à moitié fait.
for cible in "${LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"$cible"
    CODE=0
    timeout "$((DELAI + 2))" kubectl get "$genre" "$nom" -n "$ns" --request-timeout="${DELAI}s" >/dev/null 2>"$TEMPORAIRE/err" || CODE=$?
    if [ "$CODE" != 0 ]; then
        ERREUR="$(cat "$TEMPORAIRE/err")"
        echec "$ns" "$genre" "$nom" " Rien n'a été supprimé."
    fi
done

[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Suppression à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Supprimer ces ${#LISTE[@]} objet(s) ?" || die "Nettoyage abandonné : rien n'a été supprimé." 1

for cible in "${LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"$cible"
    CODE=0
    timeout "$((DELAI + 2))" kubectl delete "$genre" "$nom" -n "$ns" --request-timeout="${DELAI}s" >/dev/null 2>"$TEMPORAIRE/err" || CODE=$?
    if [ "$CODE" != 0 ]; then
        ERREUR="$(cat "$TEMPORAIRE/err")"
        echec "$ns" "$genre" "$nom"
    fi
    info "Supprimé : $genre/$nom (namespace $ns)"
done

# Relecture : chaque cible doit avoir disparu. Un get qui la rend encore, ou qui
# échoue autrement que par « NotFound », laisse le nettoyage inachevé.
RESTES=()
for cible in "${LISTE[@]}"; do
    IFS='|' read -r ns genre nom <<<"$cible"
    CODE=0
    timeout "$((DELAI + 2))" kubectl get "$genre" "$nom" -n "$ns" --request-timeout="${DELAI}s" >/dev/null 2>"$TEMPORAIRE/err" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/err")"
    if [ "$CODE" = 0 ]; then
        RESTES+=("$ns $genre/$nom — encore présent")
    else
        case "$ERREUR" in *NotFound*) ;; *) RESTES+=("$ns $genre/$nom — relecture impossible : $ERREUR") ;; esac
    fi
done
if [ "${#RESTES[@]}" -gt 0 ]; then
    printf '  %s\n' "${RESTES[@]}" >&2
    die "Suppression incomplète : ${#RESTES[@]} cible(s) sur ${#LISTE[@]}." 1
fi

success "Nettoyage terminé : ${#LISTE[@]} objet(s) supprimé(s), chacun relu absent."
