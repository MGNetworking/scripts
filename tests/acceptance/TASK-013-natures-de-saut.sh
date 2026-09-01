#!/usr/bin/env bash
# tests/acceptance/TASK-013-natures-de-saut.sh — critères de TASK-013.
#
# TASK-013 ne change aucun comportement de script d'administration : elle change
# ce qu'un SAUT vaut. Jusqu'ici, « le conteneur n'a pas systemd » et « le démon
# Docker est mort » tombaient dans le même compteur, et un fichier de cas dont
# 72 % de la preuve s'était évaporée sortait en 4 — donc en 0 au bout de la
# chaîne. Ce fichier prouve que ce n'est plus le cas, et que rien d'autre n'a
# bougé.
#
# Ce qu'il faut prouver n'est donc pas « le script fait ce qu'il annonce », mais
# « le verdict dit la vérité », y compris dans le cas où il serait le plus
# commode de mentir. D'où la §6 : le faux vert d'origine est REPRODUIT ici, avec
# l'ancien modèle de bilan, avant d'être montré fermé par le nouveau. Sans ce
# témoin, rien ne dirait que c'est bien le garde ajouté qui ferme la porte.
#
# Trois contraintes de forme, héritées de TASK-012 et toujours valables :
#
#   1. RÉCURSION. Ce fichier est découvert par run-acceptance.sh. Appeler
#      « tests/run.sh acceptance » depuis ici se rappellerait sans fin. Le
#      critère central — « démon coupé → code non nul » — est donc éprouvé sur
#      une COPIE EXACTE du harnais, dans un bac à sable, et vérifié à la main
#      sur le dépôt réel (§13) ;
#   2. POLLUTION. run-acceptance.sh découvre tout tests/acceptance/TASK-*.sh :
#      aucun fichier jetable n'est déposé dans le dépôt, même une seconde. Le
#      §12 le vérifie plutôt que de le supposer ;
#   3. DÉMON DOCKER. Il n'est jamais arrêté. L'indisponibilité est simulée par
#      DOCKER_HOST pointant sur un port fermé — le client répond, le démon non.
#
# Ce fichier sort en 4 : deux de ses cas ne sont pas applicables par nature
# (§13). C'est admis, et c'est le verdict que TASK-013 elle-même définit pour
# cette situation. Il sort en 3 si le démon Docker ne répond pas — le §8 ne peut
# alors pas être produit, et c'est une indisponibilité d'environnement, pas une
# limite de nature.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
# shellcheck source=/dev/null
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

RUN="$SCRIPTS_ROOT/tests/run.sh"
DISPATCHER="$SCRIPTS_ROOT/tests/acceptance/run-acceptance.sh"
LINT="$SCRIPTS_ROOT/tests/lint.sh"
ASSERT="$SCRIPTS_ROOT/tests/lib/assert.sh"
DOC="$SCRIPTS_ROOT/tests/README.md"

# Les fichiers de cas dont TASK-013 a qualifié les sauts, et le fichier de cas
# conteneurisé qui leur fournit la nature des siens.
CAS_REELS="
tests/acceptance/TASK-002-environnement-conteneurise.sh
tests/acceptance/TASK-011-analyse-statique.sh
tests/acceptance/TASK-012-semantique-codes.sh
"
CAS_DOCKER="$SCRIPTS_ROOT/tests/acceptance/TASK-002-environnement-conteneurise.sh"
CAS_INTERNE="$SCRIPTS_ROOT/tests/acceptance/interne/TASK-011-cas-conteneur.sh"

# Démon injoignable : le client est là, le port est fermé. Substitut fidèle de
# « Docker Desktop arrêté », sans l'arrêter.
HOTE_MORT="tcp://127.0.0.1:1"

REP_TMP="$(mktemp -d)"
BAC="$REP_TMP/bac"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

nettoyer() {
    rm -rf "$REP_TMP"
}
trap nettoyer EXIT

# -------------------------------------------------------------------
# Exécution isolée
# -------------------------------------------------------------------
# Le sous-shell est indispensable : les scripts du dépôt tournent sous
# set -Eeuo pipefail et lib/common.sh pose un trap ERR. « || CODE=$? » n'arme
# pas le trap de CE fichier, la commande n'étant pas la dernière d'une liste ||.
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" || CODE=$?
}

# assert_code_fichier <attendu> <libellé> — sur le CODE de la dernière commande.
assert_code_fichier() {
    assert_code "$1" "$CODE" "$2"
}

# Sonde du démon, BORNÉE dans le temps.
#
# Les autres fichiers de cas appellent « docker info » sans garde. C'est sans
# conséquence quand le démon est arrêté — le client rend la main aussitôt — mais
# un Docker Desktop en cours de démarrage laisse l'appel suspendu sur le tube
# nommé, plusieurs minutes durant. Constaté le 2026-09-01. Un fichier de cas ne
# doit pas pouvoir suspendre le niveau : d'où « timeout », quand il existe.
sonde_docker() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 30 docker info --format '{{.ServerVersion}}' 2>/dev/null || true
    else
        docker info --format '{{.ServerVersion}}' 2>/dev/null || true
    fi
}

