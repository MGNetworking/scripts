#!/usr/bin/env bash
set -Eeuo pipefail

# Pose les deux ClusterIssuers Let's Encrypt du cluster — staging et production —
# par kubectl apply. Chaque site demandera son certificat dans son propre Ingress.
# Rien n'est jamais supprimé ; le Secret du compte ACME, qui appartient à
# cert-manager, n'est ni lu ni affiché ici.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=10        # --request-timeout des lectures et écritures, en secondes
MARGE=2         # « timeout » qui entoure un appel : le laisser écrire son message
ATTENTE=120     # attente de la condition Ready d'un ClusterIssuer, en secondes
LABEL="app.kubernetes.io/managed-by=mgnetworking"
STAGING="https://acme-staging-v02.api.letsencrypt.org/directory"
PRODUCTION="https://acme-v02.api.letsencrypt.org/directory"
DRY_RUN="false"; OUI="false"
# Décision 45 : un parent qui exporte ASSUME_YES ne confirme pas à ma place.
export ASSUME_YES="false"
# Surcharges de test, lues avant tout trap et toute écriture de fichier.
if [ -e /.dockerenv ]; then
    [ -z "${DELAI_TEST:-}" ] || DELAI="$DELAI_TEST"
    [ -z "${ATTENTE_TEST:-}" ] || ATTENTE="$ATTENTE_TEST"
fi

usage() {
    cat <<'EOF'
configure-tls.sh — pose les deux ClusterIssuers Let's Encrypt du cluster.

Usage : configure-tls.sh [--dry-run] [-y|--yes] [--help]

  --dry-run    affiche la différence avec le cluster, sans rien appliquer
  -y, --yes    ne pose aucune question (obligatoire hors terminal)

letsencrypt-staging et letsencrypt-production sont des ressources de CLUSTER,
sans namespace, validées par HTTP-01 sur l'IngressClass traefik. L'adresse de
contact vient de SRV_K8S_ACME_EMAIL (config/server.env) : sans elle, ou mal
formée, le script rend 2 sans rien tenter. Chaque site demande ensuite son
propre certificat dans son Ingress ; ce script n'en demande aucun, ne supprime
jamais rien, et kubectl résout seul son kubeconfig (KUBECONFIG, puis ~/.kube/config).

Codes de retour :
  0  les deux ClusterIssuers sont à l'état voulu, ou l'étaient déjà ; ou --dry-run
  1  kubectl absent, apiserver injoignable, CRD ClusterIssuer absente, webhook
     cert-manager non prêt, droits insuffisants, kubeconfig invalide, délai
     dépassé, confirmation refusée, application ou attente en échec
  2  option inconnue, ou SRV_K8S_ACME_EMAIL absente ou mal formée — seuls cas de 2
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; OUI="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

# Jugée ici, avant tout appel : cette valeur est injectée dans le YAML, où une
# valeur libre ouvrirait une injection. Elle est posée entre guillemets.
EMAIL="${SRV_K8S_ACME_EMAIL:-}"
[ -n "$EMAIL" ] || die "Adresse ACME absente : renseigner SRV_K8S_ACME_EMAIL dans config/server.env (modèle : config/server.env.example). Rien n'a été tenté." 2
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$ ]] \
    || die "Adresse ACME mal formée dans SRV_K8S_ACME_EMAIL : « $EMAIL » — forme attendue local@domaine.tld. Rien n'a été tenté." 2

command -v kubectl >/dev/null 2>&1 || die "kubectl est introuvable dans le PATH : voir Kubernetes/Installation/install-kubectl.sh (TASK-062)."
require_cmd timeout
TEMPORAIRE="$(mktemp -d)" || die "Répertoire temporaire indisponible."
trap 'rm -rf "$TEMPORAIRE"' EXIT

# Écrit une fois, passé sur stdin aux deux appels : diff et apply lisent le même.
issuer() {   # <nom> <serveur> <nom du Secret de compte ACME>
    cat <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: $1
  labels:
    app.kubernetes.io/managed-by: mgnetworking
spec:
  acme:
    email: "$EMAIL"
    server: $2
    privateKeySecretRef:
      name: $3
    solvers:
      - http01:
          ingress:
            ingressClassName: traefik
EOF
}
{ issuer letsencrypt-staging "$STAGING" letsencrypt-staging-account-key
  printf -- '---\n'
  issuer letsencrypt-production "$PRODUCTION" letsencrypt-production-account-key
} > "$TEMPORAIRE/clusterissuers.yaml"

