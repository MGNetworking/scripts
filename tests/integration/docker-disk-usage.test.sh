#!/usr/bin/env bash
# tests/integration/docker-disk-usage.test.sh — Docker/Diagnostics/docker-disk-usage.sh.
# TASK-034. Pas de démon Docker ici : catégories, cas vide et causes d'échec sont
# éprouvés par un faux « docker » en tête de PATH, qui trace ses arguments.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

BASH_BIN="$(command -v bash)"
CIBLE="$SCRIPTS_ROOT/Docker/Diagnostics/docker-disk-usage.sh"
BAC="$(mktemp -d)"; TRACE="$BAC/appels"; RACINE_STUB="$BAC/donnees"
mkdir -p "$RACINE_STUB"
trap 'rm -rf "$BAC"' EXIT

# Faux docker : trace ses arguments, puis répond selon la sous-commande.
# STUB_ERREUR posée tient lieu de panne — message sur stderr, code dans STUB_CODE.
cat > "$BAC/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TRACE"
if [ -n "${STUB_ERREUR:-}" ]; then printf '%s\n' "$STUB_ERREUR" >&2; exit "${STUB_CODE:-1}"; fi
case "$*" in
    "system df -v"*) printf '%s\n' "${STUB_DETAIL:-}" ;;
    "system df"*)    printf '%s\n' "${STUB_SYNTHESE:-}" ;;
    "info"*)         printf '%s\n' "${STUB_RACINE:-}" ;;
esac
STUB
chmod +x "$BAC/docker"

# PATH sans docker : la preuve « commande absente » ne dépend pas de l'image.
SANS_DOCKER="$BAC/sans-docker"; mkdir -p "$SANS_DOCKER"
for b in dirname basename mkdir id date cat; do ln -s "$(command -v "$b")" "$SANS_DOCKER/$b"; done
CHEMIN="$BAC:$PATH"

# Lance le script et renseigne SORTIE et CODE ; $1..$4 = synthèse, racine, détail, erreur.
SORTIE=""; CODE=0
lancer() {
    SORTIE="$(STUB_SYNTHESE="${1:-}" STUB_RACINE="${2:-}" STUB_DETAIL="${3:-}" STUB_ERREUR="${4:-}" \
        STUB_CODE="${CODE_STUB:-1}" TRACE="$TRACE" PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" "${@:5}" 2>&1)" \
        && CODE=0 || CODE=$?
}

# Le cache de build est à zéro, l'espace récupérable des volumes est ABSENT.
REPARTI=$'Images|12|3|3.14GB|1.2GB\nContainers|4|2|48.5MB|0B\nLocal Volumes|6|2|210MB|\nBuild Cache|0|0|0B|0B'
VIDE=$'Images|0|0|0B|0B\nContainers|0|0|0B|0B\nLocal Volumes|0|0|0B|0B\nBuild Cache|0|0|0B|0B'
ANCIEN=$'Images|2|1|500MB|250MB\nContainers|1|1|10MB|0B\nLocal Volumes|0|0|0B|0B'
DETAIL=$'Images  2  1  500MB  250MB (50%)\nnginx:1.27  1  1  200MB  100MB'
LIGNES='^  (Images|Conteneurs|Volumes locaux|Cache de build) '
ZEROS='^  (Images|Conteneurs|Volumes locaux|Cache de build) +0 +0 +0B +0B$'
INTERDITS='(^| )(rm|rmi|prune)( |$)'

titre "Sans docker installé — l'aide, puis la dépendance nommée"
CHEMIN="$SANS_DOCKER"
lancer "" "" "" "" --help
assert_code 0 "$CODE" "--help rend 0 sans consulter le moindre démon"
assert_contient "$SORTIE" "--detail" "l'aide documente les options"
assert_contient "$SORTIE" "RECUPERABLE" "l'aide dit ce que porte chaque colonne"
assert_contient "$SORTIE" "Codes de retour" "l'aide documente les codes de retour"
lancer "" "" "" ""
assert_code 1 "$CODE" "sans --help, l'absence de la commande rend 1, jamais 2"
assert_contient "$SORTIE" "introuvable" "le message nomme la dépendance manquante"
assert_absent "$SORTIE" "ne répond pas" "elle n'est pas confondue avec un démon muet"
assert_absent "$SORTIE" "groupe docker" "ni avec un refus d'accès à la socket"

titre "Option inconnue — faute d'usage, et rien d'autre"
: > "$TRACE"
lancer "" "" "" "" --inconnue
assert_code 2 "$CODE" "une option inconnue rend 2, sans même que docker soit là"
assert_contient "$SORTIE" "[ERROR] Option inconnue" "le message porte [ERROR] et nomme l'option"
assert_absent "$SORTIE" "Usage" "l'aide n'est pas déversée"
assert_egal "1" "$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')" "le refus tient sur une seule ligne"
assert_egal "0" "$(wc -l < "$TRACE" | tr -d ' ')" "aucun appel au démon : le refus précède le préflight"
CHEMIN="$BAC:$PATH"