# -------------------------------------------------------------------
# Disponibilité de l'environnement
# -------------------------------------------------------------------
for f in "$RUN" "$DISPATCHER" "$LINT" "$ASSERT" "$DOC"; do
    [ -f "$f" ] || die "Fichier introuvable : $f" 1
done

DOCKER_UTILISABLE="false"
if command -v docker >/dev/null 2>&1; then
    version_serveur="$(sonde_docker)"
    if [ -n "$version_serveur" ]; then
        DOCKER_UTILISABLE="true"
        info "Démon Docker disponible — version serveur $version_serveur"
    fi
fi
if [ "$DOCKER_UTILISABLE" = "false" ]; then
    warn "Le démon Docker ne répond pas : l'environnement complet ne peut pas être constaté ici."
fi

# -------------------------------------------------------------------
# Bac à sable
# -------------------------------------------------------------------
# Copie EXACTE du harnais dans un répertoire temporaire. SCRIPTS_ROOT étant
# résolu à partir de l'emplacement de lib/common.sh, les copies s'y enracinent
# d'elles-mêmes et ne voient que les fichiers de cas jetables qu'on y dépose.
#
# tests/lib/ ne reçoit QUE assert.sh. Y déposer un common.sh détournerait la
# résolution en trois lignes de tous les fichiers du bac : le premier candidat
# testé depuis tests/acceptance/ est justement tests/lib/common.sh.
mkdir -p "$BAC/lib" "$BAC/tests/lib" "$BAC/tests/acceptance/interne"
cp "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"
cp "$RUN"        "$BAC/tests/run.sh"
cp "$LINT"       "$BAC/tests/lint.sh"
cp "$DISPATCHER" "$BAC/tests/acceptance/run-acceptance.sh"
cp "$ASSERT"     "$BAC/tests/lib/assert.sh"

BAC_RUN="$BAC/tests/run.sh"
BAC_DISPATCHER="$BAC/tests/acceptance/run-acceptance.sh"
BAC_CAS="$BAC/tests/acceptance"

# Modèle de fichier de cas jetable, écrit sur tests/lib/assert.sh — donc sur le
# bilan réel du dépôt, et non sur une imitation. Compteurs fixés d'avance :
# @R@ réussites, @E@ échecs, @A@ non applicables par nature, @I@ indisponibles.
MODELE="$(cat <<'CAS'
#!/usr/bin/env bash
# Fichier de cas JETABLE, écrit par TASK-013 dans un bac à sable temporaire.
# Il ne vérifie rien : ses compteurs sont fixés d'avance pour éprouver le bilan,
# le dispatcher et tests/run.sh.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$_dir/tests/lib/assert.sh"

i=0
while [ "$i" -lt @R@ ]; do ok "cas vérifié"; i=$((i + 1)); done
i=0
while [ "$i" -lt @E@ ]; do ko "cas en défaut" "détail"; i=$((i + 1)); done
i=0
while [ "$i" -lt @A@ ]; do saute_par_nature "cas hors d'atteinte" "le profil debian n'a pas systemd"; i=$((i + 1)); done
i=0
while [ "$i" -lt @I@ ]; do saute_indisponible "cas non produit" "le démon Docker ne répond pas"; i=$((i + 1)); done

bilan "TASK-@NOM@"
CAS
)"

# Modèle de fichier de cas jetable employant « saute » NU — sans qualification.
# C'est la forme des quelque soixante-dix sauts de tests/unit/ et
# tests/integration/ que personne n'a encore relus. Ce qu'il faut en prouver
# tient en deux points : l'écran ne leur invente pas de nature, et le verdict
# reste celui qu'il était.
MODELE_NEUTRE="$(cat <<'CAS'
#!/usr/bin/env bash
# Fichier de cas JETABLE, écrit par TASK-013 : un saut non qualifié.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$_dir/tests/lib/assert.sh"

ok "un cas qui a tourné"
ok "un autre cas qui a tourné"
saute "cas non relu" "propriété de cette machine, pas limite de nature"

bilan "TASK-@NOM@"
CAS
)"

# Modèle de fichier de cas jetable écrit sur l'ANCIEN bilan — celui de
# tests/README.md §5 avant TASK-013, à trois compteurs. Il sert de témoin au §6 :
# c'est lui qui reproduit le faux vert, et lui seul.
MODELE_ANCIEN="$(cat <<'CAS'
#!/usr/bin/env bash
# Fichier de cas JETABLE reproduisant l'ANCIEN bilan à trois compteurs, tel
# qu'il était avant TASK-013. Témoin du faux vert — ne pas copier.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

reussites=@R@
non_executes=@N@

info "Bilan TASK-@NOM@ : $reussites vérification(s) réussie(s), 0 échec(s), $non_executes NON EXÉCUTÉ(s)"

