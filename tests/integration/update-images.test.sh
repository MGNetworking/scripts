#!/usr/bin/env bash
# tests/integration/update-images.test.sh — Docker/Maintenance/update-images.sh, TASK-035.
# Pas de démon Docker ici : un faux « docker » en tête de PATH trace les arguments
# reçus et répond ce qu'on lui demande. Aucun registre n'est contacté, et rien
# n'est écrit dans config/.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

BASH_BIN="$(command -v bash)"; CIBLE="$SCRIPTS_ROOT/Docker/Maintenance/update-images.sh"
BAC="$(mktemp -d)"; TRACE="$BAC/appels"; LOGS="$BAC/journal"
trap 'rm -rf "$BAC"' EXIT

# Le faux docker rend les identifiants AVANT tant qu'aucun « pull » n'est tracé,
# les APRÈS ensuite : c'est ce qui permet d'éprouver le tableau avant / après.
cat > "$BAC/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TRACE"
ident() {
    table="$TABLE_AVANT"; grep -q ' pull$' "$TRACE" && table="$TABLE_APRES"
    for l in $table; do case "$l" in "$1="*) printf '%s' "${l#*=}"; return 0 ;; esac; done
}
case "$*" in
    "compose version"*)               [ -n "$P_COMPOSE" ] || exit 1; printf 'Docker Compose version %s\n' "$P_COMPOSE" ;;
    "version --format"*)              [ -n "$P_DEMON" ] || exit 1; printf '%s\n' "$P_DEMON" ;;
    "compose -f "*" config --images") [ -n "$P_IMAGES" ] || exit 1; printf '%s\n' "$P_IMAGES" ;;
    "compose -f "*" pull")            printf 'Image pulled\n' ;;
    "image inspect"*)                 ident "${*##* }" ;;
    *)                                exit 1 ;;
esac
STUB
SANS_DOCKER="$BAC/sans-docker"; mkdir -p "$SANS_DOCKER"
for b in dirname basename mkdir id date awk sed grep cat timeout; do
    c="$(command -v "$b" || true)"; [ -z "$c" ] || ln -s "$c" "$SANS_DOCKER/$b"
done; V1="$BAC/v1"; PROJET="$BAC/mon-projet"; VIDE="$BAC/repertoire-vide"
mkdir -p "$V1" "$PROJET" "$VIDE"; : > "$PROJET/compose.yaml"; chmod +x "$BAC/docker"
printf '#!/bin/sh\nexit 0\n' > "$V1/docker-compose"; chmod +x "$V1/docker-compose"

P_IMAGES=$'exemple/api:1.0\nexemple/web:2.3'
TABLE_AVANT=$'exemple/api:1.0=sha256:aaaa0000111122223333\nexemple/web:2.3=sha256:bbbb4444555566667777'
TABLE_APRES=$'exemple/api:1.0=sha256:cccc8888999900001111\nexemple/web:2.3=sha256:bbbb4444555566667777'
export TRACE P_IMAGES TABLE_AVANT TABLE_APRES LOG_DIR="$LOGS" P_COMPOSE="2.29.7" P_DEMON="27.0.0"

CHEMIN="$BAC:$PATH"; REPOND=""; SORTIE=""; CODE=0
lancer() {
    SORTIE="$(printf '%s\n' "$REPOND" | PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?
}
appels() { awk -v m="$*" 'index($0, m) { n++ } END { printf "%d", n + 0 }' "$TRACE"; }
# Liste blanche, et non liste noire : toute sous-commande inattendue — donc
# destructrice — tombe ici.
fautives() { awk '!/^(compose version|version --format |compose -f .* (config --images|pull)|image inspect )/' "$TRACE"; }

titre "L'aide, puis les refus d'usage — --project est obligatoire"
: > "$TRACE"; lancer --help
assert_code 0 "$CODE" "--help rend 0 sans consulter le moindre démon"
assert_contient "$SORTIE" "--project <chemin>" "l'aide nomme l'option obligatoire"
assert_contient "$SORTIE" "deux actes distincts" "elle distingue récupération et redéploiement"
assert_contient "$SORTIE" "Codes de retour" "elle documente les codes de retour"
lancer
assert_code 2 "$CODE" "sans --project, le script rend 2"
assert_contient "$SORTIE" "--project obligatoire" "le message nomme l'option manquante"
assert_absent "$SORTIE" "Usage" "et l'aide n'est pas déversée"
lancer --project "$BAC/inexistant"
assert_code 2 "$CODE" "un chemin inexistant rend 2"
assert_contient "$SORTIE" "$BAC/inexistant" "le message nomme le chemin cherché"
lancer --project "$VIDE"
assert_code 2 "$CODE" "un répertoire sans fichier Compose rend 2"
assert_contient "$SORTIE" "compose.yaml, compose.yml, docker-compose.yaml, docker-compose.yml" "le message nomme ce qui a été cherché"
lancer --project "$PROJET" --inconnue
assert_code 2 "$CODE" "une option inconnue rend 2"
assert_contient "$SORTIE" "[ERROR] Option inconnue" "le message porte [ERROR] et nomme l'option"
assert_absent "$SORTIE" "Usage" "l'aide n'est pas déversée"
assert_egal "1" "$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')" "le refus tient sur une seule ligne"

titre "Sans docker — --dry-run reste lisible, hors --dry-run la dépendance rend 1"
CHEMIN="$SANS_DOCKER"; : > "$TRACE"; lancer --project "$PROJET" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 sans docker"
assert_contient "$SORTIE" "$PROJET" "il affiche le projet retenu"
assert_contient "$SORTIE" "$PROJET/compose.yaml" "et le fichier Compose retenu"
assert_contient "$SORTIE" "[WARN] la commande « docker » est introuvable" "il avertit, et nomme la dépendance"
assert_contient "$SORTIE" "n'a pas pu être résolue" "l'avertissement dit que la liste manque"
assert_contient "$SORTIE" "docker compose -f $PROJET/compose.yaml pull" "il annonce la commande prévue, exacte"
lancer --project "$PROJET"
assert_code 1 "$CODE" "hors --dry-run, l'absence de docker rend 1"
assert_contient "$SORTIE" "« docker » est introuvable" "et le message nomme la dépendance"

