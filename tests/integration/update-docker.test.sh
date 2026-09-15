#!/usr/bin/env bash
# tests/integration/update-docker.test.sh — Docker/Maintenance/update-docker.sh, TASK-036.
# Faux docker, dpkg-query, apt-get et systemctl en tête de PATH : ils répondent à sa place et tracent leurs appels. Les corps de
# ces faux sont entre apostrophes, donc leurs $ sont les leurs. La confirmation exige un terminal : « script » en ouvre un.
# shellcheck disable=SC2016
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"
BASH_BIN="$(command -v bash)"; CIBLE="$SCRIPTS_ROOT/Docker/Maintenance/update-docker.sh"
BAC="$(mktemp -d)"; T_APT="$BAC/apt"; T_DOCKER="$BAC/docker.trace"; APRES="$BAC/apres"; LOGS="$BAC/journal"
trap 'rm -rf "$BAC"' EXIT
faux() { printf '#!/bin/sh\n%s\n' "$2" > "$BAC/$1"; chmod +x "$BAC/$1"; }
faux dpkg-query 'last=""; for a in "$@"; do last="$a"; done
t="$TABLE_AVANT"; [ -e "$APRES" ] && t="$TABLE_APRES"
for l in $t; do case "$l" in "$last="*) printf "install ok installed %s" "${l#*=}"; exit 0 ;; esac; done
exit 1'
# Le faux apt-get imite « -s » en rendant les lignes « Inst p [ancienne] (nouvelle) » d'un vrai
# apt-get : NOUVEAUX liste ceux qui ont une version plus récente.
faux apt-get 'printf "%s\n" "$*" >> "$T_APT"
[ "$1" = install ] && { : > "$APRES"; exit 0; }
[ "$1" = -s ] || exit 0
for a in $NOUVEAUX; do for l in $TABLE_AVANT; do case "$l" in "$a="*) printf "Inst %s [%s] (9.9.9 test)\n" "$a" "${l#*=}" ;; esac; done; done'
faux docker 'printf "%s\n" "$*" >> "$T_DOCKER"
case "$*" in
  "ps -q") [ -z "$P_MUET" ] || exit 1; [ -z "$P_CONTENEURS" ] || printf "%s\n" $P_CONTENEURS ;;
  "info --format "*) [ -z "$P_MUET" ] || exit 1; printf "%s\n" "$P_LIVE" ;;
  *) exit 1 ;;
esac'
faux systemctl 'case "$*" in "is-active docker") echo "$P_SERVICE"; [ "$P_SERVICE" = active ] ;; *) exit 1 ;; esac'
# PATH restreint : les outils du script, moins ceux que l'appelant nomme.
outils() { local d="$BAC/$1" b c; shift; mkdir -p "$d"; local PATH="$BAC:$PATH"
    for b in dirname basename mkdir id date uname awk sed grep cat tr wc tee apt-get dpkg-query docker systemctl; do case " $* " in *" $b "*) continue ;; esac; c="$(command -v "$b" 2>/dev/null || true)"; [ -n "$c" ] && ln -sf "$c" "$d/$b"; done; }
TOUS="docker-ce=28.5.2 docker-ce-cli=28.5.2 containerd.io=1.7.24 docker-buildx-plugin=0.17.1 docker-compose-plugin=2.39.1"
APRES_TOUS="docker-ce=29.0.0 docker-ce-cli=29.0.0 containerd.io=1.7.24 docker-buildx-plugin=0.17.1 docker-compose-plugin=2.39.1"
TABLE_AVANT="$TOUS"; TABLE_APRES="$APRES_TOUS"; NOUVEAUX="docker-ce docker-ce-cli"
P_CONTENEURS="c1c1c1 c2c2c2"; P_LIVE="false"; P_MUET=""; P_SERVICE="active"; export T_APT T_DOCKER APRES LOG_DIR="$LOGS" TABLE_AVANT TABLE_APRES NOUVEAUX P_CONTENEURS P_LIVE P_MUET P_SERVICE
CHEMIN="$BAC:$PATH"; SORTIE=""; CODE=0; : > "$T_DOCKER"
lancer() { SORTIE="$(PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" "$@" </dev/null 2>&1)" && CODE=0 || CODE=$?; }
lancer_pty() { SORTIE="$(printf '%s\n' "$1" | PATH="$CHEMIN" script -qec "$BASH_BIN $CIBLE" /dev/null 2>&1)" && CODE=0 || CODE=$?; }
# La trace de docker n'est jamais tronquée : la dernière section juge tout le fichier.
reinit() { : > "$T_APT"; rm -f "$APRES"; }
# Liste blanche : tout apt-get hors de ces deux formes — « upgrade », « dist-upgrade » — tombe ici.
fautives() { grep -vE '^(update|install --only-upgrade -y( (docker-ce|docker-ce-cli|containerd\.io|docker-buildx-plugin|docker-compose-plugin))+)$' "$T_APT"; }
outils sans-apt apt-get; outils sans-systemctl systemctl
titre "L'aide, puis les refus d'usage"; reinit; lancer --help
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