if [ "$reussites" -eq 0 ]; then
    warn "TASK-@NOM@ : aucune vérification n'a pu être exécutée — rien n'est prouvé."
    exit 3
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-@NOM@ : $non_executes vérification(s) NON EXÉCUTÉE(s)."
    exit 4
fi

success "TASK-@NOM@ : tous les critères vérifiés."
CAS
)"

# Fichier de cas jetable qui INTERROGE RÉELLEMENT le démon Docker. C'est la
# forme d'un fichier de cas réel : quelques vérifications de préflight, qui
# n'ont besoin de rien, puis des cas qui exigent le démon.
MODELE_DOCKER="$(cat <<'CAS'
#!/usr/bin/env bash
# Fichier de cas JETABLE, écrit par TASK-013 : il reproduit la forme d'un
# fichier de cas réel — du préflight qui passe toujours, et des cas qui exigent
# le démon Docker.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$_dir/tests/lib/assert.sh"

titre "Préflight — n'a besoin d'aucun environnement"
ok "l'aide s'affiche"
ok "une option inconnue sort en 2"
ok "un profil inexistant sort en 2"

utilisable="false"
if command -v docker >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
        version="$(timeout 30 docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"
    else
        version="$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"
    fi
    [ -n "$version" ] && utilisable="true"
fi

titre "Comportement — exige le démon"
i=0
while [ "$i" -lt 8 ]; do
    if [ "$utilisable" = "true" ]; then
        ok "cas conteneurisé n° $i"
    else
        saute_indisponible "cas conteneurisé n° $i" "le démon Docker ne répond pas"
    fi
    i=$((i + 1))
done

titre "Hors de portée par nature"
saute_par_nature "cas systemd" "le profil debian n'a pas systemd et ne l'aura jamais"

bilan "TASK-@NOM@"
CAS
)"

# poser_cas <nom> <réussites> <échecs> <non-applicables> <indisponibles>
poser_cas() {
    local nom="$1" r="$2" e="$3" a="$4" ind="$5"
    local cible="$BAC_CAS/TASK-$nom.sh"
    printf '%s\n' "$MODELE" \
        | sed -e "s/@NOM@/$nom/g" -e "s/@R@/$r/g" -e "s/@E@/$e/g" \
              -e "s/@A@/$a/g" -e "s/@I@/$ind/g" > "$cible"
    printf '%s\n' "$cible"
}

# poser_cas_neutre <nom> — deux réussites et un « saute » non qualifié.
poser_cas_neutre() {
    local nom="$1"
    local cible="$BAC_CAS/TASK-$nom.sh"
    printf '%s\n' "$MODELE_NEUTRE" | sed -e "s/@NOM@/$nom/g" > "$cible"
    printf '%s\n' "$cible"
}

# poser_cas_ancien <nom> <réussites> <non-exécutés>
poser_cas_ancien() {
    local nom="$1" r="$2" n="$3"
    local cible="$BAC_CAS/TASK-$nom.sh"
    printf '%s\n' "$MODELE_ANCIEN" \
        | sed -e "s/@NOM@/$nom/g" -e "s/@R@/$r/g" -e "s/@N@/$n/g" > "$cible"
    printf '%s\n' "$cible"
}

poser_cas_docker() {
    local nom="$1"
    local cible="$BAC_CAS/TASK-$nom.sh"
    printf '%s\n' "$MODELE_DOCKER" | sed -e "s/@NOM@/$nom/g" > "$cible"
    printf '%s\n' "$cible"
}

vider_cas() {
    rm -f "$BAC_CAS"/TASK-*.sh "$BAC_CAS"/interne/TASK-*.sh
}

# ligne_de <fichier> <motif-grep> — numéro de la DERNIÈRE ligne correspondante,
# vide si le motif est absent.
#
# La dernière, et non la première : deux des fichiers de cas réels embarquent le
# texte d'un fichier de cas jetable, bilan compris, pour éprouver le dispatcher.
# Le premier « if [ "$reussites" -eq 0 ] » d'un tel fichier appartient donc au
# modèle, pas au fichier. Le bilan d'un fichier de cas est son dernier bloc :
# c'est celui-là qu'on veut mesurer.
ligne_de() {
    grep -n -- "$2" "$1" 2>/dev/null | tail -n 1 | cut -d: -f1
}

# ===================================================================
# 1. Le bac à sable teste bien le code du dépôt
# ===================================================================
titre "1. Fidélité du bac à sable"

if cmp -s "$RUN" "$BAC_RUN" && cmp -s "$DISPATCHER" "$BAC_DISPATCHER" \
   && cmp -s "$LINT" "$BAC/tests/lint.sh" \
   && cmp -s "$ASSERT" "$BAC/tests/lib/assert.sh" \
   && cmp -s "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"; then
    ok "les cinq scripts du bac à sable sont identiques à ceux du dépôt"
