#!/usr/bin/env bash
# tests/acceptance/TASK-012-semantique-codes.sh — critères de TASK-012.
#
# TASK-012 ne change aucun comportement de script d'administration : elle change
# la façon dont le harnais PRONONCE son verdict. Ce qu'il faut prouver n'est
# donc pas « le script fait ce qu'il annonce », mais « le code de retour dit la
# vérité », y compris dans le cas où il serait le plus commode de mentir :
# une suite intégralement sautée doit sortir en 3, jamais en 0.
#
# Deux contraintes de forme dictent tout ce fichier :
#
#   1. RÉCURSION. Ce fichier est lui-même découvert par run-acceptance.sh.
#      Appeler « tests/run.sh acceptance » depuis ici relancerait ce fichier,
#      indéfiniment. Le critère « tests/run.sh acceptance sort en 0 sur l'état
#      actuel du dépôt » est donc déclaré NON EXÉCUTÉ ici (§11) et vérifié à la
#      main, hors du niveau ;
#   2. POLLUTION. run-acceptance.sh découvre tout fichier tests/acceptance/
#      TASK-*.sh. Y déposer un fichier jetable — même une seconde — le ferait
#      entrer dans toutes les exécutions du dépôt, et un résidu passerait
#      inaperçu.
#
# D'où le bac à sable : une copie EXACTE de lib/common.sh, tests/run.sh,
# tests/lint.sh et tests/acceptance/run-acceptance.sh dans un répertoire
# temporaire. SCRIPTS_ROOT étant résolu à partir de l'emplacement de
# lib/common.sh, les copies s'y enracinent d'elles-mêmes et n'y voient que les
# fichiers de cas jetables qu'on y dépose. L'identité des copies avec les
# originaux est prouvée par cmp (§1) : sans cela, ce fichier prouverait la
# sémantique d'un code qui n'est pas celui du dépôt.
#
# Les fichiers de cas jetables reproduisent le bilan documenté dans
# tests/README.md §5, compteurs fixés d'avance. Ils ne vérifient rien : ils
# servent à éprouver le dispatcher, et lui seul.
#
# Les cas qui attendent un code non nul sont isolés dans un sous-shell : les
# scripts du dépôt tournent sous set -Eeuo pipefail et lib/common.sh pose un
# trap ERR.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

RUN="$SCRIPTS_ROOT/tests/run.sh"
DISPATCHER="$SCRIPTS_ROOT/tests/acceptance/run-acceptance.sh"
LINT="$SCRIPTS_ROOT/tests/lint.sh"
LANCEUR="$SCRIPTS_ROOT/tests/env/run-in-container.sh"
DOC="$SCRIPTS_ROOT/tests/README.md"

# Fichiers de cas réels, dont l'ordre du garde est contrôlé en §7.
CAS_REELS="
tests/acceptance/TASK-002-environnement-conteneurise.sh
tests/acceptance/TASK-011-analyse-statique.sh
"

REP_TMP="$(mktemp -d)"
BAC="$REP_TMP/bac"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

reussites=0
echecs=0
non_executes=0

nettoyer() {
    rm -rf "$REP_TMP"
}
trap nettoyer EXIT

# -------------------------------------------------------------------
# Assertions — Bash pur, aucun framework
# -------------------------------------------------------------------
titre() { info "--- $* ---"; }

ok() {
    success "$1"
    reussites=$((reussites + 1))
}

ko() {
    error "ÉCHEC : $1"
    if [ -s "$F_ERR" ]; then
        printf '        dernières lignes de la sortie :\n' >&2
        tail -n 4 "$F_ERR" | sed 's/^/        /' >&2
    fi
    echecs=$((echecs + 1))
}

saute() {
    warn "NON EXÉCUTÉ : $1 — $2"
    non_executes=$((non_executes + 1))
}

# Exécute une commande en capturant flux et code, sans armer le trap ERR.
lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" || CODE=$?
}

assert_code() {
    local attendu="$1" libelle="$2"
    if [ "$CODE" -eq "$attendu" ]; then
        ok "$libelle — code $CODE"
    else
        ko "$libelle — code attendu $attendu, obtenu $CODE"
    fi
}

