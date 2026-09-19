#!/usr/bin/env bash
# tests/acceptance/TASK-098-modeles.sh — anthropic.env à plusieurs modèles, --modele et --dry-run.
#
# Fausses clés, faux powershell.exe et faux claude : aucune vraie clé n'est lue, aucun agent
# n'est lancé. Les profils réels se lisent en --dry-run ; le lancement se prouve sur un dépôt jouet.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

OUTILS="$SCRIPTS_ROOT/orchestration/outils"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
export FAUX_TMP="$TMP"

# Faux powershell.exe : registre toujours vide, pour que seule la variable d'environnement compte.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/bin/powershell.exe"
# Faux claude : note qu'il a été appelé et garde les variables de modèle qu'il reçoit.
cat > "$TMP/bin/claude" <<'FAUX'
#!/usr/bin/env bash
printf '%s\n' "$ANTHROPIC_MODEL" "$ANTHROPIC_DEFAULT_HAIKU_MODEL" "$ANTHROPIC_DEFAULT_SONNET_MODEL" "$ANTHROPIC_DEFAULT_OPUS_MODEL" > "$FAUX_TMP/env-recu"
echo '{"result":"ok"}'
FAUX
chmod +x "$TMP/bin/powershell.exe" "$TMP/bin/claude"

# lancer <script> [VAR=valeur…] -- <arguments> — sortie complète dans $sortie, code dans $code.
lancer() {
    local script="$1"; shift; local vars=()
    while [ "$1" != "--" ]; do vars+=("$1"); shift; done; shift
    sortie="$(env -u ANTHROPIC_API_KEY -u DEEPSEEK_API_KEY "${vars[@]}" PATH="$TMP/bin:$PATH" bash "$script" "$@" 2>&1)" && code=0 || code=$?
}
REEL="$OUTILS/lancer-agent.sh"
AN="ANTHROPIC_API_KEY=fausse-cle-anthropic"

# Profils réels, en --dry-run.
lancer "$REEL" "$AN" -- anthropic --dry-run
assert_code 0 "$code" "anthropic sans option"
assert_contient "$sortie" "modèle=claude-haiku-4-5" "anthropic : le défaut est Haiku"
assert_contient "$sortie" "tarifs=1.00/0.10/5.00" "anthropic : tarifs de Haiku"
lancer "$REEL" "$AN" -- anthropic --dry-run --modele sonnet
assert_contient "$sortie" "modèle=claude-sonnet-5" "--modele sonnet : identifiant"
assert_contient "$sortie" "tarifs=2.00/0.20/10.00" "--modele sonnet : tarifs"
lancer "$REEL" "$AN" -- anthropic --modele opus --dry-run
assert_contient "$sortie" "modèle=claude-opus-5" "--modele opus, avant --dry-run : identifiant"
assert_contient "$sortie" "tarifs=5.00/0.50/25.00" "--modele opus : tarifs"
lancer "$REEL" "$AN" -- anthropic --dry-run --modele gpt
assert_code 2 "$code" "alias inconnu"
assert_contient "$sortie" "haiku" "alias inconnu : liste les alias"; assert_contient "$sortie" "opus" "alias inconnu : liste opus"
lancer "$REEL" DEEPSEEK_API_KEY=fausse-cle-deepseek -- deepseek --dry-run
assert_code 0 "$code" "deepseek sans option"
assert_contient "$sortie" "modèle=deepseek-flash" "deepseek : modèle inchangé"
assert_contient "$sortie" "tarifs=0.30/0.006/1.20" "deepseek : tarifs inchangés"
lancer "$REEL" DEEPSEEK_API_KEY=fausse-cle-deepseek -- deepseek --dry-run --modele opus
assert_code 2 "$code" "deepseek refuse --modele"
assert_contient "$sortie" "pas de choix de modèle" "deepseek : message"
lancer "$REEL" -- anthropic --dry-run
assert_code 2 "$code" "anthropic sans clé, dry-run"
assert_contient "$sortie" "ANTHROPIC_API_KEY est introuvable" "anthropic sans clé : le message nomme la variable"
lancer "$REEL" "$AN" -- anthropic --dry-run --modele
assert_code 2 "$code" "--modele sans valeur"
lancer "$REEL" "$AN" -- anthropic --dry-run --modele "*"
assert_code 2 "$code" "--modele avec un joker"
lancer "$REEL" "$AN" -- anthropic --dry-run
assert_absent "$sortie" "fausse-cle-anthropic" "la clé n'apparaît pas dans la sortie"

