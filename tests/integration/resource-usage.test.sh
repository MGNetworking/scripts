#!/usr/bin/env bash
# tests/integration/resource-usage.test.sh — Kubernetes/Maintenance/resource-usage.sh.
# Aucun cluster réel : un faux kubectl rend les sorties et les codes du vrai — y
# compris « Metrics API not available » — et note ses arguments.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/resource-usage.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "resource-usage.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait le relevé"
    bilan "TASK-059 / resource-usage.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
present() { test -e "$1" && echo présente || echo absente; }
: > "$BAC/tous"
# Le faux lit la fixture « $1-$2 » ; vide, il annonce la liste vide sur stderr.
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" | tee -a "$BAC/appels" >> "$BAC/tous"
[ "${KUBECTL_INJOIGNABLE:-0}" = 1 ] && { echo "The connection to the server 127.0.0.1:6443 was refused" >&2; exit 1; }
[ "${KUBECTL_INTERDIT:-0}" = 1 ] && { echo "Error from server (Forbidden): nodes is forbidden" >&2; exit 1; }
[ "$1" = top ] && [ "${KUBECTL_METRIQUES:-1}" != 1 ] && { echo "error: Metrics API not available" >&2; exit 1; }
[ "$1" = top ] && [ "$2" = pods ] && [ "${KUBECTL_PODS_KO:-0}" = 1 ] && { echo "error: unable to retrieve metrics for pods" >&2; exit 1; }
fic="$BAC/$1-$2"
[ -e "$fic" ] || { echo "Error from server (NotFound): the server could not find the requested resource" >&2; exit 1; }
[ -s "$fic" ] || { echo "No resources found" >&2; exit 0; }
cat "$fic"
EOF
chmod +x "$BAC/kubectl"
# Ni K3s ni systemd n'ont leur place ici : leurs faux laissent une trace.
for outil in k3s systemctl; do printf '#!/bin/sh\ntouch "%s/%s-appele"\n' "$BAC" "$outil" > "$BAC/$outil" && chmod +x "$BAC/$outil"; done
CODE=0; sortie=""
# Chaque lancer repart d'un journal vierge : « appels » ne porte que sur le cas.
lancer() { : > "$BAC/appels"; sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }
avec() { local v="$1"; shift; export "${v?}"; lancer "$@"; unset "${v%%=*}"; }

# Formes réelles : « kubectl top » rend un tableau à en-tête, « describe nodes »
# les blocs Capacity: et Allocatable:, indentés de deux espaces.
metriques() {
    printf '%s\n' "NAME     CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%" \
                  "node-1   120m         3%     1500Mi          18%" > "$BAC/top-nodes"
    printf '%s\n' "NAMESPACE    NAME          CPU(cores)   MEMORY(bytes)" \
                  "kube-system  coredns-abc   4m           18Mi" \
                  "default      web-1         12m          64Mi" > "$BAC/top-pods"
    printf '%s\n' "node-1   Ready   control-plane   10d   v1.31.4" > "$BAC/get-nodes"
    printf '%s\n' "Name:               node-1" "Capacity:" "  cpu:                4" \
                  "  memory:             8123456Ki" "  pods:               110" "Allocatable:" \
                  "  cpu:                3800m" "  memory:             7600000Ki" "  pods:               110" > "$BAC/describe-nodes"
}

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "kubectl top nodes" "--help documente le mode avec métriques"
assert_contient "$sortie" "capacité et l'allocatable" "--help documente le mode sans métriques"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
sortie="$(bash "$CIBLE" --namespace 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--namespace sans valeur rend 2"
assert_contient "$sortie" "[ERROR]" "et le manque de valeur est signalé en [ERROR]"
# Une valeur en tiret serait transmise à kubectl : le refus précède tout appel.
lancer --namespace -A
assert_egal "2 0" "$CODE $(wc -l < "$BAC/appels")" "--namespace -A rend 2, sans tenter le moindre appel"

titre "kubectl introuvable"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "sans kubectl, le script rend 1"
assert_contient "$sortie" "[ERROR]" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "kubectl" "et le message nomme kubectl"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "API metrics disponible — la garde de contraste"
metriques
lancer
appels="$(cat "$BAC/appels")"
assert_code 0 "$CODE" "avec métriques, le relevé rend 0"
assert_contient "$sortie" "[SUCCESS]" "et il le dit en [SUCCESS]"
assert_contient "$sortie" "node-1   120m" "le CPU et la mémoire du nœud sont affichés tels quels"
assert_contient "$sortie" "web-1         12m" "ceux des pods aussi"
assert_contient "$appels" "top nodes --no-headers" "« kubectl top nodes » est demandé"
assert_contient "$appels" "top pods -A --no-headers" "puis « kubectl top pods » sur tous les namespaces"
assert_contient "$(head -1 "$BAC/appels")" "get nodes" "la sonde de l'apiserver ouvre le relevé, avant « top »"
assert_absent  "$appels" "describe" "aucun repli n'est tenté quand les métriques répondent"
assert_absent  "$sortie" "[WARN]" "sans aucun avertissement"