else
    ko "le bac à sable diverge du dépôt" "les verdicts qui suivent ne vaudraient rien"
fi

if [ -e "$BAC/tests/lib/common.sh" ]; then
    ko "le bac à sable contient tests/lib/common.sh" "il détournerait la résolution en trois lignes"
else
    ok "le bac à sable ne contient pas de tests/lib/common.sh"
fi

# ===================================================================
# 2. Un saut se déclare avec sa nature
# ===================================================================
titre "2. Trois déclarations distinctes"

if grep -q '^saute() {' "$ASSERT" && grep -q '^saute_par_nature() {' "$ASSERT" \
   && grep -q '^saute_indisponible() {' "$ASSERT"; then
    ok "tests/lib/assert.sh expose « saute », « saute_par_nature » et « saute_indisponible »"
else
    ko "tests/lib/assert.sh n'expose pas les trois déclarations de saut"
fi

# Chacune alimente son propre compteur, et le total commun.
corps_saute="$(sed -n '/^saute() {/,/^}/p' "$ASSERT")"
corps_nature="$(sed -n '/^saute_par_nature() {/,/^}/p' "$ASSERT")"
corps_indispo="$(sed -n '/^saute_indisponible() {/,/^}/p' "$ASSERT")"
assert_contient "$corps_saute" "non_applicables=\$((non_applicables + 1))" \
    "« saute » incrémente le compteur des non applicables"
assert_absent "$corps_saute" "indisponibilites=\$((" \
    "« saute » ne touche pas au compteur des indisponibilités"
assert_contient "$corps_nature" "non_applicables=\$((non_applicables + 1))" \
    "« saute_par_nature » incrémente le même compteur que « saute »"
assert_absent "$corps_nature" "indisponibilites=\$((" \
    "« saute_par_nature » ne touche pas au compteur des indisponibilités"
assert_contient "$corps_indispo" "indisponibilites=\$((indisponibilites + 1))" \
    "« saute_indisponible » incrémente le compteur des indisponibilités"
assert_contient "$corps_saute" "non_executes=\$((non_executes + 1))" \
    "« saute » alimente aussi le total"
assert_contient "$corps_nature" "non_executes=\$((non_executes + 1))" \
    "« saute_par_nature » alimente aussi le total"
assert_contient "$corps_indispo" "non_executes=\$((non_executes + 1))" \
    "« saute_indisponible » alimente aussi le total"

# La nature figure dans le message QUAND ELLE A ÉTÉ ÉTABLIE : un saut lu dans un
# journal se qualifie alors sans avoir à retrouver la ligne de code qui l'a
# produit.
vider_cas
fichier="$(poser_cas "930-natures" 1 0 1 1)"
lancer bash "$fichier"
assert_contient "$(cat "$F_ERR")" "NON EXÉCUTÉ (non applicable par nature)" \
    "le message d'un saut par nature nomme sa nature"
assert_contient "$(cat "$F_ERR")" "NON EXÉCUTÉ (environnement indisponible)" \
    "le message d'une indisponibilité nomme sa nature"
vider_cas

# Et le message NE LA NOMME PAS quand elle ne l'a pas été. « saute » sert les
# quelque soixante-dix sauts de tests/unit/ et tests/integration/ qui n'ont pas
# été relus un par un : plusieurs tiennent à une propriété de la machine —
# /etc/os-release illisible, harnais lancé sous root — et non à une limite de
# nature. Leur faire dire « non applicable par nature » serait requalifier par
# défaut, et l'afficher. Le compteur, lui, ne bouge pas : le verdict d'aucun
# fichier existant ne change.
assert_contient "$corps_saute" 'warn "NON EXÉCUTÉ : ' \
    "« saute » affiche un libellé neutre"
assert_absent "$corps_saute" "NON EXÉCUTÉ (non applicable par nature)" \
    "« saute » n'affirme aucune nature qu'il n'a pas établie"
assert_contient "$corps_nature" 'warn "NON EXÉCUTÉ (non applicable par nature) : ' \
    "« saute_par_nature » nomme la nature qu'il déclare"

vider_cas
fichier="$(poser_cas_neutre "933-neutre")"
lancer bash "$fichier"
assert_contient "$(cat "$F_ERR")" "NON EXÉCUTÉ : cas non relu" \
    "à l'exécution, un « saute » nu reste neutre à l'écran"
assert_absent "$(cat "$F_ERR")" "non applicable par nature) : cas non relu" \
    "à l'exécution, un « saute » nu ne se qualifie pas tout seul"
assert_code_fichier 4 "un « saute » nu rend le même verdict qu'avant : 4"
vider_cas

# ===================================================================
# 3. Verdict d'un fichier de cas selon la nature de ses sauts
# ===================================================================
# C'est la brique de base : si le bilan ne traduit pas correctement les
# compteurs, tout ce qui s'agrège au-dessus est faux.
titre "3. Verdict d'un fichier de cas"

