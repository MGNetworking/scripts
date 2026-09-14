#!/usr/bin/env bash
# tests/integration/configure-docker.test.sh — Docker/Configuration/configure-docker.sh.
#
# TASK-030. /etc/docker/daemon.json s'écrit RÉELLEMENT dans le conteneur — c'est
# le propre du niveau integration. Un trap le remet en état : tous les fichiers
# de cas du niveau partagent un seul conteneur. Les chemins modifiants éprouvent
# de faux docker, systemctl et jq en tête de PATH — aucun démon réel n'est touché.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

CIBLE="$SCRIPTS_ROOT/Docker/Configuration/configure-docker.sh"
FICHIER="/etc/docker/daemon.json"
BAC="$(mktemp -d)"
ORIG="$BAC/original.json"
avait_original="non"
if [ -f "$FICHIER" ]; then
    cp "$FICHIER" "$ORIG"
    avait_original="oui"
fi

nettoyer() {
    rm -f "$FICHIER" "$FICHIER".*.bak
    if [ "$avait_original" = "oui" ]; then cp "$ORIG" "$FICHIER"; fi
    rm -rf "$BAC"
}
trap nettoyer EXIT

JETABLE="non"
if [ -e /.dockerenv ]; then JETABLE="oui"; fi
if [ -r /proc/1/cgroup ] && grep -qE '(docker|lxc|containerd|kubepods)' /proc/1/cgroup; then
    JETABLE="oui"
fi
if [ "$JETABLE" != "oui" ] && [ "${MGNET_TEST_JETABLE:-}" != "1" ]; then
    saute_indisponible "écriture réelle dans /etc/docker" "l'hôte courant n'est pas un système jetable"
    bilan "TASK-030 / configure-docker.sh"
fi

faux() {
    cat > "$BAC/$1"
    chmod +x "$BAC/$1"
}
nettoyer_daemon() { rm -f "$FICHIER" "$FICHIER".*.bak; }

# Faux jq qui reflète le vrai contrat : « -e » approuve un fichier qui porte les
# trois clés gérées (peu importe l'ordre ou le formatage), « empty » suit
# JQ_EMPTY, la fusion renvoie le contenu de JQ_MERGE.
faux_jq() {
    cat > "$BAC/jq" <<'EOF'
#!/bin/sh
pour_e=0
dernier=""
for a in "$@"; do
    if [ "$a" = "-e" ]; then pour_e=1; fi
    dernier="$a"
done
if [ "$pour_e" = 1 ]; then
    grep -q '"log-driver"' "$dernier" \
        && grep -q '"max-size"' "$dernier" \
        && grep -q '"max-file"' "$dernier"
    exit $?
fi
if [ "$1" = "empty" ]; then exit "${JQ_EMPTY:-0}"; fi
cat "$JQ_MERGE"
EOF
    chmod +x "$BAC/jq"
}

export SYSTEMCTL_LOG="$BAC/systemctl.log"
faux systemctl <<'EOF'
#!/bin/sh
printf "%s\n" "$*" >> "$SYSTEMCTL_LOG"
exit "${SYSTEMCTL_RC:-0}"
EOF

faux docker <<'EOF'
#!/bin/sh
case "$1" in
    ps) echo "" ;;
    version) exit "${DOCKER_VERSION_RC:-0}" ;;
    *) exit 0 ;;
esac
EOF

faux_jq

titre "Codes d'usage"

bash "$CIBLE" --help >/dev/null 2>&1 && code=0 || code=$?
assert_code 0 "$code" "--help rend 0"
sortie="$(bash "$CIBLE" --help 2>&1)"
assert_contient "$sortie" "--log-driver"            "--help documente les options"
assert_contient "$sortie" "SRV_DOCKER_LOG_DRIVER"   "--help nomme les variables lues"
assert_contient "$sortie" "/etc/docker/daemon.json" "--help nomme le fichier écrit"
assert_contient "$sortie" "interrompt"              "--help dit l'effet du redémarrage"
assert_contient "$sortie" "2  option"               "--help documente les codes de retour"

bash "$CIBLE" --frobnicate >/dev/null 2>&1 && code=0 || code=$?
assert_code 2 "$code" "une option inconnue rend 2"

titre "Valeurs mal formées — refus avant toute écriture"

nettoyer_daemon
for mauvais in "--log-driver syslog" "--log-max-size 10x" "--log-max-file zero" "--log-max-file 0"; do
    # Découpage voulu : chaque valeur mal formée porte une option et son argument.
    # shellcheck disable=SC2086
    bash "$CIBLE" $mauvais >/dev/null 2>&1 && code=0 || code=$?
    assert_code 2 "$code" "« $mauvais » est refusé en 2"
done
if [ -e "$FICHIER" ]; then etat_f="présent"; else etat_f="absent"; fi
assert_egal "absent" "$etat_f" "aucune écriture après un refus de valeur"

titre "Variables SRV_DOCKER_* et priorité de la ligne de commande"

