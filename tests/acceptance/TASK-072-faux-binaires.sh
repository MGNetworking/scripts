#!/usr/bin/env bash
# tests/acceptance/TASK-072-faux-binaires.sh — détection d'un faux binaire écrit à
# travers un lien symbolique (orchestration/outils/lien-ecrit.awk, lu par juger.sh).
#
# Chaque cas est un petit fichier de cas factice : il n'est jamais exécuté, seulement
# lu par la détection. Un signalement est une ligne « FAIL » ; aucune ligne, aucun.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# eprouver <signalements attendus> <libellé> — le fichier de cas factice sur STDIN.
eprouver() {
    local attendu="$1" libelle="$2" n
    cat > "$TMP/cas.sh"
    n="$(awk -f "$SCRIPTS_ROOT/orchestration/outils/lien-ecrit.awk" "$TMP/cas.sh" | grep -c '^FAIL ' || true)"
    assert_egal "$attendu" "$n" "$libelle"
}

titre "Signalés"
eprouver 1 "lien littéral puis cat >" <<'CAS'
ln -s /usr/bin/timeout "$BAC/bin/timeout"
cat > "${BAC}/bin/timeout" <<'SH'
SH
CAS
eprouver 1 "boucle for de liens puis printf >" <<'CAS'
for c in sed timeout; do ln -sf "$(command -v "$c")" "$BAC/bin/$c"; done
printf '#!/bin/sh\nexit 1\n' >"$BAC/bin/sed"
CAS
eprouver 1 "fonction qui écrit …/\$1, forme du premier jet de TASK-071 (6ad93f8)" <<'CAS'
faux() { cat > "$BAC/bin/$1"; chmod +x "$BAC/bin/$1"; }
for outil in bash timeout; do
    for d in "$BAC/bin" "$BAC/bin-nu"; do ln -sf "$(command -v "$outil")" "$d/$outil"; done
done
faux timeout <<EOF
EOF
CAS
eprouver 1 "options séparées et redirection après le lien" <<'CAS'
ln -f -s /usr/bin/stat "$BAC/bin/stat" 2>/dev/null
echo faux >> "$BAC/bin/stat"
CAS

titre "Non signalés"
eprouver 0 "liens et faux dans deux répertoires distincts" <<'CAS'
for c in sed timeout; do ln -sf "$(command -v "$c")" "$BAC/liens/$c"; done
cat > "$BAC/faux/timeout" <<'SH'
SH
CAS
eprouver 0 "lien et écriture en commentaire" <<'CAS'
# ln -s /usr/bin/sed "$BAC/bin/sed" puis cat > "$BAC/bin/sed"
CAS
eprouver 0 "écriture avant le lien" <<'CAS'
cat > "$BAC/bin/timeout" <<'SH'
SH
ln -sf /usr/bin/timeout "$BAC/bin/timeout"
CAS
eprouver 0 "lien retiré par rm avant l'écriture" <<'CAS'
ln -sf /usr/bin/timeout "$BAC/bin/timeout"
rm -f "$BAC/bin/timeout"
cat > "$BAC/bin/timeout" <<'SH'
SH
CAS

bilan "détection des faux binaires écrits à travers un lien"
