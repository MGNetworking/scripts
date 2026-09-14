#!/usr/bin/env bash
# tests/integration/create-network.test.sh — Docker/Configuration/create-network.sh.
#
# TASK-032. AUCUN RÉSEAU RÉEL N'EST CRÉÉ : le conteneur de test n'a pas Docker,
# tous les chemins passent par un faux docker en tête de PATH, qui enregistre
# ses arguments et répond ce que chaque cas lui demande via variables d'env.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Docker/Configuration/create-network.sh"
BAC="$(mktemp -d)"
trap 'rm -rf "$BAC"' EXIT

DOCKER_LOG="$BAC/docker.log"
export DOCKER_LOG

cat >"$BAC/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "$DOCKER_LOG"
case "$1 $2" in
    "network inspect")
        if [ "${INSPECT_CODE:-0}" != 0 ]; then
            echo "${INSPECT_SORTIE:-Error: No such network: x}" >&2
            exit "${INSPECT_CODE}"
        fi
        echo "${INSPECT_SORTIE:-mgnet-test-reseau|bridge|}"
        exit 0
        ;;
    "network create")
        if [ "${CREATE_CODE:-0}" != 0 ]; then
            echo "${CREATE_SORTIE:-refuse}" >&2
            exit "${CREATE_CODE}"
        fi
        echo "idfactice"
        exit 0
        ;;
esac
exit 0
EOF
chmod +x "$BAC/docker"

titre "Codes d'usage"

sortie="$(bash "$CIBLE" --help 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
assert_contient "$sortie" "external"       "--help explique l'usage d'un réseau externe partagé"
assert_contient "$sortie" "SRV_DOCKER_NETWORK" "--help documente la variable de configuration"
assert_contient "$sortie" "proxy"          "--help donne un exemple de nom"
assert_contient "$sortie" "2  argument"    "--help documente les codes de retour"

sortie="$(bash "$CIBLE" mgnet-test-reseau --option-inexistante 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

sortie="$(SRV_DOCKER_NETWORK='' bash "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "ni argument ni SRV_DOCKER_NETWORK : rend 2"
assert_contient "$sortie" "SRV_DOCKER_NETWORK" "le refus nomme la variable de repli"

sortie="$(bash "$CIBLE" 'nom invalide' 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "un nom que Docker ne pourrait pas porter rend 2"

sortie="$(bash "$CIBLE" mgnet-test-reseau --driver overlay 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "--driver overlay est refusé en 2"
assert_contient "$sortie" "Swarm" "le refus d'overlay nomme Swarm"

sortie="$(bash "$CIBLE" mgnet-test-reseau --subnet 10.0.0.0/40 2>&1)" && code=0 || code=$?
assert_code 2 "$code" "un CIDR mal formé rend 2"

titre "docker network rm : absent du script, quelle que soit la branche"

assert_egal "0" "$(grep -c 'network rm' "$CIBLE" || true)" \
    "la chaîne docker network rm n'apparaît nulle part"

titre "--dry-run : affiche la commande, ne crée rien"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_CODE=1 INSPECT_SORTIE='Cannot connect to the Docker daemon' \
    bash "$CIBLE" mgnet-test-reseau --dry-run 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--dry-run rend 0 même sans démon joignable"
assert_contient "$sortie" "network create" "--dry-run affiche la commande qui aurait créé le réseau"
assert_absent   "$(cat "$DOCKER_LOG")" "network create" "aucun appel réel à network create"

titre "réseau absent — création"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_CODE=1 bash "$CIBLE" mgnet-test-reseau --subnet 172.20.0.0/24 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "réseau absent : rend 0"
assert_contient "$sortie" "créé" "le succès de la création est annoncé"
assert_contient "$(cat "$DOCKER_LOG")" "network create --driver bridge --subnet 172.20.0.0/24 mgnet-test-reseau" \
    "network create ne reçoit que les options demandées"

titre "réseau absent — refus de Docker à la création, relayé en 1"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_CODE=1 CREATE_CODE=1 CREATE_SORTIE='invalid pool request' \
    bash "$CIBLE" mgnet-test-reseau 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "refus de Docker à la création : rend 1"
assert_contient "$sortie" "invalid pool request" "le refus de Docker est relayé"

titre "réseau présent et conforme — rien n'est touché"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_SORTIE='mgnet-test-reseau|bridge|172.20.0.0/24' \
    bash "$CIBLE" mgnet-test-reseau --subnet 172.20.0.0/24 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "réseau conforme : rend 0"
assert_contient "$sortie" "conforme" "un [INFO] constate la conformité"
assert_absent   "$(cat "$DOCKER_LOG")" "network create" "aucune création sur un réseau déjà conforme"

titre "réseau présent mais divergent — refus, rien de supprimé"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_SORTIE='mgnet-test-reseau|macvlan|172.20.0.0/24' \
    bash "$CIBLE" mgnet-test-reseau --subnet 172.20.0.0/24 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "pilote divergent : rend 1"
assert_contient "$sortie" "macvlan"              "l'écart de pilote est affiché"
assert_contient "$sortie" "cleanup-networks.sh"  "le seul chemin de suppression est nommé"
assert_absent   "$(cat "$DOCKER_LOG")" "network create" "rien n'est créé sur un réseau divergent"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_SORTIE='mgnet-test-reseau|bridge|10.0.0.0/24' \
    bash "$CIBLE" mgnet-test-reseau --subnet 172.20.0.0/24 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sous-réseau divergent : rend 1"
assert_contient "$sortie" "10.0.0.0/24" "l'écart de sous-réseau est affiché"

titre "démon injoignable hors --dry-run"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_CODE=1 INSPECT_SORTIE='Cannot connect to the Docker daemon' \
    bash "$CIBLE" mgnet-test-reseau 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "démon injoignable : rend 1"
assert_contient "$sortie" "injoignable" "le refus dit que le démon est injoignable"

titre "idempotence — un second passage n'appelle pas network create"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_CODE=1 bash "$CIBLE" mgnet-test-reseau 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "premier passage : rend 0"
assert_contient "$(cat "$DOCKER_LOG")" "network create" "le premier passage a bien appelé network create"

: > "$DOCKER_LOG"
sortie="$(PATH="$BAC:$PATH" INSPECT_SORTIE='mgnet-test-reseau|bridge|' bash "$CIBLE" mgnet-test-reseau 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "second passage : rend 0"
assert_absent "$(cat "$DOCKER_LOG")" "network create" "le second passage n'appelle pas network create"

bilan "TASK-032 / create-network.sh"
