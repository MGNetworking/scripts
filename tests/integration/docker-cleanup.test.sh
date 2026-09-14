#!/usr/bin/env bash
# tests/integration/docker-cleanup.test.sh — Docker/Cleanup/docker-cleanup.sh.
# TASK-037. Pas de démon Docker ici : un faux « docker » en tête de PATH trace les
# arguments reçus et répond des relevés fixés — aucune suppression réelle, et rien
# n'est écrit dans config/ : le réseau protégé passe par l'environnement.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

BASH_BIN="$(command -v bash)"; CIBLE="$SCRIPTS_ROOT/Docker/Cleanup/docker-cleanup.sh"
BAC="$(mktemp -d)"; TRACE="$BAC/appels"; LOGS="$BAC/journal"
trap 'rm -rf "$BAC"' EXIT

# Le faux docker répond AVANT puis APRÈS nettoyage : un « prune » ou un « rm » déjà
# tracé fait basculer l'état. Un démon réel se comporterait de même.
cat > "$BAC/docker" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$TRACE"
apres=0; grep -qE '(prune|rm) ' "$TRACE" && apres=1
case "$*" in
    version*)          printf '%s\n' "$STUB_VERSION" ;;
    "system df"*)      if [ "$apres" = 1 ]; then printf '%s\n' "$DF_APRES"; else printf '%s\n' "$DF_AVANT"; fi ;;
    "ps -a --filter"*) [ "$apres" = 1 ] || printf '%s\n' "$CONTENEURS" ;;
    "ps -a"*)          printf '%s\n' "$ATTACHES" ;;
    images*)           [ "$apres" = 1 ] || printf '%s\n' "$IMAGES" ;;
    "volume ls"*)      [ "$apres" = 1 ] || printf '%s\n' "$VOLUMES" ;;
    "network ls"*)     [ "$apres" = 1 ] || printf '%s\n' "$RESEAUX" ;;
    "network rm"*)     printf 'Deleted network %s\n' "${*##* }" ;;
    *)                 printf 'Deleted: %s\n' "$*" ;;
esac
STUB
chmod +x "$BAC/docker"
SANS_DOCKER="$BAC/sans-docker"; mkdir -p "$SANS_DOCKER"
for b in dirname basename mkdir id date; do ln -s "$(command -v "$b")" "$SANS_DOCKER/$b"; done

export TRACE LOG_DIR="$LOGS" STUB_VERSION="27.0.0" SRV_DOCKER_RESEAUX_PROTEGES="mon-infra reseau-perime"
DF_AVANT=$'Images|3|1.5GB|1.2GB\nContainers|2|48.5MB|48.5MB\nLocal Volumes|1|210MB|210MB\nBuild Cache|0|0B|0B'
DF_APRES=$'Images|1|300MB|0B\nContainers|0|0B|0B\nLocal Volumes|0|0B|0B\nBuild Cache|0|0B|0B'
DF_VIDE=$'Images|0|0B|0B\nContainers|0|0B|0B\nLocal Volumes|0|0B|0B\nBuild Cache|0|0B|0B'
CONTENEURS=$'a1b2c3   ancien-web   nginx:1.27\nd4e5f6   bac-a-sable   alpine:3.20'
ATTACHES='reseau-utilise'; VOLUMES='donnees-a-sauver'
IMAGES=$'0a1b2c  120MB\n3d4e5f   45MB'
RESEAUX=$'bridge\nmon-infra\nreseau-utilise\nreseau-orphelin\nreseau-perime'
export DF_AVANT DF_APRES CONTENEURS ATTACHES IMAGES VOLUMES RESEAUX

CHEMIN="$BAC:$PATH"; REPOND=""; SORTIE=""; CODE=0
lancer() {
    SORTIE="$(printf '%s\n' "$REPOND" | PATH="$CHEMIN" "$BASH_BIN" "$CIBLE" "$@" 2>&1)" && CODE=0 || CODE=$?
}
# Nombre d'appels tracés contenant ce motif. awk et non grep -c : un compte nul n'est pas
# une erreur, et n'a pas à armer le trap ERR du socle.
appels() { awk -v m="$*" 'index($0, m) { n++ } END { printf "%d", n + 0 }' "$TRACE"; }

