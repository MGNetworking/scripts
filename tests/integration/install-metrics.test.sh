#!/usr/bin/env bash
# tests/integration/install-metrics.test.sh — Kubernetes/Installation/install-metrics.sh.
# RIEN N'EST INSTALLÉ : faux kubectl en tête de PATH, aux sorties et codes du vrai.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Installation/install-metrics.sh"
IMAGE="rancher/mirrored-metrics-server:v0.7.2"
# Les expressions de lecture attendues, écrites une fois : le faux kubectl ne rend
# la donnée que pour celles-là.
export CC_DEPLOIEMENT='custom-columns=IMAGE:.spec.template.spec.containers[0].image,DISPONIBLES:.status.availableReplicas,DESIREES:.spec.replicas'
export JP_APISERVICE='jsonpath={.status.conditions[?(@.type=="Available")].status}{"|"}{.status.conditions[?(@.type=="Available")].reason}{"|"}{.status.conditions[?(@.type=="Available")].message}'
if [ ! -e /.dockerenv ]; then
    saute_indisponible "install-metrics.sh" "hors conteneur : un vrai kubectl fausserait les appels"
    bilan "TASK-066 / install-metrics.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }

# Faux kubectl : la sortie des expressions demandées telle que le vrai la rend, ses
# messages d'erreur, codes compris. La donnée n'est rendue que pour l'expression -o
# attendue, sans quoi un script qui demanderait n'importe quoi serait servi pareil.
faux kubectl <<'EOF'
#!/bin/sh
printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-appels"; printf 'kubectl %s\n' "$*" >> "$BAC/kubectl-tous"
[ -z "${KUBECTL_ERREUR:-}" ] || { printf '%s\n' "$KUBECTL_ERREUR" >&2; exit "${KUBECTL_CODE:-1}"; }
o=""; precedent=""
for a in "$@"; do [ "$precedent" = "-o" ] && o="$a"; precedent="$a"; done
rendre() {   # <fichier> <expression attendue> <message NotFound>
    [ "$o" = "$2" ] || { printf 'kubectl inattendu : -o « %s »\n' "$o" >&2; exit 1; }
    [ -f "$BAC/$1" ] || { printf 'Error from server (NotFound): %s\n' "$3" >&2; exit 1; }
    cat "$BAC/$1"; }
case "$1 $2" in
    "get deployment") rendre deploiement "$CC_DEPLOIEMENT" 'deployments.apps "metrics-server" not found' ;;
    "get apiservice") rendre apiservice "$JP_APISERVICE" 'apiservices.apiregistration.k8s.io "v1beta1.metrics.k8s.io" not found' ;;
    "top nodes")
        [ ! -s "$BAC/topnodes-erreur" ] || { cat "$BAC/topnodes-erreur" >&2; exit 1; }
        cat "$BAC/topnodes" 2>/dev/null || { printf 'error: metrics not available yet\n' >&2; exit 1; } ;;
    *) printf 'kubectl inattendu : %s\n' "$*" >&2; exit 1 ;;
esac
EOF

sain() {   # déploiement disponible, APIService Available, relevé rendu
    printf '%s 1 1\n' "$IMAGE" > "$BAC/deploiement"
    printf 'True||\n' > "$BAC/apiservice"
    printf 'NAME   CPU(cores)   CPU%%   MEMORY(bytes)   MEMORY%%\nnode1  120m         6%%     1500Mi          40%%\n' > "$BAC/topnodes"
    : > "$BAC/topnodes-erreur"; : > "$BAC/kubectl-appels"; }
CHEMIN="$BAC:$PATH"
EXTRA=(); CODE=0
lancer() { sortie="$(env PATH="$CHEMIN" "${EXTRA[@]}" timeout 60 bash "$CIBLE" </dev/null 2>&1)" && CODE=0 || CODE=$?; }

titre "Codes d'usage"
sortie="$(timeout 30 bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "v1beta1.metrics.k8s.io" "--help nomme l'APIService vérifiée"
timeout 30 bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "kubectl ou timeout absent"
for b in sans-kubectl sans-timeout; do
    mkdir -p "$BAC/$b"
    for c in bash sh timeout id mkdir basename dirname date uname cat tee sed head rm mktemp; do
        ln -sf "$(command -v "$c")" "$BAC/$b/$c"; done; done
ln -sf "$BAC/kubectl" "$BAC/sans-timeout/kubectl"
rm -f "$BAC/sans-timeout/timeout"
sortie="$(PATH="$BAC/sans-kubectl" timeout 60 bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "introuvable(s) : kubectl" "le message nomme kubectl"
sortie="$(PATH="$BAC/sans-timeout" timeout 60 bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans timeout, le script rend 1"
assert_contient "$sortie" "introuvable(s) : timeout" "le message nomme timeout"