vider_cas
fichier="$(poser_cas "931-tout-reussi" 4 0 0 0)"
lancer bash "$fichier"
assert_code_fichier 0 "4 réussites, aucun saut → 0"

fichier="$(poser_cas "932-nature" 3 0 2 0)"
lancer bash "$fichier"
assert_code_fichier 4 "3 réussites, 2 non applicables par nature → 4"

fichier="$(poser_cas "933-indispo" 3 0 0 1)"
lancer bash "$fichier"
assert_code_fichier 3 "3 réussites, 1 indisponibilité → 3, ni 0 ni 4"
assert_contient "$(cat "$F_ERR")" "rien n'est prouvé de fiable" \
    "le fichier dit pourquoi il ne conclut pas"

# Le cas décisif : la preuve est massive, une seule pièce manque par accident.
fichier="$(poser_cas "934-presque-tout" 28 0 0 1)"
lancer bash "$fichier"
assert_code_fichier 3 "28 réussites et 1 indisponibilité → 3 : le nombre de réussites ne rachète rien"

# Les deux natures se côtoient : la plus grave l'emporte.
fichier="$(poser_cas "935-melange" 5 0 3 2)"
lancer bash "$fichier"
assert_code_fichier 3 "3 non applicables et 2 indisponibilités → 3"

fichier="$(poser_cas "936-sterile" 0 0 0 4)"
lancer bash "$fichier"
assert_code_fichier 3 "aucune réussite, 4 indisponibilités → 3"

fichier="$(poser_cas "937-echec" 2 1 0 3)"
lancer bash "$fichier"
assert_code_fichier 1 "un échec parmi des indisponibilités → 1 : l'échec prime sur tout"
vider_cas

# ===================================================================
# 4. Les deux natures sont affichées séparément
# ===================================================================
titre "4. Décompte des deux natures au bilan"

vider_cas
fichier="$(poser_cas "938-decompte" 2 0 3 4)"
lancer bash "$fichier"
assert_contient "$(cat "$F_ERR")" "7 NON EXÉCUTÉ(s)" \
    "le bilan publie le total des cas non exécutés"
assert_contient "$(cat "$F_ERR")" "3 sans indisponibilité déclarée" \
    "le bilan publie le décompte des sauts hors indisponibilité, sans leur inventer de nature"
assert_contient "$(cat "$F_ERR")" "4 indisponibilité(s) d'environnement" \
    "le bilan publie le décompte des indisponibilités"
vider_cas

# ===================================================================
# 5. Agrégation — le dispatcher et tests/run.sh
# ===================================================================
titre "5. Agrégation des verdicts"

vider_cas
poser_cas "940-a" 3 0 0 0 >/dev/null
poser_cas "940-b" 2 0 2 0 >/dev/null
lancer bash "$BAC_DISPATCHER"
assert_code_fichier 4 "un fichier satisfait et un fichier aux sauts par nature → 4"

vider_cas
poser_cas "941-vert" 5 0 0 0 >/dev/null
poser_cas "941-indispo" 3 0 0 1 >/dev/null
lancer bash "$BAC_DISPATCHER"
assert_code_fichier 3 "une indisponibilité parmi des fichiers verts → 3 : le lot ne rachète rien"
assert_contient "$(cat "$F_ERR")" "RIEN N'A PU ÊTRE VÉRIFIÉ" \
    "le dispatcher nomme le fichier sans preuve fiable"

vider_cas
poser_cas "942-nature" 4 0 2 0 >/dev/null
lancer bash "$BAC_RUN" acceptance
assert_code_fichier 0 "niveau aux seuls sauts par nature → 0, le 4 reste traduit en réussite"
assert_contient "$(cat "$F_ERR")" "cas non applicables à cet environnement" \
    "tests/run.sh décompte à l'écran les sauts qu'il laisse passer"

vider_cas
poser_cas "943-indispo" 4 0 0 2 >/dev/null
lancer bash "$BAC_RUN" acceptance
assert_code_fichier 3 "niveau comportant une indisponibilité → 3, jamais 0"
assert_contient "$(cat "$F_ERR")" "rien n'est prouvé" "tests/run.sh dit que rien n'est prouvé"
vider_cas

# ===================================================================
# 6. Le faux vert d'origine — reproduit, puis fermé
# ===================================================================
# Sans ce témoin, rien ne dirait que c'est bien le garde ajouté par TASK-013 qui
# ferme la porte : les cas du §5 pourraient passer pour d'autres raisons. Le
# fichier de cas de ce paragraphe reproduit l'ANCIEN bilan à trois compteurs,
# avec les chiffres exacts mesurés au §3 de docs/points-en-suspens.md.
titre "6. Le faux vert d'origine"

vider_cas
fichier="$(poser_cas_ancien "950-ancien" 8 21)"
lancer bash "$fichier"
assert_code_fichier 4 "ancien bilan, 8 réussites pour 21 sauts → 4 (le défaut, tel qu'il était)"

