#!/usr/bin/env bash
# tests/integration/update-docker.test.sh — Docker/Maintenance/update-docker.sh, TASK-036.
# Pas de démon Docker dans le conteneur : faux docker, dpkg-query, apt-get et
# systemctl en tête de PATH, qui répondent à sa place et tracent leurs appels.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
BASH_BIN="$(command -v bash)"; CIBLE="$SCRIPTS_ROOT/Docker/Maintenance/update-docker.sh"
BAC="$(mktemp -d)"; T_APT="$BAC/apt"; T_DOCKER="$BAC/docker.trace"
APRES="$BAC/apres"; LOGS="$BAC/journal"
trap 'rm -rf "$BAC"' EXIT
# shellcheck disable=SC2016
# Les corps des faux binaires sont entre apostrophes : leurs $ appartiennent au
# faux programme, exécuté plus tard, et non à ce fichier.
faux() { printf '#!/bin/sh\n%s\n' "$2" > "$BAC/$1"; chmod +x "$BAC/$1"; }

faux dpkg-query 'last=""; for a in "$@"; do last="$a"; done
t="$TABLE_AVANT"; [ -e "$APRES" ] && t="$TABLE_APRES"
for l in $t; do case "$l" in "$last="*) printf "install ok installed %s" "${l#*=}"; exit 0 ;; esac; done
exit 1'
faux apt-get 'printf "%s\n" "$*" >> "$T_APT"
[ "$1" = install ] && : > "$APRES"
exit 0'
faux docker 'printf "%s\n" "$*" >> "$T_DOCKER"
case "$*" in
  "ps -q") [ -z "$P_MUET" ] || exit 1; [ -z "$P_CONTENEURS" ] || printf "%s\n" $P_CONTENEURS ;;
  "info --format "*) [ -z "$P_MUET" ] || exit 1; printf "%s\n" "$P_LIVE" ;;
  *) exit 1 ;;
esac'
faux systemctl 'case "$*" in "is-active docker") echo "$P_SERVICE"; [ "$P_SERVICE" = active ] ;; *) exit 1 ;; esac'

# PATH restreint : les outils du script, moins ceux que l'appelant nomme.
outils() {
    local d="$BAC/$1"; shift; mkdir -p "$d"; local b c PATH="$BAC:$PATH"
    for b in dirname basename mkdir id date awk sed grep cat tr wc tee apt-get dpkg-query docker systemctl; do
        case " $* " in *" $b "*) continue ;; esac
        c="$(command -v "$b" 2>/dev/null || true)"; [ -n "$c" ] || continue
        ln -sf "$c" "$d/$b"
    done
}

