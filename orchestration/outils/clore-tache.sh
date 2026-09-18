#!/usr/bin/env bash
# clore-tache.sh — étape 8 de /tache : les gestes mécaniques de la clôture d'une
# tâche terminée, faits par un script plutôt que par un modèle.
#
# Contrôle d'abord (rapport présent, Axx des réserves inscrits au registre), écrit
# ensuite : fiche vers tasks/completed/, ligne du backlog et section « Terminé »,
# ligne du journal, lignes de mesure, puis verifier-liens.sh. Ne commite rien et
# n'écrit aucun texte : le rapport, la ligne de journal et les mesures sont fournis.
# Une tâche bloquée se clôt à la main (étape 8 de /tache).
#
# Usage : clore-tache.sh <TASK-XXX> --journal <fichier> [--mesures <fichier>]
#   --journal <fichier>  la ligne « | … | » du tableau de orchestration/mesures/journal.md
#   --mesures <fichier>  lignes à ajouter à orchestration/mesures/agents.tsv (11 colonnes)
# Codes : 0 clôture écrite — 1 contrôle en défaut, rien n'est écrit — 2 usage.
set -Eeuo pipefail

racine="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
usage() { sed -n '/^# Usage/,/^# Codes/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

tache=""; f_journal=""; f_mesures=""
while [ $# -gt 0 ]; do
    case "$1" in
        --journal) shift; f_journal="${1:-}" ;;
        --mesures) shift; f_mesures="${1:-}" ;;
        -h|--help) usage ;;
        TASK-*) tache="$1" ;;
        *) echo "Option inconnue : $1" >&2; usage ;;
    esac
    shift
done
if [ -z "$tache" ] || [ -z "$f_journal" ]; then usage; fi
cd "$racine"

fiche="tasks/active/$tache.md"
rapport="tasks/reports/$tache-report.md"
registre="tasks/pending/TASK-039.md"
backlog="tasks/backlog.md"
journal="orchestration/mesures/journal.md"
mesures="orchestration/mesures/agents.tsv"

# --- Contrôles, avant toute écriture -----------------------------------------
echec=0
signaler() { echo "FAIL  $*"; echec=1; }

[ -f "$fiche" ] || signaler "fiche absente de tasks/active/ : $tache"
[ -f "$rapport" ] || signaler "rapport absent : $rapport"
[ -f "$f_journal" ] || signaler "fichier de ligne de journal absent : $f_journal"
[ -z "$f_mesures" ] || [ -f "$f_mesures" ] || signaler "fichier de mesures absent : $f_mesures"

ligne_backlog="$(grep -n "^| \[$tache\](" "$backlog" | head -1 | cut -d: -f1 || true)"
[ -n "$ligne_backlog" ] || signaler "aucune ligne « | [$tache](… » dans $backlog"

if [ -f "$f_journal" ]; then
    n="$(grep -c '^|' "$f_journal" || true)"
    [ "$n" = 1 ] || signaler "$f_journal : $n ligne(s) de tableau, une seule attendue"
fi
if [ -n "$f_mesures" ] && [ -f "$f_mesures" ]; then
    awk -F'\t' 'NF != 11 {print "  ligne " NR " : " NF " colonnes"; c = 1} END {exit c + 0}' \
        "$f_mesures" || signaler "$f_mesures : 11 colonnes attendues par ligne"
fi

# Contrôle avant de clore : chaque Axx cité en réserve existe au registre.
if [ -f "$rapport" ]; then
    mapfile -t cites < <(awk '/^#+ .*[Rr]éserve/ {d = 1; next} /^#+ /  {d = 0} d' "$rapport" \
        | grep -oE '\bA[0-9]{2,3}\b' | sort -u)
    manquants=0
    for a in ${cites[@]+"${cites[@]}"}; do
        grep -qE "^\| \[.\] \| $a \|" "$registre" \
            || { signaler "réserve $a absente du registre $registre"; manquants=$((manquants + 1)); }
    done
    echo "CONTROLE  réserves du rapport : ${#cites[@]} Axx cités, $manquants hors registre"
fi

# Les deux points d'insertion, cherchés avant d'écrire quoi que ce soit : sans eux,
# une ligne se perdrait en silence pendant que la sortie annoncerait le succès.
ligne_termine="$(awk '/^## .*Terminé/ {d = NR} d && NR > d && /^\| \[TASK-/ {n = NR} END {print n + 0}' "$backlog")"
ligne_journal="$(awk '/^\| TASK-/ {n = NR} END {print n + 0}' "$journal")"
[ "$ligne_termine" -gt 0 ] || signaler "aucune ligne « | [TASK-… » sous « ## … Terminé » de $backlog"
[ "$ligne_journal" -gt 0 ] || signaler "aucune ligne « | TASK-… » dans $journal"

[ "$echec" = 0 ] || { echo "CLOTURE  contrôles en défaut : rien n'a été écrit"; exit 1; }

# --- Écritures ----------------------------------------------------------------
# Insérer après une ligne donnée, sans réécrire le reste : awk lit le texte dans
# l'environnement, ce qui laisse intacts barres, crochets et accents.
inserer_apres() {
    local fichier="$1" n="$2" tmp
    tmp="$(mktemp)"
    texte="$3" awk -v n="$n" '{print} NR == n {print ENVIRON["texte"]}' "$fichier" > "$tmp"
    mv "$tmp" "$fichier"
}

titre="$(awk -F'|' -v t="[$tache](" 'index($2, t) {gsub(/^ +| +$/, "", $3); print $3; exit}' "$backlog")"

# Ligne du tableau de suivi : lien vers completed/, statut completed.
sed -i "${ligne_backlog}s#\](\(pending\|active\|blocked\)/$tache\.md)#](completed/$tache.md)#" "$backlog"
sed -i "${ligne_backlog}s#| \`\(ready\|in_progress\|validating\|pending\|blocked\)\` |#| \`completed\` |#" "$backlog"

inserer_apres "$backlog" "$ligne_termine" \
    "| [$tache](completed/$tache.md) | $titre | [rapport](reports/$tache-report.md) |"
echo "CLOTURE  backlog : statut completed, ligne ajoutée à « Terminé » (ligne $ligne_termine)"

inserer_apres "$journal" "$ligne_journal" "$(cat "$f_journal")"
echo "CLOTURE  journal : 1 ligne ajoutée après la ligne $ligne_journal"

if [ -n "$f_mesures" ]; then
    cat "$f_mesures" >> "$mesures"
    echo "CLOTURE  agents.tsv : $(wc -l < "$f_mesures") ligne(s) ajoutée(s)"
fi

git mv "$fiche" "tasks/completed/$tache.md"
sed -i 's/^status: .*/status: completed/' "tasks/completed/$tache.md"
echo "CLOTURE  fiche → tasks/completed/$tache.md, status: completed"

code=0
bash orchestration/outils/verifier-liens.sh > /dev/null 2>&1 || code=$?
[ "$code" = 0 ] || { echo "FAIL  verifier-liens.sh : $code — liens cassés par le déplacement"; echec=1; }
echo "LIENS  verifier-liens.sh : $code"

# Ce qui reste au conducteur : le README du dossier, les statuts débloqués, le commit.
numero="${tache#TASK-}"
for f in tasks/pending/*.md; do
    grep -qE "^depends_on:.*\b0*$numero\b" "$f" && echo "À FAIRE  dépendante à passer en ready : $f"
done
echo "À FAIRE  README du dossier, puis : git add -A && git commit (ligne « Tâche : $tache »)"
exit "$echec"