assert_contient() {
    local fichier="$1" motif="$2" libelle="$3"
    if grep -qF -- "$motif" "$fichier"; then
        ok "$libelle"
    else
        ko "$libelle — motif absent : $motif"
    fi
}

assert_absent() {
    local fichier="$1" motif="$2" libelle="$3"
    if grep -qF -- "$motif" "$fichier"; then
        ko "$libelle — motif présent alors qu'il ne devrait pas : $motif"
    else
        ok "$libelle"
    fi
}

# -------------------------------------------------------------------
# Bac à sable
# -------------------------------------------------------------------
for f in "$RUN" "$DISPATCHER" "$LINT" "$DOC"; do
    [ -f "$f" ] || die "Fichier introuvable : $f" 1
done

mkdir -p "$BAC/lib" "$BAC/tests/acceptance/interne"
cp "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"
cp "$RUN"        "$BAC/tests/run.sh"
cp "$LINT"       "$BAC/tests/lint.sh"
cp "$DISPATCHER" "$BAC/tests/acceptance/run-acceptance.sh"

BAC_RUN="$BAC/tests/run.sh"
BAC_DISPATCHER="$BAC/tests/acceptance/run-acceptance.sh"
BAC_CAS="$BAC/tests/acceptance"

# Modèle de fichier de cas jetable — le bilan de tests/README.md §5, mot pour
# mot, compteurs fixés par substitution. @R@ réussites, @E@ échecs, @N@ non
# exécutés.
MODELE_CAS="$(cat <<'CAS'
#!/usr/bin/env bash
# Fichier de cas JETABLE, écrit par TASK-012 dans un bac à sable temporaire.
# Il ne vérifie rien : ses compteurs sont fixés d'avance pour éprouver le
# dispatcher. Le bilan ci-dessous est celui de tests/README.md §5.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

reussites=@R@
echecs=@E@
non_executes=@N@

i=0
while [ "$i" -lt "$reussites" ]; do success "cas vérifié"; i=$((i + 1)); done
i=0
while [ "$i" -lt "$echecs" ]; do error "ÉCHEC : cas en défaut"; i=$((i + 1)); done
i=0
while [ "$i" -lt "$non_executes" ]; do warn "NON EXÉCUTÉ : cas hors de portée de cet environnement"; i=$((i + 1)); done

info "Bilan TASK-@NOM@ : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s)"

if [ "$echecs" -gt 0 ]; then
    die "TASK-@NOM@ : $echecs critère(s) en défaut." 1
fi

if [ "$reussites" -eq 0 ]; then
    warn "TASK-@NOM@ : aucune vérification n'a pu être exécutée — rien n'est prouvé."
    exit 3
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-@NOM@ : $non_executes vérification(s) NON EXÉCUTÉE(s) — les critères correspondants ne sont pas prouvés."
    exit 4
fi

success "TASK-@NOM@ : tous les critères vérifiés ($reussites vérifications)."
CAS
)"

# poser_cas <nom> <réussites> <échecs> <non-exécutés> [sous-répertoire]
poser_cas() {
    local nom="$1" r="$2" e="$3" n="$4" sous="${5:-}"
    local cible="$BAC_CAS${sous:+/$sous}/TASK-$nom.sh"
    printf '%s\n' "$MODELE_CAS" \
        | sed -e "s/@NOM@/$nom/g" -e "s/@R@/$r/g" -e "s/@E@/$e/g" -e "s/@N@/$n/g" \
        > "$cible"
    printf '%s\n' "$cible"
}

# poser_cas_brut <nom> <code> — fichier qui sort sur un code arbitraire, pour
# éprouver ce que le dispatcher fait d'un verdict qu'il ne connaît pas.
poser_cas_brut() {
    local nom="$1" code="$2"
    local cible="$BAC_CAS/TASK-$nom.sh"
    {
        printf '%s\n' '#!/usr/bin/env bash'
        printf '%s\n' '# Fichier de cas JETABLE — sort sur un code hors contrat.'
        printf '%s\n' 'set -Eeuo pipefail'
        printf '%s\n' "echo 'cas jetable : sortie sur un code hors contrat' >&2"
        printf '%s\n' "exit $code"
    } > "$cible"
}

vider_cas() {
    rm -f "$BAC_CAS"/TASK-*.sh "$BAC_CAS"/interne/TASK-*.sh
}

