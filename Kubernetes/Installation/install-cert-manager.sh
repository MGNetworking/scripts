#!/usr/bin/env bash
set -Eeuo pipefail

# Installe cert-manager par le chart OCI officiel jetstack, ou le met à jour vers
# la version voulue. Rien n'est jamais désinstallé, ni aucune CRD supprimée :
# les supprimer effacerait tous les Issuers, ClusterIssuers et Certificates.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Ces variables héritées détourneraient helm de la cible annoncée au résumé. Le
# kubeconfig reste celui que helm et kubectl résolvent seuls (KUBECONFIG, sinon
# ~/.kube/config) : ce script n'en fixe aucun et ne lit jamais k3s.yaml.
unset HELM_NAMESPACE HELM_KUBECONTEXT HELM_KUBETOKEN HELM_KUBEAPISERVER HELM_KUBEASUSER \
      HELM_KUBEASGROUPS HELM_KUBECAFILE HELM_KUBEINSECURE_SKIP_TLS_VERIFY HELM_DRIVER

NS="cert-manager"; CHART="oci://quay.io/jetstack/charts/cert-manager"
DELAI=5        # --request-timeout de chaque appel kubectl, en secondes
MARGE=2        # « timeout » entoure l'appel et laisse l'outil écrire son message
ATTENTE=180    # délai d'attente des trois déploiements, en secondes
DELAI_HELM=60
VERSION_ARG=""; DRY_RUN="false"; OUI="false"

usage() {
    cat <<'EOF'
install-cert-manager.sh — installe ou met à jour cert-manager par Helm.

Usage : install-cert-manager.sh --version vX.Y.Z [--dry-run] [-y|--yes] [--help]

  --version   version du chart, obligatoire (vX.Y.Z) ; à défaut,
              SRV_CERT_MANAGER_VERSION dans config/server.env
  --dry-run   affiche version et commande prévues, sans rien exécuter
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Chart OCI officiel jetstack, oci://quay.io/jetstack/charts/cert-manager, épinglé à
la version demandée et sans « helm repo add » ; CRD posées par le chart
(crds.enabled=true), namespace cert-manager créé au besoin. Ni root ni kubeconfig
de K3s : helm et kubectl résolvent seuls le leur.
Une version voulue inférieure à celle installée est refusée : ce script ne
revient jamais en arrière, et une mise à jour demande confirmation.

Codes de retour :
  0  cert-manager est à la version voulue, ou l'était déjà
  1  helm ou kubectl absent, cluster injoignable, version absente ou invalide,
     version voulue inférieure à l'installée, confirmation refusée, échec de
     helm, déploiement non prêt, CRD manquante
  2  option inconnue
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --version) shift; VERSION_ARG="${1:-}"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

[ "$DRY_RUN" = "true" ] || enable_full_logging
command -v helm >/dev/null 2>&1 || die "helm est introuvable dans le PATH : l'installer par Kubernetes/Installation/install-helm.sh (TASK-063)."
command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout

VERSION="${VERSION_ARG:-${SRV_CERT_MANAGER_VERSION:-}}"
[ -n "$VERSION" ] || die "Version cible obligatoire : --version vX.Y.Z, ou SRV_CERT_MANAGER_VERSION dans config/server.env."
[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || die "Version invalide : « $VERSION » (forme attendue vX.Y.Z, par exemple v1.21.2)."

# Affiche le résumé des changements ; $1 dit la version, ou « installée → voulue ».
resume() {
    printf '\nChangements prévus\n'
    printf '  Version      %s\n' "$1"
    printf "  Namespace    %s, créé s'il manque\n" "$NS"
    printf '  CRD          posées par le chart (crds.enabled=true)\n'
    printf '  Commande     helm upgrade --install cert-manager %s --version %s --namespace %s --create-namespace --set crds.enabled=true\n\n' \
        "$CHART" "$VERSION" "$NS"
}

if [ "$DRY_RUN" = "true" ]; then
    resume "$VERSION"
    info "[dry-run] Aucun appel à helm ni à kubectl, aucune écriture : rien n'a été installé."
    exit 0
fi

TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

REP=""; ERREUR=""; CODE=0
lire_kubectl() {
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Traduit l'échec d'un appel kubectl ; le 124 vient de « timeout », pas du cluster.
echec() {
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel $1 a été interrompu : délai dépassé (${DELAI} s)." ;;
        *NotFound*) die "L'objet demandé est introuvable dans le cluster : $1." ;;
        *Forbidden*) die "Droits insuffisants : $1 a été refusé par le cluster." ;;
        *"error loading config file"*|*Unauthorized*|*x509*) die "Kubeconfig invalide ou périmé : $1 a été refusé." ;;
        *) die "L'apiserver est injoignable : $1 a échoué. Vérifier l'accès par install-kubectl.sh (TASK-062)." ;;
    esac
}

