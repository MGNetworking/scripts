#!/usr/bin/env bash
# tests/integration/events.test.sh — Kubernetes/Maintenance/events.sh.
# Aucun cluster réel : un faux kubectl rend les sorties et le vrai code, et note
# ses arguments — « appels » par cas, « tous » sur la suite. Le faux ne trie
# rien : c'est l'argument --sort-by qui prouve le tri, pas l'ordre rendu. La
# garde de conteneur passe avant tout trap ou écriture.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Kubernetes/Maintenance/events.sh"
if [ ! -e /.dockerenv ]; then
    saute_indisponible "events.sh" "hors conteneur : un vrai kubectl ou un vrai cluster fausserait la liste"
    bilan "TASK-057 / events.sh"
fi
BAC="$(mktemp -d)"
export BAC
trap 'rm -rf "$BAC"' EXIT

present() { test -e "$1" && echo présente || echo absente; }
tracer() { : > "$BAC/appels"; }
: > "$BAC/tous"

cat > "$BAC/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$BAC/appels"
printf '%s\n' "$*" >> "$BAC/tous"
[ "${KUBECTL_AVERTIT:-0}" = 1 ] && echo "Warning: memcache.go:265] couldn't get current server API group list" >&2
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
    events)
        shift
        ns=""; only=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -n) ns="$2"; shift 2 ;;
                --field-selector) only="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        fichier="$BAC/events-A"; entete="LAST SEEN   TYPE   REASON   OBJECT   MESSAGE"
        if [ -n "$ns" ]; then fichier="$BAC/events-$ns"; else entete="NAMESPACE   $entete"; fi
        [ -s "$fichier" ] || { echo "No resources found${ns:+ in $ns namespace}." >&2; exit 0; }
        printf '%s\n' "$entete"
        if [ "$only" = "type=Warning" ]; then
            awk '{ for (i = 1; i <= NF; i++) if ($i == "Warning") { print; next } }' "$fichier"
        else
            cat "$fichier"
        fi ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$BAC/kubectl"
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
assert_contient "$sortie" "--warnings" "--help documente --warnings"
assert_contient "$sortie" "plus ancien en tête" "--help dit dans quel sens la liste sort"
assert_contient "$sortie" "--sort-by=.lastTimestamp" "--help nomme le tri demandé à kubectl"
bash "$CIBLE" --option-inexistante >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
sortie="$(bash "$CIBLE" --namespace 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--namespace sans valeur rend 2"
assert_contient "$sortie" "[ERROR]" "et le manque de valeur est signalé en [ERROR]"
# Une valeur en tiret serait transmise à kubectl, qui lirait « -A » : tout le
# cluster au lieu du namespace demandé. Le refus doit précéder tout appel.
tracer
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" --namespace -A 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--namespace -A rend 2"
assert_contient "$sortie" "[ERROR]" "et ce nom invalide est signalé en [ERROR]"
assert_egal "0" "$(wc -l < "$BAC/appels")" "aucun appel kubectl n'est tenté pour un nom invalide"

titre "kubectl introuvable"
sans_kubectl
assert_code 1 "$CODE" "sans kubectl, le script rend 1"
assert_contient "$sortie" "[ERROR]" "l'absence est signalée en [ERROR]"
assert_contient "$sortie" "kubectl" "et le message nomme kubectl"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"

titre "Tous les namespaces — la garde de contraste des cas suivants"
printf '%s\n' \
  "default     5m   Normal    Scheduled   pod/web-1   Successfully assigned default/web-1 to node-1" \
  "kube-system 6m   Warning   FailedMount pod/db-1    MountVolume.SetUp failed for volume data" \
  "default     2m   Normal    Pulled      pod/web-2   Container image nginx already present" > "$BAC/events-A"