titre "Cluster injoignable, kubeconfig invalide, droits insuffisants"
sain; EXTRA=(KUBECTL_ERREUR='The connection to the server 127.0.0.1:6443 was refused - did you specify the right host or port?'); lancer; EXTRA=()
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "injoignable" "le message nomme l'apiserver"
sain; EXTRA=(KUBECTL_ERREUR='error: error loading config file "/root/.kube/config": yaml: line 3: mapping values are not allowed in this context'); lancer; EXTRA=()
assert_code 1 "$CODE" "un kubeconfig mal formé rend 1"
assert_contient "$sortie" "Kubeconfig invalide" "message distinct de l'apiserver injoignable"
sain; EXTRA=(KUBECTL_ERREUR='Error from server (Forbidden): deployments.apps "metrics-server" is forbidden'); lancer; EXTRA=()
assert_code 1 "$CODE" "un refus de droits rend 1"
assert_contient "$sortie" "Droits insuffisants" "troisième message, distinct des deux autres"
sain; EXTRA=("KUBECTL_ERREUR=error: the server doesn't have a resource type \"apiservices\""); lancer; EXTRA=()
assert_code 1 "$CODE" "une ressource inconnue de l'API rend 1"
assert_contient "$sortie" "Ressource inconnue de l'API" "elle est nommée pour ce qu'elle est"
assert_absent "$sortie" "injoignable" "et non prise pour un apiserver muet"

titre "Déploiement metrics-server"
sain; rm -f "$BAC/deploiement"; lancer
assert_code 1 "$CODE" "un déploiement absent rend 1"
assert_contient "$sortie" "Déploiement metrics-server absent du namespace kube-system" "le message le nomme avec son namespace"
assert_contient "$sortie" "Rien n'a été installé" "et dit que rien n'a été installé"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'absence"
sain; printf '%s <none> 1\n' "$IMAGE" > "$BAC/deploiement"; lancer
assert_code 1 "$CODE" "sans réplique disponible, le script rend 1"
assert_contient "$sortie" "non disponible dans kube-system : 0/1" "le message donne les répliques disponibles sur désirées"
sain; lancer
assert_contient "$sortie" "Image        $IMAGE" "la version de metrics-server est affichée"
assert_contient "$sortie" "Disponibles  1/1" "et ses répliques disponibles sur désirées"
assert_contient "$(cat "$BAC/kubectl-appels")" "-o $CC_DEPLOIEMENT" "le déploiement est lu par ses colonnes nommées : image, .status.availableReplicas, .spec.replicas"

titre "APIService v1beta1.metrics.k8s.io"
sain; rm -f "$BAC/apiservice"; lancer
assert_code 1 "$CODE" "une APIService absente rend 1"
assert_contient "$sortie" "APIService v1beta1.metrics.k8s.io absente" "le message la nomme"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'absence"
sain; printf 'False|ServiceUnavailable|the server is currently unable to handle the request\n' > "$BAC/apiservice"; lancer
assert_code 1 "$CODE" "une APIService non Available rend 1, sans rien installer"
assert_contient "$sortie" "non Available (ServiceUnavailable)" "sa raison est affichée"
sain; printf 'False||\n' > "$BAC/apiservice"; lancer
assert_code 1 "$CODE" "une APIService sans raison rend 1 aussi"
assert_contient "$sortie" "raison non donnée" "l'absence de raison est dite, non passée sous silence"

titre "Relevé « kubectl top nodes »"
sain; rm -f "$BAC/topnodes"; lancer
assert_code 1 "$CODE" "un relevé refusé rend 1"
assert_contient "$sortie" "metrics not available yet" "l'erreur réelle de kubectl est montrée"
assert_contient "$sortie" "[WARN] L'API metrics est enregistrée mais ne sert pas encore" "elle est signalée en [WARN], nommée"
assert_contient "$sortie" "~1 minute" "et rapportée au délai de démarrage de metrics-server"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque le relevé manquant"
sain; printf 'error: Metrics API not available\n' > "$BAC/topnodes-erreur"; lancer
assert_code 1 "$CODE" "une API metrics absente rend 1"
assert_contient "$sortie" "L'API metrics n'est pas enregistrée" "distinguée de l'API enregistrée mais muette"
sain; : > "$BAC/topnodes"; lancer
assert_code 1 "$CODE" "un relevé vide rend 1"
assert_contient "$sortie" "Le relevé est vide" "le vide est dit, non pris pour une réussite"
sain; lancer
assert_code 0 "$CODE" "un cluster sain rend 0"
assert_contient "$sortie" "Available    True" "la condition Available est constatée"
assert_contient "$sortie" "node1  120m" "le relevé est affiché tel quel"
assert_contient "$sortie" "[SUCCESS]" "et le verdict est déclaré"
assert_contient "$(cat "$BAC/kubectl-appels")" "-o $JP_APISERVICE" "l'APIService est lue par son jsonpath, condition Available comprise"
assert_contient "$(cat "$BAC/kubectl-appels")" "top nodes --request-timeout=5s" "et le relevé est demandé par « kubectl top nodes »"