# Rend 0 si la CRD existe, 1 si le cluster répond NotFound ; tout autre échec arrête.
crd_presente() {
    lire_kubectl get crd "$1"
    if [ "$CODE" = 0 ]; then return 0; fi
    case "$ERREUR" in *NotFound*) return 1 ;; esac
    echec "« kubectl get crd $1 »"
}

# Renseigne RELEASE, vide si la release est absente ; « helm list » en échec arrête.
lire_release() {
    CODE=0
    REP="$(timeout "$DELAI_HELM" helm list --namespace "$NS" -f '^cert-manager$' 2>"$TEMPORAIRE/erreur")" || CODE=$?
    [ "$CODE" = 0 ] || { sed 's/^/  /' "$TEMPORAIRE/erreur" >&2; die "« helm list » a échoué : le cluster n'a pas répondu. Vérifier l'accès par install-kubectl.sh (TASK-062)."; }
    RELEASE="$(printf '%s\n' "$REP" | sed -n 's/^cert-manager[[:space:]].*[[:space:]]\(cert-manager-v[0-9][0-9.]*\).*/\1/p' | head -n 1)"
    RELEASE="${RELEASE#cert-manager-}"
}

# Rend « > », « = » ou « < » : comparaison champ par champ, jamais lexicale.
comparer() {
    local -a A B; local i
    IFS=. read -r -a A <<<"${1#v}"
    IFS=. read -r -a B <<<"${2#v}"
    for i in 0 1 2; do
        if [ "${A[i]}" -gt "${B[i]}" ]; then printf '>'; return 0; fi
        if [ "${A[i]}" -lt "${B[i]}" ]; then printf '<'; return 0; fi
    done
    printf '='
}

lire_kubectl version
[ "$CODE" = 0 ] || echec "« kubectl version »"
lire_release
DETAIL="$VERSION (première installation)"
if [ -n "$RELEASE" ]; then
    ORDRE="$(comparer "$RELEASE" "$VERSION")"
    [ "$ORDRE" != "=" ] || { success "cert-manager $RELEASE est déjà à la version voulue : rien n'a été refait."; exit 0; }
    [ "$ORDRE" != ">" ] || die "Version voulue $VERSION inférieure à celle installée ($RELEASE) : refus, rien n'a été modifié."
    DETAIL="$RELEASE → $VERSION"
elif crd_presente certificates.cert-manager.io; then
    die "Des CRD cert-manager.io existent sans release Helm cert-manager : refus, rien n'a été modifié."
fi

resume "$DETAIL"
[ -z "$RELEASE" ] || warn "Mise à jour : lire les notes de version de cert-manager avant de poursuivre."
[ -t 0 ] || [ "$OUI" = "true" ] \
    || die "Installation à confirmer, et aucun terminal n'est disponible. Relancer avec --yes."
confirm "Installer cert-manager ($DETAIL) dans le namespace $NS ?" || die "Installation abandonnée."

ECHEC=""
run_logged timeout "$DELAI_HELM" helm upgrade --install cert-manager "$CHART" --version "$VERSION" \
    --namespace "$NS" --create-namespace --set crds.enabled=true || ECHEC="oui"
[ -z "$ECHEC" ] || die "helm upgrade --install a échoué : l'état de la release est incertain. La relire par « helm -n $NS status cert-manager »."

lire_release
[ "$RELEASE" = "$VERSION" ] || die "Version relue « $RELEASE », différente de la voulue ($VERSION)."

printf '\nAttente des déploiements (délai %s s)\n' "$ATTENTE"
NON_PRETS=""
for d in cert-manager cert-manager-cainjector cert-manager-webhook; do
    CODE=0
    timeout "$((ATTENTE + MARGE))" kubectl rollout status "deployment/$d" --namespace "$NS" \
        --timeout="${ATTENTE}s" --request-timeout="${DELAI}s" >/dev/null 2>"$TEMPORAIRE/erreur" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
    if [ "$CODE" = 0 ]; then printf '  %s : prêt\n' "$d"; continue; fi
    NON_PRETS="$NON_PRETS $d"
    case "$CODE:$ERREUR" in
        124:*|*"timed out waiting"*) warn "Déploiement $d : délai de ${ATTENTE} s dépassé." ;;
        *) warn "Déploiement $d : $(printf '%s' "$ERREUR" | head -n 1)" ;;
    esac
done
[ -z "$NON_PRETS" ] || die "Déploiements non prêts :$NON_PRETS. Rien n'a été désinstallé."

MANQUANTES=""
for crd in certificates issuers clusterissuers; do
    crd_presente "$crd.cert-manager.io" || MANQUANTES="$MANQUANTES $crd.cert-manager.io"
done
[ -z "$MANQUANTES" ] || die "CRD manquante(s) après installation :$MANQUANTES."
success "cert-manager $VERSION est installé dans $NS : trois déploiements prêts, CRD relues."