titre "Le démon ne répond pas — par connexion, puis par délai dépassé"
lancer "" "" "" "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?"
assert_code 1 "$CODE" "un démon muet rend 1"
assert_contient "$SORTIE" "ne répond pas" "le message nomme le démon"
assert_absent "$SORTIE" "groupe docker" "et ne renvoie pas au groupe docker, qui n'y changerait rien"
assert_absent "$SORTIE" "Cannot connect" "le message brut du client ne filtre pas à l'écran"
# Le délai prime sur le texte du client, ici « permission denied », qui mènerait ailleurs.
CODE_STUB=124
lancer "" "" "" "permission denied while trying to connect to the Docker daemon socket"
unset CODE_STUB
assert_code 1 "$CODE" "une sonde qui expire rend 1"
assert_contient "$SORTIE" "ne répond pas" "le message nomme le démon qui ne répond pas"
assert_contient "$SORTIE" "silence au-delà de 5 s" "il dit le délai dépassé"
assert_absent "$SORTIE" "trop long" "sans le confondre avec une mesure trop longue"
assert_absent "$SORTIE" "groupe docker" "et sans suivre le texte du client, ici trompeur"

titre "La socket est là, l'utilisateur n'y a pas droit"
lancer "" "" "" 'permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock: connect: permission denied'
assert_code 1 "$CODE" "un refus d'accès rend 1, comme les deux autres causes"
assert_contient "$SORTIE" "groupe docker" "le message nomme l'appartenance au groupe docker"
assert_contient "$SORTIE" "usermod" "et donne la commande qui répare"
assert_absent "$SORTIE" "ne répond pas" "il ne se fond pas dans le message du démon muet"

titre "Relevé — quatre catégories, et ce que le démon dit de chacune"
lancer "$REPARTI" "$RACINE_STUB" "" ""
assert_code 0 "$CODE" "le relevé rend 0"
assert_egal "4" "$(grep -cE "$LIGNES" <<< "$SORTIE")" "les quatre catégories ont chacune leur ligne"
assert_contient "$SORTIE" "3.14GB" "la taille des images est reprise"
assert_contient "$SORTIE" "1.2GB" "l'espace récupérable des images est repris"
ligne_volumes="$(grep -F "Volumes locaux" <<< "$SORTIE")"
assert_contient "$ligne_volumes" "210MB" "la taille des volumes reste dans sa colonne"
assert_contient "$ligne_volumes" "non fourni" "l'espace récupérable absent est nommé, jamais zéro"
assert_absent "$ligne_volumes" " 0 " "et rien ne l'a remplacé par un zéro"
assert_contient "$SORTIE" "$RACINE_STUB" "le répertoire de données du démon est affiché"
assert_contient "$SORTIE" "occupés" "l'occupation du système de fichiers qui le porte est affichée"
assert_contient "$SORTIE" "différer" "la sortie dit que la somme peut différer de l'occupation réelle"

titre "Machine vide, et catégorie que le démon tait"
lancer "$VIDE" "$RACINE_STUB" "" ""
assert_code 0 "$CODE" "aucune image, aucun conteneur, aucun volume : le relevé rend 0"
assert_egal "4" "$(grep -cE "$ZEROS" <<< "$SORTIE")" "les quatre catégories gardent leur ligne, à 0 objet, 0 actif, 0 B"
lancer "$ANCIEN" "$RACINE_STUB" "" ""
assert_code 0 "$CODE" "un démon qui ne rapporte pas le cache de build rend 0"
ligne_cache="$(grep -F "Cache de build" <<< "$SORTIE")"
assert_contient "$ligne_cache" "non fourni" "la catégorie tue garde sa ligne, avec une mention explicite"
assert_absent "$ligne_cache" "0" "et aucun zéro n'y est inventé"
lancer "$REPARTI" "/chemin/qui-nexiste-pas" "" ""
assert_contient "$SORTIE" "non disponible" "un répertoire de données invisible est dit non disponible"

titre "--detail — le relevé par objet s'ajoute, il ne remplace pas"
lancer "$REPARTI" "$RACINE_STUB" "$DETAIL" ""
assert_absent "$SORTIE" "nginx:1.27" "sans --detail, aucun relevé par objet"
sans_detail="$(sed -n '/^Consommation/,/^Répertoire de données/p' <<< "$SORTIE")"
lancer "$REPARTI" "$RACINE_STUB" "$DETAIL" "" --detail
assert_code 0 "$CODE" "--detail rend 0"
avec_detail="$(sed -n '/^Consommation/,/^Répertoire de données/p' <<< "$SORTIE")"
assert_egal "$sans_detail" "$avec_detail" "le relevé synthétique est identique avec et sans --detail"
assert_contient "${SORTIE#*RECUPERABLE}" "nginx:1.27" "et le relevé par objet le suit, jamais avant"

titre "Lecture seule — ce que la trace des appels prouve"
: > "$TRACE"
lancer "$REPARTI" "$RACINE_STUB" "" ""
assert_egal "3" "$(wc -l < "$TRACE" | tr -d ' ')" "trois appels suffisent au relevé synthétique"
assert_egal "info
system
version" "$(awk '{print $1}' "$TRACE" | sort -u)" "seules « version », « info » et « system » sont appelées"
lancer "$REPARTI" "$RACINE_STUB" "$DETAIL" "" --detail
assert_contient "$(cat "$TRACE")" "system df -v" "le relevé par objet vient de « docker system df -v »"
assert_egal "0" "$(grep -cE "$INTERDITS" "$TRACE")" "ni rm, ni rmi, ni prune, sans --detail comme avec"

SORTIE="$(cd /tmp && STUB_SYNTHESE="$REPARTI" STUB_RACINE="$RACINE_STUB" TRACE="$TRACE" \
    PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" 2>&1)" && code=0 || code=$?
assert_code 0 "$code" "le script s'exécute depuis n'importe quel répertoire"
assert_contient "$SORTIE" "3.14GB" "et produit le même relevé"

bilan "TASK-034 / docker-disk-usage.sh"