titre "Refus avant toute action — système hors cibles, apt-get absent"; reinit
SORTIE="$(OS_ID=fedora OS_VERSION=41 PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" --dry-run </dev/null 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "une distribution hors cibles est refusée en 1"
assert_contient "$SORTIE" "fedora" "le refus nomme ce qui a été détecté"
SORTIE="$(OS_ID=debian OS_VERSION=11 PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" --dry-run </dev/null 2>&1)" && CODE=0 || CODE=$?
assert_code 1 "$CODE" "une version hors cibles est refusée en 1 : Debian 11"
assert_contient "$SORTIE" "debian 11" "le refus nomme la version détectée"
CHEMIN="$BAC/sans-apt"; reinit; lancer --dry-run
assert_code 1 "$CODE" "sans apt-get, le script rend 1 avant toute action"
assert_contient "$SORTIE" "apt-get" "le message nomme la commande requise"
assert_egal "" "$(cat "$T_APT")" "et rien n'a été tenté"
titre "Aucun composant installé — aucun index rafraîchi"; CHEMIN="$BAC:$PATH"; TABLE_AVANT=""; TABLE_APRES=""; reinit; lancer --dry-run
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

titre "--dry-run — le relevé, la coupure, l'index rafraîchi, les commandes prévues"; TABLE_AVANT="$TOUS"; TABLE_APRES="$APRES_TOUS"; reinit; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "28.5.2" "le relevé affiche la version installée"
assert_contient "$SORTIE" "$(printf '%-24s %s' containerd.io 1.7.24)" "containerd.io est relevé avec sa version, pas seulement cité dans une commande"
assert_contient "$SORTIE" "service docker" "et l'état du service avec eux"
assert_contient "$SORTIE" "2 conteneur(s) en cours d'exécution seront INTERROMPUS" "il compte les conteneurs et annonce la coupure"
assert_contient "$SORTIE" "live-restore n'est pas actif" "il dit ce qu'implique live-restore"
assert_contient "$SORTIE" "apt-get install --only-upgrade -y docker-ce docker-ce-cli" "seuls les composants ayant une version plus récente sont annoncés"
assert_absent "$SORTIE" "install --only-upgrade -y docker-ce docker-ce-cli containerd.io" "un composant à jour n'entre pas dans la commande prévue"
assert_contient "$(cat "$T_APT")" "update" "l'index est rafraîchi : lecture du cache, aucune installation"
assert_absent "$(cat "$T_APT")" "install --only-upgrade -y" "aucune installation n'est lancée"
assert_egal "1" "$(awk 'index($0, "ps -q") { n++ } END { printf "%d", n + 0 }' "$T_DOCKER")" "le décompte des conteneurs a bien été lu"
TABLE_AVANT="docker-ce=28.5.2 containerd.io=1.7.24"; TABLE_APRES="$TABLE_AVANT"; NOUVEAUX=""; reinit; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 sur un jeu partiel : buildx et compose absents"
assert_contient "$SORTIE" "Composants à mettre à jour — 0" "aucun composant à niveau n'est annoncé"
assert_egal "0" "$(grep -c buildx "$T_APT" || true)" "buildx, absent, n'entre dans aucune commande apt-get"

