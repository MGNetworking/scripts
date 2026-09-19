#!/usr/bin/env bash
# tests/acceptance/TASK-095-lib-agents.sh — la bibliothèque des gestes génériques.
#
# Aucun agent n'est lancé, aucune clé n'est lue : un faux claude, un faux
# powershell.exe et un dépôt jouet. Ce que ce fichier prouve :
#
#   1. les deux fichiers du scope tiennent dans 150 lignes ;
#   2. lib-agents.sh ne nomme ni un chemin, ni une tâche, ni une règle du dépôt ;
#   3. la copie isolée se crée, puis se réutilise sans être refaite ;
#   4. un profil inconnu est refusé en 2 ;
#   5. un lancement réel garde la ligne VERDICT et la ligne de mesure.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

OUTILS="$SCRIPTS_ROOT/orchestration/outils"
LIB="$OUTILS/lib-agents.sh"
LANCEUR="$OUTILS/lancer-agent.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

titre "1. Les fichiers du scope"
for f in "$LIB" "$LANCEUR"; do
    [ -f "$f" ] || die "Fichier absent : $f" 1
    n="$(wc -l < "$f")"
    if [ "$n" -le 150 ]; then ok "$(basename "$f") — $n lignes"; else ko "$(basename "$f")" "$n lignes, cible 150"; fi
done

titre "2. Générique — aucune mention du dépôt"
contenu="$(cat "$LIB")"
for motif in TASK- SCRIPTS_ROOT orchestration/ tasks/ lib/common.sh agents.tsv limites.json MGNetworking; do
    assert_absent "$contenu" "$motif" "lib-agents.sh ne nomme pas « $motif »"
done

titre "3. Copie isolée — création, puis réutilisation"
if command -v git > /dev/null 2>&1; then
    depot="$TMP/depot"
    mkdir -p "$depot"
    git -C "$depot" init -q -b master
    echo "base" > "$depot/fichier.txt"
    git -C "$depot" add -A
    git -C "$depot" -c user.email=t@t -c user.name=t commit -qm init
    copie="$TMP/depot-agents/TASK-999"

    # shellcheck source=/dev/null
    source "$LIB"

    code=0; copie_isolee "$depot" "agent/TASK-999" "$copie" master || code=$?
    assert_code 0 "$code" "copie_isolee : création"
    assert_egal "agent/TASK-999" "$(git -C "$copie" rev-parse --abbrev-ref HEAD)" "la copie porte la branche demandée"
    assert_egal "base" "$(cat "$copie/fichier.txt")" "la copie porte le contenu de la base"

    echo "travail" > "$copie/MARQUE"
    code=0; copie_isolee "$depot" "agent/TASK-999" "$copie" master || code=$?
    assert_code 0 "$code" "copie_isolee : second appel"
    assert_egal "travail" "$(cat "$copie/MARQUE" 2> /dev/null)" "la réutilisation laisse la copie intacte"
    assert_egal "1" "$(git -C "$depot" worktree list | grep -c 'TASK-999' || true)" "un seul arbre de travail"

    git -C "$depot" worktree remove --force "$copie"
    code=0; copie_isolee "$depot" "agent/TASK-999" "$copie" master || code=$?
    assert_code 0 "$code" "copie_isolee : la branche existe déjà"
    assert_egal "agent/TASK-999" "$(git -C "$copie" rev-parse --abbrev-ref HEAD)" "elle rattache la branche existante"
else
    saute_indisponible "copie isolée" "git est introuvable"
fi

titre "4. lancer-agent.sh sur un dépôt jouet"
J="$TMP/jouet"
mkdir -p "$J/orchestration/outils" "$J/orchestration/modeles" "$J/orchestration/mesures" "$J/tasks/active"
cp "$LANCEUR" "$LIB" "$OUTILS/resoudre-cle.sh" "$J/orchestration/outils/"
printf 'ADRESSE=https://exemple.invalid\nVARIABLE_CLE=TEST_CLE_MGNET\nMODELE_DEFAUT=petit\nMODELE_petit=m-petit\nPRIX_petit=1.00 0.10 5.00\n' > "$J/orchestration/modeles/jouet.env"
printf '{\n  "mode": "api",\n  "modele": "petit"\n}\n' > "$J/orchestration/relecture.json"
echo "fiche" > "$J/tasks/active/TASK-999.md"
JOUET="$J/orchestration/outils/lancer-agent.sh"
export FAUX_TMP="$TMP" CLAUDE_CONFIG_DIR="$TMP/config"

