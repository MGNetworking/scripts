#!/usr/bin/env bash
# tests/run.sh — point d'entrée unique des validations du dépôt.
#
# Toute validation passe par ici : à la main comme depuis l'agent. Un seul
# point d'entrée évite que la commande de validation d'une tâche diverge de
# celle qu'un humain tape réellement.
#
# Un niveau non encore implémenté n'est jamais compté comme réussi. Demandé
# explicitement, il fait sortir en 3 — un code distinct de l'échec, pour qu'un
# validator ne puisse pas confondre « rien à exécuter » et « tout va bien ».
#
# Le code rendu par un niveau est LU, jamais réduit à réussi/échoué. Quatre
# situations, et non deux :
#
#   0   le niveau a tout vérifié, tout a réussi
#   4   le niveau a réussi, mais des cas ne s'appliquent pas à cet
#       environnement — la preuve est partielle, elle existe
#   3   le niveau n'a RIEN pu vérifier — aucune preuve
#   *   au moins un cas est en défaut
#
# « Presque tout est prouvé, trois cas ne s'appliquent pas ici » et « rien n'est
# prouvé » ne portent pas le même verdict : le premier vaut réussite, avec son
# décompte affiché ; le second ne sort jamais en 0.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

TESTS_DIR="$SCRIPTS_ROOT/tests"

# Niveaux dans leur ordre d'exécution. Voir AGENTS.md §10.
NIVEAUX="lint unit integration environment acceptance"

# -------------------------------------------------------------------
# Aide
# -------------------------------------------------------------------
show_help() {
    cat <<'AIDE'
Usage : tests/run.sh [options] [niveau...]

Sans niveau, exécute tous les niveaux implémentés.

Niveaux :
  lint          analyse statique — bash -n, shellcheck si disponible
  unit          tests unitaires de lib/common.sh
  integration   exécution réelle des scripts, dry-run, idempotence
  environment   services et état système — nécessite systemd
  acceptance    critères d'acceptation d'une tâche

Options :
      --liste     Afficher les niveaux et leur état d'implémentation.
  -h, --help      Afficher cette aide

Exemples :
  tests/run.sh
  tests/run.sh lint
  tests/run.sh unit integration

Codes de retour :
  0   tous les niveaux exécutés ont réussi ; les cas non applicables à cet
      environnement, s'il y en a, sont décomptés à l'écran
  1   au moins un niveau a échoué
  2   erreur d'usage
  3   rien n'est prouvé : un niveau demandé explicitement n'est pas
      implémenté, ou un niveau exécuté n'a rien pu vérifier
AIDE
}

# Le script qui porte un niveau, implémenté ou non.
script_du_niveau() {
    case "$1" in
        lint)        printf '%s\n' "$TESTS_DIR/lint.sh" ;;
        unit)        printf '%s\n' "$TESTS_DIR/unit/run-unit.sh" ;;
        integration) printf '%s\n' "$TESTS_DIR/integration/run-integration.sh" ;;
        environment) printf '%s\n' "$TESTS_DIR/environment/run-environment.sh" ;;
        acceptance)  printf '%s\n' "$TESTS_DIR/acceptance/run-acceptance.sh" ;;
        *)           return 1 ;;
    esac
}

niveau_connu() {
    local niveau
    for niveau in $NIVEAUX; do
        if [ "$niveau" = "$1" ]; then
            return 0
        fi
    done
    return 1
}

lister_niveaux() {
    local niveau script
    for niveau in $NIVEAUX; do
        script="$(script_du_niveau "$niveau")"
        if [ -x "$script" ] || [ -f "$script" ]; then
            printf '  %-12s implémenté   (%s)\n' "$niveau" "${script#"$SCRIPTS_ROOT"/}"
        else
            printf '  %-12s NON IMPLÉMENTÉ\n' "$niveau"
        fi
    done
}

# -------------------------------------------------------------------
# Arguments
# -------------------------------------------------------------------
DEMANDES=()

