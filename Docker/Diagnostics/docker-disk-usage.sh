#!/usr/bin/env bash
# docker-disk-usage.sh — consommation de stockage de Docker, en lecture seule.
# Quatre catégories — images, conteneurs, volumes locaux, cache de build — et
# l'occupation du système de fichiers qui porte le répertoire de données.
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5; DETAIL="non"

show_help() {
    cat <<'AIDE'
Usage : docker-disk-usage.sh [--detail] [--help]

Consommation de stockage du démon Docker, en lecture seule : images, conteneurs,
volumes locaux, cache de build. Ni prune ni suppression ; aucun privilège root,
un compte du groupe docker suffit.

Options :
      --detail   ajouter le relevé par objet de « docker system df -v », après
                 le relevé synthétique, qui reste affiché
  -h, --help     afficher cette aide

Colonnes : CATEGORIE ; OBJETS et ACTIFS, les objets comptabilisés puis ceux en
service ; TAILLE, l'espace occupé ; RECUPERABLE, l'espace que le démon dit
récupérable, ou « non fourni » quand il ne le dit pas — jamais un zéro, qui se
lirait « rien à récupérer » alors que c'est l'inverse qui est vrai. Un « - »
marque une catégorie que ce démon ne rapporte pas ; la somme des quatre peut
différer de l'occupation réelle du répertoire de données, journaux et résidus
de couches compris.

Codes de retour :
  0  relevé produit, même sans aucune image
  1  relevé impossible : « docker » absent, démon muet, ou socket interdite
  2  option inconnue — seul cas de 2
AIDE
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --detail)  DETAIL="oui"; shift ;;
        -h|--help) show_help; exit 0 ;;
        *)         die "Option inconnue : $1" 2 ;;
    esac
done

require_cmd docker

# Trois causes, jamais confondues, toutes en 1 : la commande tapée était juste.
diagnostiquer() {
    if [ "$1" -eq 124 ]; then
        error "Le démon Docker ne répond pas : le relevé n'a rien rendu en ${DELAI}s."
    elif [[ "$2" == *"permission denied"* ]]; then
        error "Accès refusé à la socket du démon Docker : le compte « $(id -un) » n'appartient probablement pas au groupe docker."
        error "L'y ajouter — sudo usermod -aG docker $(id -un) — puis rouvrir la session."
    elif [[ "$2" == *"Cannot connect to the Docker daemon"* || "$2" == *"Is the docker daemon running"* ]]; then
        error "Le démon Docker ne répond pas : le client est installé, mais la socket ne mène à aucun démon."
    else
        error "« docker system df » a échoué : la consommation n'a pas pu être relevée."
    fi
    exit 1
}

BORNE=(); command -v timeout >/dev/null 2>&1 && BORNE=(timeout "$DELAI")

# Interroge le démon, et meurt en 1 s'il ne répond pas. La capture précède le
# découpage : sous « pipefail », « docker … | awk » mourrait avant d'avoir écrit
# le moindre message utile. L'affectation est en contexte de condition — nue,
# elle ferait parler deux fois le trap ERR du socle.
REPONSE=""
relever() {
    local code=0
    REPONSE="$(LC_ALL=C "${BORNE[@]}" docker "$@" 2>&1)" || code=$?
    [ "$code" -eq 0 ] || diagnostiquer "$code" "$REPONSE"
}

GABARIT=$'{{.Type}}|{{.TotalCount}}|{{.Active}}|{{.Size}}|{{.Reclaimable}}'
relever system df --format "$GABARIT"
SYNTHESE="$REPONSE"
relever info --format '{{.DockerRootDir}}'
RACINE="${REPONSE%%$'\n'*}"

DETAIL_TEXTE=""
if [ "$DETAIL" = "oui" ]; then relever system df -v; DETAIL_TEXTE="$REPONSE"; fi

# Les quatre catégories, dans cet ordre : celle que le démon tait garde sa ligne.
NOMS=(Images Conteneurs "Volumes locaux" "Cache de build")
OBJETS=("" "" "" ""); ACTIFS=("" "" "" ""); TAILLES=("" "" "" ""); RECUPS=("" "" "" "")
# Le séparateur « | » n'est pas une espace : deux séparateurs voisins délimitent
# un champ VIDE au lieu de se fondre en un seul — ce qui distingue un espace
# récupérable absent, à nommer, d'un décalage de colonnes.
i=0
while IFS='|' read -r type total actif taille recup; do
    [ -n "$type" ] || continue
    case "$type" in
        Images)          i=0 ;;
        Containers)      i=1 ;;
        "Local Volumes") i=2 ;;
        "Build Cache")   i=3 ;;
        *)               continue ;;
    esac
    OBJETS[i]="$total"; ACTIFS[i]="$actif"
    TAILLES[i]="$taille"; RECUPS[i]="$recup"
done <<< "$SYNTHESE"

# La valeur rendue par le démon, ou la mention de repli quand il n'a rien dit.
# « <no value> » est ce que le gabarit écrit pour un champ non renseigné.
valeur() {
    case "${1:-}" in ''|'<no value>') printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}

printf '\nConsommation par catégorie\n%s\n' "------------------------------------------------------------"
printf '  %-16s%8s%8s%12s%14s\n' "CATEGORIE" "OBJETS" "ACTIFS" "TAILLE" "RECUPERABLE"
for i in 0 1 2 3; do
    printf '  %-16s%8s%8s%12s%14s\n' "${NOMS[$i]}" "$(valeur "${OBJETS[$i]}" "-")" \
        "$(valeur "${ACTIFS[$i]}" "-")" "$(valeur "${TAILLES[$i]}" "-")" \
        "$(valeur "${RECUPS[$i]}" "non fourni")"
done

printf '\nRépertoire de données du démon\n%s\n' "------------------------------------------------------------"
printf '  %-14s%s\n' "Chemin" "$(valeur "$RACINE" "non communiqué")"

# « df » rend 1 si un point de montage résiste ; la ligne du chemin demandé
# reste exploitable — c'est le vide, et non le code, qui décide ici.
SORTIE_DF=""
if [ -n "$RACINE" ] && [ -d "$RACINE" ] && ! SORTIE_DF="$(df -P -h -- "$RACINE" 2>/dev/null)"; then
    SORTIE_DF=""
fi
BLOC="$(awk 'NR == 2' <<< "$SORTIE_DF")"
if [ -z "$BLOC" ]; then
    printf '  %-14s%s\n' "Occupation" "non disponible — chemin invisible depuis cette machine"
else
    read -r _ TAILLE_FS UTILISE_FS LIBRE_FS POURCENT MONTAGE <<< "$BLOC"
    printf '  %-14s%s\n' "Occupation" "$POURCENT occupés — $UTILISE_FS utilisés sur $TAILLE_FS, $LIBRE_FS libres"
    printf '  %-14s%s\n' "Monte sur" "$MONTAGE"
fi

printf '\nCe que cette mesure ne compte pas\n  %s\n' \
    "La somme des quatre catégories peut différer de l'occupation réelle du répertoire de données :" \
    "« docker system df » ne compte ni les journaux de conteneurs, ni les résidus de couches."

if [ "$DETAIL" = "oui" ]; then
    printf '\nRelevé par objet — docker system df -v\n%s\n' "------------------------------------------------------------"
    printf '%s\n' "$DETAIL_TEXTE"
fi

info "Relevé produit en lecture seule : rien n'a été supprimé, ni seulement simulé."
exit 0
