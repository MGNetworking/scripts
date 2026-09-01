#!/usr/bin/env bash
# tests/acceptance/TASK-011-analyse-statique.sh — critères de TASK-011.
#
# TASK-011 n'a rien ajouté : elle a corrigé la forme de six fichiers pour que
# l'analyse statique cesse de les refuser. (Un commentaire dont le premier mot
# est le nom de l'outil serait lu comme une directive : c'est précisément le
# défaut que TASK-011 a corrigé dans tests/lint.sh, et il vaut ici aussi.)
# Le critère central — « tests/run.sh lint
# sort en 0 » — est facile à vérifier ; le difficile est l'autre : « aucun
# comportement de script n'est modifié ». Ces cinq scripts d'administration
# tournent sur un serveur réel et n'avaient jusqu'ici aucun test.
#
# La preuve est conduite sur deux plans :
#
#   1. l'analyse statique elle-même, dans le conteneur qui embarque shellcheck ;
#   2. le comportement, par exécution réelle des cinq scripts : préflight,
#      aide, --dry-run, idempotence, et surtout le chemin « -y », seul à même
#      de prouver que confirm() voit toujours ASSUME_YES après son passage à
#      « export ».
#
# Un troisième plan a existé : le contrôle de forme du diff, qui vérifiait que
# les corrections de TASK-011 n'avaient touché que ce qu'elles annonçaient. Il a
# été retiré le 2026-09-02 (ADR-0003, décision 13). Les corrections étant
# commitées, « git diff HEAD » était vide sur un arbre propre : ses six contrôles
# sortaient en NON EXÉCUTÉ à chaque exécution et n'en seraient jamais revenus.
# Six sauts permanents finissent par être ignorés — c'est le bruit qui masque un
# vrai problème. Le niveau « integration » est le domicile durable de ces
# preuves.
#
# Chaque groupe de cas comportementaux part d'un conteneur NEUF : deux
# exécutions dans un conteneur recyclé ne prouveraient aucune idempotence.
#
# Le conteneur n'a ni systemd ni CAP_SYS_ADMIN : les chemins qui passent par
# timedatectl, hostnamectl, « hostname » ou l'activation d'un swap sont déclarés
# NON EXÉCUTÉS, jamais réussis. Ce fichier sort alors en 4 — les critères
# vérifiés le sont, ceux-là ne le sont pas, et leur nombre s'affiche. Il ne sort
# en 3 que si AUCUNE vérification n'a pu être exécutée : « pas pu vérifier » ne
# vaut jamais « vérifié », mais ne doit pas non plus effacer ce qui l'a été.
#
# NATURE DES SAUTS (TASK-013). Ces sauts-là sont NON APPLICABLES PAR NATURE : le
# profil « debian » n'aura jamais systemd, et aucune exécution ne l'y mettra.
# Ils valent 4. Les sauts dus au démon Docker qui ne répond pas, à git
# introuvable ou au miroir apt injoignable sont d'une autre nature —
# l'ENVIRONNEMENT A MANQUÉ — et valent 3. C'est le scénario mesuré au §3 de
# docs/points-en-suspens.md : 21 des 29 vérifications de ce fichier
# s'évaporaient, et le verdict restait vert.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

LANCEUR="$SCRIPTS_ROOT/tests/env/run-in-container.sh"
CAS_CONTENEUR="tests/acceptance/interne/TASK-011-cas-conteneur.sh"

# Les cinq scripts corrigés par TASK-011 : eux seuls ont vu leur code touché.
SCRIPTS_CORRIGES="
Linux/System/configure-hostname.sh
Linux/System/configure-logging.sh
Linux/System/configure-swap.sh
Linux/System/configure-timezone.sh
Linux/System/update-system.sh
"

# Groupes de cas, dans l'ordre. Un conteneur neuf par groupe.
GROUPES="preflight aide dry-run regex enfants timezone hostname hosts-existant swap-fstab logging update"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

reussites=0
echecs=0
non_executes=0
# Les deux natures de saut, décomptées séparément — voir tests/README.md §2.
# « non_executes » reste leur total.
non_applicables=0
indisponibilites=0

trap 'rm -rf "$REP_TMP"' EXIT

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
    echecs=$((echecs + 1))
}

# saute_par_nature <libellé> — cas NON APPLICABLE PAR NATURE : aucune exécution ne le
# rendra atteignable ici. Le fichier peut sortir en 4.
saute_par_nature() {
    warn "NON EXÉCUTÉ (non applicable par nature) : $1"
    non_executes=$((non_executes + 1))
    non_applicables=$((non_applicables + 1))
}

# saute_indisponible <libellé> — ENVIRONNEMENT INDISPONIBLE : la preuve existe,
# elle n'a pas pu être produite. Un seul suffit à faire sortir ce fichier en 3.
saute_indisponible() {
    warn "NON EXÉCUTÉ (environnement indisponible) : $1"
    non_executes=$((non_executes + 1))
    indisponibilites=$((indisponibilites + 1))
}

# verifier <0-si-vrai> <libellé> [détail]
verifier() {
    if [ "$1" = "0" ]; then
        ok "$2"
    else
        ko "$2${3:+ — $3}"
    fi
}