lancer bash "$BAC_RUN" acceptance
assert_code_fichier 0 "ancien bilan : 72 % de la preuve envolée, verdict global 0 (le faux vert)"

# Le même fichier, mêmes chiffres, avec les sauts qualifiés en indisponibilité.
vider_cas
fichier="$(poser_cas "951-qualifie" 8 0 0 21)"
lancer bash "$fichier"
assert_code_fichier 3 "mêmes chiffres, sauts qualifiés → 3"

lancer bash "$BAC_RUN" acceptance
assert_code_fichier 3 "mêmes chiffres, sauts qualifiés : verdict global 3 — le faux vert est fermé"
vider_cas

# ===================================================================
# 7. Démon Docker coupé → tests/run.sh acceptance en code non nul
# ===================================================================
# Le critère décisif de TASK-013, éprouvé sur un fichier de cas qui interroge
# RÉELLEMENT le démon — pas sur des compteurs fixés d'avance.
#
# DOCKER_HOST pointe sur un port fermé : le client répond, le démon non. Docker
# Desktop n'est jamais arrêté. Ce cas est donc valable que le démon de la
# machine tourne ou non.
titre "7. Démon Docker coupé"

if ! command -v docker >/dev/null 2>&1; then
    saute_indisponible "démon coupé → code non nul" "docker n'est pas dans le PATH, la simulation n'a pas de sens"
else
    vider_cas
    fichier="$(poser_cas_docker "960-docker")"

    lancer env DOCKER_HOST="$HOTE_MORT" bash "$fichier"
    assert_code_fichier 3 "démon coupé : le fichier de cas sort en 3"
    assert_contient "$(cat "$F_ERR")" "8 indisponibilité(s) d'environnement" \
        "démon coupé : les huit cas conteneurisés sont comptés comme indisponibles"
    assert_contient "$(cat "$F_ERR")" "1 sans indisponibilité déclarée" \
        "démon coupé : le cas systemd reste compté hors indisponibilité, il ne dépend pas du démon"

    lancer env DOCKER_HOST="$HOTE_MORT" bash "$BAC_DISPATCHER"
    assert_code_fichier 3 "démon coupé : le niveau acceptance sort en 3"

    lancer env DOCKER_HOST="$HOTE_MORT" bash "$BAC_RUN" acceptance
    assert_code_non_nul "$CODE" "démon coupé : tests/run.sh acceptance sort en code non nul"
    assert_code_fichier 3 "démon coupé : ce code non nul est 3, et non 1 — rien n'est en défaut"
    vider_cas
fi

# ===================================================================
# 8. Environnement complet → aucun verdict ne change
# ===================================================================
# L'autre moitié du contrat, et la plus facile à oublier : un harnais qui
# rougirait dès qu'un saut existe serait aussi inutile qu'un harnais qui verdit
# toujours. Le MÊME fichier de cas qu'au §7, sans DOCKER_HOST truqué.
titre "8. Environnement complet"

if [ "$DOCKER_UTILISABLE" = "false" ]; then
    saute_indisponible "environnement complet → aucun changement de verdict" \
        "le démon Docker ne répond pas sur cette machine : l'environnement complet ne peut pas être constaté"
else
    vider_cas
    fichier="$(poser_cas_docker "961-docker")"

    lancer bash "$fichier"
    assert_code_fichier 4 "démon disponible : le fichier de cas sort en 4, pas en 3"
    assert_contient "$(cat "$F_ERR")" "0 indisponibilité(s) d'environnement" \
        "démon disponible : plus aucune indisponibilité"
    assert_contient "$(cat "$F_ERR")" "1 sans indisponibilité déclarée" \
        "démon disponible : le saut par nature demeure, compté hors indisponibilité — il ne dépend pas de l'environnement"

    lancer bash "$BAC_RUN" acceptance
    assert_code_fichier 0 "démon disponible : tests/run.sh acceptance sort en 0"
    vider_cas
fi

# Le même contrôle, sans dépendre du démon : un fichier dont TOUS les sauts sont
# qualifiés par nature rend le même verdict, démon coupé ou non. C'est ce qui
# garantit que les sauts « systemd », « swapon » et « paquet obsolète » des
# fichiers réels ne changeront pas d'avis selon l'humeur de Docker.
vider_cas
fichier="$(poser_cas "962-nature-seule" 6 0 3 0)"
lancer bash "$fichier"
assert_code_fichier 4 "sauts par nature, environnement quelconque → 4"
lancer env DOCKER_HOST="$HOTE_MORT" bash "$fichier"
assert_code_fichier 4 "sauts par nature, démon coupé → 4 encore : la nature ne dépend pas de l'environnement"
vider_cas

# ===================================================================
# 9. Les fichiers de cas réels déclarent la nature de leurs sauts
# ===================================================================
# Contrôle structurel, faute de pouvoir exécuter ces fichiers dans les deux
# environnements sans y passer l'après-midi. Ce qui est vérifié ici, c'est que
# la mécanique est en place et dans le bon ordre ; ce qu'elle donne à
# l'exécution est mesuré au §10 et déclaré au §13.
titre "9. Qualification des fichiers de cas réels"

