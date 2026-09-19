#!/usr/bin/env bash
# tests/acceptance/TASK-099-relecture.sh — la relecture lancée par l'API, et l'interrupteur
# orchestration/relecture.json qui dit qui relit.
#
# Faux claude, faux transcript de session, fausses clés : aucun agent n'est lancé, aucune
# vraie clé n'est lue, rien n'est facturé. Le lancement se prouve sur un dépôt jouet ; le
# réglage réel du dépôt n'est lu qu'en --dry-run.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

OUTILS="$SCRIPTS_ROOT/orchestration/outils"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/config"
export FAUX_TMP="$TMP" CLAUDE_CONFIG_DIR="$TMP/config"

# Faux powershell.exe : registre toujours vide, pour que seule la variable d'environnement compte.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/powershell.exe"
# Faux claude : consigne ses arguments et son répertoire de travail, pose un transcript de
# session avec des jetons connus, et rend le verdict attendu d'un relecteur.
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
chmod +x "$TMP/bin/powershell.exe" "$TMP/bin/claude"

# lancer <script> [VAR=valeur…] -- <arguments> — sortie complète dans $sortie, code dans $code.
lancer() {
    local script="$1"; shift; local vars=()
    while [ "$1" != "--" ]; do vars+=("$1"); shift; done; shift
    sortie="$(env -u ANTHROPIC_API_KEY -u DEEPSEEK_API_KEY "${vars[@]}" PATH="$TMP/bin:$PATH" bash "$script" "$@" 2>&1)" && code=0 || code=$?
}
# regle <mode> <modele> — écrit le réglage du dépôt jouet.
regle() { printf '{\n  "mode": "%s",\n  "modele": "%s"\n}\n' "$1" "$2" > "$J/orchestration/relecture.json"; }

# --- Le réglage réel du dépôt -------------------------------------------------
REEL="$OUTILS/lancer-agent.sh"
REGLAGE="$SCRIPTS_ROOT/orchestration/relecture.json"
if [ -f "$REGLAGE" ]; then
    ok "orchestration/relecture.json existe"
    mode_reel="$(sed -n 's/.*"mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REGLAGE" | head -1)"
    modele_reel="$(sed -n 's/.*"modele"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REGLAGE" | head -1)"
    lancer "$REEL" ANTHROPIC_API_KEY=fausse-cle -- anthropic --relecture --dry-run
    case "$mode_reel" in
        api)
            assert_code 0 "$code" "réglage réel en mode api : le lancement est permis"
            assert_contient "$sortie" "relecture=oui" "réglage réel : le dry-run dit que c'est une relecture"
            assert_contient "$sortie" "modèle=" "réglage réel : le dry-run nomme le modèle"
            ok "réglage réel : modèle de relecture « $modele_reel »" ;;
        abonnement)
            assert_code 2 "$code" "réglage réel en mode abonnement : le lancement est refusé"
            assert_contient "$sortie" "sous-agent relecteur" "réglage réel : le refus renvoie au sous-agent" ;;
        *) ko "réglage réel" "mode « $mode_reel » : attendu api ou abonnement" ;;
    esac
else
    ko "réglage réel" "orchestration/relecture.json est absent"
fi

# --- Dépôt jouet : les deux modes, et ce que reçoit vraiment claude -----------
J="$TMP/jouet"
mkdir -p "$J/orchestration/outils" "$J/orchestration/mesures" "$J/orchestration/modeles" "$J/tasks/active"
cp "$OUTILS/lancer-agent.sh" "$OUTILS/resoudre-cle.sh" "$J/orchestration/outils/"
printf 'ADRESSE=https://exemple.invalid\nVARIABLE_CLE=TEST_CLE_MGNET\nMODELE_DEFAUT=petit\nMODELE_petit=m-petit\nPRIX_petit=1.00 0.10 5.00\nMODELE_grand=m-grand\nPRIX_grand=5.00 0.50 25.00\n' > "$J/orchestration/modeles/multi.env"
echo "fiche" > "$J/tasks/active/TASK-999.md"
JOUET="$J/orchestration/outils/lancer-agent.sh"
CLE="TEST_CLE_MGNET=fausse-cle"
TSV="$J/orchestration/mesures/agents.tsv"

