#!/usr/bin/env bash
# verifier-travail.sh — étape 5 de /tache : vérifier le travail d'un agent sans le
# croire sur parole, par un script déterministe plutôt que par un modèle.
#
# Quatre contrôles, une ligne de verdict chacun :
#   PERIMETRE   les fichiers modifiés entre master et la branche sont tous au scope
#   LONGUEUR    les .sh du scope tiennent dans 150 lignes (signalé, jamais bloquant, A43)
#   JUGE        orchestration/outils/juger.sh sur la fiche
#   VALIDATION  chaque commande du champ validation, avec son code réel
#
# Usage : verifier-travail.sh <TASK-XXX> [options]
#   --ref <ref>        ref Git à vérifier (défaut : agent/<TASK-XXX>)
#   --base <ref>       ref dont elle part (défaut : master ; utile sur une branche
#                      déjà fusionnée, dont master n'est plus le point de départ)
#   --copie <chemin>   arbre où lancer juge et validations
#                      (défaut : ../script-agents/<TASK-XXX>, sinon la racine du dépôt)
#   --sans-validation  contrôle le périmètre, la longueur et le juge seulement
#   --perimetre        contrôle le périmètre et la longueur seulement
# Codes : 0 tout passe — 1 un contrôle en défaut — 2 usage.
set -Eeuo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
usage() { sed -n '/^# Usage/,/^# Codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

tache=""; ref=""; base="master"; copie=""; avec_juge=1; avec_validation=1
while [ $# -gt 0 ]; do
    case "$1" in
        --ref) shift; ref="${1:-}" ;;
        --base) shift; base="${1:-}" ;;
        --copie) shift; copie="${1:-}" ;;
        --sans-validation) avec_validation=0 ;;
        --perimetre) avec_juge=0; avec_validation=0 ;;
        -h|--help) usage ;;
        TASK-*) tache="$1" ;;
        *) echo "Option inconnue : $1" >&2; usage ;;
    esac
    shift
done
[ -n "$tache" ] || usage

fiche=""
for d in active pending blocked completed; do
    [ -f "$racine/tasks/$d/$tache.md" ] && { fiche="tasks/$d/$tache.md"; break; }
done
[ -n "$fiche" ] || { echo "FAIL  fiche introuvable : $tache" >&2; exit 2; }
ref="${ref:-agent/$tache}"
git -C "$racine" rev-parse --verify -q "$ref^{commit}" >/dev/null \
    || { echo "FAIL  ref Git inconnue : $ref" >&2; exit 2; }
if [ -z "$copie" ]; then
    copie="$racine/../script-agents/$tache"
    [ -d "$copie" ] || copie="$racine"
fi

# Les entrées d'un bloc de la fiche, une par ligne, tiret et guillemets ôtés.
entrees() {
    awk -v bloc="^$1:" '
        $0 ~ bloc {d = 1; next}
        /^[a-z_]+:/ {d = 0}
        d && /^[[:space:]]*-[[:space:]]/ {
            sub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/^"|"$/, ""); print
        }' "$racine/$fiche"
}

echec=0
mapfile -t scope < <(entrees scope | awk '{print $1}')

total=0; hors=0; preuves=0
while IFS=$'\t' read -r etat f; do
    [ -n "$f" ] || continue
    total=$((total + 1))
    admis=0
    for s in ${scope[@]+"${scope[@]}"}; do
        s="${s%/}"
        if [ "$f" = "$s" ] || [ "${f#"$s"/}" != "$f" ]; then admis=1; break; fi
    done
    # Un fichier de cas AJOUTÉ sous tests/ est la preuve que le processus exige, et
    # qu'un scope nomme rarement : admis, mais compté à part. Un test MODIFIÉ hors
    # scope reste un débordement — c'est le garde-fou de l'étape 5.3 de /tache.
    if [ "$admis" = 0 ] && [ "$etat" = A ] && [ "${f#tests/}" != "$f" ]; then
        admis=1; preuves=$((preuves + 1))
        echo "PREUVE  fichier de cas ajouté hors scope : $f"
    fi
    if [ "$admis" = 0 ]; then
        echo "FAIL  hors périmètre ($etat) : $f"
        hors=$((hors + 1))
    fi
done < <(git -C "$racine" diff --name-status --no-renames "$base...$ref")

if [ "$total" -eq 0 ]; then
    echo "PERIMETRE  aucun fichier modifié entre $base et $ref : ÉCHEC"
    echec=1; etat_perimetre="ÉCHEC"
elif [ "$hors" -eq 0 ]; then
    echo "PERIMETRE  $total fichiers, $((total - preuves)) au scope, $preuves de preuve : PASSE"
    etat_perimetre="PASSE"
else
    echo "PERIMETRE  $total fichiers, $hors hors scope : ÉCHEC"
    echec=1; etat_perimetre="ÉCHEC"
fi

# Longueur : la cible de 150 lignes souffre une raison écrite (A43) — d'où le
# simple signalement, que le relecteur tranche.
for s in ${scope[@]+"${scope[@]}"}; do
    case "$s" in *.sh) ;; *) continue ;; esac
    [ -f "$copie/$s" ] || continue
    n="$(wc -l < "$copie/$s")"
    [ "$n" -le 150 ] || echo "LONGUEUR  $s : $n lignes (cible 150) — raison à donner au rapport"
done

etat_juge="non demandé"
if [ "$avec_juge" = 1 ]; then
    code=0
    sortie="$(bash "$copie/orchestration/outils/juger.sh" "$fiche" 2>&1)" || code=$?
    printf '%s\n' "$sortie" | sed 's/^/  /'
    if [ "$code" = 0 ]; then etat_juge="PASSE"; else etat_juge="ÉCHEC ($code)"; echec=1; fi
fi

etat_valid="non demandées"
if [ "$avec_validation" = 1 ]; then
    n=0; passees=0
    journal="$(mktemp)"
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        n=$((n + 1)); code=0
        (cd "$copie" && bash -c "$cmd") > "$journal" 2>&1 || code=$?
        # 4 : la suite a réussi, des cas n'ont pas tourné — preuve partielle mais
        # existante, lue comme telle par tests/run.sh.
        if [ "$code" = 0 ] || [ "$code" = 4 ]; then
            passees=$((passees + 1))
            echo "VALIDATION  $cmd : $code"
        else
            echo "VALIDATION  $cmd : $code — ÉCHEC"
            tail -n 15 "$journal" | sed 's/^/  /'
        fi
    done < <(entrees validation)
    rm -f "$journal"
    etat_valid="$passees/$n"
    [ "$passees" = "$n" ] || echec=1
    [ "$n" -gt 0 ] || { echo "VALIDATION  aucune commande au champ validation : ÉCHEC"; echec=1; }
fi

verdict="FUSIONNABLE"
[ "$echec" = 0 ] || verdict="ÉCHEC"
echo "VERDICT  périmètre $etat_perimetre · juge $etat_juge · validations $etat_valid : $verdict"
exit "$echec"
