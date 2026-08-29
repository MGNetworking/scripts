#!/usr/bin/env bash
# tests/acceptance/run-acceptance.sh — niveau « acceptance » : critères d'acceptation des tâches.
#
# Ce script n'assure aucune vérification lui-même : il exécute chaque fichier
# tests/acceptance/TASK-*.sh, dans l'ordre, et agrège leurs verdicts.
#
# Une tâche ajoute ses preuves en déposant son fichier ici. Aucune liste n'est
# tenue en dur.
#
# Trois verdicts par fichier, jamais deux :
#
#   0   les critères vérifiés sont satisfaits
#   3   au moins un critère n'a PAS PU être vérifié (NON EXÉCUTÉ)
#   *   au moins un critère est en défaut (ÉCHEC)
#
# Le verdict 3 ne se confond pas avec 0 : « pas pu vérifier » n'est pas
# « vérifié ». C'est la règle d'AGENTS.md §10, appliquée fichier par fichier.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

REPERTOIRE="$SCRIPTS_ROOT/tests/acceptance"

fichiers=()
while IFS= read -r f; do
    fichiers+=("$f")
done < <(find "$REPERTOIRE" -maxdepth 1 -type f -name 'TASK-*.sh' | sort)

if [ "${#fichiers[@]}" -eq 0 ]; then
    warn "Aucun fichier tests/acceptance/TASK-*.sh — rien n'est prouvé."
    exit 3
fi

info "Acceptance — ${#fichiers[@]} fichier(s) de critères"

reussis=0
echoues=0
non_executes=0

for fichier in "${fichiers[@]}"; do
    relatif="${fichier#"$SCRIPTS_ROOT"/}"
    info "=== $relatif ==="

    code=0
    bash "$fichier" || code=$?

    case "$code" in
        0) success "$relatif : critères satisfaits"
           reussis=$((reussis + 1)) ;;
        3) warn "$relatif : NON EXÉCUTÉ (au moins un critère non vérifiable)"
           non_executes=$((non_executes + 1)) ;;
        *) error "$relatif : ÉCHEC (code $code)"
           echoues=$((echoues + 1)) ;;
    esac
done

if [ "$echoues" -gt 0 ]; then
    die "Acceptance : $echoues fichier(s) en échec, $reussis réussi(s), $non_executes non exécuté(s)." 1
fi

if [ "$non_executes" -gt 0 ]; then
    warn "Acceptance : $reussis fichier(s) réussi(s), $non_executes NON EXÉCUTÉ(s) — rien n'est prouvé pour ceux-là."
    exit 3
fi

success "Acceptance : $reussis fichier(s) de critères satisfaits."