# lancer <VAR=valeur…> -- <arguments> — sortie complète dans $sortie, code dans $code.
lancer() {
    local vars=()
    while [ "$1" != "--" ]; do vars+=("$1"); shift; done; shift
    sortie="$(env -u ANTHROPIC_API_KEY -u TEST_CLE_MGNET "${vars[@]}" PATH="$TMP/bin:$PATH" bash "$JOUET" "$@" 2>&1)" && code=0 || code=$?
}

lancer TEST_CLE_MGNET=fausse-cle -- inconnu TASK-999 --dry-run
assert_code 2 "$code" "profil inconnu : refusé"
assert_contient "$sortie" "Usage" "profil inconnu : le refus dit l'usage"

if command -v git > /dev/null && command -v node > /dev/null; then
    git -C "$J" init -q -b master
    git -C "$J" add -A 2> /dev/null
    git -C "$J" -c user.email=t@t -c user.name=t commit -qm init
    # Faux claude : consigne ses arguments et son dossier, pose un transcript de
    # session à deux tours aux jetons connus, et rend le verdict attendu d'un
    # relecteur. Deux tours : la mesure doit sommer, pas lire le dernier.
    cat > "$TMP/bin/claude" <<'FAUX'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAUX_TMP/args"
pwd > "$FAUX_TMP/pwd"
mkdir -p "$CLAUDE_CONFIG_DIR/projects/jouet"
cat > "$CLAUDE_CONFIG_DIR/projects/jouet/sess-test.jsonl" <<'J'
{"message":{"role":"assistant","id":"m1","usage":{"input_tokens":2000,"output_tokens":300,"cache_read_input_tokens":3000,"cache_creation_input_tokens":1000}}}
{"message":{"role":"assistant","id":"m2","usage":{"input_tokens":0,"output_tokens":100,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
J
echo '{"result":"VERDICT : FUSIONNABLE","session_id":"sess-test"}'
FAUX
    chmod +x "$TMP/bin/claude"

    lancer TEST_CLE_MGNET=fausse-cle -- jouet TASK-999 --relecture
    assert_code 0 "$code" "relecture : lancement"
    args="$(cat "$TMP/args")"
    assert_contient "$args" "relecteur" "les arguments gardent l'agent relecteur"
    assert_contient "$args" "Read,Grep,Glob" "les arguments gardent les outils de lecture"
    assert_contient "$args" "Relis le travail de TASK-999" "les arguments gardent la consigne de relecture"
    assert_egal "$J-agents/TASK-999" "$(cat "$TMP/pwd")" "le lancement tourne dans la copie isolée"
    assert_egal "agent/TASK-999" "$(git -C "$J-agents/TASK-999" rev-parse --abbrev-ref HEAD)" "la copie vient de copie_isolee"
    assert_contient "$sortie" "VERDICT : FUSIONNABLE" "la ligne VERDICT est rendue telle quelle"

    TSV="$J/orchestration/mesures/agents.tsv"
    assert_egal "11" "$(awk -F'\t' '{print NF; exit}' "$TSV")" "l'en-tête du journal garde ses onze colonnes"
    assert_egal "2" "$(wc -l < "$TSV" | tr -d ' ')" "le journal porte l'en-tête et la ligne du lancement"
    ligne="$(tail -1 "$TSV")"
    assert_egal "relecteur" "$(cut -f3 <<< "$ligne")" "la ligne de mesure garde la colonne relecteur"
    assert_egal "m-petit" "$(cut -f4 <<< "$ligne")" "elle porte le modèle"
    assert_egal "2" "$(cut -f5 <<< "$ligne")" "elle compte les tours du transcript"
    assert_egal "2000" "$(cut -f6 <<< "$ligne")" "elle porte les jetons d'entrée"
    assert_egal "4000" "$(cut -f7 <<< "$ligne")" "elle porte les jetons de cache"
    assert_egal "400" "$(cut -f8 <<< "$ligne")" "elle porte les jetons produits"
    assert_egal "0.004" "$(cut -f11 <<< "$ligne")" "elle porte le coût au tarif du profil"
else
    saute_indisponible "lancement jouet" "git ou node est introuvable"
fi

bilan "TASK-095"
