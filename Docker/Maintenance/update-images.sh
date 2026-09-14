#!/usr/bin/env bash
set -Eeuo pipefail
# update-images.sh — récupère les images d'un projet Compose désigné, et rien de
# plus : ni redéploiement, ni suppression. Le projet n'est jamais deviné.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

PROJET=""; DRY_RUN="false"; DELAI_SONDE=5
FICHIERS_COMPOSE="compose.yaml compose.yml docker-compose.yaml docker-compose.yml"
show_help() {
    while IFS= read -r l; do printf '%s\n' "$l"; done <<'AIDE'
Usage : update-images.sh --project <chemin> [--dry-run] [-y|--yes] [--help]

Récupère les images d'UN projet Compose, celui que --project désigne, et s'arrête
là. Récupérer et redéployer sont deux actes distincts : « docker compose pull »
ne coupe rien, les conteneurs continuent de tourner sur l'ancienne image ;
« docker compose up -d » les recrée. Ce script affiche en fin d'exécution la
commande exacte de redéploiement, et ne la lance jamais.

      --project <chemin>  obligatoire — un répertoire, où les quatre noms de fichier
                          Compose sont cherchés de compose.yaml à docker-compose.yml,
                          ou le chemin d'un fichier Compose. Aucun balayage.
      --dry-run           projet, fichier, images et commandes prévues, sans rien
                          récupérer ; reste lisible sans démon Docker
  -y, --yes               ne poser aucune question
  -h, --help              afficher cette aide

Jamais exécutés : down, stop, rm, ni rien qui supprime une image ou touche à un
volume. L'ancienne image reste sur le disque, retenue par les conteneurs qui
tournent encore dessus — la libérer est le travail de docker-cleanup.sh.

Codes de retour : 0 récupération faite, simulée ou annulée ; 1 docker absent,
greffon Compose v2 absent, ou démon injoignable hors --dry-run ; 2 usage.
AIDE
}
while [ "${1:-}" != "" ]; do
    case "$1" in
        --project) [ "$#" -ge 2 ] || die "Option --project : un chemin est attendu." 2
                   PROJET="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done
[ -n "$PROJET" ] || die "Option --project obligatoire : elle nomme le projet Compose dont les images sont à récupérer." 2

# Un chemin inexistant ou un répertoire sans fichier Compose est une erreur de
# l'appelant : le message dit ce qui a été cherché, et où.
resoudre_projet() {
    local nom
    [ -d "$PROJET" ] || die "Chemin introuvable : « $PROJET » — ni fichier, ni répertoire." 2
    for nom in $FICHIERS_COMPOSE; do
        if [ -f "$PROJET/$nom" ]; then FICHIER_COMPOSE="$PROJET/$nom"; return 0; fi
    done
    die "Aucun fichier Compose dans « $PROJET » : cherché ${FICHIERS_COMPOSE// /, }." 2
}
[ -f "$PROJET" ] && FICHIER_COMPOSE="$PROJET" || resoudre_projet

# Sonde bornée : un démon muet se dit, et ne se confond pas avec une machine vide.
BORNE=()
if command -v timeout >/dev/null 2>&1; then BORNE=(timeout "$DELAI_SONDE"); fi
BLOQUE=""; IMAGES=()
sonde() {
    if ! command -v docker >/dev/null 2>&1; then
        BLOQUE="la commande « docker » est introuvable"; return 0
    fi
    local code=0 version=""
    "${BORNE[@]}" docker compose version >/dev/null 2>&1 || code=$?
    if [ "$code" -ne 0 ]; then
        BLOQUE="le greffon Compose v2 est absent : « docker compose », en deux mots, ne répond pas"
        if command -v docker-compose >/dev/null 2>&1; then
            BLOQUE="seul docker-compose v1 est présent — c'est le greffon Compose v2, « docker compose », qui est attendu"
        fi
        return 0
    fi
    code=0
    version="$("${BORNE[@]}" docker version --format '{{.Server.Version}}' 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ] || [ -z "$version" ]; then
        BLOQUE="le démon Docker ne répond pas : les images ne peuvent être ni identifiées ni récupérées"
    fi
}
# La liste vient du fichier Compose : « config --images » ne contacte aucun registre.
resoudre_images() {
    local code=0 img
    LISTE="$("${BORNE[@]}" docker compose -f "$FICHIER_COMPOSE" config --images)" || code=$?
    if [ "$code" -ne 0 ]; then
        BLOQUE="« docker compose config --images » a échoué (code $code) : la liste des images n'a pas pu être résolue"
        return 0
    fi
    while IFS= read -r img; do [ -n "$img" ] || continue; IMAGES+=("$img"); done <<< "$LISTE"
    [ "${#IMAGES[@]}" -gt 0 ] || BLOQUE="le fichier Compose ne déclare aucune image"
}
sonde
[ -n "$BLOQUE" ] || resoudre_images

