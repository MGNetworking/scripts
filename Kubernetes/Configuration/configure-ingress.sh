#!/usr/bin/env bash
set -Eeuo pipefail

# Pose deux Middlewares Traefik réutilisables — redirection HTTPS et en-têtes de
# sécurité — que chaque site active dans son Ingress. Rien n'est jamais supprimé :
# ni delete, ni --prune. HSTS court (décision 48) : un max-age long, mal posé, rend
# un site injoignable en HTTP pour sa durée entière.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5                  # --request-timeout de chaque appel kubectl, en secondes
MARGE=2                  # « timeout » qui l'entoure : le laisser écrire son message
HSTS=3600                # stsSeconds : HSTS court, décision 48
NS="default"; DRY_RUN="false"; OUI="false"
# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Surcharge de test : dans un conteneur seul, le délai peut être raccourci.
if [ -e /.dockerenv ] && [ -n "${DELAI_TEST:-}" ]; then DELAI="$DELAI_TEST"; fi

usage() {
    cat <<'EOF'
configure-ingress.sh — pose deux Middlewares Traefik réutilisables.

Usage : configure-ingress.sh [--namespace <ns>] [--dry-run] [-y|--yes] [--help]

  --namespace  namespace des Middlewares (défaut : default)
  --dry-run    affiche la différence avec le cluster, sans rien appliquer
  -y, --yes    ne pose aucune question (obligatoire hors terminal)
redirect-https redirige HTTP vers HTTPS de façon permanente ; security-headers
pose un HSTS court (stsSeconds 3600), contentTypeNosniff, frameDeny,
browserXssFilter et referrerPolicy strict-origin-when-cross-origin. Chaque site
les active dans son Ingress par l'annotation :
  traefik.ingress.kubernetes.io/router.middlewares: <ns>-redirect-https@kubernetescrd,<ns>-security-headers@kubernetescrd

Un Ingress ne peut peut-être pas viser un Middleware d'un autre namespace
(allowCrossNamespace n'est documenté que pour les IngressRoutes) : si la
référence est refusée, poser les Middlewares dans le namespace du site.
kubectl résout seul son kubeconfig (KUBECONFIG, sinon ~/.kube/config).

Codes de retour :
  0  les deux Middlewares sont à l'état voulu, ou l'étaient déjà ; ou --dry-run
  1  kubectl absent, cluster injoignable, CRD Middleware ou namespace absent,
     droits insuffisants, kubeconfig invalide, délai dépassé, confirmation
     refusée, application ou relecture en échec
  2  option inconnue ou namespace mal formé — seuls cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --namespace) shift; NS="${1:-}"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# DNS-1123, jugé avant tout appel : sinon kubectl lirait le namespace comme une option.
case "$NS" in
    ""|*[!a-z0-9-]*|[!a-z0-9]*|*[!a-z0-9]) die "Namespace mal formé : « $NS » — minuscules, chiffres et « - » attendus." 2 ;;
esac
[ "${#NS}" -le 63 ] || die "Namespace mal formé : « $NS » — 63 caractères au plus." 2

command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Écrit une fois, passé sur stdin aux deux appels : diff et apply lisent le même.
cat > "$TEMPORAIRE/middlewares.yaml" <<EOF
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: redirect-https
  namespace: $NS
  labels:
    app.kubernetes.io/managed-by: mgnetworking
spec:
  redirectScheme:
    scheme: https
    permanent: true
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: $NS
  labels:
    app.kubernetes.io/managed-by: mgnetworking
spec:
  headers:
    stsSeconds: $HSTS
    stsIncludeSubdomains: false
    stsPreload: false
    contentTypeNosniff: true
    frameDeny: true
    browserXssFilter: true
    referrerPolicy: strict-origin-when-cross-origin
EOF