# Dépôt jouet : le lancement transmet le modèle choisi.
J="$TMP/jouet"
mkdir -p "$J/orchestration/outils" "$J/orchestration/modeles" "$J/orchestration/mesures" "$J/tasks/active"
cp "$OUTILS/lancer-agent.sh" "$OUTILS/resoudre-cle.sh" "$OUTILS/lib-agents.sh" "$J/orchestration/outils/"
printf 'ADRESSE=https://exemple.invalid\nVARIABLE_CLE=TEST_CLE_MGNET\nMODELE_DEFAUT=petit\nMODELE_petit=m-petit\nPRIX_petit=1.00 0.10 5.00\nMODELE_grand=m-grand\nPRIX_grand=5.00 0.50 25.00\n' > "$J/orchestration/modeles/multi.env"
printf 'ADRESSE=https://exemple.invalid\nMODELE=m-ancien\nVARIABLE_CLE=TEST_CLE_MGNET\nPRIX_ENTREE=0.30\nPRIX_CACHE=0.006\nPRIX_SORTIE=1.20\n' > "$J/orchestration/modeles/ancien.env"
echo "fiche" > "$J/tasks/active/TASK-999.md"
CLE="TEST_CLE_MGNET=fausse-cle"

lancer "$J/orchestration/outils/lancer-agent.sh" "$CLE" -- multi --dry-run --modele grand
assert_code 0 "$code" "jouet : dry-run"
if [ -d "$TMP/jouet-agents" ] || [ -e "$TMP/env-recu" ] || [ -e "$J/orchestration/mesures/agents.tsv" ]; then
    ko "dry-run" "une copie, un lancement ou un relevé est apparu"; else ok "dry-run : ni copie, ni agent, ni relevé"; fi

if command -v git > /dev/null && command -v node > /dev/null; then
    git -C "$J" init -q -b master && git -C "$J" add -A 2> /dev/null && git -C "$J" -c user.email=t@t -c user.name=t commit -qm init
    lancer "$J/orchestration/outils/lancer-agent.sh" "$CLE" -- multi --dry-run
    assert_egal "" "$(git -C "$J" branch --list 'agent/*')" "dry-run : aucune branche agent créée"
    # recu <alias…> : lance et rend les quatre variables de modèle reçues par l'agent, sur une ligne.
    recu() { lancer "$J/orchestration/outils/lancer-agent.sh" "$CLE" -- "$@"; tr '\n' ' ' < "$TMP/env-recu"; }
    assert_egal "m-petit m-petit m-petit m-petit " "$(recu multi TASK-999)" "lancement sans --modele : le défaut, aux quatre variables"
    assert_egal "m-petit" "$(tail -1 "$J/orchestration/mesures/agents.tsv" | cut -f4)" "le relevé porte l'identifiant du défaut"
    assert_egal "m-grand m-grand m-grand m-grand " "$(recu multi TASK-999 --modele grand)" "lancement --modele grand"
    assert_egal "m-grand" "$(tail -1 "$J/orchestration/mesures/agents.tsv" | cut -f4)" "le relevé porte l'identifiant choisi"
    echo "retours" > "$TMP/retours.md"
    assert_egal "m-grand m-grand m-grand m-grand " "$(recu multi TASK-999 "$TMP/retours.md" --modele grand)" "fichier de retours et --modele mêlés"
    assert_egal "m-ancien m-ancien m-ancien m-ancien " "$(recu ancien TASK-999)" "profil à un seul modèle : comportement d'avant"
else
    saute_indisponible "lancement jouet : git ou node indisponible"
fi

bilan "TASK-098"