nettoyer_daemon
sortie="$(SRV_DOCKER_LOG_DRIVER=local SRV_DOCKER_LOG_MAX_SIZE=1g SRV_DOCKER_LOG_MAX_FILE=5 \
    bash "$CIBLE" --dry-run 2>&1)"
assert_contient "$sortie" '"log-driver": "local"' "SRV_DOCKER_LOG_DRIVER est lu"
assert_contient "$sortie" '"max-size": "1g"'     "SRV_DOCKER_LOG_MAX_SIZE est lu"
assert_contient "$sortie" '"max-file": "5"'      "SRV_DOCKER_LOG_MAX_FILE est lu"
sortie="$(SRV_DOCKER_LOG_DRIVER=local bash "$CIBLE" --dry-run --log-driver json-file 2>&1)"
assert_contient "$sortie" '"log-driver": "json-file"' "la ligne de commande prime sur la variable"

titre "--dry-run — le contenu visé, sans rien écrire, et selon l'état du fichier"

nettoyer_daemon
sortie="$(bash "$CIBLE" --dry-run 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "--dry-run rend 0 sans docker ni root"
if [ -e "$FICHIER" ]; then etat_f="présent"; else etat_f="absent"; fi
assert_egal "absent" "$etat_f" "--dry-run n'a rien écrit"
assert_contient "$sortie" '"log-driver": "json-file"' "--dry-run montre le contenu visé"
assert_contient "$sortie" "sera créé"                 "--dry-run annonce l'état absent"

mkdir -p "$(dirname "$FICHIER")"
printf '{\n  "log-driver": "json-file",\n  "log-opts": {\n    "max-size": "10m",\n    "max-file": "3"\n  }\n}\n' > "$FICHIER"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" --dry-run 2>&1)"
assert_contient "$sortie" "déjà conforme" "--dry-run sur un fichier conforme le constate"

printf '{"log-driver":"local","data-root":"/srv/docker"}\n' > "$FICHIER"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" --dry-run 2>&1)"
assert_contient "$sortie" "Contenu actuel" "--dry-run divergent montre l'existant"
assert_contient "$sortie" "sera remplacé"  "--dry-run divergent annonce le remplacement"

titre "Fichier absent — création (garde P0 != A)"

nettoyer_daemon
p0="$(cat "$FICHIER" 2>/dev/null || echo ABSENT)"
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
a="$(cat "$FICHIER" 2>/dev/null || echo ABSENT)"

assert_code 0 "$code" "fichier absent : créé, rend 0"
assert_contient "$a" '"log-driver": "json-file"' "le pilote par défaut est écrit"
assert_contient "$a" '"max-size": "10m"'         "la taille par défaut est écrite"
assert_contient "$a" '"max-file": "3"'           "le nombre par défaut est écrit"
assert_contient "$(cat "$SYSTEMCTL_LOG")" "restart docker" "le démon a été redémarré"
if [ "$p0" != "$a" ]; then
    ok "garde P0 != A — la première exécution a modifié le fichier"
else
    ko "garde P0 != A" "P0 et A identiques : rien n'a été prouvé"
fi

titre "Fichier conforme — rien, et surtout pas un redémarrage"

inode_avant="$(stat -c %i "$FICHIER")"
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "fichier conforme (texte identique) : rend 0"
assert_egal "$inode_avant" "$(stat -c %i "$FICHIER")" "ni écriture ni remplacement (même inode)"
assert_contient "$sortie" "déjà conforme" "l'idempotence est annoncée"
assert_egal "" "$(cat "$SYSTEMCTL_LOG")" "le démon n'est pas redémarré"

printf '{"log-opts":{"max-file":"3","max-size":"10m"},"log-driver":"json-file"}\n' > "$FICHIER"
inode_avant="$(stat -c %i "$FICHIER")"
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "compact réordonné mais sémantiquement conforme : rend 0"
assert_egal "$inode_avant" "$(stat -c %i "$FICHIER")" "aucune écriture"
assert_contient "$sortie" "déjà conforme" "l'idempotence est annoncée"
assert_egal "" "$(cat "$SYSTEMCTL_LOG")" "aucun redémarrage"

titre "Fichier divergent — fusion avec jq, clés non gérées préservées"

nettoyer_daemon
printf '{"log-driver":"local","data-root":"/srv/docker"}\n' > "$FICHIER"
cp "$FICHIER" "$BAC/original-divergent.json"
printf '{"log-driver":"local","log-opts":{"max-size":"10m","max-file":"3"},"data-root":"/srv/docker"}\n' > "$BAC/fusion.json"
export JQ_MERGE="$BAC/fusion.json"
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "fichier divergent : fusion, rend 0"
assert_egal "$(cat "$BAC/fusion.json")" "$(cat "$FICHIER")" "le fichier reçoit la sortie de jq"
assert_contient "$(cat "$FICHIER")" "data-root" "les clés non gérées sont conservées"
sauvegarde="$(find /etc/docker -maxdepth 1 -name 'daemon.json.*.bak' | head -n1)"
assert_non_vide "$sauvegarde" "l'original est sauvegardé horodaté à côté"
assert_egal "$(cat "$BAC/original-divergent.json")" "$(cat "$sauvegarde" 2>/dev/null)" "la sauvegarde contient l'original"
assert_contient "$(cat "$SYSTEMCTL_LOG")" "restart docker" "le démon est redémarré"