lancer() {
    CODE=0
    ( "$@" ) >"$F_OUT" 2>"$F_ERR" || CODE=$?
}

# -------------------------------------------------------------------
# Disponibilité de l'environnement
# -------------------------------------------------------------------
[ -f "$LANCEUR" ] || die "Lanceur introuvable : $LANCEUR" 1
[ -f "$SCRIPTS_ROOT/$CAS_CONTENEUR" ] || die "Fichier de cas introuvable : $CAS_CONTENEUR" 1

DOCKER_UTILISABLE="false"
if command -v docker >/dev/null 2>&1; then
    if [ -n "$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)" ]; then
        DOCKER_UTILISABLE="true"
    fi
fi

# Vrai pour un commentaire ou une ligne vide. Servait au contrôle de forme du
# §1, retiré ; reste employé au §2 pour vérifier qu'une directive shellcheck
# porte bien une justification au-dessus d'elle.
est_commentaire() {
    local ligne="$1"
    local indentation="${ligne%%[![:space:]]*}"
    case "${ligne#"$indentation"}" in
        '#'*) return 0 ;;
        '')   return 0 ;;
        *)    return 1 ;;
    esac
}

# ===================================================================
# 2. Contrôles statiques du dépôt
# ===================================================================
titre "2. Contrôles statiques"

# La branche -y doit exister dans les cinq scripts, et porter l'export.
for fichier in $SCRIPTS_CORRIGES; do
    verifier "$(grep -qF 'export ASSUME_YES="true"' "$SCRIPTS_ROOT/$fichier" && echo 0 || echo 1)" \
        "$fichier porte la branche -y avec export"
done

# Aucun autre fichier que lib/common.sh ne LIT ASSUME_YES : c'est ce qui borne
# le risque de l'export à la seule frontière déjà connue.
#
# Les deux motifs sont assemblés en morceaux pour que ces lignes-ci ne se
# désignent pas elles-mêmes comme lectrices de la variable.
motif_lecture="\$""ASSUME_YES"
motif_lecture_accolade="\${""ASSUME_YES"
lecteurs="$(grep -rlF --include='*.sh' \
    -e "$motif_lecture" -e "$motif_lecture_accolade" "$SCRIPTS_ROOT" || true)"
lecteurs_hors_common="$(printf '%s\n' "$lecteurs" | grep -v '/lib/common\.sh$' | grep -c . || true)"
verifier "$([ "$lecteurs_hors_common" -eq 0 ] && echo 0 || echo 1)" \
    "ASSUME_YES n'est lue que par lib/common.sh" \
    "$lecteurs_hors_common autre(s) lecteur(s) : $(printf '%s' "$lecteurs" | tr '\n' ' ')"

# Aucune règle shellcheck désactivée globalement au-delà des deux historiques.
exclusions="$(grep -E '^SHELLCHECK_EXCLUS=' "$SCRIPTS_ROOT/tests/lint.sh" | head -n 1 || true)"
verifier "$([ "$exclusions" = 'SHELLCHECK_EXCLUS="SC1090,SC1091"' ] && echo 0 || echo 1)" \
    "tests/lint.sh n'exclut globalement que SC1090 et SC1091" \
    "trouvé : $exclusions"

# Le motif est assemblé en deux morceaux pour que cette ligne-ci ne se
# signale pas elle-même comme une directive sans justification.
MOTIF_DISABLE="shellcheck dis""able="
directives_sans_justification=0
while IFS= read -r trouvaille; do
    [ -n "$trouvaille" ] || continue
    fichier="${trouvaille%%:*}"
    reste="${trouvaille#*:}"
    numero="${reste%%:*}"
    precedente="$(sed -n "$((numero - 1))p" "$fichier")"
    if ! est_commentaire "$precedente"; then
        directives_sans_justification=$((directives_sans_justification + 1))
        printf '        %s ligne %s : rien au-dessus de la directive\n' "$fichier" "$numero" >&2
    fi
done < <(grep -rn --include='*.sh' -e "$MOTIF_DISABLE" "$SCRIPTS_ROOT" || true)

verifier "$([ "$directives_sans_justification" -eq 0 ] && echo 0 || echo 1)" \
    "toute directive shellcheck locale porte une justification au-dessus" \
    "$directives_sans_justification directive(s) nue(s)"

# ===================================================================
# 3. L'analyse statique elle-même — le critère central de TASK-011
# ===================================================================
titre "3. tests/run.sh lint dans le conteneur"

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    lancer bash "$LANCEUR" -- tests/run.sh lint
    verifier "$([ "$CODE" -eq 0 ] && echo 0 || echo 1)" \
        "tests/run.sh lint sort en 0 dans le conteneur" "code $CODE"
    verifier "$(grep -qF '0 erreur' "$F_ERR" && echo 0 || echo 1)" \
        "l'analyse statique annonce 0 erreur" "bilan absent de la sortie"

    # L'outil doit avoir réellement tourné : sans lui, « 0 erreur » ne
    # signifierait que « bash -n est content », ce qui ne prouve rien ici.
    verifier "$(grep -qF 'analyse approfondie NON EXÉCUTÉE' "$F_ERR" && echo 1 || echo 0)" \
        "shellcheck a bien tourné dans le conteneur" \
        "le lint annonce lui-même son analyse approfondie non exécutée"
