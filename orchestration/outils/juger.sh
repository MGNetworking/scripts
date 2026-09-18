#!/usr/bin/env bash
# juger.sh — juge automatique d'une fiche (orchestration/decisions.md, décision 40).
#
# Lance, dans le conteneur de test, shellcheck sur les .sh du périmètre de la
# fiche, son fichier de cas, puis les règles transverses de TASK-011. Aucun jeton.
#
# Une fiche dont le périmètre ne vise que Ansible/ n'a pas de fichier de cas : elle
# est jugée sur la présence d'un scénario Molecule complet (A158, décision 50).
# Une fiche qui ne livre ni .sh ni rôle — un cadrage, une documentation — est « sans
# objet » et passe ; seul un scope vide reste un défaut (A172).
#
# Usage : juger.sh <fiche>
# Codes : 0 tout passe — 1 échec, lignes « FAIL » sur la sortie — 2 usage.
set -Eeuo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fiche="${1:-}"
[ -f "$racine/$fiche" ] || { echo "Usage : juger.sh <fiche>" >&2; exit 2; }

# Les .sh du périmètre : le script et son fichier de cas.
mapfile -t fichiers < <(awk '
    /^scope:/ {s=1; next}
    /^[a-z_]+:/ {s=0}
    s && match($0, /(Docker|Linux|Kubernetes|Synology)\/[^ ]+\.sh|tests\/integration\/[^ ]+\.test\.sh/) {
        print substr($0, RSTART, RLENGTH)
    }' "$racine/$fiche")

# Un rôle Ansible ne livre pas de fichier de cas : il se prouve par un scénario
# Molecule (décision 50). Les chemins Ansible du périmètre, et les rôles qui s'en
# déduisent, servent à juger sa présence — jamais à le lancer (A158).
mapfile -t ansible < <(awk '
    /^scope:/ {s=1; next}
    /^[a-z_]+:/ {s=0}
    s && match($0, /Ansible\/[^ ,]+/) {
        print substr($0, RSTART, RLENGTH)
    }' "$racine/$fiche")
mapfile -t roles < <(printf '%s\n' ${ansible[@]+"${ansible[@]}"} \
    | sed -n 's#^\(Ansible/roles/[A-Za-z0-9_-]\+\).*#\1#p' | sort -u)

# Les entrées brutes du périmètre : elles seules distinguent une fiche mal formée,
# au scope vide, d'une tâche documentaire qui ne livre ni script ni rôle (A172).
mapfile -t entrees < <(awk '
    /^scope:/ {s=1; next}
    /^[a-z_]+:/ {s=0}
    s && /^[[:space:]]*-[[:space:]]/ {sub(/^[[:space:]]*-[[:space:]]*/, ""); print}' "$racine/$fiche")

# Présence du scénario : molecule/<nom>/ avec molecule.yml, converge.yml, verify.yml.
juger_ansible() {
    local role scenario f manque trouve echec=0
    if [ "${#roles[@]}" -eq 0 ]; then
        echo "FAIL  périmètre Ansible sans rôle : aucun Ansible/roles/<nom>/ dans le scope de $fiche"
        echo "JUGE  scénario Molecule : ÉCHEC"
        return 1
    fi
    for role in "${roles[@]}"; do
        trouve=""; manque=""
        for scenario in "$racine/$role"/molecule/*/; do
            [ -d "$scenario" ] || continue
            manque=""
            for f in molecule.yml converge.yml verify.yml; do
                [ -f "$scenario$f" ] || manque="$manque $f"
            done
            if [ -n "$manque" ]; then continue; fi
            trouve="${scenario#"$racine"/}"
            break
        done
        if [ -n "$trouve" ]; then
            echo "JUGE  scénario Molecule ${trouve%/} (molecule.yml, converge.yml, verify.yml) : PASSE"
        else
            echo "FAIL  $role : aucun scénario Molecule complet sous molecule/<nom>/"
            echo "FAIL  attendus : molecule.yml, converge.yml, verify.yml${manque:+ — manquants :$manque}"
            echec=1
        fi
    done
    [ "$echec" = 0 ] || echo "JUGE  scénario Molecule : ÉCHEC"
    return "$echec"
}

cas=""
for f in "${fichiers[@]}"; do
    [ -f "$racine/$f" ] || { echo "FAIL  fichier absent : $f"; exit 1; }
    case "$f" in *.test.sh) cas="$f" ;; esac
done
# Périmètre sans aucun .sh mais visant Ansible/ : c'est Molecule qui fait foi.
if [ -z "$cas" ] && [ "${#fichiers[@]}" -eq 0 ] && [ "${#ansible[@]}" -gt 0 ]; then
    if juger_ansible; then exit 0; else exit 1; fi
fi
# Périmètre sans aucun .sh ni rôle : documentaire, ou fiche mal formée (A172). Les
# deux rendaient le même « aucun fichier de cas » ; seul le second est un défaut.
if [ -z "$cas" ] && [ "${#fichiers[@]}" -eq 0 ] && [ "${#ansible[@]}" -eq 0 ]; then
    if [ "${#entrees[@]}" -eq 0 ]; then
        echo "FAIL  périmètre vide : aucune entrée sous « scope: » dans $fiche"
        echo "JUGE  périmètre vide : ÉCHEC"
        exit 1
    fi
    if ! printf '%s\n' "${entrees[@]}" | grep -qE '\.sh([^A-Za-z0-9]|$)'; then
        echo "JUGE  périmètre documentaire (${#entrees[@]} entrées, aucun .sh, aucun rôle Ansible) : SANS OBJET"
        exit 0
    fi
fi
[ -n "$cas" ] || { echo "FAIL  aucun fichier de cas dans le périmètre de $fiche"; exit 1; }

cd "$racine"
# Faux binaire écrit à travers un lien (A122, tests/README.md) : refusé avant tout
# lancement, il remplacerait le vrai binaire du conteneur.
lien_ecrit="$(awk -f orchestration/outils/lien-ecrit.awk "$cas")"
[ -z "$lien_ecrit" ] || { echo "$lien_ecrit"; echo "JUGE  fichier de cas refusé avant lancement : ÉCHEC"; exit 1; }

# Le conteneur rend le code de sa propre enveloppe : les verdicts utiles sont
# imprimés par la commande elle-même, puis relus.
sortie="$(bash tests/env/run-in-container.sh -- bash -c \
    "shellcheck -x -f gcc ${fichiers[*]}; echo SHELLCHECK=\$?; bash $cas; echo CAS=\$?; bash tests/acceptance/TASK-011-analyse-statique.sh; echo REGLES=\$?" 2>&1 || true)"

sc="$(sed -n 's/^SHELLCHECK=//p' <<<"$sortie")"
tc="$(sed -n 's/^CAS=//p' <<<"$sortie")"
# Règles transverses du dépôt (directives justifiées, ASSUME_YES…) : 1 seul est un échec (A02).
rg="$(sed -n 's/^REGLES=//p' <<<"$sortie")"

grep -E '\[SC[0-9]{4}\]$' <<<"$sortie" | sed 's/^/FAIL  /' || true
# Chaque échec du harnais est suivi, en retrait, de son détail (attendu, obtenu).
awk '/ÉCHEC :/ {sub(/^\[ERROR\] /, ""); print "FAIL  " $0; d=1; next}
     d && /^        / {sub(/^ +/, ""); print "      " $0; next}
     {d=0}' <<<"$sortie"
grep -E 'Bilan ' <<<"$sortie" | sed 's/^\[INFO\] //' || true
# Longueur (A43) : signalée, jamais bloquante — la cible de 150 lignes souffre une raison écrite.
for f in "${fichiers[@]}"; do
    n="$(wc -l < "$f")"
    [ "$n" -le 150 ] || echo "LONGUEUR  $f : $n lignes (cible 150) — raison à donner sur la ligne VERDICT"
done

# 4 : cas sautés par nature, preuve partielle mais existante.
if [ "$sc" = 0 ] && { [ "$tc" = 0 ] || [ "$tc" = 4 ]; } && [ "${rg:-1}" != 1 ]; then
    echo "JUGE  shellcheck $sc, fichier de cas $tc, règles du dépôt $rg : PASSE"
    exit 0
fi
echo "JUGE  shellcheck ${sc:-?}, fichier de cas ${tc:-?}, règles du dépôt ${rg:-?} : ÉCHEC"
exit 1
