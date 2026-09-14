#!/usr/bin/env bash
# tests/unit/journalisation-complete.test.sh — enable_full_logging et le chargement
# de configuration de lib/common.sh (TASK-039, A19 à A21, A23).
#
# Chaque cas lance un petit script dans un bac à sable : une copie du socle, un
# LOG_DIR temporaire, et au besoin un config/server.env ou un config/essai.env.

# Les corps de script sont entre guillemets simples : ils doivent atteindre le bac
# à sable tels quels, pour y être développés.
# shellcheck disable=SC2016
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# bac — crée un bac à sable neuf et l'imprime.
bac() {
    local b
    b="$(mktemp -d "$TMP/bac.XXXXXX")"
    mkdir -p "$b/lib" "$b/config" "$b/logs"
    cp "$SCRIPTS_ROOT/lib/common.sh" "$b/lib/"
    printf '%s' "$b"
}

# lancer <bac> <corps du script> — exécute le script, pose SORTIE et CODE.
lancer() {
    printf '#!/usr/bin/env bash\nset -Eeuo pipefail\nsource "%s/lib/common.sh"\n%s\n' "$1" "$2" > "$1/essai.sh"
    CODE=0
    SORTIE="$(cd "$1" && LOG_DIR="$1/logs" bash essai.sh 2>&1)" || CODE=$?
}

titre "1. enable_full_logging"

B="$(bac)"
lancer "$B" "LOG_DIR_ATTENDU=1; enable_full_logging; echo 'ligne ordinaire'; echo 'erreur brute' >&2"
assert_code 0 "$CODE" "le script journalisé se termine en 0"
JOURNAL="$(cat "$B/logs/essai.log" 2>/dev/null || true)"
assert_contient "$JOURNAL" "ligne ordinaire" "la sortie standard est recopiée dans le journal"
assert_contient "$JOURNAL" "erreur brute" "la sortie d'erreur aussi"
assert_contient "$JOURNAL" "Journalisation complète activée" "l'activation est annoncée"

B="$(bac)"
lancer "$B" "enable_full_logging; enable_full_logging; echo unique"
assert_egal 1 "$(grep -c 'Journalisation complète activée' "$B/logs/essai.log")" \
    "un second appel ne rebranche pas la capture"

B="$(bac)"
lancer "$B" "LOG_FILE=''; enable_full_logging; echo sans-journal"
assert_code 0 "$CODE" "sans journal, enable_full_logging ne fait rien et ne tue pas le script"
assert_contient "$SORTIE" "sans-journal" "la sortie reste à l'écran"

B="$(bac)"
lancer "$B" "enable_full_logging; run_logged echo sortie-commande"
assert_egal 1 "$(grep -c "^sortie-commande" "$B/logs/essai.log")" \
    "sous capture complète, la sortie de run_logged n'est journalisée qu'une fois (A40)"

titre "2. LOG_DIR doit être absolu (A19)"

B="$(bac)"
printf 'LOG_DIR=-piege\n' > "$B/config/server.env"
lancer "$B" 'echo "LOG_DIR=$LOG_DIR"'
assert_code 0 "$CODE" "une valeur à tiret ne tue pas le script"
assert_contient "$SORTIE" "LOG_DIR ignoré" "elle est signalée"
DEFAUT="$B/logs"; [ "$(id -u)" -ne 0 ] || DEFAUT="/var/log/mgnetworking"
assert_contient "$SORTIE" "LOG_DIR=$DEFAUT" "et remplacée par la valeur par défaut"

titre "3. server.env exporte, comme load_config (A20)"

B="$(bac)"
printf 'SRV_ESSAI=present\n' > "$B/config/server.env"
lancer "$B" 'bash -c "echo fils=\${SRV_ESSAI:-absent}"; case "$-" in *a*) echo allexport=arme ;; *) echo allexport=eteint ;; esac'
assert_contient "$SORTIE" "fils=present" "une variable de server.env atteint les processus fils"
assert_contient "$SORTIE" "allexport=eteint" "allexport est éteint après le chargement"

titre "4. Un .env qui tuerait le shell (A21)"

B="$(bac)"
printf 'SRV_X="$VARIABLE_JAMAIS_DEFINIE"\n' > "$B/config/server.env"
lancer "$B" 'echo ne-doit-pas-sortir'
assert_code 1 "$CODE" "server.env illisible sous set -u : sortie en 1"
assert_contient "$SORTIE" "Configuration illisible : config/server.env" "avec un message qui nomme le fichier"
assert_absent "$SORTIE" "ne-doit-pas-sortir" "et rien ne s'exécute après"

B="$(bac)"
printf 'X="$VARIABLE_JAMAIS_DEFINIE"\n' > "$B/config/essai.env"
lancer "$B" 'trap '"'"'case "$-" in *a*) echo piege=arme ;; *) echo piege=eteint ;; esac'"'"' EXIT; load_config essai'
assert_code_non_nul "$CODE" "load_config sur un .env illisible sous set -u échoue"
assert_contient "$SORTIE" "Configuration illisible : config/essai.env" "avec un message qui nomme le fichier"
assert_contient "$SORTIE" "piege=eteint" "le piège EXIT ne tourne pas avec allexport armé"

bilan "journalisation complète et chargement de configuration"