# REP — stdout — et ERREUR — stderr, tenu à part : un avertissement mêlé à une
# lecture serait pris pour une donnée.
REP=""; ERREUR=""; CODE=0
appel() {   # <stdin> <verbe kubectl...>
    local entree="$1"; shift
    CODE=0
    REP="$(timeout "$((DELAI + MARGE))" kubectl "$@" --request-timeout="${DELAI}s" < "$entree" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
}

# Traduit l'échec du dernier appel : le 124 vient de « timeout », pas du cluster.
echec() {
    [ -z "$ERREUR" ] || printf '%s\n' "$ERREUR" | sed 's/^/  /' >&2
    case "$CODE:$ERREUR" in
        124:*) die "L'appel $1 a été interrompu : délai dépassé (${DELAI} s)." ;;
        *Forbidden*) die "Droits insuffisants : $1 a été refusé par le cluster." ;;
        *Unauthorized*|*x509*|*"error loading config file"*) die "Kubeconfig invalide ou périmé : $1 a été refusé." ;;
        *"could not find the requested resource"*|*"doesn't have a resource type"*) die "Ressource inconnue de l'API : $1 a échoué — l'apiserver répond, mais ne connaît pas cette ressource." ;;
        *) die "L'apiserver est injoignable : $1 a échoué. Vérifier l'accès par install-kubectl.sh (TASK-062)." ;;
    esac
}

# Préflight : rien n'est appliqué avant que ces deux lectures aient répondu.
appel /dev/null get crd middlewares.traefik.io
case "$ERREUR" in *NotFound*) die "CRD middlewares.traefik.io absente : le Middleware est une extension de Traefik, qui n'est pas posé sur ce cluster. Rien n'a été appliqué." ;; esac
[ "$CODE" = 0 ] || echec "« kubectl get crd middlewares.traefik.io »"
appel /dev/null get namespace "$NS"
case "$ERREUR" in *NotFound*) die "Namespace $NS absent du cluster : le créer d'abord. Rien n'a été appliqué." ;; esac
[ "$CODE" = 0 ] || echec "« kubectl get namespace $NS »"

# C'est kubectl diff qui juge de l'idempotence : 0 sans différence, 1 avec.
appel "$TEMPORAIRE/middlewares.yaml" diff -f -
case "$CODE" in
    0) success "Les deux Middlewares sont déjà à l'état voulu dans $NS : rien n'a été appliqué."; exit 0 ;;
    1) printf '\nDifférence avec le cluster\n%s\n' "$(printf '%s\n' "$REP" | sed 's/^/  /')" ;;
    *) echec "« kubectl diff -f - »" ;;
esac
if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] kubectl apply n'a pas été appelé : rien n'a été modifié."
    exit 0
fi
[ -t 0 ] || [ "$OUI" = "true" ] || die "Application à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Poser les deux Middlewares Traefik dans le namespace $NS ?" || die "Configuration abandonnée : rien n'a été appliqué." 1

appel "$TEMPORAIRE/middlewares.yaml" apply -f -
if [ "$CODE" != 0 ]; then printf '%s\n' "$REP" | sed 's/^/  /' >&2; echec "« kubectl apply -f - »"; fi
printf '%s\n' "$REP" | sed 's/^/  /'

# Relecture par le label : elle seule prouve qu'il y en a exactement deux.
LABEL="app.kubernetes.io/managed-by=mgnetworking"
appel /dev/null get middlewares -n "$NS" -l "$LABEL" -o name
[ "$CODE" = 0 ] || echec "« kubectl get middlewares -n $NS -l $LABEL »"
NOMBRE="$(printf '%s\n' "$REP" | grep -c . || true)"
for m in redirect-https security-headers; do printf '%s\n' "$REP" | grep -q "middleware.traefik.io/$m$" || die "Relecture : $m absent de $NS après application."; done
[ "$NOMBRE" = 2 ] || die "Relecture : $NOMBRE Middleware(s) portant $LABEL dans $NS — deux sont attendus."
success "Middlewares redirect-https et security-headers en place dans $NS (HSTS ${HSTS} s). Rien n'a été supprimé."