lancer_dispatcher() { lancer bash "$BAC_DISPATCHER"; }
lancer_run()        { lancer bash "$BAC_RUN" "$@"; }

# ===================================================================
# 1. Le bac à sable teste bien le code du dépôt
# ===================================================================
titre "1. Fidélité du bac à sable"

if cmp -s "$RUN" "$BAC_RUN" && cmp -s "$DISPATCHER" "$BAC_DISPATCHER" \
   && cmp -s "$LINT" "$BAC/tests/lint.sh" \
   && cmp -s "$SCRIPTS_ROOT/lib/common.sh" "$BAC/lib/common.sh"; then
    ok "les quatre scripts du bac à sable sont identiques à ceux du dépôt"
else
    ko "le bac à sable diverge du dépôt — les verdicts qui suivent ne vaudraient rien"
fi

poser_cas "900-temoin" 1 0 0 >/dev/null
lancer bash "$BAC_RUN" --liste
if grep -q 'acceptance.*implémenté' "$F_OUT" && grep -q 'tests/acceptance/run-acceptance.sh' "$F_OUT"; then
    ok "le tests/run.sh du bac à sable s'enracine dans le bac à sable"
else
    ko "le tests/run.sh du bac à sable ne voit pas son propre répertoire"
fi
vider_cas

# ===================================================================
# 2. Verdict d'un fichier de cas — le bilan documenté
# ===================================================================
# C'est la brique de base : si le bilan de tests/README.md §5 ne traduit pas
# correctement les compteurs, tout ce qui s'agrège au-dessus est faux.
titre "2. Verdict d'un fichier de cas"

vider_cas
fichier="$(poser_cas "901-tout-reussi" 4 0 0)"
lancer bash "$fichier"
assert_code 0 "4 réussites, 0 échec, 0 saut → 0"

fichier="$(poser_cas "902-partiel" 3 0 7)"
lancer bash "$fichier"
assert_code 4 "3 réussites, 0 échec, 7 sauts → 4 (preuve partielle)"
assert_contient "$F_ERR" "7 NON EXÉCUTÉ(s)" "le décompte des sauts figure au bilan du fichier"

fichier="$(poser_cas "903-sterile" 0 0 5)"
lancer bash "$fichier"
assert_code 3 "0 réussite, 0 échec, 5 sauts → 3 (rien n'est prouvé)"
assert_contient "$F_ERR" "rien n'est prouvé" "le fichier stérile le dit explicitement"

fichier="$(poser_cas "904-echec" 3 1 2)"
lancer bash "$fichier"
assert_code 1 "1 échec parmi des réussites et des sauts → 1 (l'échec prime)"

fichier="$(poser_cas "905-echec-sterile" 0 1 4)"
lancer bash "$fichier"
assert_code 1 "1 échec sans aucune réussite → 1, et non 3"
vider_cas

# ===================================================================
# 3. run-acceptance.sh — agrégation des verdicts
# ===================================================================
titre "3. Agrégation par le dispatcher"

vider_cas
poser_cas "910-a" 2 0 0 >/dev/null
poser_cas "910-b" 3 0 0 >/dev/null
lancer_dispatcher
assert_code 0 "deux fichiers entièrement satisfaits → 0"

vider_cas
poser_cas "911-partiel" 3 0 7 >/dev/null
lancer_dispatcher
assert_code 4 "un fichier partiel → 4"
assert_contient "$F_ERR" "Dont 1 fichier(s) comportant des cas non applicables" \
    "le dispatcher affiche le nombre de fichiers partiels"
assert_contient "$F_ERR" "7 NON EXÉCUTÉ(s)" "le décompte du fichier reste visible sous le dispatcher"

vider_cas
poser_cas "912-reussi" 5 0 0 >/dev/null
poser_cas "912-partiel" 1 0 2 >/dev/null
lancer_dispatcher
assert_code 4 "un fichier satisfait et un fichier partiel → 4"

# Le garde central de TASK-012 : rien n'a tourné, rien n'est prouvé.
vider_cas
poser_cas "913-sterile" 0 0 5 >/dev/null
lancer_dispatcher
assert_code 3 "un fichier stérile seul → 3, jamais 0"
assert_contient "$F_ERR" "RIEN N'A PU ÊTRE VÉRIFIÉ" "le dispatcher nomme le fichier sans preuve"

