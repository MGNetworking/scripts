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
# La preuve est donc conduite sur trois plans :
#
#   1. la forme des corrections — le diff ne contient que les transformations
#      annoncées, et rien d'autre ;
#   2. l'analyse statique elle-même, dans le conteneur qui embarque shellcheck ;
#   3. le comportement, par exécution réelle des cinq scripts : préflight,
#      aide, --dry-run, idempotence, et surtout le chemin « -y », seul à même
#      de prouver que confirm() voit toujours ASSUME_YES après son passage à
#      « export ».
#
# Chaque groupe de cas comportementaux part d'un conteneur NEUF : deux
# exécutions dans un conteneur recyclé ne prouveraient aucune idempotence.
#
# Ce fichier sort en 3 dès qu'un critère n'a pas pu être vérifié. Le conteneur
# n'a ni systemd ni CAP_SYS_ADMIN : les chemins qui passent par timedatectl,
# hostnamectl, « hostname » ou l'activation d'un swap sont déclarés NON
# EXÉCUTÉS, jamais réussis.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

LANCEUR="$SCRIPTS_ROOT/tests/env/run-in-container.sh"
CAS_CONTENEUR="tests/acceptance/interne/TASK-011-cas-conteneur.sh"

# Les six fichiers corrigés par TASK-011.
FICHIERS_CORRIGES="
Linux/System/configure-hostname.sh
Linux/System/configure-logging.sh
Linux/System/configure-swap.sh
Linux/System/configure-timezone.sh
Linux/System/update-system.sh
tests/lint.sh
"

# Les cinq scripts, sans tests/lint.sh : eux seuls ont vu leur code touché.
SCRIPTS_CORRIGES="
Linux/System/configure-hostname.sh
Linux/System/configure-logging.sh
Linux/System/configure-swap.sh
Linux/System/configure-timezone.sh
Linux/System/update-system.sh
"

# Groupes de cas, dans l'ordre. Un conteneur neuf par groupe.
GROUPES="preflight aide dry-run regex enfants timezone hostname hosts-existant swap-fstab logging update"

# Référence de comparaison pour le contrôle de forme. HEAD tant que les
# corrections ne sont pas commitées ; sinon le commit qui les précède, à passer
# par l'environnement.
REF_AVANT="${TASK011_REF:-HEAD}"

REP_TMP="$(mktemp -d)"
F_OUT="$REP_TMP/stdout"
F_ERR="$REP_TMP/stderr"
CODE=0

reussites=0
echecs=0
non_executes=0

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

saute() {
    warn "NON EXÉCUTÉ : $1"
    non_executes=$((non_executes + 1))
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

GIT_UTILISABLE="false"
if command -v git >/dev/null 2>&1 && git -C "$SCRIPTS_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_UTILISABLE="true"
fi

# ===================================================================
# 1. Forme des corrections — le diff ne dit que ce qu'il annonce
# ===================================================================
# Trois transformations ont été annoncées, et trois seulement :
#   ASSUME_YES="true"   ->  export ASSUME_YES="true"
#   $ADRESSE_HOTE[      ->  ${ADRESSE_HOTE}[
#   $FICHIER_SWAP[      ->  ${FICHIER_SWAP}[
# Toute autre ligne modifiée serait une évolution fonctionnelle déguisée.
titre "1. Forme des corrections"

# Les deux dernières expressions sont écrites entre guillemets doubles avec
# des échappements plutôt qu'entre apostrophes : le résultat est le même pour
# sed, mais l'analyse statique ne les prend pas pour des variables oubliées.
transformer() {
    printf '%s\n' "$1" | sed \
        -e 's/ASSUME_YES="true"/export ASSUME_YES="true"/' \
        -e "s/\\\$ADRESSE_HOTE\\[/\${ADRESSE_HOTE}[/g" \
        -e "s/\\\$FICHIER_SWAP\\[/\${FICHIER_SWAP}[/g"
}

# Vrai pour un commentaire ou une ligne vide : tout le reste est du code, et
# du code modifié serait, par définition, un changement de comportement.
est_commentaire() {
    local ligne="$1"
    local indentation="${ligne%%[![:space:]]*}"
    case "${ligne#"$indentation"}" in
        '#'*) return 0 ;;
        '')   return 0 ;;
        *)    return 1 ;;
    esac
}