titre "Namespace désigné, puis pods sans métrique à rendre"
lancer --namespace kube-system
assert_code 0 "$CODE" "--namespace rend 0"
assert_contient "$sortie" "pods (namespace kube-system)" "la rubrique annonce la portée demandée"
assert_contient "$(cat "$BAC/appels")" "top pods -n kube-system --no-headers" "les pods sont demandés pour ce seul namespace"
assert_absent  "$(cat "$BAC/appels")" " -A " "et -A n'est pas employé"
: > "$BAC/top-pods"
lancer
assert_code 0 "$CODE" "aucun pod à relever : le script rend 0, ce n'est pas une panne"
assert_contient "$sortie" "[INFO] Aucun pod" "il le dit en [INFO]"
assert_absent  "$sortie" "No resources found" "la sortie d'erreur de kubectl n'entre pas dans la liste"
assert_contient "$sortie" "[SUCCESS]" "le relevé reste complet"

titre "API metrics absente — repli sur la capacité des nœuds"
metriques
avec KUBECTL_METRIQUES=0
assert_code 0 "$CODE" "sans API metrics, le relevé rend 0 : ce n'est pas une panne"
assert_contient "$sortie" "[WARN] API metrics absente" "et l'absence est dite en [WARN]"
assert_contient "$(cat "$BAC/appels")" "describe nodes" "la capacité et l'allocatable sont relevés à sa place"
assert_contient "$sortie" "8123456Ki" "la capacité mémoire du nœud est affichée"
assert_contient "$sortie" "3800m" "l'allocatable CPU aussi, distinct de la capacité"
assert_absent  "$sortie" "Allocatable:" "le décrivant n'est pas rendu tel quel"
assert_absent  "$(cat "$BAC/appels")" "top pods" "aucun relevé de pods n'est tenté sans métriques"
assert_contient "$sortie" "[SUCCESS]" "le relevé reste déclaré terminé"

titre "Une rubrique illisible interdit le [SUCCESS] (A78)"
metriques
avec KUBECTL_PODS_KO=1
assert_code 1 "$CODE" "des métriques de pods illisibles rendent 1"
assert_contient "$sortie" "Relevé impossible : CPU et mémoire des pods" "la rubrique est nommée"
assert_absent  "$sortie" "[SUCCESS]" "et jamais [SUCCESS] : un relevé amputé n'est pas terminé"
rm -f "$BAC/describe-nodes"
avec KUBECTL_METRIQUES=0
assert_code 1 "$CODE" "un repli illisible rend 1"
assert_contient "$sortie" "ne connaît pas la ressource" "la cause rendue par kubectl est distinguée"
assert_absent  "$sortie" "[SUCCESS]" "sans [SUCCESS] : rien n'a pu être relevé"
metriques
avec KUBECTL_METRIQUES=0
assert_code 0 "$CODE" "contraste : la description revenue, le repli rend 0"

titre "Apiserver injoignable, puis droit refusé sur la sonde"
avec KUBECTL_INJOIGNABLE=1
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "apiserver" "l'échec est signalé en [ERROR] et nomme l'apiserver"
assert_contient "$sortie" "was refused" "la raison rendue par kubectl est montrée"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel est tenté : la sonde arrête le relevé"
avec KUBECTL_INTERDIT=1
assert_code 1 "$CODE" "un « get nodes » refusé rend 1"
assert_contient "$sortie" "Droits insuffisants" "le refus est nommé pour ce qu'il est"
assert_absent  "$sortie" "apiserver ne répond pas" "un refus de droits n'est pas un apiserver muet"

titre "kubectl seul, appels bornés, lecture seule"
assert_egal "0" "$(grep -vc -- '--request-timeout=5s' "$BAC/tous" || true)" "chaque appel kubectl de la suite porte --request-timeout"
assert_egal "0" "$(grep -vcE '^(get nodes|top nodes|top pods|describe nodes) ' "$BAC/tous" || true)" "aucun appel ne sort des quatre relevés attendus"
for verbe in delete apply patch exec cordon drain scale rollout edit create; do
    assert_absent "$(cat "$BAC/tous")" "$verbe" "aucun appel « $verbe » : rien n'est modifié sur le cluster"
done
assert_absent "$(cat "$CIBLE")" "k3s.yaml" "aucune référence à /etc/rancher/k3s/k3s.yaml : kubectl résout son kubeconfig"
assert_absent "$(cat "$CIBLE")" "require_root" "aucun require_root : le script s'exécute sans root"
assert_egal "absente absente" "$(present "$BAC/k3s-appele") $(present "$BAC/systemctl-appele")" "ni k3s ni systemctl ne sont appelés"

bilan "TASK-059 / resource-usage.sh"