# Le lot ne rachète pas le silence d'un fichier : trois fichiers verts autour
# d'un stérile ne rendent pas la preuve manquante.
vider_cas
poser_cas "914-reussi" 4 0 0 >/dev/null
poser_cas "914-partiel" 2 0 3 >/dev/null
poser_cas "914-sterile" 0 0 6 >/dev/null
lancer_dispatcher
assert_code 3 "un stérile parmi des fichiers satisfaits → 3, et non 4"

vider_cas
poser_cas "915-echec" 2 1 0 >/dev/null
lancer_dispatcher
assert_code 1 "un fichier en échec → 1"

vider_cas
poser_cas "916-echec" 1 1 0 >/dev/null
poser_cas "916-partiel" 2 0 3 >/dev/null
poser_cas "916-sterile" 0 0 2 >/dev/null
lancer_dispatcher
assert_code 1 "un échec mêlé à un partiel et à un stérile → 1 (l'échec prime sur tout)"

vider_cas
poser_cas_brut "917-code-2" 2
poser_cas "917-reussi" 2 0 0 >/dev/null
lancer_dispatcher
assert_code 1 "un fichier sortant sur un code hors contrat (2) est compté en échec → 1"

vider_cas
lancer_dispatcher
assert_code 3 "aucun fichier de cas → 3"

# maxdepth 1 : un fichier destiné au conteneur, rangé dans interne/, ne doit ni
# être exécuté ni peser sur le verdict. S'il l'était, ce stérile ferait 3.
vider_cas
poser_cas "918-reussi" 3 0 0 >/dev/null
poser_cas "918-interne-sterile" 0 0 4 interne >/dev/null
lancer_dispatcher
assert_code 0 "un fichier rangé dans interne/ est ignoré par le dispatcher"
assert_absent "$F_ERR" "918-interne-sterile" "le fichier de interne/ n'apparaît pas dans le rapport"
vider_cas

# ===================================================================
# 4. tests/run.sh — traduction du verdict d'un niveau
# ===================================================================
titre "4. Verdict global de tests/run.sh"

vider_cas
poser_cas "920-reussi" 3 0 0 >/dev/null
lancer_run acceptance
assert_code 0 "niveau entièrement satisfait → 0"

vider_cas
poser_cas "921-partiel" 3 0 7 >/dev/null
lancer_run acceptance
assert_code 0 "niveau partiel (4) → 0 : tests/run.sh ne rend jamais 4"
assert_contient "$F_ERR" "Dont 1 niveau(x) comportant des cas non applicables" \
    "tests/run.sh affiche le nombre de niveaux partiels"
assert_contient "$F_ERR" "7 NON EXÉCUTÉ(s)" \
    "le décompte des cas non applicables remonte jusqu'au verdict global"

# Le même garde, à l'étage du dessus : c'est là que le 3 était autrefois écrasé.
vider_cas
poser_cas "922-sterile" 0 0 5 >/dev/null
lancer_run acceptance
assert_code 3 "niveau stérile (3) → 3, ni 0 ni 1"
assert_contient "$F_ERR" "rien n'est prouvé" "tests/run.sh dit que rien n'est prouvé"

vider_cas
poser_cas "923-echec" 2 1 0 >/dev/null
lancer_run acceptance
assert_code 1 "niveau en échec → 1"

# Un niveau vert n'efface pas un niveau stérile : sans cette règle, le lint
# suffirait à faire passer une exécution complète pour une preuve.
vider_cas
poser_cas "924-sterile" 0 0 3 >/dev/null
lancer_run
assert_code 3 "sans argument : lint satisfait + acceptance stérile → 3"

vider_cas
poser_cas "925-partiel" 4 0 2 >/dev/null
lancer_run
assert_code 0 "sans argument : lint satisfait + acceptance partielle → 0"
assert_contient "$F_ERR" "non implémenté, ignoré" "les niveaux absents sont signalés sans faire échouer"

vider_cas
poser_cas "926-reussi" 2 0 0 >/dev/null
lancer_run lint acceptance
assert_code 0 "deux niveaux demandés explicitement, tous deux satisfaits → 0"

lancer_run unit
assert_code 3 "niveau demandé explicitement mais non implémenté → 3"