titre "Sans docker installé — l'aide d'abord, puis la dépendance nommée"
CHEMIN="$SANS_DOCKER"; lancer --help
assert_code 0 "$CODE" "--help rend 0 sans consulter le moindre démon"
assert_contient "$SORTIE" "--supprimer-volumes" "l'aide nomme le drapeau des volumes"
assert_contient "$SORTIE" "tâche planifiée" "elle dit que --yes est le seul mode planifiable"
assert_contient "$SORTIE" "Jamais supprimés" "elle dit ce qui n'est jamais supprimé"
assert_contient "$SORTIE" "Codes de retour" "elle documente les codes de retour"
lancer
assert_code 1 "$CODE" "sans --help, l'absence de docker rend 1, jamais 2"
assert_contient "$SORTIE" "introuvable" "le message nomme la dépendance manquante"
titre "Option inconnue — faute d'usage, sur une seule ligne"
CHEMIN="$BAC:$PATH"; : > "$TRACE"; lancer --inconnue
assert_code 2 "$CODE" "une option inconnue rend 2"
assert_contient "$SORTIE" "[ERROR] Option inconnue" "le message porte [ERROR] et nomme l'option"
assert_absent "$SORTIE" "Usage" "l'aide n'est pas déversée"
assert_egal "1" "$(printf '%s\n' "$SORTIE" | wc -l | tr -d ' ')" "le refus tient sur une seule ligne"
titre "Démon injoignable — 1 sans --dry-run, 0 avec, et rien de supprimé"
STUB_VERSION=""; : > "$TRACE"; lancer
assert_code 1 "$CODE" "hors --dry-run, un démon injoignable rend 1"
assert_contient "$SORTIE" "ne répond pas" "le message nomme le démon"
: > "$TRACE"; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 malgré le démon injoignable"
assert_contient "$SORTIE" "[WARN]" "il avertit au lieu de mesurer"
assert_contient "$SORTIE" "Aucune mesure n'a pu être faite" "l'avertissement dit que rien n'a été mesuré"
assert_contient "$SORTIE" "conteneurs arrêtés ; réseaux inutilisés, un par un ; images" "il énumère les opérations, dans l'ordre"
assert_egal "0" "$(appels "prune")" "et ne supprime rien"
STUB_VERSION="27.0.0"
titre "--dry-run — quatre catégories, aucun geste"
: > "$TRACE"; REPOND=""; lancer --dry-run
assert_code 0 "$CODE" "--dry-run rend 0 sur un démon qui répond"
assert_contient "$SORTIE" "ancien-web" "les conteneurs arrêtés sont identifiés"
assert_contient "$SORTIE" "0a1b2c" "les images sans étiquette sont identifiées"
assert_contient "$SORTIE" "donnees-a-sauver" "les volumes inutilisés sont affichés"
assert_contient "$SORTIE" "1.2GB" "l'espace récupérable des images est repris"
assert_contient "$SORTIE" "2 objet(s)" "chaque catégorie donne son nombre d'objets"
assert_contient "$SORTIE" "--supprimer-volumes" "les volumes exclus disent quel drapeau les inclurait"
assert_contient "$SORTIE" "mon-infra reseau-perime" "les réseaux protégés par la configuration sont nommés"
assert_contient "$SORTIE" "bridge, host, none" "les réseaux prédéfinis du démon aussi"
assert_contient "$SORTIE" "reseau-orphelin" "le réseau réellement inutilisé est proposé"
assert_absent "$SORTIE" "reseau-utilise" "celui qu'un conteneur retient n'est pas proposé"
assert_contient "$SORTIE" "à l'instant où il a été fait" "le relevé dit qu'il est daté"
assert_egal "0" "$(appels "prune")" "et rien n'est supprimé"
titre "Confirmation refusée — rien n'est supprimé, et ce n'est pas une erreur"
: > "$TRACE"; REPOND="n"; lancer
assert_code 0 "$CODE" "un refus rend 0"
assert_contient "$SORTIE" "annulé" "le script dit le nettoyage annulé"
assert_contient "$SORTIE" "2 conteneur(s) arrêté(s), 1 réseau(x) inutilisé(s) et 2 image(s)" "la question rappelle les totaux par catégorie"
assert_egal "0" "$(appels "prune")" "et ne lance aucune suppression"
: > "$TRACE"; REPOND="o"; lancer
assert_egal 1 "$(appels "container prune")" "la même exécution, confirmée, supprime bien"
titre "Sous --yes — un réseau à la fois, rien de protégé, récapitulatif au journal"
: > "$TRACE"; rm -f "$LOGS/docker-cleanup.log"; REPOND=""; lancer --yes
assert_code 0 "$CODE" "--yes mène le nettoyage à son terme"
assert_egal 1 "$(appels "container prune")" "les conteneurs arrêtés partent"
assert_egal 1 "$(appels "image prune")" "les images sans étiquette aussi"
assert_egal 1 "$(appels "network rm")" "un seul réseau est supprimé — un par un"
assert_contient "$(cat "$TRACE")" "network rm reseau-orphelin" "et c'est le réseau orphelin, nommé"
assert_egal 0 "$(appels "network prune")" "jamais de purge globale, qui emporterait les protégés"
assert_absent "$(cat "$TRACE")" "mon-infra" "le réseau protégé n'est pas touché"
assert_absent "$(cat "$TRACE")" "reseau-perime" "ni le second de la liste"
assert_absent "$(cat "$TRACE")" "bridge" "ni un réseau prédéfini du démon"
assert_absent "$(cat "$TRACE")" "reseau-utilise" "ni celui qu'un conteneur retient"
assert_egal "0" "$(appels "volume rm")" "aucun volume n'est détruit sans --supprimer-volumes"
assert_contient "$SORTIE" "conteneurs arrêtés : 2 supprimé(s), espace récupéré 48.5MB" "le récapitulatif dit ce qui a disparu et l'espace rendu"
assert_contient "$SORTIE" "images sans étiquette : 2 supprimée(s), espace récupéré 1.2GB" "par catégorie, jamais en bloc"
assert_contient "$(cat "$LOGS/docker-cleanup.log")" "Récapitulatif — volumes inutilisés" "le journal porte le récapitulatif"
assert_contient "$(cat "$LOGS/docker-cleanup.log")" "Deleted network reseau-orphelin" "et la liste des objets réellement supprimés"
assert_egal "$(printf '%s\n' 'container prune -f' 'network rm reseau-orphelin' 'image prune -f')" "$(awk '/prune|network rm/' "$TRACE")" "l'ordre est conteneurs, réseaux, images — et rien d'autre"
titre "--supprimer-volumes — une confirmation de plus, qui nomme les volumes"
: > "$TRACE"; REPOND=$'o\nn'; lancer --supprimer-volumes
assert_code 0 "$CODE" "refuser la confirmation des volumes n'est pas une erreur"
assert_contient "$SORTIE" "donnees-a-sauver" "elle nomme les volumes qu'elle détruit"
assert_contient "$SORTIE" "Volumes conservés" "le refus est dit"
assert_egal "0" "$(appels "volume rm")" "et aucun volume n'est détruit"
assert_egal 1 "$(appels "container prune")" "le reste du nettoyage se poursuit"
: > "$TRACE"; REPOND=$'o\no'; lancer --supprimer-volumes
assert_contient "$(cat "$TRACE")" "volume rm donnees-a-sauver" "acceptée, elle détruit les volumes nommés"
titre "Machine vide — quatre catégories à zéro, aucune question"
DF_AVANT="$DF_VIDE"; DF_APRES="$DF_VIDE"; CONTENEURS=""; IMAGES=""; VOLUMES=""; RESEAUX=""
: > "$TRACE"; REPOND=""; lancer
assert_code 0 "$CODE" "une machine vide rend 0"
assert_egal "4" "$(awk '/0 objet\(s\)/ { n++ } END { printf "%d", n + 0 }' <<< "$SORTIE")" "les quatre catégories sont à zéro"
assert_absent "$SORTIE" "[o/N]" "aucune confirmation n'est demandée"
assert_egal "0" "$(appels "prune")" "et rien n'est lancé"

bilan "TASK-037 / docker-cleanup.sh"
