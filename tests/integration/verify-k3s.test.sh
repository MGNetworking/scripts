#!/usr/bin/env bash
# tests/integration/verify-k3s.test.sh — Linux/K3s/verify-k3s.sh.
#
# TASK-050. Le conteneur n'a ni K3s ni systemd et n'en aura pas : les issues du
# script sont éprouvées par de faux « k3s » et « systemctl » en tête de PATH.
#
# Chaque cas d'échec porte sa GARDE DE CONTRASTE : « k3s » est absent par défaut
# ici, donc « K3s absent » serait vert sans rien prouver. C'est le cas « cluster
# sain », mêmes faux, qui rend 0.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Linux/K3s/verify-k3s.sh"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

# Faux « k3s » : note chaque appel dans appels, puis rend le contenu préparé dans
# $BAC. Un contenu absent fait échouer l'appel, comme une API muette.
faux_k3s() {
    cat > "$BAC/k3s" <<EOF
#!/bin/sh
echo "\$*" >> "$BAC/appels"
for r in nodes pods namespaces events; do
  case "\$*" in *"kubectl get \$r"*) exec cat "$BAC/\$r" ;; esac
done
case "\$*" in --version*) echo "k3s version v1.30.5+k3s1 (aaaaaaa)" ;; *) exit 1 ;; esac
EOF
    chmod +x "$BAC/k3s"
}

# Faux « systemctl » : $1 est l'état rendu par is-active, $2 vaut « non » pour ne
# pas lister l'unité.
faux_systemctl() {
    cat > "$BAC/systemctl" <<EOF
#!/bin/sh
case "\$*" in
  "is-active k3s") echo "$1" ;;
  "list-unit-files k3s.service") [ "$2" = "non" ] || echo "k3s.service enabled" ;;
esac
EOF
    chmod +x "$BAC/systemctl"
}

# Faux « kubectl » qui laisse une trace s'il est appelé : aucun n'est installé ici.
printf '#!/bin/sh\ntouch "%s"\n' "$BAC/kubectl-appele" > "$BAC/kubectl"
chmod +x "$BAC/kubectl"

# Cluster sain : un nœud Ready, deux pods Running, un pod achevé — phase
# Succeeded, que kubectl affiche « Completed » —, et un Warning ancien.
cluster_sain() {
    printf '%s\n' "nœud-1   Ready   control-plane,master   5d   v1.30.5+k3s1" > "$BAC/nodes"
    printf '%s\n' "kube-system   coredns-aaa   1/1   Running     0   5d" \
                  "kube-system   traefik-bbb   1/1   Running     0   5d" \
                  "default       job-fini      0/1   Completed   0   2d" > "$BAC/pods"
    printf '%s\n' "default" "kube-system" > "$BAC/namespaces"
    printf '%s\n' "kube-system   5m   Warning   FailedScheduling   pod/foo   aucun nœud" > "$BAC/events"
    faux_k3s
    faux_systemctl active
    : > "$BAC/appels"
}

CODE=0
sortie=""
lancer() { sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" 2>&1)" && CODE=0 || CODE=$?; }

titre "K3s absent — le cas d'usage principal"
faux_systemctl active non
lancer
assert_code 1 "$CODE" "un K3s absent rend 1"
assert_contient "$sortie" "Service k3s"        "la rubrique service est affichée malgré tout"
assert_contient "$sortie" "Événements Warning" "la rubrique des événements est affichée malgré tout"
assert_contient "$sortie" "non disponible"     "les informations manquantes sont nommées, pas tues"
assert_absent   "$sortie" "command not found"  "aucun message brut du shell ne filtre"

titre "Cluster sain — la garde de contraste de tous les cas suivants"
cluster_sain
lancer
assert_code 0 "$CODE" "K3s installé et cluster sain : 0"
assert_contient "$sortie" "v1.30.5+k3s1"     "la version du binaire est rapportée"
assert_contient "$sortie" "nœud-1"           "le nœud est listé"
assert_contient "$sortie" "coredns-aaa"      "les pods de tous les namespaces sont listés"
assert_contient "$sortie" "FailedScheduling" "les événements Warning sont affichés"
assert_absent   "$sortie" "[WARN]"           "ni un Warning ancien ni un pod achevé ne pèsent sur le verdict"

