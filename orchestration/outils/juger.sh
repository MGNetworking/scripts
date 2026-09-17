#!/usr/bin/env bash
# juger.sh — juge automatique d'une fiche (orchestration/decisions.md, décision 40).
#
# Lance, dans le conteneur de test, shellcheck sur les .sh du périmètre de la
# fiche, son fichier de cas, puis les règles transverses de TASK-011. Aucun jeton.
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

cas=""
for f in "${fichiers[@]}"; do
    [ -f "$racine/$f" ] || { echo "FAIL  fichier absent : $f"; exit 1; }
    case "$f" in *.test.sh) cas="$f" ;; esac
done
[ -n "$cas" ] || { echo "FAIL  aucun fichier de cas dans le périmètre de $fiche"; exit 1; }

cd "$racine"
# Faux binaire écrit à travers un lien (A122, tests/README.md) : « ln -s » puis « > »
# vers le même chemin remplace le vrai binaire du conteneur. Refusé avant tout
# lancement. Comparaison textuelle des chemins ; seuls sont développés les
# « for v in … » et l'argument d'une fonction qui écrit « …/$1 ».
lien_ecrit="$(awk '
    function net(s) { gsub(/["{}]/, "", s); return s }
    function dev(p, prof,   v, n, i, it, r, av, ap) {
        if (prof < 4) for (v in liste) if (match(p, "[$]" v "([^A-Za-z0-9_]|$)")) {
            # RSTART gardé : les appels imbriqués le réécrivent.
            av = substr(p, 1, RSTART - 1); ap = substr(p, RSTART + 1 + length(v))
            n = split(liste[v], it, " "); r = ""
            for (i = 1; i <= n; i++) r = r " " dev(av it[i] ap, prof + 1)
            return r
        }
        return p
    }
    function ecrit(p,   n, i, it) {
        n = split(dev(net(p), 0), it, " ")
        for (i = 1; i <= n; i++) if (it[i] in lien)
            printf "FAIL  faux binaire écrit à travers un lien : %s:%d, %s (lien ligne %d) — tests/README.md\n",
                FILENAME, FNR, it[i], lien[it[i]]
    }
    {
        l = $0; sub(/(^|[ \t])#.*/, "", l)
        if (match(l, /for [A-Za-z_][A-Za-z0-9_]* in [^;]*/)) {
            s = substr(l, RSTART, RLENGTH); split(s, m, " ")
            liste[m[2]] = net(substr(s, 9 + length(m[2])))
        }
        if (match(l, /(^|[;&|{( \t])ln +-[A-Za-z]*s[^;&|]*/)) {
            n = split(substr(l, RSTART, RLENGTH), m, " ")
            n = split(dev(net(m[n]), 0), d, " ")
            for (i = 1; i <= n; i++) if (!(d[i] in lien)) lien[d[i]] = FNR
        }
        if (match(l, /^[ \t]*[A-Za-z_][A-Za-z0-9_]*\(\)/)) {
            f = substr(l, RSTART, RLENGTH - 2); sub(/^[ \t]*/, "", f)
            if (match(l, /[^0-9&>]>>? *"?[^" ;|&)]*\$1/)) {
                p = net(substr(l, RSTART, RLENGTH)); sub(/^[^>]*>+ */, "", p); fonction[f] = p; next
            }
        }
        for (f in fonction) if (match(l, "(^|[;&|{( \t])" f " +[A-Za-z0-9_.-]+")) {
            a = substr(l, RSTART, RLENGTH); sub(/^.*[ \t]/, "", a)
            p = fonction[f]; sub(/\$1/, a, p); ecrit(p)
        }
        while (match(l, /(^|[^0-9&>])>>? *"?[^" ;|&)<>]+/)) {
            p = substr(l, RSTART, RLENGTH); l = substr(l, RSTART + RLENGTH)
            sub(/^[^>]*>+ */, "", p); ecrit(p)
        }
    }' "$cas")"
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