# REP — stdout — et ERREUR — stderr, tenus à part : un avertissement mêlé à une
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
        # Avant la règle réseau : ce webhook joint un Service du cluster, et son
        # « connection refused » ne dit rien de l'apiserver.
        *"failed calling webhook"*|*"no endpoints available"*) die "Le webhook d'admission cert-manager (webhook.cert-manager.io) ne répond pas : cert-manager est installé, mais son webhook n'est pas prêt. $1 a échoué — voir Kubernetes/Installation/install-cert-manager.sh (TASK-065)." ;;
        *Forbidden*) die "Droits insuffisants : $1 a été refusé par le cluster." ;;
        *Unauthorized*|*x509*|*"error loading config file"*) die "Kubeconfig invalide ou périmé : $1 a été refusé." ;;
        *"no matches for kind"*|*"ensure CRDs are installed"*|*"unable to recognize"*) die "CRD cert-manager.io/v1 absente ou non servie : cert-manager est-il installé ? ($1)" ;;
        *"could not find the requested resource"*|*"doesn't have a resource type"*) die "Ressource inconnue de l'API : $1 a échoué — l'apiserver répond, mais ne connaît pas cette ressource." ;;
        # Réservée au réseau : c'est l'apiserver lui-même qui ne répond pas.
        *"connection refused"*|*"was refused"*|*"Unable to connect"*|*"no such host"*|*"i/o timeout"*) die "L'apiserver est injoignable : $1 a échoué. Vérifier l'accès par install-kubectl.sh (TASK-062)." ;;
        *) die "Échec de $1. La cause est dans le message ci-dessus : le cluster a répondu, et a refusé." ;;
    esac
}

# Préflight : rien n'est appliqué avant que cette lecture ait répondu.
appel /dev/null get crd clusterissuers.cert-manager.io
case "$ERREUR" in *NotFound*) die "CRD clusterissuers.cert-manager.io absente : l'extension cert-manager n'est pas posée sur ce cluster (Kubernetes/Installation/install-cert-manager.sh, TASK-065). Rien n'a été appliqué." ;; esac
[ "$CODE" = 0 ] || echec "« kubectl get crd clusterissuers.cert-manager.io »"

# C'est kubectl diff qui juge de l'idempotence : 0 sans différence, 1 avec.
appel "$TEMPORAIRE/clusterissuers.yaml" diff -f -
case "$CODE" in
    0) success "Les deux ClusterIssuers sont déjà à l'état voulu : rien n'a été appliqué."; exit 0 ;;
    1) printf '\nDifférence avec le cluster\n%s\n' "$(printf '%s\n' "$REP" | sed 's/^/  /')" ;;
    *) echec "« kubectl diff -f - »" ;;
esac
if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] kubectl apply n'a pas été appelé : rien n'a été modifié."
    exit 0
fi
[ -t 0 ] || [ "$OUI" = "true" ] || die "Application à confirmer, et aucun terminal n'est disponible. Relancer avec --yes." 1
confirm "Créer les ClusterIssuers letsencrypt-staging et letsencrypt-production ?" || die "Configuration abandonnée : rien n'a été appliqué." 1

appel "$TEMPORAIRE/clusterissuers.yaml" apply -f -
if [ "$CODE" != 0 ]; then printf '%s\n' "$REP" | sed 's/^/  /' >&2; echec "« kubectl apply -f - »"; fi
printf '%s\n' "$REP" | sed 's/^/  /'

# Relecture par le label : elle seule prouve qu'il y en a exactement deux.
appel /dev/null get clusterissuers -l "$LABEL" -o name
[ "$CODE" = 0 ] || echec "« kubectl get clusterissuers -l $LABEL »"
NOMBRE="$(printf '%s\n' "$REP" | grep -c . || true)"
for i in letsencrypt-staging letsencrypt-production; do
    printf '%s\n' "$REP" | grep -q "clusterissuer.cert-manager.io/$i$" || die "Relecture : $i est absent du cluster après application."
done
[ "$NOMBRE" = 2 ] || die "Relecture : $NOMBRE ClusterIssuer(s) portant $LABEL — deux sont attendus."

# Le compte ACME est enregistré par cert-manager au premier certificat demandé :
# d'ici là, la condition Ready peut rester fausse. L'attente est bornée.
printf '\nAttente de la condition Ready (délai %s s)\n' "$ATTENTE"
for i in letsencrypt-staging letsencrypt-production; do
    CODE=0
    # --request-timeout vaut ici l'attente entière : une valeur plus courte
    # couperait le watch, et l'attente de 120 s n'irait jamais à son terme.
    REP="$(timeout "$((ATTENTE + MARGE))" kubectl wait --for=condition=Ready "clusterissuer/$i" \
        --timeout="${ATTENTE}s" --request-timeout="${ATTENTE}s" 2>"$TEMPORAIRE/erreur")" || CODE=$?
    ERREUR="$(cat "$TEMPORAIRE/erreur")"
    if [ "$CODE" = 124 ]; then die "L'attente de la condition Ready de $i a été interrompue : délai dépassé (${ATTENTE} s)."; fi
    [ "$CODE" = 0 ] || echec "l'attente de la condition Ready de $i"
    printf '  %s : prêt\n' "$i"
done
success "ClusterIssuers letsencrypt-staging et letsencrypt-production prêts (HTTP-01, IngressClass traefik). Aucun certificat demandé, rien supprimé."
