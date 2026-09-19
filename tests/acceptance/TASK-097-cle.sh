#!/usr/bin/env bash
# tests/acceptance/TASK-097-cle.sh — resoudre-cle.sh, et lancer-agent.sh qui l'appelle.
#
# Fausses valeurs seulement, faux powershell.exe et faux claude : aucune vraie clé
# n'est lue, aucun agent n'est lancé. Le dépôt jouet vit dans un répertoire temporaire.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

OUTILS="$SCRIPTS_ROOT/orchestration/outils"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

export FAUX_TMP="$TMP"

# Faux powershell.exe : rend $FAUX_REGISTRE avec un retour chariot, comme Windows, et note l'appel.
cat > "$TMP/bin/powershell.exe" <<'FAUX'
#!/usr/bin/env bash
touch "$FAUX_TMP/appel"
printf '%s\r\n' "${FAUX_REGISTRE:-}"
FAUX
# Faux claude : garde la clé qu'il reçoit, rend une sortie JSON minimale.
cat > "$TMP/bin/claude" <<'FAUX'
#!/usr/bin/env bash
printf '%s' "$ANTHROPIC_API_KEY" > "$FAUX_TMP/cle-recue"
echo '{"result":"ok"}'
FAUX
chmod +x "$TMP/bin/powershell.exe" "$TMP/bin/claude"

# cle<FAUX_REGISTRE> [VAR=valeur…] -- <nom> — stdout de resoudre-cle.sh ; code dans $code.
cle() {
    local reg="$1"; shift
    rm -f "$TMP/appel"
    env -u TEST_CLE_MGNET "$@" FAUX_REGISTRE="$reg" PATH="$TMP/bin:$PATH" bash "$OUTILS/resoudre-cle.sh" "${nom:-TEST_CLE_MGNET}" > "$TMP/brut" 2> "$TMP/err" && code=0 || code=$?
    out="$(cat "$TMP/brut")"
    octets_cr="$(tr -cd '\r' < "$TMP/brut" | wc -c | tr -d ' ')"
}

# pas_appele <libellé> — le dernier cle n'a pas dû appeler powershell.exe.
pas_appele() { if [ -e "$TMP/appel" ]; then ko "$1" "powershell.exe appelé"; else ok "$1"; fi; }

nom="" cle "" TEST_CLE_MGNET=valeur-env
assert_code 0 "$code" "environnement seul"; assert_egal "valeur-env" "$out" "environnement seul : la valeur"

cle "valeur-registre"
assert_code 0 "$code" "registre seul"; assert_egal "valeur-registre" "$out" "registre seul : la valeur"
# Preuve du retour chariot : conteneur Linux seulement — Git Bash le retire lui-même, l'hôte ne peut pas la voir.
assert_egal "0" "$octets_cr" "registre seul : aucun retour chariot dans les octets écrits"

cle "valeur-registre" TEST_CLE_MGNET=valeur-env
assert_egal "valeur-env" "$out" "l'environnement passe avant le registre"
pas_appele "environnement présent : powershell.exe n'est pas appelé"

cle ""
assert_code 1 "$code" "introuvable nulle part"; assert_egal "" "$out" "introuvable : rien sur stdout"

for mauvais in "test_cle" "A'B" "1ABC" "A B"; do
    nom="$mauvais" cle "valeur-registre"
    assert_code 2 "$code" "nom invalide « $mauvais »"
    pas_appele "nom invalide « $mauvais » : powershell.exe n'est pas appelé"
done

# lancer-agent.sh sur un dépôt jouet : la clé absente arrête en 2, la clé du registre part à l'agent.
J="$TMP/jouet"
mkdir -p "$J/orchestration/outils" "$J/orchestration/modeles" "$J/orchestration/mesures" "$J/tasks/active"
cp "$OUTILS/lancer-agent.sh" "$OUTILS/resoudre-cle.sh" "$J/orchestration/outils/"
printf 'ADRESSE=https://exemple.invalid\nMODELE=faux\nVARIABLE_CLE=TEST_CLE_ABSENTE_MGNET\n' > "$J/orchestration/modeles/faux.env"
echo "fiche" > "$J/tasks/active/TASK-999.md"
env -u TEST_CLE_ABSENTE_MGNET FAUX_REGISTRE="" PATH="$TMP/bin:$PATH" bash "$J/orchestration/outils/lancer-agent.sh" faux TASK-999 > /dev/null 2> "$TMP/err" && code=0 || code=$?
assert_code 2 "$code" "lancer-agent.sh : clé introuvable"
assert_contient "$(cat "$TMP/err")" "TEST_CLE_ABSENTE_MGNET" "le message nomme la variable"
assert_contient "$(cat "$TMP/err")" "variables utilisateur de Windows" "le message nomme les deux endroits"

if command -v git > /dev/null && command -v node > /dev/null; then
    git -C "$J" init -q -b master && git -C "$J" add -A \
        && git -C "$J" -c user.email=t@t -c user.name=t commit -qm init
    FAUX_REGISTRE="valeur-registre" PATH="$TMP/bin:$PATH" bash "$J/orchestration/outils/lancer-agent.sh" faux TASK-999 > "$TMP/sortie" 2>&1 && code=0 || code=$?
    assert_code 0 "$code" "lancer-agent.sh : clé du registre, agent lancé"
    assert_egal "valeur-registre" "$(cat "$TMP/cle-recue" 2> /dev/null)" "l'agent reçoit la clé du registre"
    # Garde limitée : le faux claude n'affiche jamais la clé ; elle attrape un « set -x » ou un « echo » ajouté au script.
    assert_absent "$(cat "$TMP/sortie")" "valeur-registre" "la clé n'est pas affichée"
    assert_absent "$(cat "$J/orchestration/mesures/agents.tsv" 2> /dev/null)" "valeur-registre" "la clé n'est pas dans le relevé"
else
    saute_indisponible "lancer-agent.sh jouet : git ou node indisponible"
fi

bilan "TASK-097"
