#!/usr/bin/env bash
# tests/integration/diagnostics.test.sh — Kubernetes/Maintenance/diagnostics.sh.
# Aucun cluster réel : un faux kubectl rend les tableaux et le vrai code, et note
# ses arguments — « appels » par cas, « tous » sur la suite. Chaque cas
# d'anomalie a sa garde de contraste : l'anomalie retirée, le même faux rend 0.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/diagnostics.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "diagnostics.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait le diagnostic"
    bilan "TASK-058 / diagnostics.sh"
fi
BAC="$(mktemp -d)"; export BAC
trap 'rm -rf "$BAC"' EXIT
present() { test -e "$1" && echo présente || echo absente; }
: > "$BAC/tous"
cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" | tee -a "$BAC/appels" >> "$BAC/tous"
[ "${KUBECTL_INJOIGNABLE:-0}" = 1 ] && { echo "The connection to the server 127.0.0.1:6443 was refused" >&2; exit 1; }
[ "${KUBECTL_INTERDIT:-0}" = 1 ] && [ "$2" = pods ] && { echo "Error from server (Forbidden): pods is forbidden" >&2; exit 1; }
[ "$1" = get ] || exit 1
shift
[ -f "$BAC/$1" ] || exit 1
cat "$BAC/$1"
EOF
chmod +x "$BAC/kubectl"
# Ni K3s ni systemd n'ont leur place ici : leurs faux laissent une trace.
for outil in k3s systemctl; do printf '#!/bin/sh\ntouch "%s/%s-appele"\n' "$BAC" "$outil" > "$BAC/$outil" && chmod +x "$BAC/$outil"; done
CODE=0; sortie=""
# Chaque lancer repart d'un journal vierge : « appels » ne porte que sur le cas.
lancer() { : > "$BAC/appels"; sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?; }
# Cluster sain — la garde de contraste de tous les cas d'anomalie ci-dessous.
sain() {
    printf '%s\n' "node-1  Ready  control-plane  10d  v1.31.4" > "$BAC/nodes"
    printf '%s\n' "kube-system  coredns-abc  1/1  Running  0  10d" "default  job-1  0/1  Completed  0  2d" > "$BAC/pods"
    printf '%s\n' "default  web  2/2  2  2  10d" > "$BAC/deployments"
    printf '%s\n' "default  db  1/1  1  1  10d" > "$BAC/statefulsets"
    printf '%s\n' "kube-system  agent  3  3  3/3  3  3  <none>  10d" > "$BAC/daemonsets"
    : > "$BAC/events"
}
titre "Codes d'usage, et kubectl introuvable"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "CrashLoopBackOff" "--help nomme les anomalies de pod recherchées"
assert_contient "$sortie" "« Ready »" "--help nomme l'état de nœud recherché"
assert_contient "$sortie" "répliques prêtes" "--help annonce le critère des workloads"
assert_contient "$sortie" "Warning" "--help dit le sort des événements Warning"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans kubectl, le script rend 1"
assert_contient "$sortie" "[ERROR]" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "kubectl" "et le message nomme kubectl"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "Cluster sain — la garde de contraste"
sain
lancer
assert_code 0 "$CODE" "aucune anomalie : le diagnostic rend 0"
assert_contient "$sortie" "[SUCCESS]" "et il le dit en [SUCCESS]"
assert_absent  "$sortie" "[WARN]" "sans aucun avertissement"
assert_contient "$sortie" "2 pod(s) examiné(s)" "tous les pods sont examinés"
assert_absent  "$sortie" "job-1" "un Job terminé n'est pas une anomalie"

titre "Nœud non prêt, nœud cordonné"
sain
printf '%s\n' "node-1  Ready  control-plane  10d  v1.31.4" "node-2  NotReady  <none>  2m  v1.31.4" > "$BAC/nodes"
lancer
assert_code 1 "$CODE" "un nœud non prêt rend 1"
assert_contient "$sortie" "[WARN] Nœud node-2 non prêt : NotReady" "le nœud est nommé en [WARN], avec sa raison"
assert_absent  "$sortie" "node-1" "un nœud prêt n'est pas signalé"
printf '%s\n' "node-1  Ready,SchedulingDisabled  control-plane  10d  v1.31.4" > "$BAC/nodes"
lancer
assert_code 0 "$CODE" "un nœud cordonné reste prêt : ce n'est pas une anomalie"

titre "Pods en anomalie"
sain
printf '%s\n' "default  crash-1  0/1  CrashLoopBackOff  5  2d" "default  init-1  0/1  Init:CrashLoopBackOff  5  2d" \
              "default  pull-1  0/1  ImagePullBackOff  0  5m" "default  pend-1  0/1  Pending  0  5m" \
              "default  fail-1  0/1  Failed  0  1h" "default  err-1  0/1  Error  0  1h" \
              "default  web-1  1/1  Running  0  10d" > "$BAC/pods"