lancer_run lint unit
assert_code 3 "un niveau satisfait et un niveau non implémenté → 3"
vider_cas

# ===================================================================
# 5. Contrat d'usage de tests/run.sh sur le dépôt réel
# ===================================================================
# Ces cas ne dépendent d'aucun fichier de cas : ils s'exécutent sur le vrai
# tests/run.sh, sans rien lancer de coûteux.
titre "5. Préflight et usage sur le dépôt réel"

lancer bash "$RUN" --option-inconnue
assert_code 2 "option inconnue → 2"

lancer bash "$RUN" niveau-inexistant
assert_code 2 "niveau inconnu → 2"

lancer bash "$RUN" --help
assert_code 0 "--help → 0"
assert_contient "$F_OUT" "Usage : tests/run.sh" "--help affiche l'usage"
assert_contient "$F_OUT" "rien n'est prouvé" "--help documente le sens du code 3"

lancer bash "$RUN" --liste
assert_code 0 "--liste → 0"

# Un niveau demandé explicitement mais non implémenté rend 3. Ce comportement
# ne doit s'adosser au NOM d'aucun niveau : celui qui manque aujourd'hui sera
# implémenté demain, et l'assertion deviendrait fausse sans que rien ne soit
# cassé — c'est ce qui est arrivé à « unit », implémenté par TASK-003.
# Le niveau éprouvé est donc LU dans la sortie de --liste, jamais écrit en dur.
# N'étant par construction pas implémenté, il ne déclenche l'exécution
# d'aucune suite : le cas reste aussi peu coûteux que les précédents.
premier_niveau_absent() {
    awk '$2 == "NON" && vu == 0 { print $1; vu = 1 }' "$1"
}

lancer bash "$RUN" --liste
LISTE_REELLE="$REP_TMP/liste-reelle"
cp "$F_OUT" "$LISTE_REELLE"
NIVEAU_ABSENT="$(premier_niveau_absent "$LISTE_REELLE")"
RUN_EPROUVE="$RUN"
OU_EPROUVE="le dépôt réel"

# Le jour où le dépôt implémentera ses cinq niveaux, le comportement reste
# vérifiable dans le bac à sable, qui ne porte que lint et acceptance et dont
# l'état ne dépend de rien d'extérieur à ce fichier.
if [ -z "$NIVEAU_ABSENT" ]; then
    lancer bash "$BAC_RUN" --liste
    LISTE_BAC="$REP_TMP/liste-bac"
    cp "$F_OUT" "$LISTE_BAC"
    NIVEAU_ABSENT="$(premier_niveau_absent "$LISTE_BAC")"
    RUN_EPROUVE="$BAC_RUN"
    OU_EPROUVE="le bac à sable"
fi

if [ -z "$NIVEAU_ABSENT" ]; then
    saute "niveau non implémenté → 3" \
        "aucun niveau annoncé NON IMPLÉMENTÉ, ni par le dépôt ni par le bac à sable"
else
    lancer bash "$RUN_EPROUVE" "$NIVEAU_ABSENT"
    assert_code 3 "niveau « $NIVEAU_ABSENT », non implémenté dans $OU_EPROUVE, demandé explicitement → 3"
    # Sans ce motif, le 3 ci-dessus pourrait tout aussi bien venir d'un niveau
    # exécuté n'ayant rien pu vérifier : ce n'est pas ce qu'on prouve ici.
    assert_contient "$F_ERR" "NON IMPLÉMENTÉ" \
        "tests/run.sh nomme le niveau non implémenté avant de sortir en 3"
fi

# ===================================================================
# 6. La sémantique est documentée
# ===================================================================
titre "6. Documentation de la sémantique"

assert_contient "$DOC" "aucun cas n'a pu être exécuté" "README : le sens du code 3 d'un niveau"
assert_contient "$DOC" "la preuve est partielle, elle existe" "README : le sens du code 4 d'un niveau"
assert_contient "$DOC" "ne rend jamais 4" "README : tests/run.sh ne rend jamais 4"
assert_contient "$DOC" "il exige **au" "README : le 4 exige au moins une réussite"

