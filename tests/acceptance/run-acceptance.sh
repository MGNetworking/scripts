#!/usr/bin/env bash
# tests/acceptance/run-acceptance.sh — niveau « acceptance » : critères d'acceptation des tâches.
#
# Ce script n'assure aucune vérification lui-même : il exécute chaque fichier
# tests/acceptance/TASK-*.sh, dans l'ordre, et agrège leurs verdicts.
#
# Une tâche ajoute ses preuves en déposant son fichier ici. Aucune liste n'est
# tenue en dur.
#
# Quatre verdicts par fichier, jamais trois :
#
#   0   tous les critères ont été vérifiés et sont satisfaits
#   4   les critères vérifiés sont satisfaits, mais certains cas ne
#       s'appliquaient pas à cet environnement — la preuve est partielle
#   3   AUCUN critère n'a pu être vérifié — rien n'est prouvé
#   *   au moins un critère est en défaut (ÉCHEC)
#
# Le verdict 3 ne se confond pas avec 0 : « pas pu vérifier » n'est pas
# « vérifié ». C'est la règle d'AGENTS.md §10, appliquée fichier par fichier.
#
# Le 4 sépare deux natures de saut que le 3 confondait : « le conteneur n'a pas
# systemd, sept cas sur cent cinquante-six sont hors de portée » n'est pas
# « rien n'a tourné ». Le premier laisse une preuve, le second aucune. Le
# décompte reste affiché dans les deux cas — un saut invisible serait pire que
# le faux vert qu'on cherche à empêcher.

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

reussis=0    # tout vérifié, tout satisfait
partiels=0   # satisfaits, avec des cas non applicables à cet environnement
steriles=0   # aucun critère vérifié — rien n'est prouvé
echoues=0

for fichier in "${fichiers[@]}"; do
    relatif="${fichier#"$SCRIPTS_ROOT"/}"
    info "=== $relatif ==="

    code=0
    bash "$fichier" || code=$?

    case "$code" in
        0) success "$relatif : critères satisfaits"
           reussis=$((reussis + 1)) ;;
        4) warn "$relatif : critères satisfaits, avec des cas non applicables à cet environnement — voir le bilan du fichier ci-dessus"
           partiels=$((partiels + 1)) ;;
        3) warn "$relatif : RIEN N'A PU ÊTRE VÉRIFIÉ — aucun critère prouvé"
           steriles=$((steriles + 1)) ;;
        *) error "$relatif : ÉCHEC (code $code)"
           echoues=$((echoues + 1)) ;;
    esac
done

if [ "$echoues" -gt 0 ]; then
    die "Acceptance : $echoues fichier(s) en échec, $reussis satisfait(s), $partiels partiel(s), $steriles sans preuve." 1
fi

# Un fichier qui n'a rien pu vérifier laisse les critères de sa tâche sans
# preuve : le reste du lot ne rachète pas ce silence.
if [ "$steriles" -gt 0 ]; then
    warn "Acceptance : $steriles fichier(s) n'ont RIEN pu vérifier — rien n'est prouvé pour ceux-là."
    exit 3
fi

if [ "$partiels" -gt 0 ]; then
    success "Acceptance : $((reussis + partiels)) fichier(s) de critères satisfaits."
    warn "Dont $partiels fichier(s) comportant des cas non applicables à cet environnement — les critères correspondants ne sont pas prouvés."
    exit 4
fi

success "Acceptance : $reussis fichier(s) de critères satisfaits."
