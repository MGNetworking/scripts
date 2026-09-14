#!/usr/bin/env bash
# executer.sh — fait exécuter une fiche N1 ou N2 par DeepSeek (ADR-0005).
#
# Génère, juge, et renvoie une seule fois les lignes en échec à l'exécutant.
# La relecture Opus et la correction par Sonnet restent à l'arbitre.
#
# Usage : executer.sh <fiche> [--exemple chemin]...
# Codes : 0 le juge passe — 1 il échoue encore après correction — 2 usage.
set -Eeuo pipefail

ici="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
racine="$(cd "$ici/../../.." && pwd)"
fiche="${1:-}"
[ -f "$racine/$fiche" ] || { echo "Usage : executer.sh <fiche> [--exemple chemin]..." >&2; exit 2; }
shift

champ() { awk -v k="$1" '/^---$/ {d++} d == 1 && index($0, k ": ") == 1 {print substr($0, length(k) + 3); exit}' "$racine/$fiche"; }
executor="$(champ executor)"
effort="$(champ effort)"
case "$executor" in
    deepseek-*) ;;
    *) echo "executor « ${executor:-absent} » : pas un exécutant par API, voir /tache étape 5." >&2; exit 2 ;;
esac

cd "$racine"
retours="$(mktemp)"
trap 'rm -f "$retours"' EXIT
generer() { node "$ici/deleguer.mjs" . "$executor" "$fiche" --effort "${effort:-low}" "$@"; }

if ! produits="$(generer "$@")"; then printf '%s\n' "$produits"; exit 1; fi
printf '%s\n' "$produits"

if juge="$(bash "$ici/juger.sh" "$fiche")"; then printf '%s\n' "$juge"; exit 0; fi
printf '%s\n' "$juge"

{
    grep '^PRODUIT ' <<<"$produits"
    echo "Le juge automatique a relevé ces échecs. Corrige-les, ne touche à rien d'autre."
    grep -E '^(FAIL |      )' <<<"$juge"
} > "$retours"
echo "[executer] correction automatique, une seule fois"

if ! produits="$(generer --retours "$retours" "$@")"; then printf '%s\n' "$produits"; exit 1; fi
printf '%s\n' "$produits"
juge="$(bash "$ici/juger.sh" "$fiche")" && code=0 || code=$?
printf '%s\n' "$juge"
exit "$code"
