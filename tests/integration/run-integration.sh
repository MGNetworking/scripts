#!/usr/bin/env bash
# tests/integration/run-integration.sh — niveau « integration » : exécution réelle.
#
# C'est le chemin qu'annonce « tests/run.sh --liste » pour ce niveau. Aucune
# modification de tests/run.sh n'est nécessaire : déposer ce fichier suffit à
# rendre le niveau implémenté.
#
# Ce script ne vérifie rien lui-même : il exécute chaque fichier
# tests/integration/*.test.sh et agrège leurs verdicts, exactement comme
# run-unit.sh le fait pour le niveau « unit ».
#
# Quatre verdicts par fichier, jamais deux :
#
#   0   tous les cas ont été exécutés et ont réussi
#   4   les cas exécutés ont réussi, mais certains ne s'appliquaient pas à cet
#       environnement — la preuve est partielle, elle existe
#   3   AUCUN cas n'a pu être exécuté — rien n'est prouvé
#   *   au moins un cas est en défaut (ÉCHEC)
#
# La découverte est en « maxdepth 1 », comme pour l'unit et l'acceptance : un
# fichier de cas destiné à un autre environnement se range dans un
# sous-répertoire et n'est alors pas ramassé ici.
#
# CE NIVEAU MODIFIE LE SYSTÈME SUR LEQUEL IL TOURNE. Il crée un fichier
# d'échange, réécrit /etc/hosts, /etc/localtime et /etc/logrotate.d : il n'a
# rien à faire sur une machine de travail. Il s'exécute dans le conteneur
# jetable, et nulle part ailleurs :
#
#   tests/env/run-in-container.sh -- tests/run.sh integration
#
# Les fichiers de cas se protègent eux-mêmes — ils refusent de modifier un
# système qui n'est pas jetable — mais la garde de premier rang est ici : ne
# pas lancer ce niveau à la main sur un serveur.

set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

REPERTOIRE="$SCRIPTS_ROOT/tests/integration"

fichiers=()
while IFS= read -r f; do
    fichiers+=("$f")
done < <(find "$REPERTOIRE" -maxdepth 1 -type f -name '*.test.sh' | sort)

if [ "${#fichiers[@]}" -eq 0 ]; then
    warn "Aucun fichier tests/integration/*.test.sh — rien n'est prouvé."
    exit 3
fi

info "Integration — ${#fichiers[@]} fichier(s) de cas"

reussis=0    # tout exécuté, tout réussi
partiels=0   # réussis, avec des cas non applicables à cet environnement
steriles=0   # aucun cas exécuté — rien n'est prouvé
echoues=0

for fichier in "${fichiers[@]}"; do
    relatif="${fichier#"$SCRIPTS_ROOT"/}"
    info "=== $relatif ==="

    # Le code est capturé, pas testé : « if bash "$fichier" » écraserait le 3 et
    # le 4 en un simple échec. La forme « || code=$? » n'arme pas le trap ERR de
    # lib/common.sh, la commande n'étant pas la dernière d'une liste ||.
    code=0
    bash "$fichier" || code=$?

    case "$code" in
        0) success "$relatif : tous les cas vérifiés"
           reussis=$((reussis + 1)) ;;
        4) warn "$relatif : cas vérifiés satisfaits, avec des cas non applicables à cet environnement — voir le bilan du fichier ci-dessus"
           partiels=$((partiels + 1)) ;;
        3) warn "$relatif : RIEN N'A PU ÊTRE VÉRIFIÉ — aucun cas prouvé"
           steriles=$((steriles + 1)) ;;
        *) error "$relatif : ÉCHEC (code $code)"
           echoues=$((echoues + 1)) ;;
    esac
done

if [ "$echoues" -gt 0 ]; then
    die "Integration : $echoues fichier(s) en échec, $reussis complet(s), $partiels partiel(s), $steriles sans preuve." 1
fi

# Un fichier qui n'a rien pu vérifier laisse les scripts concernés sans preuve
# d'exécution : le reste du lot ne rachète pas ce silence.
if [ "$steriles" -gt 0 ]; then
    warn "Integration : $steriles fichier(s) n'ont RIEN pu vérifier — rien n'est prouvé pour ceux-là."
    exit 3
fi

if [ "$partiels" -gt 0 ]; then
    success "Integration : $((reussis + partiels)) fichier(s) de cas satisfaits."
    warn "Dont $partiels fichier(s) comportant des cas non applicables à cet environnement — les cas correspondants ne sont pas prouvés."
    exit 4
fi

success "Integration : $reussis fichier(s) de cas satisfaits."