# ===================================================================
# 7. Ordre du garde dans les fichiers de cas réels
# ===================================================================
# Contrôle structurel, faute de pouvoir forcer les fichiers réels à ne rien
# vérifier du tout : « aucune réussite » doit être testé AVANT « des cas
# sautés », sinon une suite intégralement sautée sortirait en 4.
titre "7. Ordre du garde dans les fichiers réels"

for relatif in $CAS_REELS; do
    fichier="$SCRIPTS_ROOT/$relatif"
    if [ ! -f "$fichier" ]; then
        saute "ordre du garde dans $relatif" "fichier absent"
        continue
    fi
    ligne_sterile="$(grep -n 'reussites" -eq 0' "$fichier" | head -n 1 | cut -d: -f1)"
    ligne_partiel="$(grep -n 'non_executes" -gt 0' "$fichier" | head -n 1 | cut -d: -f1)"
    if [ -z "$ligne_sterile" ] || [ -z "$ligne_partiel" ]; then
        ko "$relatif — bilan incomplet : garde « aucune réussite » ou « cas sautés » introuvable"
    elif [ "$ligne_sterile" -lt "$ligne_partiel" ]; then
        ok "$relatif — « aucune réussite » testé avant « cas sautés » (lignes $ligne_sterile < $ligne_partiel)"
    else
        ko "$relatif — « cas sautés » testé avant « aucune réussite » (lignes $ligne_partiel < $ligne_sterile)"
    fi
    if grep -q 'exit 4' "$fichier"; then
        ok "$relatif — sort en 4 quand des cas ne s'appliquent pas"
    else
        ko "$relatif — aucun exit 4 : le fichier ne distingue pas la preuve partielle"
    fi
    # Le décompte des sauts vient du fichier lui-même : le dispatcher ne compte
    # que des fichiers. Sans cette ligne, le nombre de cas sautés disparaîtrait.
    if grep -q 'info "Bilan .*non_executes NON EXÉCUTÉ' "$fichier"; then
        ok "$relatif — le bilan affiche le nombre de cas NON EXÉCUTÉS"
    else
        ko "$relatif — le bilan ne publie pas le nombre de cas NON EXÉCUTÉS"
    fi
done

# ===================================================================
# 8. Diagnostic : environnement indisponible
# ===================================================================
# Les compteurs ne distinguent pas « non applicable par nature » (le conteneur
# n'a pas systemd) de « environnement indisponible » (le démon Docker ne répond
# pas). Ce cas mesure ce que rend un fichier de cas réel quand l'essentiel de sa
# preuve est hors d'atteinte. Le contrat de TASK-012 exige seulement qu'il ne
# sorte pas en 0 ; le code observé est affiché, quel qu'il soit.
titre "8. Diagnostic — un fichier de cas privé de son environnement"

PATH_SANS_DOCKER=""
if command -v docker >/dev/null 2>&1; then
    dossier_docker="$(dirname "$(command -v docker)")"
    while IFS= read -r element; do
        [ -n "$element" ] || continue
        if [ "$element" = "$dossier_docker" ]; then
            continue
        fi
        if [ -z "$PATH_SANS_DOCKER" ]; then
            PATH_SANS_DOCKER="$element"
        else
            PATH_SANS_DOCKER="$PATH_SANS_DOCKER:$element"
        fi
    done <<<"$(printf '%s' "$PATH" | tr ':' '\n')"
fi

CAS_DOCKER="$SCRIPTS_ROOT/tests/acceptance/TASK-002-environnement-conteneurise.sh"
if [ -z "$PATH_SANS_DOCKER" ] || [ ! -f "$CAS_DOCKER" ]; then
    saute "fichier de cas privé de Docker" "docker n'est pas dans le PATH, la simulation n'a pas de sens"
else
    lancer env PATH="$PATH_SANS_DOCKER" bash "$CAS_DOCKER"
    case "$CODE" in
        3|4) ok "TASK-002 sans client docker ne sort pas en 0 — code $CODE" ;;
        0)   ko "TASK-002 sans client docker sort en 0 alors que ses cas n'ont pas pu tourner" ;;
        *)   ko "TASK-002 sans client docker sort en $CODE — attendu 3 ou 4, pas un échec" ;;
    esac
    if [ "$CODE" -eq 4 ]; then
        warn "LIMITE CONNUE : le code 4 est rendu parce que les cas de préflight, eux, ont tourné."
        warn "LIMITE CONNUE : les compteurs ne distinguent pas « non applicable ici » de « environnement indisponible »."
        warn "LIMITE CONNUE : ce 4 se traduit en 0 par tests/run.sh, alors que l'essentiel de la preuve est absent."
    fi