TOUS="docker-ce=28.5.2 docker-ce-cli=28.5.2 containerd.io=1.7.24 docker-buildx-plugin=0.17.1 docker-compose-plugin=2.39.1"
APRES_TOUS="docker-ce=29.0.0 docker-ce-cli=29.0.0 containerd.io=1.7.24 docker-buildx-plugin=0.17.1 docker-compose-plugin=2.39.1"
TABLE_AVANT="$TOUS"; TABLE_APRES="$APRES_TOUS"
P_CONTENEURS="c1c1c1 c2c2c2"; P_LIVE="false"; P_MUET=""; P_SERVICE="active"
export T_APT T_DOCKER APRES LOG_DIR="$LOGS" TABLE_AVANT TABLE_APRES P_CONTENEURS P_LIVE P_MUET P_SERVICE
CHEMIN="$BAC:$PATH"; REPOND=""; SORTIE=""; CODE=0
lancer() { SORTIE="$(printf '%s\n' "$REPOND" | PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?; }
reinit() { : > "$T_APT"; : > "$T_DOCKER"; rm -f "$APRES"; }
appels() { awk -v m="$*" 'index($0, m) { n++ } END { printf "%d", n + 0 }' "$T_APT"; }
d_appels() { awk -v m="$*" 'index($0, m) { n++ } END { printf "%d", n + 0 }' "$T_DOCKER"; }
# Liste blanche : tout apt-get hors de ces deux formes — « upgrade »,
# « dist-upgrade » — tombe ici.
fautives() { grep -vE '^(update|install --only-upgrade -y (docker-ce|docker-ce-cli|containerd\.io|docker-buildx-plugin|docker-compose-plugin))$' "$T_APT"; }
outils sans-apt apt-get; outils sans-systemctl systemctl

titre "L'aide, puis les refus d'usage"
reinit; lancer --help
assert_code 0 "$CODE" "--help rend 0"
assert_contient "$SORTIE" "docker-ce, docker-ce-cli," "l'aide nomme les composants pris en charge"
assert_contient "$SORTIE" "conteneurs en cours" "elle annonce l'interruption des conteneurs"
assert_contient "$SORTIE" "tâche planifiée" "elle dit que --yes est le seul mode d'une tâche planifiée"
assert_contient "$SORTIE" "Codes :" "elle documente les codes de retour"
assert_egal "" "$(cat "$T_APT" "$T_DOCKER")" "--help sort avant tout préflight : aucune sonde n'est lancée"
lancer --inconnue
assert_code 2 "$CODE" "une option inconnue rend 2"
assert_contient "$SORTIE" "[ERROR] Option inconnue" "le message porte [ERROR] et nomme l'option"
assert_absent "$SORTIE" "Usage" "l'aide n'est pas déversée"
assert_egal "1" "$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')" "le refus tient sur une seule ligne"

titre "Refus avant toute action — système hors cibles, apt-get absent"
reinit
SORTIE="$(OS_ID=fedora OS_VERSION=41 PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" --dry-run 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "une distribution hors cibles est refusée en 1"
assert_contient "$SORTIE" "fedora" "le refus nomme ce qui a été détecté"
CHEMIN="$BAC/sans-apt"; reinit; lancer --dry-run
assert_code 1 "$CODE" "sans apt-get, le script rend 1 avant toute action"
assert_contient "$SORTIE" "apt-get" "le message nomme la commande requise"
assert_egal "" "$(cat "$T_APT")" "et rien n'a été tenté"
CHEMIN="$BAC:$PATH"

titre "Aucun composant installé — aucun index rafraîchi"
TABLE_AVANT=""; TABLE_APRES=""; reinit; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 quand rien n'est installé"
assert_contient "$SORTIE" "Composants Docker — état relevé" "le relevé est affiché"
assert_contient "$SORTIE" "absent — non installé" "chaque composant est dit absent"
assert_contient "$SORTIE" "aucun composant Docker n'est installé" "le script le dit"
assert_contient "$SORTIE" "install-docker.sh" "et nomme le script qui installe"
assert_egal "" "$(cat "$T_APT")" "aucun index de paquets n'est rafraîchi"
reinit; lancer
assert_code 1 "$CODE" "hors --dry-run, il n'y a rien à mettre à jour : 1"
assert_egal "" "$(cat "$T_APT")" "et l'index n'est pas rafraîchi davantage"
assert_absent "$SORTIE" "[o/N]" "aucune question n'est posée"

titre "--dry-run — le relevé, la coupure annoncée, les commandes prévues"
TABLE_AVANT="$TOUS"; TABLE_APRES="$APRES_TOUS"; reinit; REPOND=""; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "28.5.2" "le relevé affiche la version installée"
assert_contient "$SORTIE" "containerd.io" "chaque composant est relevé, installé ou non"
assert_contient "$SORTIE" "service docker" "et l'état du service avec eux"
assert_contient "$SORTIE" "2 conteneur(s) en cours d'exécution seront INTERROMPUS" "il compte les conteneurs et annonce la coupure"
assert_contient "$SORTIE" "live-restore n'est pas actif" "il dit ce qu'implique live-restore"
assert_contient "$SORTIE" "apt-get install --only-upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "la commande prévue est bornée aux composants relevés"
assert_egal "" "$(cat "$T_APT")" "aucune commande apt-get n'est exécutée"
assert_egal "1" "$(d_appels 'ps -q')" "le décompte des conteneurs a bien été lu"

titre "live-restore actif — la coupure change de forme, daemon.json n'est pas touché"
P_LIVE="true"; reinit; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "live-restore est actif" "il dit que les conteneurs survivent au redémarrage du démon"
assert_contient "$SORTIE" "containerd n'y est pas sensible" "et réserve le cas de containerd"
assert_absent "$SORTIE" "emportera les conteneurs" "sans reprendre le message de l'autre cas"
assert_egal "" "$(grep -nE '(>|>>|tee |sed -i|install ).*daemon\.json' "$CIBLE" || true)" "le script n'écrit jamais dans /etc/docker/daemon.json"
P_LIVE="false"

titre "Confirmation — refusée puis acceptée, la commande reste bornée"
reinit; REPOND="n"; lancer
assert_code 0 "$CODE" "un refus rend 0"
assert_contient "$SORTIE" "[o/N]" "la confirmation est posée"
assert_contient "$SORTIE" "Les conteneurs en cours seront interrompus" "la question rappelle la coupure"
assert_contient "$SORTIE" "annulée" "le refus est dit"
assert_egal "" "$(cat "$T_APT")" "et rien n'est installé : pas même l'index rafraîchi"
reinit; REPOND="o"; lancer
assert_code 0 "$CODE" "acceptée, la mise à jour rend 0"
assert_contient "$(cat "$T_APT")" "install --only-upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "la commande est bornée à la liste relevée"
assert_egal "" "$(fautives)" "aucun apt-get hors de ces deux formes : ni upgrade, ni dist-upgrade"
assert_contient "$SORTIE" "28.5.2 → 29.0.0" "l'avant / après montre la version mise à jour"
assert_contient "$SORTIE" "inchangé" "et dit inchangé ce qui n'a pas bougé"
assert_contient "$(cat "$LOGS/update-docker.log")" "apt-get install --only-upgrade" "la commande part au journal"

titre "Après coup — --yes, service inactif, puis systemctl absent"
reinit; REPOND=""; lancer --yes
assert_code 0 "$CODE" "--yes mène la mise à jour à son terme"
assert_absent "$SORTIE" "[o/N]" "aucune question n'est posée"
assert_contient "$SORTIE" "Le service docker est actif" "le service relevé après coup est actif"
P_SERVICE="inactive"; reinit; lancer --yes
assert_code 1 "$CODE" "un service docker inactif après la mise à jour rend 1"
assert_contient "$SORTIE" "inactive" "le message dit l'état constaté"
assert_contient "$SORTIE" "journalctl -u docker" "et nomme la commande de diagnostic"
P_SERVICE="active"; CHEMIN="$BAC/sans-systemctl"; reinit; lancer --yes
assert_code 0 "$CODE" "sans systemctl, le script ne conclut pas à l'échec"
assert_contient "$SORTIE" "invérifiable" "il dit que l'état n'a pas pu être relevé"
assert_absent "$SORTIE" "Échec (code" "et le trap ERR se tait : ces échecs de lecture sont nominaux"
CHEMIN="$BAC:$PATH"

titre "Ce que le script ne fait jamais"
assert_egal "" "$(grep -vE '^(ps -q|info --format )' "$T_DOCKER" || true)" "aucune commande docker hors de la lecture — ni pull, ni restart"
assert_egal "0" "$(grep -cE 'docker (pull|restart|stop|rm)' "$CIBLE" || true)" "le source ne porte ni pull, ni restart : les images applicatives sont hors de portée"
bilan "TASK-036 / update-docker.sh"