controler_forme() {
    local fichier="$1"
    local diff="$REP_TMP/diff"
    local retirees="$REP_TMP/retirees"
    local ajoutees="$REP_TMP/ajoutees"
    local attendues="$REP_TMP/attendues"
    local ligne anomalies=0

    git -C "$SCRIPTS_ROOT" diff "$REF_AVANT" -- "$fichier" > "$diff" 2>/dev/null || true

    if [ ! -s "$diff" ]; then
        saute "forme de $fichier — aucun écart avec « $REF_AVANT », la comparaison n'a plus de référence"
        return 0
    fi

    grep '^-' "$diff" | grep -v '^---' | sed 's/^-//' > "$retirees" || true
    grep '^+' "$diff" | grep -v '^+++' | sed 's/^+//' > "$ajoutees" || true

    : > "$attendues"
    while IFS= read -r ligne; do
        transformer "$ligne" >> "$attendues"
    done < "$retirees"

    # tests/lint.sh : rien d'autre que des commentaires n'a bougé.
    if [ "$fichier" = "tests/lint.sh" ]; then
        while IFS= read -r ligne; do
            if ! est_commentaire "$ligne"; then
                anomalies=$((anomalies + 1))
                printf '        ligne de code modifiée : %s\n' "$ligne" >&2
            fi
        done < <(cat "$retirees" "$ajoutees")
        verifier "$([ "$anomalies" -eq 0 ] && echo 0 || echo 1)" \
            "tests/lint.sh : seuls des commentaires ont changé" "$anomalies ligne(s) de code"
        return 0
    fi

    # Les cinq scripts : toute ligne retirée doit se retrouver, transformée,
    # parmi les lignes ajoutées ; et toute ligne ajoutée est soit un
    # commentaire, soit la transformée d'une ligne retirée.
    while IFS= read -r ligne; do
        if est_commentaire "$ligne"; then
            anomalies=$((anomalies + 1))
            printf '        commentaire retiré : %s\n' "$ligne" >&2
            continue
        fi
        if ! grep -qxF -- "$(transformer "$ligne")" "$ajoutees"; then
            anomalies=$((anomalies + 1))
            printf '        ligne retirée sans transformée connue : %s\n' "$ligne" >&2
        fi
    done < "$retirees"

    while IFS= read -r ligne; do
        est_commentaire "$ligne" && continue
        if ! grep -qxF -- "$ligne" "$attendues"; then
            anomalies=$((anomalies + 1))
            printf '        ligne ajoutée hors transformations annoncées : %s\n' "$ligne" >&2
        fi
    done < "$ajoutees"

    verifier "$([ "$anomalies" -eq 0 ] && echo 0 || echo 1)" \
        "$fichier : le diff ne contient que les transformations annoncées" \
        "$anomalies anomalie(s)"
}

if [ "$GIT_UTILISABLE" = "true" ]; then
    for fichier in $FICHIERS_CORRIGES; do
        controler_forme "$fichier"
    done
else
    saute "forme des corrections — git indisponible, le diff ne peut pas être relu"
fi

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
    saute "tests/run.sh lint dans le conteneur — le démon Docker ne répond pas"
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
                case "$statut" in
                    PASS) ok "[$groupe] $libelle" ;;
                    FAIL) ko "[$groupe] $libelle" ;;
                    SKIP) saute "[$groupe] $libelle" ;;
                    *)    ko "[$groupe] verdict illisible : $ligne" ;;
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
        saute "groupe « $groupe » — le démon Docker ne répond pas"
    done
fi

# ===================================================================
# 5. Ce que cet environnement ne permet pas de vérifier
# ===================================================================
titre "5. Hors de portée de cet environnement"

# Ces déclarations ne sont pas des cas manqués : ce sont des cas dont on sait
# qu'ils ne peuvent pas être joués ici. Les taire ferait croire à une
# couverture complète.
saute "update-system.sh appliquant réellement « apt-get upgrade » — l'image ne fournit pas de paquet obsolète à mettre à jour"
saute "configure-swap.sh créant et activant un fichier d'échange — swapon exige CAP_SYS_ADMIN, refusé au conteneur non privilégié"
saute "configure-logging.sh sur un serveur sans le groupe « adm » — l'image Debian le fournit toujours"

# ===================================================================
# Bilan
# ===================================================================
info "Bilan TASK-011 : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s)"

if [ "$echecs" -gt 0 ]; then
    die "TASK-011 : $echecs critère(s) en défaut." 1
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-011 : $non_executes vérification(s) NON EXÉCUTÉE(s) — les critères correspondants ne sont pas prouvés."
    exit 3
fi

success "TASK-011 : tous les critères vérifiés ($reussites vérifications)."
