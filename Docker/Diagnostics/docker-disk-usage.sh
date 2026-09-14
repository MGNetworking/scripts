#!/usr/bin/env bash
set -Eeuo pipefail

# docker-disk-usage.sh — consommation de stockage de Docker, en lecture seule :
# quatre catégories, et l'occupation du système de fichiers qui porte les données.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI_SONDE=5      # la sonde ne mesure rien : elle peut rester courte
DELAI_MESURE=120   # « system df » pèse les volumes : cela peut être long
DETAIL="non"

show_help() {
    cat <<'AIDE'
Usage : docker-disk-usage.sh [--detail] [--help]

Consommation de stockage du démon Docker, en lecture seule : images, conteneurs,
volumes locaux, cache de build. Ni prune ni suppression ; aucun privilège root,
un compte du groupe docker suffit.

      --detail   ajouter le relevé par objet de « docker system df -v », après
                 le relevé synthétique, qui reste affiché
  -h, --help     afficher cette aide

Colonnes : CATÉGORIE ; OBJETS et ACTIFS, comptabilisés puis en service ; TAILLE,
l'espace occupé ; RÉCUPÉRABLE, ce que le démon dit récupérable, ou « non fourni »
quand il ne le dit pas — jamais un zéro, qui se lirait « rien à récupérer ».

Codes de retour : 0 relevé produit, même sans aucune image ; 1 relevé impossible :
« docker » absent, démon muet ou socket interdite ; 2 option inconnue — seul cas.
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
ERREUR=""
diagnostiquer() {
    if [ "$1" -eq 124 ]; then
        error "Le démon Docker ne répond pas : silence au-delà de ${DELAI_SONDE} s."
    elif [[ "$ERREUR" == *"permission denied"* ]]; then
        error "Accès refusé à la socket du démon Docker : « $(id -un) » n'appartient probablement pas au groupe docker."
        error "L'y ajouter — sudo usermod -aG docker $(id -un) — puis rouvrir la session."
    elif [[ "$ERREUR" == *"Cannot connect"* || "$ERREUR" == *"daemon running"* ]]; then
        error "Le démon Docker ne répond pas : le client est installé, mais la socket ne mène à aucun démon."
    else
        error "Le démon Docker n'a pas répondu à la sonde : la consommation n'a pas pu être relevée."
    fi
    exit 1
}

BORNE_SONDE=(); BORNE_MESURE=()
command -v timeout >/dev/null 2>&1 && { BORNE_SONDE=(timeout "$DELAI_SONDE"); BORNE_MESURE=(timeout "$DELAI_MESURE"); }

# Sonde courte du démon : « system df » peut dépasser cinq secondes sans que le
# démon soit muet. Sa sortie n'est lue qu'en cas d'échec, comme message d'erreur.
sonde() {
    local code=0
    ERREUR="$(LC_ALL=C "${BORNE_SONDE[@]}" docker version --format '{{.Server.Version}}' 2>&1)" || code=$?
    [ "$code" -eq 0 ] || diagnostiquer "$code"
}

# Mesure d'une donnée : stdout SEUL est retenu, stderr écarté, sinon un
# avertissement du client deviendrait la première ligne du répertoire de
# données. La capture précède le découpage — « docker … | awk » mourrait sous
# « pipefail » avant d'avoir écrit le moindre message utile.
REPONSE=""
mesure() {
    local code=0
    REPONSE="$(LC_ALL=C "${BORNE_MESURE[@]}" docker "$@" 2>/dev/null)" || code=$?
    [ "$code" -ne 124 ] || die "La mesure a dépassé ${DELAI_MESURE} s : le démon répond, mais l'inventaire des volumes est trop long."
    [ "$code" -eq 0 ] || die "« docker $* » a échoué (code $code) : la consommation n'a pas pu être relevée."
}

sonde

GABARIT=$'{{.Type}}|{{.TotalCount}}|{{.Active}}|{{.Size}}|{{.Reclaimable}}'
mesure system df --format "$GABARIT"; SYNTHESE="$REPONSE"
mesure info --format '{{.DockerRootDir}}'; RACINE="${REPONSE%%$'\n'*}"

DETAIL_TEXTE=""
if [ "$DETAIL" = "oui" ]; then mesure system df -v; DETAIL_TEXTE="$REPONSE"; fi

NOMS=(Images Conteneurs "Volumes locaux" "Cache de build")
OBJETS=("" "" "" ""); ACTIFS=("" "" "" ""); TAILLES=("" "" "" ""); RECUPS=("" "" "" "")
# Deux « | » voisins délimitent un champ VIDE : un espace récupérable absent se distingue d'un décalage.
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

# Ce que le démon a rendu, ou la mention de repli ; « <no value> » est ce que le
# gabarit écrit pour un champ qu'il n'a pas trouvé.
valeur() {
    case "${1:-}" in ''|'<no value>') printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}

printf '\nConsommation par catégorie\n%s\n' "------------------------------------------------------------"
printf '  %-17s%8s%8s%12s%16s\n' "CATÉGORIE" "OBJETS" "ACTIFS" "TAILLE" "RÉCUPÉRABLE" # largeurs en octets : +1 et +2 pour les accents
for i in 0 1 2 3; do
    printf '  %-16s%8s%8s%12s%14s\n' "${NOMS[$i]}" "$(valeur "${OBJETS[$i]}" "-")" \
        "$(valeur "${ACTIFS[$i]}" "-")" "$(valeur "${TAILLES[$i]}" "-")" \
        "$(valeur "${RECUPS[$i]}" "non fourni")"
done

printf '\nRépertoire de données du démon\n%s\n' "------------------------------------------------------------"
printf '  %-14s%s\n' "Chemin" "$(valeur "$RACINE" "non communiqué")"

# « df » rend 1 si un point de montage résiste, sans taire la ligne demandée :
# c'est le vide de la sortie qui décide, et non le code de retour.
SORTIE_DF=""
[ -n "$RACINE" ] && [ -d "$RACINE" ] && SORTIE_DF="$(df -P -h -- "$RACINE" 2>/dev/null || true)"
BLOC="$(awk 'NR == 2' <<< "$SORTIE_DF")"
if [ -z "$BLOC" ]; then
    printf '  %-14s%s\n' "Occupation" "non disponible — chemin invisible depuis cette machine"
else
    read -r _ TAILLE_FS UTILISE_FS LIBRE_FS POURCENT MONTAGE <<< "$BLOC"
    printf '  %-14s%s\n' "Occupation" "$POURCENT occupés — $UTILISE_FS utilisés sur $TAILLE_FS, $LIBRE_FS libres"
    printf '  %-15s%s\n' "Monté sur" "$MONTAGE"
fi

printf '\nCe que cette mesure ne compte pas\n  %s\n  %s\n' \
    "La somme des quatre catégories peut différer de l'occupation réelle du répertoire de données :" \
    "« docker system df » ne compte ni les journaux de conteneurs, ni les résidus de couches."

if [ "$DETAIL" = "oui" ]; then
    printf '\nRelevé par objet — docker system df -v\n%s\n%s\n' "------------------------------------------------------------" "$DETAIL_TEXTE"
fi

info "Relevé produit en lecture seule : rien n'a été supprimé, ni seulement simulé."
exit 0
