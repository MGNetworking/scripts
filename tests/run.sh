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
  0   tous les niveaux exécutés ont réussi
  1   au moins un niveau a échoué
  2   erreur d'usage
  3   un niveau demandé explicitement n'est pas implémenté
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
executes=0
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
    if bash "$script"; then
        executes=$((executes + 1))
    else
        error "Niveau « $niveau » : ÉCHEC"
        executes=$((executes + 1))
        echecs=$((echecs + 1))
    fi
done

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

if [ "$EXPLICITE" = "true" ] && [ "$absents" -gt 0 ]; then
    warn "Validation : $executes niveau(x) réussi(s), $absents non implémenté(s)."
    exit 3
fi

success "Validation : $executes niveau(x) réussi(s)."
