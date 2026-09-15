#!/usr/bin/env bash
# verifier-liens.sh — liens Markdown morts dans les fichiers vivants (TASK-039, A16).
#
# Une fiche change de répertoire à chaque changement de statut, et tous les liens
# vers elle cassent. /tache lance ce contrôle à la clôture. L'historique (tâches
# terminées, annulées, rapports) n'est pas contrôlé : il décrit ce qui était vrai.
#
# Usage : verifier-liens.sh
# Codes : 0 aucun lien mort — 1 au moins un, listé « MORT fichier -> cible ».
set -Eeuo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$racine"

morts=0
while IFS= read -r trouvaille; do
    fichier="${trouvaille%%:*}"
    cible="${trouvaille##*](}"
    # Une fiche en cours vit dans active/ : un lien vers pending/ reste juste jusqu'à la clôture.
    en_cours="$(dirname "$fichier")/${cible/pending\//active/}"
    if [ ! -e "$(dirname "$fichier")/$cible" ] && [ ! -e "$en_cours" ]; then
        echo "MORT  $fichier -> $cible"
        morts=$((morts + 1))
    fi
done < <(grep -rnoE '\]\([^)#: ]+\.(md|sh|json|env|png|svg)' --include='*.md' \
    CLAUDE.md README.md orchestration .claude tasks/README.md tasks/backlog.md \
    tasks/pending tasks/active docs Linux Docker Synology config tests 2>/dev/null || true)

[ "$morts" -eq 0 ] || { echo "LIENS  $morts lien(s) mort(s)"; exit 1; }
echo "LIENS  aucun lien mort"