rm -f "$BAC/jq"

titre "Fichier divergent sans jq — refus, rien n'est écrit"

nettoyer_daemon
printf '{"log-driver":"local","data-root":"/srv/docker"}\n' > "$FICHIER"
cp "$FICHIER" "$BAC/sans-jq.json"
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "fichier divergent sans jq : rend 1"
assert_contient "$sortie" "jq"         "le refus nomme la dépendance manquante"
assert_contient "$sortie" "log-driver" "le contenu visé est affiché"
assert_egal "$(cat "$BAC/sans-jq.json")" "$(cat "$FICHIER")" "rien n'a été écrit"
assert_egal "" "$(cat "$SYSTEMCTL_LOG")" "le démon n'est pas redémarré"

faux_jq

titre "Docker absent — refus nommant la dépendance"

nettoyer_daemon
BD="$BAC/sans-docker"
mkdir -p "$BD"
sortie="$(PATH="$BD:/usr/bin:/bin" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "docker absent : rend 1"
assert_contient "$sortie" "docker" "le refus nomme la dépendance manquante"

titre "Hors terminal et sans --yes — refus avant écriture"

nettoyer_daemon
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" </dev/null 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "sans terminal et sans --yes : rend 1"
assert_contient "$sortie" "--yes" "le message nomme l'option qui débloque"
assert_absent "$sortie" "Échec (code" "aucune ligne du trap ERR : refus délibéré"
if [ -e "$FICHIER" ]; then etat_f="présent"; else etat_f="absent"; fi
assert_egal "absent" "$etat_f" "rien n'a été écrit avant la confirmation"

titre "Échec de systemctl restart — l'original est restauré, le démon relancé"

nettoyer_daemon
printf '{"log-driver":"local","data-root":"/srv/docker"}\n' > "$FICHIER"
cp "$FICHIER" "$BAC/precedent.json"
export JQ_MERGE="$BAC/fusion.json"
export SYSTEMCTL_RC=1
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "échec du redémarrage : rend 1"
assert_contient "$sortie" "restaurée" "la restauration est annoncée"
assert_egal "$(cat "$BAC/precedent.json")" "$(cat "$FICHIER")" "l'original est remis en place"
assert_egal 2 "$(grep -c 'restart docker' "$SYSTEMCTL_LOG" || true)" "le démon est relancé après la restauration"
unset SYSTEMCTL_RC

titre "Le démon ne revient pas — l'original est restauré"

nettoyer_daemon
printf '{"log-driver":"local","data-root":"/srv/docker"}\n' > "$FICHIER"
cp "$FICHIER" "$BAC/precedent2.json"
export DOCKER_VERSION_RC=1
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "démon non revenu : rend 1"
assert_contient "$sortie" "restaurée" "la restauration est annoncée"
assert_egal "$(cat "$BAC/precedent2.json")" "$(cat "$FICHIER")" "l'original est remis en place"
unset DOCKER_VERSION_RC

titre "Sans root — refus avant toute action"

if command -v setpriv >/dev/null 2>&1; then
    nettoyer_daemon
    sortie="$(setpriv --reuid=65534 --regid=65534 --clear-groups -- bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
    assert_code 1 "$code" "sans privilège root : rend 1"
    assert_contient "$sortie" "root" "le refus nomme le privilège manquant"
    if [ -e "$FICHIER" ]; then etat_f="présent"; else etat_f="absent"; fi
    assert_egal "absent" "$etat_f" "aucune écriture tentée sans root"
else
    saute_par_nature "refus sans root" "setpriv est absent de l'image"
fi

titre "JSON produit invalide — jamais mis en place"

nettoyer_daemon
printf '{"log-driver":"local","data-root":"/srv/docker"}\n' > "$FICHIER"
cp "$FICHIER" "$BAC/avant-invalide.json"
export JQ_MERGE="$BAC/invalide.json"
printf '{"invalide\n' > "$JQ_MERGE"
export JQ_EMPTY=1
: > "$SYSTEMCTL_LOG"
sortie="$(PATH="$BAC:$PATH" bash "$CIBLE" -y 2>&1)" && code=0 || code=$?
assert_code 1 "$code" "JSON invalide produit : rend 1"
assert_contient "$sortie" "invalide" "le refus est explicite"
assert_egal "$(cat "$BAC/avant-invalide.json")" "$(cat "$FICHIER")" "le fichier existant est intact"
assert_egal "" "$(cat "$SYSTEMCTL_LOG")" "aucun redémarrage tenté"
unset JQ_EMPTY JQ_MERGE

bilan "TASK-030 / configure-docker.sh"