titre "live-restore actif — la coupure change de forme, daemon.json n'est pas touché"; NOUVEAUX="docker-ce docker-ce-cli"; TABLE_AVANT="$TOUS"; TABLE_APRES="$APRES_TOUS"; P_LIVE="true"; reinit; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0"
assert_contient "$SORTIE" "live-restore est actif" "il dit que les conteneurs survivent au redémarrage du démon"
assert_contient "$SORTIE" "containerd n'y est pas sensible" "et réserve le cas de containerd — non mesuré ici"
assert_absent "$SORTIE" "emportera les conteneurs" "sans reprendre le message de l'autre cas"
assert_absent "$SORTIE" "INTERROMPUS" "il n'annonce pas une interruption que live-restore évite"
assert_egal "" "$(grep -nE '(>|>>|tee |sed -i|install ).*daemon\.json' "$CIBLE" || true)" "le script n'écrit jamais dans /etc/docker/daemon.json"

titre "Ce que le script ne peut pas lire — démon injoignable, aucun conteneur"; P_LIVE="false"; P_MUET=1; reinit; lancer --dry-run
assert_code 0 "$CODE" "--dry-run reste utilisable quand le démon ne répond pas"
assert_contient "$SORTIE" "Démon Docker injoignable" "le script dit le démon injoignable"
assert_contient "$SORTIE" "illisible" "live-restore est dit illisible, et non inactif"
assert_absent "$SORTIE" "live-restore n'est pas actif" "il ne conclut pas à l'inactivité de live-restore"
P_MUET=""; P_CONTENEURS=""; reinit; lancer --dry-run
assert_contient "$SORTIE" "Aucun conteneur en cours" "un parc vide est annoncé comme tel"
assert_absent "$SORTIE" "INTERROMPUS" "et aucune interruption n'est annoncée"
titre "Confirmation — refusée puis acceptée, la commande reste bornée"; P_CONTENEURS="c1c1c1 c2c2c2"; reinit; lancer_pty "n"
assert_code 0 "$CODE" "un refus rend 0"
assert_contient "$SORTIE" "[o/N]" "la confirmation est posée"
assert_contient "$SORTIE" "Les conteneurs en cours seront interrompus" "la question rappelle la coupure"
assert_contient "$SORTIE" "annulée" "le refus est dit"
assert_egal "" "$(cat "$T_APT")" "et rien n'est installé : pas même l'index rafraîchi"
reinit; lancer_pty "o"
assert_code 0 "$CODE" "acceptée, la mise à jour rend 0"
assert_contient "$(cat "$T_APT")" "install --only-upgrade -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "la commande est bornée à la liste relevée"
assert_egal "" "$(fautives)" "aucun apt-get hors de ces deux formes : ni upgrade, ni dist-upgrade"
assert_contient "$SORTIE" "28.5.2 → 29.0.0" "l'avant / après montre la version mise à jour"
assert_contient "$SORTIE" "inchangé" "et dit inchangé ce qui n'a pas bougé"
assert_contient "$(cat "$LOGS/update-docker.log")" "apt-get install --only-upgrade" "la commande part au journal"
reinit; lancer
assert_code 1 "$CODE" "hors terminal et sans --yes, le script rend 1 au lieu de lire un stdin fermé"
assert_contient "$SORTIE" "--yes" "le message nomme l'option qui débloque la situation"
assert_egal "" "$(cat "$T_APT")" "et rien n'a été tenté avant la question"

titre "Après coup — --yes, service inactif, puis systemctl absent"; reinit; lancer --yes
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

titre "Ce que le script ne fait jamais"; assert_egal "" "$(grep -vE '^(ps -q|info --format )' "$T_DOCKER" || true)" "aucune commande docker hors de la lecture — ni pull, ni restart"
assert_egal "0" "$(grep -cE 'docker (pull|restart|stop|rm)' "$CIBLE" || true)" "le source ne porte ni pull, ni restart : les images applicatives sont hors de portée"
bilan "TASK-036 / update-docker.sh"