titre "Greffon Compose v2 absent, puis seul docker-compose v1 présent"
CHEMIN="$BAC:$PATH"; P_COMPOSE=""; : > "$TRACE"; lancer --project "$PROJET"
assert_code 1 "$CODE" "sans greffon Compose v2, le script rend 1"
assert_contient "$SORTIE" "greffon Compose v2" "le message nomme le greffon attendu"
assert_absent "$SORTIE" "docker-compose v1 est présent" "et ne parle pas d'un binaire qui n'est pas là"
P_COMPOSE="2.29.7"; CHEMIN="$BAC:$V1:$PATH"; lancer --project "$PROJET"
assert_code 1 "$CODE" "le seul docker-compose v1 est refusé en 1"
assert_contient "$SORTIE" "seul docker-compose v1 est présent — c'est le greffon Compose v2, « docker compose », qui est attendu" "le message dit lequel est là, et lequel est attendu"
titre "Démon injoignable — 1 hors --dry-run, 0 avec, et rien de récupéré"
CHEMIN="$BAC:$PATH"; P_COMPOSE="2.29.7"; P_DEMON=""
: > "$TRACE"; lancer --project "$PROJET"
assert_code 1 "$CODE" "un démon muet rend 1 hors --dry-run"
assert_contient "$SORTIE" "démon Docker ne répond pas" "le message nomme le démon"
: > "$TRACE"; lancer --project "$PROJET" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 malgré le démon muet"
assert_contient "$SORTIE" "[WARN] le démon Docker ne répond pas" "il avertit, et nomme la cause"
assert_contient "$SORTIE" "n'a pas pu être résolue" "en disant que la liste des images manque"
assert_egal "0" "$(appels " pull")" "sans rien récupérer"
P_DEMON="27.0.0"

titre "--dry-run — la cible, les images, la commande, aucun geste"
: > "$TRACE"; lancer --project "$PROJET" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 sur un démon qui répond"
assert_contient "$SORTIE" "Projet retenu   : $PROJET" "le projet retenu est affiché"
assert_contient "$SORTIE" "Fichier Compose : $PROJET/compose.yaml" "le fichier Compose aussi"
assert_contient "$SORTIE" "Images à récupérer — 2" "le nombre d'images est annoncé"
assert_contient "$SORTIE" "exemple/api:1.0" "les images sont nommées, une par ligne"
assert_contient "$SORTIE" "docker compose -f $PROJET/compose.yaml pull" "la commande exacte est annoncée"
assert_absent "$SORTIE" "up -d" "mais rien n'annonce un redéploiement exécuté"
assert_egal "0" "$(appels " pull")" "et rien n'est récupéré"
: > "$TRACE"; P_IMAGES=""; lancer --project "$PROJET" --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 sur un projet sans image"
assert_contient "$SORTIE" "ne déclare aucune image" "il dit pourquoi la liste est vide"
lancer --project "$PROJET"
assert_code 1 "$CODE" "hors --dry-run, un projet sans image rend 1"
P_IMAGES=$'exemple/api:1.0\nexemple/web:2.3'

titre "Chemin nominal — confirmation, récupération, puis avant / après"
: > "$TRACE"; REPOND="n"; lancer --project "$PROJET"
assert_code 0 "$CODE" "un refus rend 0"
assert_contient "$SORTIE" "[o/N]" "la confirmation est posée"
assert_contient "$SORTIE" "annulé" "le refus est dit"
assert_contient "$SORTIE" "2 image(s)" "la question rappelle le nombre d'images"
assert_egal "0" "$(appels " pull")" "et rien n'est récupéré"
: > "$TRACE"; REPOND="o"; lancer --project "$PROJET"
assert_code 0 "$CODE" "confirmée, la récupération rend 0"
assert_egal 1 "$(appels " pull")" "la récupération a lieu une fois pour les deux images"
assert_contient "$SORTIE" "CHANGÉE" "celle dont l'identifiant a bougé est dite changée"
assert_contient "$SORTIE" "inchangée" "celle qui n'a pas bougé est dite inchangée"
assert_contient "$SORTIE" "sha256:cccc88889999" "et le tableau montre l'identifiant court d'après"
assert_contient "$SORTIE" "docker compose -f $PROJET/compose.yaml up -d" "la commande exacte de redéploiement termine"
assert_contient "$SORTIE" "TOUJOURS" "avec l'avertissement que les conteneurs n'ont pas suivi"

titre "Après coup — la trace ne porte que de la lecture et de la récupération"
: > "$TRACE"; REPOND=""; lancer --project "$PROJET" --yes
assert_code 0 "$CODE" "--yes mène la récupération à son terme sans question"
assert_absent "$SORTIE" "[o/N]" "aucune question n'est posée"
assert_contient "$(cat "$LOGS/update-images.log")" "docker compose -f $PROJET/compose.yaml pull" "la récupération part au journal"
assert_egal "" "$(fautives)" "aucun appel destructeur : ni down, ni rm, ni stop, ni volume"
assert_egal 1 "$(appels " pull")" "et une seule récupération, quel que soit le nombre d'images"
lancer --project "$PROJET/compose.yaml" --dry-run
assert_code 0 "$CODE" "--project accepte le chemin direct d'un fichier Compose"
bilan "TASK-035 / update-images.sh"
