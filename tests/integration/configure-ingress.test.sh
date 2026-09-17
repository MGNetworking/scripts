#!/usr/bin/env bash
# tests/integration/configure-ingress.test.sh — Kubernetes/Configuration/configure-ingress.sh.
# AUCUN CLUSTER RÉEL : un faux kubectl en tête de PATH, aux codes et messages du
# vrai, qui lit le manifeste reçu sur stdin et refuse tout champ inattendu.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Configuration/configure-ingress.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "configure-ingress.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait les appels"
    bilan "TASK-069 / configure-ingress.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
: > "$BAC/kubectl-tous"

# Faux kubectl : les messages et codes du vrai, NotFound compris. Le manifeste
# reçu sur stdin est jugé champ par champ — une valeur forcée, un autre groupe
# d'API, un objet de plus ou de moins font échouer le faux, donc le cas.
faux kubectl <<'SH'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-tous"
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
manifeste() {   # <diff|apply> <namespace attendu>
    cat > "$BAC/manifeste-$1"; sed 's/^[[:space:]]*//' "$BAC/manifeste-$1" > "$BAC/manifeste-$1.nu"
    for l in 'apiVersion: traefik.io/v1alpha1' 'kind: Middleware' 'name: redirect-https' 'name: security-headers' 'namespace: '"$2" \
             'scheme: https' 'permanent: true' 'app.kubernetes.io/managed-by: mgnetworking' 'stsSeconds: 3600' 'stsPreload: false' \
             'stsIncludeSubdomains: false' 'contentTypeNosniff: true' 'frameDeny: true' 'browserXssFilter: true' 'referrerPolicy: strict-origin-when-cross-origin'; do
        grep -qxF "$l" "$BAC/manifeste-$1.nu" || { printf 'manifeste : « %s » attendu\n' "$l" >&2; exit 1; }
    done
    [ "$(grep -c '^kind: Middleware$' "$BAC/manifeste-$1.nu")" = 2 ] || { echo 'manifeste : deux Middlewares attendus' >&2; exit 1; }
    grep -q 'containo.us' "$BAC/manifeste-$1.nu" && { echo 'manifeste : groupe traefik.containo.us proscrit' >&2; exit 1; }
    return 0
}
notfound() { printf 'Error from server (NotFound): %s not found\n' "$1" >&2; exit 1; }
case "$1 $2" in
    "get crd")       [ -f "$BAC/crd" ] || notfound 'customresourcedefinitions.apiextensions.k8s.io "middlewares.traefik.io"'
                     printf 'NAME CREATED AT\nmiddlewares.traefik.io 2026-09-17T00:00:00Z\n' ;;
    "get namespace") [ -f "$BAC/ns-$3" ] || notfound "namespaces \"$3\""
                     printf 'NAME STATUS AGE\n%s Active 3d\n' "$3" ;;
    "diff -f")       manifeste diff "${NS_ATTENDU:-default}"
                     [ "${DIFF_CODE:-1}" = "0" ] && exit 0
                     printf '%s\n' "${DIFF_TEXTE:-+  name: redirect-https}"; exit "${DIFF_CODE:-1}" ;;
    "apply -f")      manifeste apply "${NS_ATTENDU:-default}"; : > "$BAC/pose"
                     printf 'middleware.traefik.io/redirect-https created\nmiddleware.traefik.io/security-headers created\n' ;;
    "get middlewares")
                     [ -f "$BAC/pose" ] || exit 0
                     printf 'middleware.traefik.io/redirect-https\n'
                     [ -z "${POSE_UN_SEUL:-}" ] && printf 'middleware.traefik.io/security-headers\n'
                     exit 0 ;;
    *) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
SH