titre "Délai dépassé — « timeout » enveloppe chaque appel"
REEL_TIMEOUT="$(command -v timeout)"
# Faux « timeout » : 124 sans attente réelle, sur le seul appel kubectl nommé.
faux timeout <<EOF
#!/bin/sh
case "\${TIMEOUT_SUR:-}:\$*" in
    "kubectl:7 kubectl "*) printf '%s\n' "\$*" >> "$BAC/timeout-appels"; exit 124 ;;
    *) exec $REEL_TIMEOUT "\$@" ;;
esac
EOF
: > "$BAC/timeout-appels"
sain; EXTRA=(TIMEOUT_SUR=kubectl); lancer; EXTRA=()
assert_code 1 "$CODE" "un appel kubectl qui expire rend 1"
assert_contient "$sortie" "délai dépassé" "le délai est nommé pour ce qu'il est"
assert_contient "$sortie" "« kubectl get deployment metrics-server -n kube-system » a été interrompu" "et l'appel qui a expiré est nommé"
assert_absent "$sortie" "[SUCCESS]" "aucun [SUCCESS] ne masque l'expiration"
assert_egal "7 kubectl get deployment metrics-server -n kube-system --no-headers -o $CC_DEPLOIEMENT --request-timeout=5s" "$(head -1 "$BAC/timeout-appels")" "le délai externe vaut 7 (5 + 2), et l'appel reste borné à 5 s"
rm -f "$BAC/timeout"

titre "Mutation — la vérification de l'APIService porte la preuve"
mkdir -p "$BAC/mutant/lib"
cp "$SCRIPTS_ROOT/lib/common.sh" "$BAC/mutant/lib/common.sh"
sed 's/\[ "\$STATUT" = "True" \]/[ "$STATUT" != "True" ]/' "$CIBLE" > "$BAC/mutant/install-metrics.sh"
assert_egal "non" "$(cmp -s "$CIBLE" "$BAC/mutant/install-metrics.sh" && echo oui || echo non)" "la copie jetable diffère bien de l'original : la mutation a mordu"
sain; printf 'False|ServiceUnavailable|the server is currently unable to handle the request\n' > "$BAC/apiservice"
sortie="$(env PATH="$CHEMIN" timeout 60 bash "$BAC/mutant/install-metrics.sh" </dev/null 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "condition inversée, l'APIService non Available passe : l'assertion du script n'est pas creuse"
assert_contient "$sortie" "[SUCCESS]" "et c'est bien le [SUCCESS] interdit qui apparaît"

titre "Ce que le script ne fait jamais"
assert_egal "0" "$(grep -c require_root "$CIBLE" || true)" "aucun require_root : lecture seule"
assert_egal "0" "$(grep -vc -- '--request-timeout=5s' "$BAC/kubectl-tous" || true)" "chaque appel kubectl de toute la suite porte --request-timeout"
assert_egal "0" "$(grep -vcE '^kubectl (get deployment|get apiservice|top nodes) ' "$BAC/kubectl-tous" || true)" "aucun appel kubectl ne sort de ces trois lectures"
assert_egal "0" "$(grep -cE 'apply|create|patch|delete|edit|annotate|label|scale' "$BAC/kubectl-tous" || true)" "aucune écriture dans le cluster"
assert_egal "0" "$(grep -c 'k3s.yaml' "$CIBLE" || true)" "aucune référence au kubeconfig de K3s"
# Sondes du faux, après la relecture du journal : elles l'écriraient sinon.
PATH="$CHEMIN" kubectl get deployment metrics-server -o 'jsonpath={.items}' >/dev/null 2>&1 && code=0 || code=$?
assert_code 1 "$code" "le faux refuse une expression -o qu'il n'attend pas : les colonnes demandées sont donc prouvées"
PATH="$CHEMIN" kubectl get pods >/dev/null 2>&1 && code=0 || code=$?
assert_code 1 "$code" "et il refuse une lecture hors des trois vérifiées"

bilan "TASK-066 / install-metrics.sh"
