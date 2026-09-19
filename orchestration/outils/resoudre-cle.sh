#!/usr/bin/env bash
# resoudre-cle.sh <NOM> — écrit sur stdout la valeur de la variable NOM (TASK-097).
# Ordre : environnement, puis variable utilisateur de Windows. Le harnais ne retransmet
# pas toujours les variables ANTHROPIC_* à ses outils, alors que Windows les porte.
# Codes : 0 trouvée — 1 introuvable, rien n'est écrit — 2 nom invalide.
set -Eeuo pipefail

nom="${1:-}"
[[ "$nom" =~ ^[A-Z][A-Z0-9_]*$ ]] || { echo "Usage : resoudre-cle.sh <NOM_DE_VARIABLE>" >&2; exit 2; }

valeur="${!nom:-}"
if [ -z "$valeur" ] && command -v powershell.exe > /dev/null 2>&1; then
    valeur="$(powershell.exe -NoProfile -Command \
        "[Environment]::GetEnvironmentVariable('$nom','User')" 2> /dev/null | tr -d '\r')" || valeur=""
fi
[ -n "$valeur" ] || exit 1
printf '%s\n' "$valeur"
