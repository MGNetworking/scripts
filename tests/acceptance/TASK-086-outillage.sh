#!/usr/bin/env bash
# tests/acceptance/TASK-086-outillage.sh — les deux outils du conducteur
# (verifier-travail.sh, clore-tache.sh) et la branche documentaire de juger.sh (A172).
#
# Rien n'est écrit dans le dépôt : les cas qui ont besoin d'un dépôt travaillent
# soit sur un dépôt jouet créé dans un répertoire temporaire, soit sur un worktree
# détaché, retiré à la sortie. Les cas de non-régression de juger.sh restent sur les
# chemins qui ne démarrent aucun conteneur (périmètre Ansible, fiche documentaire) ;
# le périmètre Bash, qui lance le conteneur, est prouvé à part, au rapport.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

OUTILS="$SCRIPTS_ROOT/orchestration/outils"
TMP="$(mktemp -d)"
worktree=""
nettoyer() {
    [ -z "$worktree" ] || git -C "$SCRIPTS_ROOT" worktree remove --force "$worktree" > /dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap nettoyer EXIT

# racine_jouet <chemin> — une arborescence minimale portant les outils à éprouver.
racine_jouet() {
    mkdir -p "$1/orchestration/outils" "$1/tasks/active" "$1/Docker" "$1/tests/integration"
    cp "$OUTILS/juger.sh" "$OUTILS/verifier-travail.sh" "$1/orchestration/outils/"
}

# code_de <fichier de sortie> <commande...> — le code réel, sortie capturée.
code_de() {
    local sortie="$1"; shift
    local c=0
    "$@" > "$sortie" 2>&1 || c=$?
    echo "$c"
}

titre "juger.sh — branche documentaire (A172)"
jouet="$TMP/jouet"
racine_jouet "$jouet"

cat > "$jouet/tasks/active/TASK-901.md" <<'FICHE'
---
id: TASK-901
scope:
  - Docker/CADRAGE.md — lignes « Prouvé par »
  - Kubernetes/CADRAGE.md — lignes « Prouvé par »
validation:
  - "true"
---
FICHE
c="$(code_de "$TMP/s1" bash "$jouet/orchestration/outils/juger.sh" tasks/active/TASK-901.md)"
assert_egal 0 "$c" "fiche documentaire : code 0"
assert_contient "$(cat "$TMP/s1")" "SANS OBJET" "fiche documentaire : verdict « sans objet »"

cat > "$jouet/tasks/active/TASK-902.md" <<'FICHE'
---
id: TASK-902
scope:
out_of_scope:
  - rien
---
FICHE
c="$(code_de "$TMP/s2" bash "$jouet/orchestration/outils/juger.sh" tasks/active/TASK-902.md)"
assert_egal 1 "$c" "scope vide : code 1"
assert_contient "$(cat "$TMP/s2")" "périmètre vide" "scope vide : le défaut est nommé"

cat > "$jouet/tasks/active/TASK-903.md" <<'FICHE'
---
id: TASK-903
scope:
  - Docker/Cleanup/absent.sh — un script du périmètre
  - tests/integration/absent.test.sh — son fichier de cas
---
FICHE
c="$(code_de "$TMP/s3" bash "$jouet/orchestration/outils/juger.sh" tasks/active/TASK-903.md)"
assert_egal 1 "$c" "périmètre Bash : code 1 inchangé, la branche documentaire ne l'absorbe pas"
assert_contient "$(cat "$TMP/s3")" "fichier absent" "périmètre Bash : le fichier manquant est nommé"

c="$(code_de "$TMP/s4" bash "$OUTILS/juger.sh" tasks/completed/TASK-081.md)"
assert_egal 0 "$c" "non-régression Ansible : TASK-081 rend toujours 0"
assert_contient "$(cat "$TMP/s4")" "scénario Molecule" "non-régression Ansible : verdict Molecule"

c="$(code_de "$TMP/s5" bash "$OUTILS/juger.sh" tasks/completed/TASK-083.md)"
assert_egal 0 "$c" "TASK-083, la fiche qui a révélé A172 : code 0"

titre "verifier-travail.sh — périmètre"
depot="$TMP/depot"
racine_jouet "$depot"
git init -q "$depot"
git -C "$depot" symbolic-ref HEAD refs/heads/master
git -C "$depot" config user.email "cas@exemple.test"
git -C "$depot" config user.name "Cas"
git -C "$depot" config core.autocrlf false
cat > "$depot/tasks/active/TASK-904.md" <<'FICHE'
---
id: TASK-904
scope:
  - Docker/exemple.sh — le script de la tâche
validation:
  - "true"
---
FICHE
git -C "$depot" add -A && git -C "$depot" commit -qm "socle"
git -C "$depot" checkout -q -b agent/TASK-904
echo "#!/usr/bin/env bash" > "$depot/Docker/exemple.sh"
git -C "$depot" add -A && git -C "$depot" commit -qm "premier jet"
c="$(code_de "$TMP/s6" bash "$depot/orchestration/outils/verifier-travail.sh" TASK-904 --perimetre)"
assert_egal 0 "$c" "périmètre conforme : code 0"

echo "cas" > "$depot/tests/integration/exemple.test.sh"
git -C "$depot" add -A && git -C "$depot" commit -qm "fichier de cas"
c="$(code_de "$TMP/s7" bash "$depot/orchestration/outils/verifier-travail.sh" TASK-904 --perimetre)"
assert_egal 0 "$c" "fichier de cas ajouté hors scope : admis comme preuve"
assert_contient "$(cat "$TMP/s7")" "PREUVE" "fichier de cas : compté à part"

mkdir -p "$depot/Linux"
echo "hors" > "$depot/Linux/intrus.sh"
git -C "$depot" add -A && git -C "$depot" commit -qm "débordement"
c="$(code_de "$TMP/s8" bash "$depot/orchestration/outils/verifier-travail.sh" TASK-904 --perimetre)"
assert_egal 1 "$c" "fichier hors scope : code 1"
assert_contient "$(cat "$TMP/s8")" "hors périmètre" "fichier hors scope : nommé"

# Sur données réelles : le premier jet de TASK-085, branche déjà fusionnée, d'où --base.
if git -C "$SCRIPTS_ROOT" rev-parse --verify -q "7be628a^{commit}" > /dev/null; then
    c="$(code_de "$TMP/s9" bash "$OUTILS/verifier-travail.sh" TASK-085 \
        --ref 7be628a --base 7f75838 --perimetre)"
    assert_egal 0 "$c" "premier jet de TASK-085 : périmètre conforme"
else
    saute "premier jet de TASK-085 : commit 7be628a absent de ce dépôt"
fi

titre "clore-tache.sh — clôture de TASK-083 rejouée"
if git -C "$SCRIPTS_ROOT" rev-parse --verify -q "2bb9dc0^{commit}" > /dev/null \
    && git -C "$SCRIPTS_ROOT" worktree add -q --detach "$TMP/cloture" aefd205 > /dev/null 2>&1; then
    worktree="$TMP/cloture"
    cp "$OUTILS/clore-tache.sh" "$worktree/orchestration/outils/"
    git -C "$worktree" checkout -q 2bb9dc0 -- tasks/reports/TASK-083-report.md tasks/pending/TASK-039.md
    git -C "$SCRIPTS_ROOT" show 2bb9dc0 -- orchestration/mesures/journal.md \
        | sed -n 's/^+\(| TASK-083 .*\)$/\1/p' > "$TMP/journal.txt"
    git -C "$SCRIPTS_ROOT" show 2bb9dc0 -- orchestration/mesures/agents.tsv \
        | sed -n 's/^+\(2026.*\)$/\1/p' > "$TMP/mesures.tsv"
    assert_egal 1 "$(wc -l < "$TMP/journal.txt")" "ligne de journal extraite du commit réel"

    # Contrôle avant de clore : un Axx cité en réserve et absent du registre arrête tout.
    sed -i 's/ (A172)\./ (A172, A999)./' "$worktree/tasks/reports/TASK-083-report.md"
    c="$(code_de "$TMP/s10" bash "$worktree/orchestration/outils/clore-tache.sh" TASK-083 \
        --journal "$TMP/journal.txt" --mesures "$TMP/mesures.tsv")"
    assert_egal 1 "$c" "réserve A999 hors registre : code 1"
    assert_contient "$(cat "$TMP/s10")" "rien n'a été écrit" "réserve absente : aucune écriture"
    assert_egal "oui" "$([ -f "$worktree/tasks/active/TASK-083.md" ] && echo oui)" \
        "réserve absente : la fiche reste dans active/"

    git -C "$worktree" checkout -q 2bb9dc0 -- tasks/reports/TASK-083-report.md
    c="$(code_de "$TMP/s11" bash "$worktree/orchestration/outils/clore-tache.sh" TASK-083 \
        --journal "$TMP/journal.txt" --mesures "$TMP/mesures.tsv")"
    assert_egal 0 "$c" "clôture rejouée : code 0"
    assert_egal "" "$(git -C "$worktree" diff --name-only 2bb9dc0)" \
        "clôture rejouée : aucun écart avec la clôture réelle (2bb9dc0)"
    assert_contient "$(cat "$TMP/s11")" "LIENS  verifier-liens.sh : 0" "clôture rejouée : liens à 0"
else
    saute_indisponible "clôture rejouée : worktree jetable ou commit 2bb9dc0 indisponible"
fi

bilan "TASK-086"