CHEMIN="$BAC:$PATH"
EXTRA=(); codes=""; CODE=0
lancer() { sortie="$(env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 bash "$CIBLE" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }
# Réponse tapée sous un pseudo-terminal : le terrain de la décision 45.
lancer_pty() { rep="$1"; shift; sortie="$(printf '%s\n' "$rep" | env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 script -qec "bash $CIBLE $*" /dev/null 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }
sain() {   # cluster sain : CRD posée, namespaces default et site, rien de posé
    : > "$BAC/crd"; : > "$BAC/ns-default"; : > "$BAC/ns-site"; rm -f "$BAC/pose"; : > "$BAC/kubectl-appels"; }
appels() { cat "$BAC/kubectl-appels"; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "traefik.ingress.kubernetes.io/router.middlewares" "--help nomme l'annotation qui active les Middlewares"
assert_contient "$sortie" "<ns>-redirect-https@kubernetescrd,<ns>-security-headers@kubernetescrd" "elle porte les deux noms, séparés par une virgule"
assert_contient "$sortie" "2  option" "--help documente les codes de retour"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Namespace mal formé — jugé avant tout appel kubectl"
sain
for ns in Mon_NS -site site- Site site.autre ""; do
    sortie="$(env PATH="$CHEMIN" timeout 60 bash "$CIBLE" --namespace "$ns" --yes </dev/null 2>&1)" && code=0 || code=$?
    assert_code 2 "$code" "« $ns » est refusé en 2"
done
sortie="$(env PATH="$CHEMIN" timeout 60 bash "$CIBLE" --namespace "$(printf 'a%.0s' {1..64})" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "un namespace de 64 caractères est refusé en 2"
assert_contient "$sortie" "mal formé" "le message dit ce qui est mal formé"
assert_egal "" "$(appels)" "aucun appel kubectl n'a eu lieu"

titre "kubectl absent"
mkdir -p "$BAC/sans-kubectl"
for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp grep tr; do
    ln -sf "$(command -v "$c")" "$BAC/sans-kubectl/$c"; done
sortie="$(PATH="$BAC/sans-kubectl" timeout 60 bash "$CIBLE" --yes </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "kubectl est introuvable" "le message nomme kubectl"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"

titre "Cluster injoignable, kubeconfig, droits, ressource inconnue"
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"; assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
assert_contient "$sortie" "install-kubectl.sh" "et renvoie vers TASK-062"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": no such file or directory'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig invalide rend 1"; assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
assert_absent "$sortie" "injoignable" "sans confondre les deux causes"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): customresourcedefinitions.apiextensions.k8s.io is forbidden'); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"; assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"
sain; EXTRA=(KUBECTL_ERREUR="error: the server doesn't have a resource type \"middlewares\""); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "une ressource inconnue de l'API rend 1"; assert_contient "$sortie" "Ressource inconnue de l'API" "elle est nommée pour ce qu'elle est"
assert_absent "$sortie" "injoignable" "et non prise pour un apiserver muet"

titre "CRD Middleware et namespace absents"
sain; rm -f "$BAC/crd"; lancer --yes
assert_code 1 "$CODE" "une CRD Middleware absente rend 1"; assert_contient "$sortie" "CRD middlewares.traefik.io absente" "le message la nomme"
assert_contient "$sortie" "Traefik" "et dit à quoi elle tient"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'absence"; assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; rm -f "$BAC/ns-site"; lancer --namespace site --yes
assert_code 1 "$CODE" "un namespace absent du cluster rend 1"
assert_contient "$sortie" "Namespace site absent du cluster" "le message nomme le namespace demandé"
assert_absent "$(appels)" "apply" "et rien n'est appliqué"

titre "Idempotence, --dry-run et confirmation"
sain; EXTRA=(DIFF_CODE=0); lancer --yes; EXTRA=()
assert_code 0 "$CODE" "sans différence, le script rend 0"; assert_contient "$sortie" "déjà à l'état voulu" "il constate au lieu de refaire"
assert_absent "$(appels)" "apply" "aucun apply n'est tenté"
sain; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"; assert_contient "$sortie" "Différence avec le cluster" "la différence est affichée"
assert_contient "$sortie" "+  name: redirect-https" "avec ce que kubectl a rendu"
assert_contient "$sortie" "[dry-run]" "et le dry-run est annoncé"
assert_contient "$(appels)" "diff -f - " "le manifeste est lu sur stdin"; assert_absent "$(appels)" "apply" "--dry-run n'appelle jamais apply"
sain; lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, un changement à faire rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque"; assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; EXTRA=(ASSUME_YES=true); lancer; EXTRA=()
assert_code 1 "$CODE" "un ASSUME_YES hérité ne confirme pas à la place du --yes"; assert_absent "$(appels)" "apply" "et rien n'est appliqué"
sain; lancer_pty n
assert_code 1 "$CODE" "une réponse « n » sous terminal abandonne en 1"; assert_contient "$sortie" "Configuration abandonnée" "le refus est celui de confirm"
assert_absent "$(appels)" "apply" "et rien n'est appliqué"

titre "Application et relecture"
sain; lancer_pty o
assert_code 0 "$CODE" "une réponse « o » sous terminal applique, en 0"; assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
assert_contient "$sortie" "HSTS 3600 s" "avec la durée HSTS courte retenue"
assert_contient "$(appels)" "apply -f - " "le manifeste est appliqué depuis stdin"
assert_contient "$(appels)" "get middlewares -n default -l app.kubernetes.io/managed-by=mgnetworking -o name" "et relu par le label, dans le bon namespace"
assert_contient "$sortie" "middleware.traefik.io/redirect-https created" "ce que kubectl a créé est affiché"
sain; EXTRA=(NS_ATTENDU=site); lancer --namespace site --yes; EXTRA=()
assert_code 0 "$CODE" "un namespace nommé est accepté"; assert_contient "$(appels)" "get middlewares -n site -l " "et les Middlewares y sont posés et relus"
sain; EXTRA=(POSE_UN_SEUL=1); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un seul Middleware relu rend 1"; assert_contient "$sortie" "security-headers absent de default" "le message nomme celui qui manque"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque la relecture incomplète"

titre "Délai dépassé — « timeout » enveloppe chaque appel"
REEL_TIMEOUT="$(command -v timeout)"
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in
    "kubectl:7 kubectl "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
: > "$BAC/timeout-appels"
sain; EXTRA=(TIMEOUT_SUR=kubectl); lancer --yes; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"; assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "« kubectl get crd middlewares.traefik.io »" "et l'appel qui a expiré est nommé"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'expiration"
assert_egal "7 kubectl get crd middlewares.traefik.io --request-timeout=5s" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2), et l'appel reste borné à 5 s"
rm -f "$BAC/timeout"

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root"
assert_egal "0" "$(grep -vE '^[[:space:]]*#' "$CIBLE" | grep -c 'k3s.yaml' || true)" "aucune référence à k3s.yaml hors commentaire"
assert_egal "0" "$(grep -vc -- '--request-timeout=5s' "$BAC/kubectl-tous" || true)" "chaque appel kubectl de toute la suite porte --request-timeout"
hors_forme="$(grep -vcE '^kubectl (get crd|get namespace|get middlewares|diff|apply) ' "$BAC/kubectl-tous" || true)"
assert_egal "0" "$hors_forme" "aucun appel kubectl ne sort de ces cinq lectures et écritures"
assert_egal "0" "$(grep -cE -- '--prune| delete|patch|replace|edit|scale' "$BAC/kubectl-tous" || true)" "aucune suppression ni écriture hors apply"
assert_egal "0" "$(grep -c 'k3s.yaml' "$BAC/kubectl-tous" || true)" "aucune lecture du kubeconfig de K3s"
case "$codes" in *" 2"*) cas2="oui" ;; *) cas2="non" ;; esac
assert_egal "non" "$cas2" "hors namespace mal formé, aucun chemin éprouvé ne rend 2"

bilan "TASK-069 / configure-ingress.sh"
