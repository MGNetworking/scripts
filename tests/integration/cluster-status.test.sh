#!/usr/bin/env bash
# tests/integration/cluster-status.test.sh — Kubernetes/Maintenance/cluster-status.sh.
# Aucun cluster réel : un faux kubectl en tête de PATH rend les sorties et le
# vrai code de retour — 1 dès que l'apiserver est injoignable. La garde de
# conteneur passe avant tout trap ou écriture.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/cluster-status.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "cluster-status.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait le relevé"
    bilan "TASK-055 / cluster-status.sh"
fi
BAC="$(mktemp -d)"
export BAC
trap 'rm -rf "$BAC"' EXIT

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
present() { test -e "$1" && echo présente || echo absente; }

# Le faux rend le fichier de la ressource demandée, et le code de cat : un
# fichier absent est un échec, comme un apiserver muet.
faux kubectl <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels"
printf '%s' "${KUBECONFIG:-aucun}" > "$BAC/kubeconfig-vu"
if [ "${KUBECTL_INJOIGNABLE:-0}" = 1 ]; then
    echo "The connection to the server 127.0.0.1:6443 was refused" >&2
    exit 1
fi
case "$*" in
  *"get nodes"*)       exec cat "$BAC/nodes" ;;
  *"get namespaces"*)  exec cat "$BAC/namespaces" ;;
  *"get pods"*)        exec cat "$BAC/pods" ;;
  *"get deployments"*) exec cat "$BAC/deployments" ;;
  *"get services"*)    exec cat "$BAC/services" ;;
  *version*)           exec cat "$BAC/version" ;;
esac
exit 1
EOF
# Ni K3s ni systemd n'ont leur place ici : leurs faux laissent une trace.
for outil in k3s systemctl; do
    printf '#!/bin/sh\ntouch "%s/%s-appele"\nexit 0\n' "$BAC" "$outil" > "$BAC/$outil"
    chmod +x "$BAC/$outil"
done

cluster_sain() {
    printf '%s\n' "nœud-1   Ready   control-plane   5d   v1.30.5   10.0.0.1   <none>   Debian 12" > "$BAC/nodes"
    printf '%s\n' "Client Version: v1.31.0" "Server Version: v1.30.5" > "$BAC/version"
    printf '%s\n' "default" "kube-system" > "$BAC/namespaces"
    printf '%s\n' "kube-system   coredns-aaa   1/1   Running   0   5d" > "$BAC/pods"
    printf '%s\n' "kube-system   traefik-bbb   1/1   1   1   5d" > "$BAC/deployments"
    printf '%s\n' "default   kubernetes   10.96.0.1   <none>   443/TCP   5d" > "$BAC/services"
    : > "$BAC/appels"
}

CODE=0; codes=""; sortie=""
# codes garde chaque code rendu : à la fin, le 2 ne doit venir que de l'usage.
lancer() { sortie="$(KUBECONFIG="$BAC/kubeconfig-essai" PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }
sans_kubectl() { sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "Nœuds"          "--help nomme les rubriques"
assert_contient "$sortie" "KUBECONFIG"     "--help dit comment le kubeconfig est résolu"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "kubectl introuvable"
sans_kubectl
assert_code 1 "$CODE" "sans kubectl, le script rend 1"
assert_contient "$sortie" "[ERROR]" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "kubectl" "et le message nomme kubectl"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "Cluster joignable — la garde de contraste de tous les cas suivants"
cluster_sain
lancer
assert_code 0 "$CODE" "un cluster joignable rend 0"
assert_contient "$sortie" "nœud-1"  "les nœuds sont listés"
assert_contient "$sortie" "Server Version: v1.30.5" "les versions client et serveur sont rapportées"
assert_contient "$sortie" "kube-system" "les namespaces sont listés"
assert_contient "$sortie" "coredns-aaa" "les pods de tous les namespaces sont listés"
assert_contient "$sortie" "traefik-bbb" "les deployments de tous les namespaces sont listés"
assert_contient "$sortie" "10.96.0.1"   "les services de tous les namespaces sont listés"

ordonnancees="$(printf '%s\n' "$sortie" | grep -oE '^(Nœuds|Versions client et serveur|Namespaces|Pods \(tous les namespaces\)|Deployments \(tous les namespaces\)|Services \(tous les namespaces\))$' | tr '\n' '|')"
assert_egal "Nœuds|Versions client et serveur|Namespaces|Pods (tous les namespaces)|Deployments (tous les namespaces)|Services (tous les namespaces)|" \
    "$ordonnancees" "les six rubriques s'affichent, dans l'ordre du plan"

titre "Les appels passent par kubectl, et sont bornés"
assert_contient "$(cat "$BAC/appels")" "get nodes -o wide" "les nœuds sont demandés en -o wide"
for forme in "get namespaces" "get pods -A" "get deployments -A" "get services -A"; do
    assert_contient "$(cat "$BAC/appels")" "$forme" "l'appel « $forme » est passé à kubectl"
done
sans_delai="$(grep -vc -- '--request-timeout=5s' "$BAC/appels" || true)"
assert_egal "0" "$sans_delai" "chaque appel kubectl porte --request-timeout"
hors_forme="$(grep -vcE '^(version|get (nodes|namespaces|pods|deployments|services)) ' "$BAC/appels" || true)"
assert_egal "0" "$hors_forme" "aucun appel ne sort de ces six formes"
assert_egal "$BAC/kubeconfig-essai" "$(cat "$BAC/kubeconfig-vu")" "le KUBECONFIG de l'appelant atteint kubectl tel quel"
assert_egal "absente" "$(present "$BAC/k3s-appele")" "rien ne passe par k3s"
assert_egal "absente" "$(present "$BAC/systemctl-appele")" "ni par systemctl"

titre "Sans KUBECONFIG, le script n'en invente aucun"
sortie="$(env -u KUBECONFIG PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?
codes="$codes $CODE"
assert_code 0 "$CODE" "le relevé se fait sans KUBECONFIG déclaré"
assert_egal "aucun" "$(cat "$BAC/kubeconfig-vu")" "kubectl reste seul juge de sa résolution"

titre "Apiserver injoignable"
cluster_sain
export KUBECTL_INJOIGNABLE=1
lancer
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]"  "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "et le message nomme l'apiserver"
assert_absent  "$sortie" "Namespaces" "aucune rubrique suivante n'est enchaînée"
assert_absent  "$sortie" "Services (tous les namespaces)" "pas même la dernière"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel kubectl a été tenté"

titre "Pods dégradés : le verdict ne juge pas la santé du cluster"
cluster_sain
printf '%s\n' "default   cassé-1   0/1   CrashLoopBackOff   7   3m" > "$BAC/pods"
lancer
assert_code 0 "$CODE" "un pod en CrashLoopBackOff ne rend pas 1 : la recherche d'anomalies relève de diagnostics.sh"
assert_contient "$sortie" "CrashLoopBackOff" "et son état est affiché tel quel"

titre "Root non requis"
faux id <<'EOF'
#!/bin/sh
[ "$*" = "-u" ] && { echo 1000; exit 0; }
exec /usr/bin/id "$@"
EOF
cluster_sain
lancer
assert_code 0 "$CODE" "un utilisateur non privilégié obtient le même relevé"

cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'erreur d'usage"

bilan "TASK-055 / cluster-status.sh"
