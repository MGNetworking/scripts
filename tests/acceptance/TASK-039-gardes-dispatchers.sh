#!/usr/bin/env bash
# tests/acceptance/TASK-039-gardes-dispatchers.sh — gardes de run-unit.sh et
# run-integration.sh (TASK-039, A15).
#
# Chaque dispatcher traduit les codes de ses fichiers de cas en un verdict de
# niveau. Ces gardes n'étaient prouvées qu'une fois, par sonde jetable. Ici, un bac
# à sable par combinaison : une copie du socle et du dispatcher, et de faux
# fichiers de cas qui rendent le code voulu.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# eprouver <niveau> <code attendu> <libellé> [code de chaque faux fichier…]
eprouver() {
    local niveau="$1" attendu="$2" libelle="$3" bac code=0 i=0
    shift 3
    bac="$(mktemp -d "$TMP/bac.XXXXXX")"
    mkdir -p "$bac/lib" "$bac/tests/$niveau" "$bac/logs"
    cp "$SCRIPTS_ROOT/lib/common.sh" "$bac/lib/"
    cp "$SCRIPTS_ROOT/tests/$niveau/run-$niveau.sh" "$bac/tests/$niveau/"
    for c in "$@"; do
        i=$((i + 1))
        printf '#!/usr/bin/env bash\nexit %s\n' "$c" > "$bac/tests/$niveau/cas$i.test.sh"
    done
    LOG_DIR="$bac/logs" bash "$bac/tests/$niveau/run-$niveau.sh" >/dev/null 2>&1 || code=$?
    assert_code "$attendu" "$code" "$niveau — $libelle"
}

for niveau in unit integration; do
    titre "Dispatcher $niveau"
    eprouver "$niveau" 3 "aucun fichier de cas → 3"
    eprouver "$niveau" 1 "un fichier en échec → 1" 0 1
    eprouver "$niveau" 3 "un fichier sans preuve → 3" 0 3
    eprouver "$niveau" 4 "un complet et un partiel → 4" 0 4
    eprouver "$niveau" 0 "que des fichiers complets → 0" 0 0
done

bilan "gardes des dispatchers"