regle inconnu opus
lancer "$JOUET" "$CLE" -- multi TASK-999 --relecture --dry-run
assert_code 2 "$code" "mode inconnu : refusé"
assert_contient "$sortie" "inconnu" "mode inconnu : le message le dit"

regle abonnement opus
lancer "$JOUET" "$CLE" -- multi TASK-999 --relecture --dry-run
assert_code 2 "$code" "mode abonnement : la relecture ne passe pas par ce script"
assert_contient "$sortie" "sous-agent relecteur" "mode abonnement : le message renvoie au sous-agent"

rm -f "$J/orchestration/relecture.json"
lancer "$JOUET" "$CLE" -- multi TASK-999 --relecture --dry-run
assert_code 2 "$code" "réglage absent : refusé"

regle api grand
lancer "$JOUET" "$CLE" -- multi TASK-999 --relecture --dry-run
assert_code 0 "$code" "mode api : le lancement est permis"
assert_contient "$sortie" "modèle=m-grand" "mode api : le modèle vient du réglage"
lancer "$JOUET" "$CLE" -- multi TASK-999 --relecture --dry-run --modele petit
assert_contient "$sortie" "modèle=m-petit" "--modele l'emporte sur le réglage"

if command -v git > /dev/null && command -v node > /dev/null; then
    git -C "$J" init -q -b master && git -C "$J" add -A 2> /dev/null && git -C "$J" -c user.email=t@t -c user.name=t commit -qm init
    rm -f "$TMP/args" "$TMP/pwd"

    lancer "$JOUET" "$CLE" -- multi TASK-999 --relecture --modele grand
    assert_code 0 "$code" "relecture : lancement"
    args="$(cat "$TMP/args")"
    assert_contient "$args" "--agent" "les arguments portent --agent"
    assert_contient "$args" "relecteur" "l'agent demandé est le relecteur"
    assert_contient "$args" "--tools" "les arguments portent --tools"
    assert_contient "$args" "Read,Grep,Glob" "les outils sont ceux de la lecture seule"
    assert_absent "$args" "Bash" "aucun Bash dans les arguments"
    assert_absent "$args" "Edit" "aucun Edit dans les arguments"
    assert_absent "$args" "Write" "aucun Write dans les arguments"
    assert_absent "$args" "acceptEdits" "aucune permission d'écriture dans les arguments"
    assert_contient "$args" "Relis le travail de TASK-999" "la consigne est celle de la relecture"
    assert_absent "$args" "/executer-tache" "la consigne n'est pas celle de l'exécution"
    assert_egal "$J-agents/TASK-999" "$(cat "$TMP/pwd")" "la relecture tourne dans la copie de la tâche"
    assert_contient "$sortie" "VERDICT : FUSIONNABLE" "la sortie du relecteur est rendue telle quelle"

    ligne="$(tail -1 "$TSV")"
    assert_egal "relecteur" "$(cut -f3 <<< "$ligne")" "la ligne de mesure porte « relecteur »"
    assert_egal "m-grand" "$(cut -f4 <<< "$ligne")" "elle porte le modèle"
    assert_egal "2" "$(cut -f5 <<< "$ligne")" "elle compte les tours du transcript"
    assert_egal "2000" "$(cut -f6 <<< "$ligne")" "elle porte les jetons d'entrée"
    assert_egal "4000" "$(cut -f7 <<< "$ligne")" "elle porte les jetons de cache"
    assert_egal "400" "$(cut -f8 <<< "$ligne")" "elle porte les jetons produits"
    assert_egal "0.022" "$(cut -f11 <<< "$ligne")" "elle porte le coût au tarif du profil"

    # L'exécution ordinaire n'a pas changé.
    rm -f "$TMP/args"
    lancer "$JOUET" "$CLE" -- multi TASK-999
    args="$(cat "$TMP/args")"
    assert_contient "$args" "/executer-tache TASK-999" "sans --relecture : consigne d'exécution"
    assert_contient "$args" "acceptEdits" "sans --relecture : l'agent garde le droit d'écrire"
    assert_absent "$args" "--agent" "sans --relecture : aucun agent imposé"
    assert_egal "multi" "$(cut -f3 <<< "$(tail -1 "$TSV")")" "sans --relecture : la mesure porte le profil"
else
    saute_indisponible "lancement jouet : git ou node indisponible"
fi

bilan "TASK-099"
