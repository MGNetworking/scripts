#!/usr/bin/env bash
# tests/integration/pods-status.test.sh — Kubernetes/Maintenance/pods-status.sh.
# Aucun cluster réel : un faux kubectl en tête de PATH rend les sorties et le
# vrai code de retour, et note les arguments reçus — c'est la preuve du -A ou
# du -n <ns>. La garde de conteneur passe avant tout trap ou écriture.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/pods-status.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "pods-status.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait la liste"
    bilan "TASK-056 / pods-status.sh"
fi
BAC="$(mktemp -d)"
export BAC
trap 'rm -rf "$BAC"' EXIT

faux() { cat > "$BAC/$1"; chmod +x "$BAC/$1"; }
present() { test -e "$1" && echo présente || echo absente; }
tracer() { : > "$BAC/appels"; }

faux kubectl <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels"
if [ "${KUBECTL_INJOIGNABLE:-0}" = 1 ]; then
    echo "The connection to the server 127.0.0.1:6443 was refused" >&2
    exit 1
fi
[ "$1" = get ] || exit 1
shift
case "$1" in
    namespace)
        shift
        [ -f "$BAC/ns-$1" ] || { echo "Error from server (NotFound): namespaces \"$1\" not found" >&2; exit 1; }
        cat "$BAC/ns-$1" ;;
    pods)
        shift
        case "$1" in
            -A) cat "$BAC/pods-A" ;;
            -n) if [ -f "$BAC/pods-$2" ]; then cat "$BAC/pods-$2"
                else echo "No resources found in $2 namespace." >&2; fi ;;
            *)  exit 1 ;;
        esac ;;
    *) exit 1 ;;
esac
EOF
# Ni K3s ni systemd n'ont leur place ici : leurs faux laissent une trace.
for outil in k3s systemctl; do
    printf '#!/bin/sh\ntouch "%s/%s-appele"\n' "$BAC" "$outil" > "$BAC/$outil" && chmod +x "$BAC/$outil"
done

CODE=0; codes=""; sortie=""
# codes garde chaque code rendu : à la fin, le 2 ne doit venir que de l'usage.
lancer() { sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }
sans_kubectl() { sortie="$(PATH="/usr/bin:/bin" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?; codes="$codes $CODE"; }

titre "Codes d'usage"
sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "Codes de retour" "--help documente les codes de retour"
assert_contient "$sortie" "--namespace <ns>" "--help documente --namespace"
assert_contient "$sortie" "get pods -A -o wide" "--help dit ce que fait l'absence d'option"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
sortie="$(bash "$CIBLE" --namespace 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--namespace sans valeur rend 2"
assert_contient "$sortie" "[ERROR]" "et le manque de valeur est signalé en [ERROR]"

titre "kubectl introuvable"
sans_kubectl
assert_code 1 "$CODE" "sans kubectl, le script rend 1"
assert_contient "$sortie" "[ERROR]" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "kubectl" "et le message nomme kubectl"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "Tous les namespaces — la garde de contraste des cas suivants"
printf '%s\n' "default       web-1     1/1   Running   0   5d" \
              "kube-system   coredns-1 1/1   Running   0   5d" > "$BAC/pods-A"
printf '%s\n' "kube-system" > "$BAC/ns-kube-system"
printf '%s\n' "kube-system   coredns-1 1/1   Running   0   5d" > "$BAC/pods-kube-system"
tracer
lancer
assert_code 0 "$CODE" "sans option, le relevé rend 0"
assert_contient "$sortie" "web-1" "les pods du namespace default sont listés"
assert_contient "$sortie" "coredns-1" "ceux de kube-system aussi : tous les namespaces"
assert_contient "$(cat "$BAC/appels")" "get pods -A -o wide" "l'appel est « get pods -A -o wide »"
assert_absent  "$(cat "$BAC/appels")" "get pods -n" "aucun namespace n'est imposé"
assert_absent  "$(cat "$BAC/appels")" "get namespace " "et rien n'est vérifié quand rien n'est demandé"

titre "Namespace désigné"
tracer
lancer --namespace kube-system
appels="$(cat "$BAC/appels")"
assert_code 0 "$CODE" "--namespace rend 0"
assert_contient "$sortie" "coredns-1" "les pods du namespace sont listés"
assert_contient "$appels" "get namespace kube-system" "l'existence du namespace est vérifiée d'abord"
assert_contient "$appels" "get pods -n kube-system -o wide" "la liste est restreinte à ce namespace"
assert_absent  "$appels" "-A" "et -A n'est pas employé"

titre "Namespace inconnu"
tracer
lancer --namespace inconnu
appels="$(cat "$BAC/appels")"
assert_code 1 "$CODE" "un namespace inexistant rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "inconnu" "et le message le nomme"
assert_contient "$appels" "get namespace inconnu" "le namespace a bien été vérifié"
assert_absent  "$appels" "get pods" "aucune liste n'est demandée pour un namespace inconnu"

titre "Namespace existant, aucun pod"
printf '%s\n' "vide" > "$BAC/ns-vide"
tracer
lancer --namespace vide
assert_code 0 "$CODE" "un namespace sans pod rend 0"
assert_contient "$sortie" "[INFO]" "il est signalé en [INFO], pas en erreur"
assert_contient "$sortie" "Aucun pod" "et le message dit qu'il n'y a aucun pod"
assert_contient "$(cat "$BAC/appels")" "get pods -n vide -o wide" "la liste a bien été demandée"

titre "Apiserver injoignable"
export KUBECTL_INJOIGNABLE=1
tracer
lancer
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "et le message nomme l'apiserver"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel kubectl a été tenté"

titre "Pod en échec : le script ne juge pas la santé"
printf '%s\n' "default   cassé-1   0/1   CrashLoopBackOff   7   3m" > "$BAC/pods-A"
tracer
lancer
assert_code 0 "$CODE" "un pod en CrashLoopBackOff ne change pas le code"
assert_contient "$sortie" "CrashLoopBackOff" "et son état est affiché tel quel"

titre "kubectl seul, et appels bornés"
sans_delai="$(grep -vc -- '--request-timeout=5s' "$BAC/appels" || true)"
assert_egal "0" "$sans_delai" "chaque appel kubectl porte --request-timeout"
hors_forme="$(grep -vcE '^get (pods|namespace) ' "$BAC/appels" || true)"
assert_egal "0" "$hors_forme" "aucun appel ne sort de « get pods » et « get namespace »"
assert_egal "absente" "$(present "$BAC/k3s-appele")" "rien ne passe par k3s"
assert_egal "absente" "$(present "$BAC/systemctl-appele")" "ni par systemctl"

cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'erreur d'usage"

bilan "TASK-056 / pods-status.sh"