printf '%s\n' "kube-system" > "$BAC/ns-kube-system"
tracer
lancer
appels="$(cat "$BAC/appels")"
assert_code 0 "$CODE" "sans option, le relevé rend 0"
assert_contient "$sortie" "web-1" "les événements du namespace default sont listés"
assert_contient "$sortie" "db-1" "ceux de kube-system aussi : tous les namespaces"
assert_contient "$sortie" "NAMESPACE" "l'en-tête de -A est affiché, intitulés de colonnes gardés"
assert_contient "$sortie" "3 événement(s)" "et le compte est exact : l'en-tête n'est pas compté"
assert_contient "$sortie" "FailedMount" "un Warning est affiché tel quel, sans jugement"
assert_absent  "$sortie" "[ERROR]" "et sa présence ne change pas le code : il est resté à 0"
assert_contient "$appels" "get events -A --sort-by=.lastTimestamp" "l'appel couvre tous les namespaces et demande le tri croissant"
assert_absent  "$appels" "get events -n" "aucun namespace n'est imposé"
assert_absent  "$appels" "--field-selector" "aucun filtre de type sans --warnings"

titre "Type Warning seulement"
tracer
lancer --warnings
appels="$(cat "$BAC/appels")"
assert_code 0 "$CODE" "--warnings rend 0"
assert_contient "$appels" "get events -A --sort-by=.lastTimestamp --field-selector type=Warning" "le filtre part avec la liste : c'est l'apiserver qui trie par type"
assert_contient "$sortie" "db-1" "l'événement Warning est affiché"
assert_absent  "$sortie" "web-1" "les événements Normal ne sont pas rendus"
assert_contient "$sortie" "1 événement(s)" "et le compte ne retient que le Warning"
assert_contient "$sortie" "NAMESPACE" "l'en-tête reste affiché sous filtre"

titre "Namespace désigné"
printf '%s\n' \
  "3m   Warning   FailedScheduling pod/db-1  0/1 nodes are available" \
  "4m   Normal    Scheduled        pod/db-1  Successfully assigned kube-system/db-1" > "$BAC/events-kube-system"
tracer
lancer --namespace kube-system
appels="$(cat "$BAC/appels")"
assert_code 0 "$CODE" "--namespace rend 0"
assert_contient "$sortie" "FailedScheduling" "les événements du namespace sont listés"
assert_contient "$sortie" "2 événement(s)" "et le compte de ce namespace est exact"
assert_contient "$appels" "get namespace kube-system" "l'existence du namespace est vérifiée d'abord"
assert_contient "$appels" "get events -n kube-system --sort-by=.lastTimestamp" "la liste est restreinte à ce namespace, tri croissant compris"
assert_absent  "$appels" "-A" "et -A n'est pas employé"

titre "--warnings avec --namespace"
tracer
lancer --namespace kube-system --warnings
assert_code 0 "$CODE" "les deux options se combinent et rendent 0"
assert_contient "$(cat "$BAC/appels")" "get events -n kube-system --sort-by=.lastTimestamp --field-selector type=Warning" "le filtre de type s'ajoute à la liste du namespace"
assert_contient "$sortie" "FailedScheduling" "le Warning du namespace est affiché"
assert_absent  "$sortie" "Successfully assigned" "l'événement Normal du même namespace est écarté"

titre "Namespace inconnu"
tracer
lancer --namespace inconnu
assert_code 1 "$CODE" "un namespace inexistant rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "Namespace inconnu : inconnu" "le message dit le nom et la cause"
assert_absent  "$sortie" "apiserver" "sans confondre avec un apiserver injoignable"
assert_contient "$(cat "$BAC/appels")" "get namespace inconnu" "le namespace a bien été vérifié"
assert_absent  "$(cat "$BAC/appels")" "get events" "aucune liste n'est demandée pour un namespace inconnu"