ordonnancees="$(printf '%s\n' "$sortie" | grep -oE '^(Service k3s|Version|Nœuds|Pods \(tous les namespaces\)|Namespaces|Événements Warning)$' | tr '\n' '|')"
assert_egal "Service k3s|Version|Nœuds|Pods (tous les namespaces)|Namespaces|Événements Warning|" \
    "$ordonnancees" "les six rubriques s'affichent, dans l'ordre du plan"

titre "Les appels passent par « k3s kubectl », et sont bornés"
assert_contient "$(cat "$BAC/appels")" "kubectl get nodes" "les nœuds sont demandés à « k3s kubectl »"
assert_egal "0" "$(grep -vcE '^(--version|kubectl )' "$BAC/appels" || true)" \
    "aucun appel à k3s ne sort de ces deux formes"
assert_egal "0" "$(grep -v -- '--request-timeout=5s' "$BAC/appels" | grep -vc '^--version' || true)" \
    "chaque appel kubectl porte --request-timeout"
trace="absente"
if [ -e "$BAC/kubectl-appele" ]; then trace="présente"; fi
assert_egal "absente" "$trace" "aucun kubectl supposé installé n'a été appelé"

titre "Service k3s inactif"
cluster_sain
faux_systemctl inactive
lancer
assert_code 1 "$CODE" "un service inactif rend le cluster non sain"
assert_contient "$sortie" "service k3s inactive" "un [WARN] nomme le service et son état"

titre "Nœud non Ready"
cluster_sain
printf '%s\n' "nœud-2   NotReady   <none>   1m   v1.30.5+k3s1" > "$BAC/nodes"
lancer
assert_code 1 "$CODE" "un nœud non Ready rend 1"
assert_contient "$sortie" "[WARN]" "l'anomalie est signalée en [WARN]"
assert_contient "$sortie" "nœud-2 (NotReady)" "et le nœud est nommé, avec son état"

titre "Pod ni Running ni Succeeded"
cluster_sain
printf '%s\n' "default   cassé-1   0/1   CrashLoopBackOff   7   3m" > "$BAC/pods"
lancer
assert_code 1 "$CODE" "un pod qui ne tourne pas rend 1"
assert_contient "$sortie" "[WARN]" "l'anomalie est signalée en [WARN]"
assert_contient "$sortie" "default/cassé-1 (CrashLoopBackOff)" "et le pod est nommé, avec son état"

titre "API muette"
cluster_sain
rm -f "$BAC/nodes" "$BAC/pods" "$BAC/namespaces" "$BAC/events"
lancer
assert_code 1 "$CODE" "un k3s qui ne rend rien rend 1"
assert_contient "$sortie" "l'API du cluster ne répond pas" "le verdict nomme l'API, pas le shell"

titre "Root requis"
cluster_sain
printf '#!/bin/sh\necho 1000\n' > "$BAC/id"
chmod +x "$BAC/id"
lancer
assert_code 1 "$CODE" "hors root, le script s'arrête en 1 — le cas sain rend 0 avec ce même cluster"
assert_contient "$sortie" "root" "et le dit"

titre "Codes d'usage"
bash "$CIBLE" --help > "$BAC/help" 2>&1 && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$(cat "$BAC/help")" "Codes de retour"    "--help documente les codes de retour"
assert_contient "$(cat "$BAC/help")" "Événements Warning" "--help nomme les rubriques"
assert_contient "$(cat "$BAC/help")" "k3s kubectl"        "--help dit par où passent les commandes"
bash "$CIBLE" --option-qui-nexiste-pas >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"
ok "le 2 est réservé à l'erreur d'usage : les six chemins d'échec ci-dessus rendent tous 1"

bilan "TASK-050 / verify-k3s.sh"