for relatif in $CAS_REELS; do
    fichier="$SCRIPTS_ROOT/$relatif"
    court="$(basename "$relatif")"

    if [ ! -f "$fichier" ]; then
        saute_indisponible "qualification de $court" "fichier absent"
        continue
    fi

    if grep -q '^saute_indisponible() {' "$fichier"; then
        ok "$court — déclare « saute_indisponible »"
    else
        ko "$court — ne déclare pas « saute_indisponible »" "ses sauts n'ont pas de nature"
    fi

    # Ordre des gardes : échec, aucune réussite, indisponibilité, non
    # applicable. Sans cet ordre, un fichier presque entièrement sauté
    # ressortirait en 4.
    l_sterile="$(ligne_de "$fichier" 'reussites" -eq 0')"
    l_indispo="$(ligne_de "$fichier" 'indisponibilites" -gt 0')"
    l_partiel="$(ligne_de "$fichier" 'non_executes" -gt 0')"
    if [ -z "$l_sterile" ] || [ -z "$l_indispo" ] || [ -z "$l_partiel" ]; then
        ko "$court — bilan incomplet" "garde « aucune réussite », « indisponibilité » ou « cas sautés » introuvable"
    elif [ "$l_sterile" -lt "$l_indispo" ] && [ "$l_indispo" -lt "$l_partiel" ]; then
        ok "$court — gardes dans l'ordre : aucune réussite ($l_sterile) < indisponibilité ($l_indispo) < non applicable ($l_partiel)"
    else
        ko "$court — gardes dans le désordre" "lignes $l_sterile, $l_indispo, $l_partiel"
    fi

    if grep -q 'info "Bilan .*non_applicables non applicable.*indisponibilites indisponibilité' "$fichier"; then
        ok "$court — le bilan publie les deux natures séparément"
    else
        ko "$court — le bilan ne publie pas les deux natures" "voir tests/README.md §5"
    fi

    # Aucun saut dû au démon Docker ne doit rester déclaré « par nature » : un
    # démon arrêté n'est pas une limite de l'environnement de test, c'est un
    # accident. Ce contrôle est le seul qui porte sur la QUALIFICATION elle-même
    # et non sur la mécanique.
    #
    # Les deux formes sont cherchées. Ces trois fichiers déclarent leur « saute »
    # localement, avec le message qualifié, et leurs appels ont été relus ; le
    # jour où ils passeraient à « saute_par_nature » de tests/lib/assert.sh, le
    # motif suivrait au lieu de devenir aveugle.
    egares="$(grep -cE '^[[:space:]]*saute(_par_nature)? "[^"]*[Dd]émon Docker' "$fichier" || true)"
    if [ "$egares" -eq 0 ]; then
        ok "$court — aucun saut dû au démon Docker n'est déclaré « par nature »"
    else
        ko "$court — $egares saut(s) dus au démon Docker restent déclarés « par nature »" \
           "un démon arrêté est une indisponibilité, pas une limite de nature"
    fi
done

# Le fichier de cas conteneurisé qualifie ses propres sauts, et son appelant sait
# les lire. Sans ce couple, les onze sauts venus du conteneur arriveraient tous
# avec la même nature — celle que l'appelant aurait choisie pour eux.
if [ -f "$CAS_INTERNE" ]; then
    if grep -q "^skip_indisponible() {" "$CAS_INTERNE"; then
        ok "le fichier de cas conteneurisé déclare « skip_indisponible »"
    else
        ko "le fichier de cas conteneurisé ne déclare pas « skip_indisponible »" \
           "ses sauts arriveraient sans leur nature"
    fi
    if grep -q "RESULTAT|INDISPO|" "$CAS_INTERNE"; then
        ok "le fichier de cas conteneurisé émet le verdict INDISPO"
    else
        ko "le fichier de cas conteneurisé n'émet aucun verdict INDISPO"
    fi
    if grep -q 'INDISPO)[[:space:]]*saute_indisponible' "$SCRIPTS_ROOT/tests/acceptance/TASK-011-analyse-statique.sh"; then
        ok "TASK-011 relaie INDISPO vers « saute_indisponible »"
    else
        ko "TASK-011 ne relaie pas INDISPO" "la nature déclarée dans le conteneur serait perdue"
    fi
else
    saute_indisponible "qualification du fichier de cas conteneurisé" "fichier absent : $CAS_INTERNE"
fi

# ===================================================================
# 10. Mesure sur les fichiers de cas réels privés de leur environnement
# ===================================================================
# Le §7 prouve la mécanique sur un fichier jetable. Ici, ce sont les vrais
# fichiers du dépôt, privés du démon Docker — c'est le scénario du §3 de
# docs/points-en-suspens.md, rejoué.
#
# Ces deux fichiers ne lancent aucun conteneur quand le démon ne répond pas :
# la mesure coûte quelques secondes, pas les six minutes du niveau complet.
titre "10. Fichiers de cas réels, démon coupé"

if ! command -v docker >/dev/null 2>&1; then
    saute_indisponible "TASK-002 et TASK-011 privés du démon" "docker n'est pas dans le PATH"
else
    lancer env DOCKER_HOST="$HOTE_MORT" bash "$CAS_DOCKER"
    assert_code_fichier 3 "TASK-002 privé du démon sort en 3, et non en 4"
    assert_contient "$(cat "$F_ERR")" "indisponibilité(s) d'environnement" \
        "TASK-002 privé du démon publie le décompte de ses indisponibilités"

    lancer env DOCKER_HOST="$HOTE_MORT" bash "$SCRIPTS_ROOT/tests/acceptance/TASK-011-analyse-statique.sh"
    assert_code_fichier 3 "TASK-011 privé du démon sort en 3, et non en 4 — le cas mesuré au §3 des points en suspens"
fi

# ===================================================================
# 11. La sémantique est documentée
# ===================================================================
titre "11. Documentation"

contenu_doc="$(cat "$DOC")"
assert_contient "$contenu_doc" "non applicable par nature" \
    "README : la première nature est nommée"
assert_contient "$contenu_doc" "environnement indisponible" \
    "README : la seconde nature est nommée"
assert_contient "$contenu_doc" "Une seule indisponibilité fait" \
    "README : la règle « une seule indisponibilité suffit » est écrite"
assert_contient "$contenu_doc" "dans le doute, indisponibilité" \
    "README : la règle de prudence est écrite"
assert_contient "$contenu_doc" "saute_indisponible" \
    "README : la fonction de déclaration est documentée"
assert_contient "$contenu_doc" "indisponibilites\" -gt 0" \
    "README : le garde figure dans le modèle de bilan"

# ===================================================================
# 12. Hygiène — aucun fichier jetable dans le dépôt
# ===================================================================
# run-acceptance.sh découvre tout tests/acceptance/TASK-*.sh : un résidu
# polluerait chaque exécution ultérieure.
titre "12. Hygiène du répertoire de cas"

case "$REP_TMP" in
    "$SCRIPTS_ROOT"/*) ko "le bac à sable a été créé dans le dépôt : $REP_TMP" ;;
    *)                 ok "le bac à sable est hors du dépôt" ;;
esac

residus="$(find "$SCRIPTS_ROOT/tests/acceptance" -type f -name 'TASK-9*.sh' | sort || true)"
if [ -z "$residus" ]; then
    ok "aucun fichier de cas jetable dans tests/acceptance/"
else
    ko "fichiers jetables laissés dans le dépôt" "$(printf '%s' "$residus" | tr '\n' ' ')"
fi

# Ce fichier ne crée aucun conteneur : il n'en reste donc aucun. Le contrôle est
# fait quand même — c'est la règle du dépôt, et un jour quelqu'un en créera un.
if command -v docker >/dev/null 2>&1 && [ "$DOCKER_UTILISABLE" = "true" ]; then
    restants="$(docker ps -a --filter 'name=mgnet-test-' --format '{{.Names}}' 2>/dev/null || true)"
    if [ -z "$restants" ]; then
        ok "aucun conteneur mgnet-test- ne subsiste"
    else
        ko "des conteneurs mgnet-test- subsistent" "$(printf '%s' "$restants" | tr '\n' ' ')"
    fi
else
    saute_indisponible "absence de conteneur résiduel" "le démon Docker ne répond pas, l'inventaire est impossible"
fi

# ===================================================================
# 13. Ce que cet environnement ne permet pas de vérifier
# ===================================================================
titre "13. Hors de portée de cet environnement"

# NON APPLICABLE PAR NATURE, comme le §11 de TASK-012 : ce fichier est découvert
# par run-acceptance.sh. Lancer le niveau complet depuis ici s'appellerait sans
# fin. Aucun environnement ne lève cette limite — elle est structurelle.
saute_par_nature "tests/run.sh acceptance sur le dépôt réel, démon coupé puis démon vivant" \
    "récursion : ce fichier fait partie du niveau qu'il faudrait lancer ; la mesure est faite à la main, hors du niveau"

# NON APPLICABLE PAR NATURE également : prouver que les trois fichiers réels
# gardent leur verdict sur un environnement complet demanderait de les exécuter
# tous, donc de reconstruire les onze conteneurs de TASK-011 — six minutes, et
# depuis l'intérieur du niveau qu'ils composent. Le §8 en donne l'équivalent sur
# un fichier de même forme ; le §9 vérifie que la mécanique est en place.
saute_par_nature "verdict des trois fichiers de cas réels sur un environnement complet" \
    "il faudrait les exécuter depuis l'intérieur du niveau qu'ils composent, et reconstruire onze conteneurs"

# ===================================================================
# Bilan
# ===================================================================
bilan "TASK-013"