while [ "${1:-}" != "" ]; do
    case "$1" in
        --liste)   lister_niveaux; exit 0 ;;
        -h|--help) show_help; exit 0 ;;
        -*)        die "Option inconnue : $1" 2 ;;
        *)
            niveau_connu "$1" || die "Niveau inconnu : $1 (attendu : $NIVEAUX)" 2
            DEMANDES+=("$1")
            shift
            ;;
    esac
done

EXPLICITE="true"
if [ "${#DEMANDES[@]}" -eq 0 ]; then
    EXPLICITE="false"
    for niveau in $NIVEAUX; do
        DEMANDES+=("$niveau")
    done
fi

# -------------------------------------------------------------------
# Exécution
# -------------------------------------------------------------------
reussis=0    # niveaux dont tous les cas ont réussi, sans réserve
partiels=0   # niveaux réussis, comportant des cas non applicables ici
steriles=0   # niveaux exécutés qui n'ont rien pu vérifier — aucune preuve
echecs=0
absents=0

for niveau in "${DEMANDES[@]}"; do
    script="$(script_du_niveau "$niveau")"

    if [ ! -f "$script" ]; then
        if [ "$EXPLICITE" = "true" ]; then
            warn "Niveau « $niveau » : NON IMPLÉMENTÉ — aucune validation exécutée"
        else
            info "Niveau « $niveau » : non implémenté, ignoré"
        fi
        absents=$((absents + 1))
        continue
    fi

    info "--- Niveau « $niveau » ---"

    # Le code est capturé, pas testé : « if bash "$script" » écraserait le 3 et
    # le 4 en un simple échec. La forme « || code=$? » n'arme pas le trap ERR de
    # lib/common.sh, la commande n'étant pas la dernière d'une liste ||.
    code=0
    bash "$script" || code=$?

    case "$code" in
        0)
            reussis=$((reussis + 1))
            ;;
        4)
            warn "Niveau « $niveau » : RÉUSSI, avec des cas non applicables à cet environnement"
            partiels=$((partiels + 1))
            ;;
        3)
            warn "Niveau « $niveau » : RIEN N'A PU ÊTRE VÉRIFIÉ — aucune preuve produite"
            steriles=$((steriles + 1))
            ;;
        *)
            error "Niveau « $niveau » : ÉCHEC (code $code)"
            echecs=$((echecs + 1))
            ;;
    esac
done

executes=$((reussis + partiels + steriles + echecs))

# -------------------------------------------------------------------
# Bilan
# -------------------------------------------------------------------
if [ "$echecs" -gt 0 ]; then
    die "Validation : $echecs niveau(x) en échec sur $executes exécuté(s)." 1
fi

if [ "$executes" -eq 0 ]; then
    warn "Aucune validation exécutée — rien n'est prouvé."
    exit 3
fi

# Un niveau exécuté qui n'a rien pu vérifier ne vaut pas mieux qu'un niveau
# absent : dans les deux cas, la preuve manque.
if [ "$steriles" -gt 0 ]; then
    warn "Validation : $steriles niveau(x) n'ont rien pu vérifier sur $executes exécuté(s) — rien n'est prouvé pour ceux-là."
    exit 3
fi

if [ "$EXPLICITE" = "true" ] && [ "$absents" -gt 0 ]; then
    warn "Validation : $((reussis + partiels)) niveau(x) réussi(s), $absents non implémenté(s)."
    exit 3
fi

# Des cas non applicables ne changent pas le verdict, mais restent affichés :
# un saut silencieux serait un faux vert.
if [ "$partiels" -gt 0 ]; then
    success "Validation : $executes niveau(x) réussi(s)."
    warn "Dont $partiels niveau(x) comportant des cas non applicables à cet environnement — voir leur bilan ci-dessus."
    exit 0
fi

success "Validation : $executes niveau(x) réussi(s)."