fi

# ===================================================================
# 9. Le niveau lint traverse le conteneur
# ===================================================================
# TASK-012 a réécrit la boucle d'exécution des niveaux de tests/run.sh. Le
# chemin conteneurisé — celui qu'inscrit la tâche en validation — doit rendre
# le même verdict que sur l'hôte.
titre "9. tests/run.sh lint dans le conteneur"

DOCKER_UTILISABLE="false"
if command -v docker >/dev/null 2>&1; then
    if [ -n "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)" ]; then
        DOCKER_UTILISABLE="true"
    fi
fi

if [ ! -f "$LANCEUR" ]; then
    saute "tests/run.sh lint dans le conteneur" "lanceur introuvable : $LANCEUR"
elif [ "$DOCKER_UTILISABLE" = "false" ]; then
    saute "tests/run.sh lint dans le conteneur" "le démon Docker ne répond pas"
else
    lancer bash "$LANCEUR" -- tests/run.sh lint
    assert_code 0 "tests/run.sh lint dans le conteneur (shellcheck présent)"
fi

lancer bash "$RUN" lint
assert_code 0 "tests/run.sh lint sur l'hôte"

# ===================================================================
# 10. Hygiène — aucun fichier jetable dans le dépôt
# ===================================================================
# run-acceptance.sh découvre tout tests/acceptance/TASK-*.sh : un résidu
# polluerait chaque exécution ultérieure. Les fichiers jetables de ce test sont
# tous nés hors du dépôt, et ce cas le vérifie.
titre "10. Hygiène du répertoire de cas"

case "$REP_TMP" in
    "$SCRIPTS_ROOT"/*) ko "le bac à sable a été créé dans le dépôt : $REP_TMP" ;;
    *)                 ok "le bac à sable est hors du dépôt" ;;
esac

residus="$(find "$SCRIPTS_ROOT/tests/acceptance" -type f -name 'TASK-9*.sh' | sort || true)"
if [ -z "$residus" ]; then
    ok "aucun fichier de cas jetable dans tests/acceptance/"
else
    ko "fichiers jetables laissés dans le dépôt : $(printf '%s' "$residus" | tr '\n' ' ')"
fi

# ===================================================================
# 11. Ce que cet environnement ne permet pas de vérifier
# ===================================================================
titre "11. Hors de portée de cet environnement"

# Ce fichier est lui-même découvert par run-acceptance.sh : lancer le niveau
# complet depuis ici s'appellerait sans fin. Le critère « tests/run.sh
# acceptance sort en 0 sur l'état actuel du dépôt » se vérifie donc à la main,
# hors du niveau — il ne peut pas être prouvé de l'intérieur.
saute "tests/run.sh acceptance sur le dépôt réel" "récursion : ce fichier fait partie du niveau qu'il faudrait lancer"

# Le profil systemd n'existe pas : aucun fichier de cas réel ne peut aujourd'hui
# être placé dans un environnement où ses sauts disparaîtraient. La preuve que
# « 0 saut → 0 » sur un fichier réel reste hors d'atteinte.
saute "un fichier de cas réel sortant en 0 sans aucun saut" "aucun environnement du dépôt ne rend exécutables les cas systemd et CAP_SYS_ADMIN"

# ===================================================================
# Bilan
# ===================================================================
info "Bilan TASK-012 : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s)"

if [ "$echecs" -gt 0 ]; then
    die "TASK-012 : $echecs critère(s) en défaut." 1
fi

# Testé AVANT le cas des non exécutés : sans cet ordre, une exécution où tout
# aurait été sauté sortirait en 4, c'est-à-dire en réussite partielle, alors que
# rien n'aurait été prouvé.
if [ "$reussites" -eq 0 ]; then
    warn "TASK-012 : aucune vérification n'a pu être exécutée — rien n'est prouvé."
    exit 3
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-012 : $non_executes vérification(s) NON EXÉCUTÉE(s) — les critères correspondants ne sont pas prouvés."
    exit 4
fi

success "TASK-012 : tous les critères vérifiés ($reussites vérifications)."