else
    saute_indisponible "tests/run.sh lint dans le conteneur — le démon Docker ne répond pas"
fi

# ===================================================================
# 4. Comportement — un conteneur neuf par groupe de cas
# ===================================================================
titre "4. Comportement des cinq scripts"

executer_groupe() {
    local groupe="$1"
    local resultats="$REP_TMP/resultats-$groupe"
    local ligne statut libelle vus=0

    lancer bash "$LANCEUR" -- bash "$CAS_CONTENEUR" "$groupe"

    grep -E '^(RESULTAT|FIN)\|' "$F_OUT" > "$resultats" || true

    while IFS= read -r ligne; do
        case "$ligne" in
            RESULTAT\|*)
                statut="${ligne#RESULTAT|}"
                libelle="${statut#*|}"
                statut="${statut%%|*}"
                vus=$((vus + 1))
                # SKIP et INDISPO viennent du fichier de cas conteneurisé, qui
                # qualifie lui-même la nature de chacun de ses sauts : lui seul
                # sait si c'est CAP_SYS_ADMIN qui manquait — pour toujours — ou
                # le miroir apt — pour cette fois. Un verdict inconnu reste un
                # échec : une nature ajoutée là-bas et oubliée ici se voit.
                case "$statut" in
                    PASS)    ok "[$groupe] $libelle" ;;
                    FAIL)    ko "[$groupe] $libelle" ;;
                    SKIP)    saute_par_nature "[$groupe] $libelle" ;;
                    INDISPO) saute_indisponible "[$groupe] $libelle" ;;
                    *)       ko "[$groupe] verdict illisible : $ligne" ;;
                esac
                ;;
        esac
    done < "$resultats"

    # Sans la ligne FIN, le groupe s'est interrompu : les cas non atteints
    # n'ont pas été exécutés, et le silence ne vaut pas réussite.
    if ! grep -q "^FIN|$groupe|" "$resultats"; then
        ko "[$groupe] le groupe s'est interrompu avant la fin (code $CODE, $vus cas relevés)"
        if [ -s "$F_ERR" ]; then
            tail -n 10 "$F_ERR" | sed 's/^/        /' >&2
        fi
    fi
}

if [ "$DOCKER_UTILISABLE" = "true" ]; then
    for groupe in $GROUPES; do
        info "Groupe « $groupe » — conteneur neuf"
        executer_groupe "$groupe"
    done
else
    for groupe in $GROUPES; do
        saute_indisponible "groupe « $groupe » — le démon Docker ne répond pas"
    done
fi

# ===================================================================
# 5. Ce que cet environnement ne permet pas de vérifier
# ===================================================================
titre "5. Hors de portée de cet environnement"

# Ces déclarations ne sont pas des cas manqués : ce sont des cas dont on sait
# qu'ils ne peuvent pas être joués ici. Les taire ferait croire à une
# couverture complète.
saute_par_nature "update-system.sh appliquant réellement « apt-get upgrade » — l'image ne fournit pas de paquet obsolète à mettre à jour"
saute_par_nature "configure-swap.sh créant et activant un fichier d'échange — swapon exige CAP_SYS_ADMIN, refusé au conteneur non privilégié"
saute_par_nature "configure-logging.sh sur un serveur sans le groupe « adm » — l'image Debian le fournit toujours"

# ===================================================================
# Bilan
# ===================================================================
info "Bilan TASK-011 : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s) — dont $non_applicables non applicable(s) par nature et $indisponibilites indisponibilité(s) d'environnement"

if [ "$echecs" -gt 0 ]; then
    die "TASK-011 : $echecs critère(s) en défaut." 1
fi

# Testé AVANT le cas des non exécutés : sans cet ordre, une exécution où tout
# aurait été sauté sortirait en 4, c'est-à-dire en réussite partielle, alors que
# rien n'aurait été prouvé.
if [ "$reussites" -eq 0 ]; then
    warn "TASK-011 : aucune vérification n'a pu être exécutée — rien n'est prouvé."
    exit 3
fi

# Une indisponibilité suffit. La mesure du §3 de docs/points-en-suspens.md
# l'impose : démon Docker coupé, ce fichier annonçait 8 réussites pour 21 NON
# EXÉCUTÉ(s) et sortait en 4, traduit en 0 par tests/run.sh. Les 8 réussites
# étaient des contrôles statiques, qui n'ont besoin de rien. Testé AVANT les non
# applicables : des deux natures, la plus grave l'emporte.
if [ "$indisponibilites" -gt 0 ]; then
    warn "TASK-011 : $indisponibilites cas n'ont pas pu être produits faute d'environnement — rien n'est prouvé de fiable."
    exit 3
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-011 : $non_executes vérification(s) NON EXÉCUTÉE(s) — les critères correspondants ne sont pas prouvés."
    exit 4
fi

success "TASK-011 : tous les critères vérifiés ($reussites vérifications)."