printf '\nProjet retenu   : %s\nFichier Compose : %s\n' "$(dirname "$FICHIER_COMPOSE")" "$FICHIER_COMPOSE"
if [ -n "$BLOQUE" ]; then
    warn "$BLOQUE."
    if [ "$DRY_RUN" != "true" ]; then
        die "Récupération impossible : $BLOQUE. Relancer avec --dry-run pour voir l'état établi." 1
    fi
    warn "La liste des images n'a pas pu être résolue : rien n'est annoncé ici sur ce qui changerait."
else
    printf 'Images à récupérer — %d :\n' "${#IMAGES[@]}"
    printf '  %s\n' "${IMAGES[@]}"
fi
if [ "$DRY_RUN" = "true" ]; then
    printf '\nCommande qui serait exécutée :\n  docker compose -f %s pull\n' "$FICHIER_COMPOSE"
    info "[dry-run] Aucune image n'a été récupérée, rien n'a été modifié."
    exit 0
fi

# Identifiant court d'une image, ou « absente » : c'est la comparaison avant /
# après qui dit si l'étiquette a réellement changé de contenu.
etat_image() {
    local code=0 id
    id="$("${BORNE[@]}" docker image inspect --format '{{.Id}}' "$1" 2>/dev/null)" || code=$?
    if [ "$code" -ne 0 ] || [ -z "$id" ]; then printf 'absente'; else printf '%s' "${id:0:19}"; fi
}
table_etats() {
    local img
    while IFS= read -r img; do
        [ -n "$img" ] || continue
        printf '%s\t%s\n' "$img" "$(etat_image "$img")"
    done <<< "$LISTE"
}
avant_de() { awk -F'\t' -v i="$1" '$1 == i { print $2 }' <<< "$AVANT"; }
AVANT="$(table_etats)"

confirm "Récupérer ${#IMAGES[@]} image(s) pour le projet « $(dirname "$FICHIER_COMPOSE") » ?" \
    || { info "Récupération annulée : rien n'a été téléchargé."; exit 0; }
run_logged docker compose -f "$FICHIER_COMPOSE" pull \
    || die "« docker compose pull » a échoué : certaines images n'ont pas été récupérées." 1

printf '\nImages — ce que la récupération a changé :\n'
for img in "${IMAGES[@]}"; do
    a="$(avant_de "$img")"; b="$(etat_image "$img")"
    if [ "$a" = "$b" ]; then etat="inchangée, identique à avant"
    elif [ "$a" = "absente" ]; then etat="nouvelle, absente avant"
    else etat="CHANGÉE, nouvelle révision récupérée"
    fi
    printf '  %-44s %s (%s → %s)\n' "$img" "$etat" "$a" "$b"
done

printf "\nRécupération terminée. Les conteneurs en cours tournent TOUJOURS sur l'ancienne image :\nrien n'est redéployé ici, et rien ne le sera.\n"
printf '\nRedéploiement, à lancer quand la coupure est acceptable :\n  docker compose -f %s up -d\n' "$FICHIER_COMPOSE"
warn "Tant que cette commande n'a pas été lancée, les conteneurs en cours utilisent encore l'ancienne image."
success "Images récupérées. Aucun conteneur, volume ni image n'a été supprimé."