titre "Aucun événement"
: > "$BAC/events-vide"
printf '%s\n' "vide" > "$BAC/ns-vide"
tracer
lancer --namespace vide
assert_code 0 "$CODE" "un namespace sans événement rend 0"
assert_contient "$sortie" "[INFO]" "il est signalé en [INFO], pas en erreur"
assert_contient "$sortie" "Aucun événement" "et le message dit qu'il n'y en a aucun"
assert_absent  "$sortie" "[SUCCESS]" "rien n'est annoncé en [SUCCESS] : aucune ligne n'a été listée"
assert_contient "$(cat "$BAC/appels")" "get events -n vide --sort-by=.lastTimestamp" "la liste a bien été demandée"
# Liste vide de tout le cluster : même verdict. Les événements expirent — une
# heure par défaut côté apiserver —, un relevé vide n'est donc pas une panne.
: > "$BAC/events-A"
tracer
lancer
assert_code 0 "$CODE" "aucun événement dans le cluster rend 0 aussi"
assert_contient "$sortie" "[INFO]" "et il est signalé en [INFO]"
assert_absent  "$sortie" "[ERROR]" "sans être pris pour une panne"

titre "Apiserver injoignable"
export KUBECTL_INJOIGNABLE=1
tracer
lancer --warnings
assert_code 1 "$CODE" "un apiserver injoignable rend 1"
assert_contient "$sortie" "[ERROR]" "l'échec est signalé en [ERROR]"
assert_contient "$sortie" "apiserver" "et le message nomme l'apiserver"
assert_absent  "$sortie" "command not found" "aucun message brut du shell ne filtre"
assert_egal "1" "$(wc -l < "$BAC/appels")" "un seul appel kubectl a été tenté"
tracer
lancer --namespace kube-system
unset KUBECTL_INJOIGNABLE
assert_code 1 "$CODE" "l'apiserver muet rend 1 même avec --namespace"
assert_contient "$sortie" "apiserver" "et le message nomme l'apiserver"
assert_absent  "$sortie" "Namespace inconnu" "sans accuser le namespace, qui existe"

titre "Avertissement de kubectl sur stderr"
printf '%s\n' "default 5m Normal Pulled pod/web-1 Container image nginx already present" > "$BAC/events-A"
export KUBECTL_AVERTIT=1
tracer
lancer
unset KUBECTL_AVERTIT
assert_code 0 "$CODE" "un avertissement sur stderr ne change pas le code"
assert_contient "$sortie" "1 événement(s)" "il n'entre pas dans le compte : une ligne d'en-tête, un événement"
assert_absent  "$sortie" "Warning:" "et il n'est pas affiché quand kubectl réussit"

titre "kubectl seul, et appels bornés"
# Le journal cumulé, jamais vidé, couvre toute la suite : les contrôles portent
# sur l'ensemble des chemins éprouvés, vérifications de namespace comprises.
assert_contient "$(cat "$BAC/tous")" "get namespace " "le journal cumulé retient les vérifications de namespace"
assert_egal "0" "$(grep -vc -- '--request-timeout=5s' "$BAC/tous" || true)" "chaque appel kubectl de la suite porte --request-timeout"
listes="$(grep -c -- '^get events ' "$BAC/tous" || true)"
triees="$(grep -c -- '^get events .*--sort-by=\.lastTimestamp' "$BAC/tous" || true)"
assert_egal "$listes" "$triees" "toutes les listes d'événements demandent le tri croissant"
assert_egal "0" "$(grep -vcE '^get (events|namespace) ' "$BAC/tous" || true)" "aucun appel ne sort de « get events » et « get namespace »"
assert_egal "absente" "$(present "$BAC/k3s-appele")" "rien ne passe par k3s"
assert_egal "absente" "$(present "$BAC/systemctl-appele")" "ni par systemctl"

cas2="non"; case "$codes" in *" 2"*) cas2="oui" ;; esac
assert_egal "non" "$cas2" "aucun chemin éprouvé ne rend 2 : le 2 reste réservé à l'erreur d'usage"

bilan "TASK-057 / events.sh"