lancer
assert_code 1 "$CODE" "des pods en anomalie rendent 1"
assert_contient "$sortie" "Pod default/crash-1 : CrashLoopBackOff" "CrashLoopBackOff est lu dans STATUS, pas dans la phase"
assert_contient "$sortie" "Pod default/init-1 : Init:CrashLoopBackOff" "y compris préfixé par un conteneur d'init"
assert_contient "$sortie" "Pod default/pull-1 : ImagePullBackOff" "ImagePullBackOff est signalé"
assert_contient "$sortie" "Pod default/pend-1 : Pending" "Pending est signalé"
assert_contient "$sortie" "Pod default/fail-1 : Failed" "Failed est signalé"
assert_contient "$sortie" "Pod default/err-1 : Error" "Error est signalé"
assert_absent  "$sortie" "web-1" "un pod Running n'est pas signalé"
assert_contient "$sortie" "7 pod(s) examiné(s)" "les six anomalies sont vues parmi les sept pods"

titre "Workloads incomplets"
sain
printf '%s\n' "default  web  1/2  1  1  10d" > "$BAC/deployments"
printf '%s\n' "default  db  0/1  1  0  10d" > "$BAC/statefulsets"
printf '%s\n' "kube-system  agent  3  3  2/3  3  2  <none>  10d" > "$BAC/daemonsets"
lancer
assert_code 1 "$CODE" "des répliques manquantes rendent 1"
assert_contient "$sortie" "default/web : 1/2 répliques prêtes" "un Deployment incomplet est signalé"
assert_contient "$sortie" "default/db : 0/1 répliques prêtes" "un StatefulSet incomplet est signalé"
assert_contient "$sortie" "kube-system/agent : 2/3 répliques prêtes" "un DaemonSet aussi, READY n'étant pas son premier champ"

titre "Événements Warning : affichés, sans effet sur le verdict"
sain
printf '%s\n' "default  5m  Warning  FailedMount  pod/db-1  MountVolume.SetUp failed" > "$BAC/events"
lancer
assert_code 0 "$CODE" "un Warning ne change pas le code de retour"
assert_contient "$sortie" "FailedMount" "il est affiché"
assert_absent  "$sortie" "[WARN]" "sans être compté comme une anomalie"
assert_contient "$sortie" "[SUCCESS]" "le cluster reste déclaré sain"
assert_contient "$(cat "$BAC/appels")" "get events -A --field-selector type=Warning" "le filtre de type est demandé à l'apiserver"
: > "$BAC/events"
lancer
assert_code 0 "$CODE" "aucun Warning rend 0 aussi"
assert_contient "$sortie" "Aucun événement Warning" "et le script le dit"

titre "Apiserver injoignable, puis droit RBAC manquant"
export KUBECTL_INJOIGNABLE=1
lancer
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "et le message nomme l'apiserver"
assert_contient "$sortie" "was refused" "la raison rendue par kubectl est montrée, pas tue"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel est tenté : la sonde arrête le diagnostic"
sain
export KUBECTL_INTERDIT=1
lancer
unset KUBECTL_INTERDIT
assert_code 1 "$CODE" "une rubrique illisible rend 1 sans interrompre le diagnostic"
assert_contient "$sortie" "Relevé impossible : Pods (tous les namespaces)" "elle est signalée en nommant la rubrique"
assert_contient "$(cat "$BAC/appels")" "get deployments" "les rubriques suivantes sont quand même tentées"

titre "kubectl seul, appels bornés, lecture seule"
appels="$(cat "$BAC/tous")"
assert_egal "0" "$(grep -vc -- '--request-timeout=5s' "$BAC/tous" || true)" "chaque appel kubectl porte --request-timeout"
assert_egal "0" "$(grep -vcE '^get (nodes|pods|deployments|statefulsets|daemonsets|events) ' "$BAC/tous" || true)" "aucun appel ne sort des six relevés attendus"
for verbe in logs describe delete cordon drain exec apply patch scale rollout; do
    assert_absent "$appels" "$verbe" "aucun appel « $verbe » : rien n'est corrigé, rien n'est déplié"
done
assert_absent "$appels" "-o yaml" "aucun manifeste n'est relu en YAML"
assert_absent "$appels" "-o json" "aucun manifeste n'est relu en JSON"
assert_egal "absente absente" "$(present "$BAC/k3s-appele") $(present "$BAC/systemctl-appele")" "ni k3s ni systemctl ne sont appelés"

bilan "TASK-058 / diagnostics.sh"
