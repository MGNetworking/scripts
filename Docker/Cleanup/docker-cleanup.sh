#!/usr/bin/env bash
set -Eeuo pipefail
# docker-cleanup.sh — supprime les ressources Docker inutilisées : énumère par
# catégorie, ne supprime qu'après confirmation, et ne touche jamais ce qui sert.
_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"; AVEC_VOLUMES="false"; DELAI_SONDE=5
# Seules des fonctions internes du shell : « cat » peut manquer sur une machine nue.
show_help() { while IFS= read -r l; do printf '%s\n' "$l"; done <<'AIDE'
Usage : docker-cleanup.sh [--dry-run] [--supprimer-volumes] [-y|--yes] [--help]

Supprime les ressources inutilisées dans cet ordre — conteneurs arrêtés, réseaux, images,
puis volumes si le drapeau est donné : un conteneur arrêté retient l'image qu'il référence.

      --dry-run            énumère par catégorie ce qui serait supprimé, avec
                           l'espace récupérable annoncé par le démon, sans rien supprimer
      --supprimer-volumes  inclut les volumes inutilisés, qui portent des données ; sans
                           ce drapeau ils sont affichés mais jamais supprimés, et les
                           détruire demande une confirmation qui les nomme
  -y, --yes                ne pose aucune question — seul mode utilisable depuis une
                           tâche planifiée
  -h, --help               afficher cette aide

Jamais supprimés : ce qui sert encore, les réseaux prédéfinis du démon (bridge, host,
none), ceux que protègent SRV_DOCKER_RESEAUX_PROTEGES et SRV_DOCKER_NETWORK de
config/server.env, et les volumes sans --supprimer-volumes. Les réseaux partent un par
un, par leur nom.

Codes de retour : 0 nettoyage fait, simulé, ou rien à nettoyer ; 1 démon injoignable
hors --dry-run ; 2 option inconnue.
AIDE
}
export ASSUME_YES="false"  # destructif : seule --yes confirme, jamais un parent (décision 45)
while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run)           DRY_RUN="true"; shift ;;
        --supprimer-volumes) AVEC_VOLUMES="true"; shift ;;
        -y|--yes)            export ASSUME_YES="true"; shift ;;
        -h|--help)           show_help; exit 0 ;;
        *)                   die "Option inconnue : $1" 2 ;;
    esac
done

# Réseaux jamais proposés : les prédéfinis du démon, et ceux que protège la configuration.
PREDEFINIS="bridge host none"
PROTEGES=" $PREDEFINIS ${SRV_DOCKER_RESEAUX_PROTEGES:-} ${SRV_DOCKER_NETWORK:-} "
protege() { case "$PROTEGES" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
# Un relevé impossible arrête tout : mieux vaut ne rien supprimer que supprimer à l'aveugle.
mesure() {
    local code=0
    REPONSE="$(docker "$@" 2>/dev/null)" || code=$?
    [ "$code" -eq 0 ] || die "« docker $* » a échoué (code $code) : le relevé est impossible, la suite est abandonnée." 1
}
compter() { awk 'NF { n++ } END { printf "%d", n + 0 }' <<< "${1:-}"; }
champ() {  # <relevé> <type> <colonne> <repli> — 3 = taille, 4 = récupérable
    local v; v="$(awk -F'|' -v t="$2" -v c="$3" '$1 == t { print $c }' <<< "$1")"
    case "$v" in ''|'<no value>') printf '%s' "$4" ;; *) printf '%s' "$v" ;; esac
}
# Gain entre deux TAILLES : le récupérable du démon (« 1.2GB (80%) ») n'en est pas une.
gain() {  # <taille avant> <taille après>
    awk -v a="${1:-}" -v b="${2:-}" '
      function o(s, u) { sub(/ *\(.*/, "", s); gsub(/ /, "", s); if (s !~ /^[0-9.]+[kKMGTP]?B?$/) return -1
        if (s ~ /B$/) s = substr(s, 1, length(s) - 1); u = substr(s, length(s), 1)
        if (u ~ /[0-9]/) u = ""; else s = substr(s, 1, length(s) - 1)
        return s * (u ~ /[kK]/ ? 1e3 : u == "M" ? 1e6 : u == "G" ? 1e9 : u == "T" ? 1e12 : u == "P" ? 1e15 : 1) }
      BEGIN { x = o(a); y = o(b); if (x < 0 || y < 0) { print "non fourni"; exit }
        d = x - y; if (d < 0) d = 0; u = "B"
        if (d >= 1e9) { d /= 1e9; u = "GB" } else if (d >= 1e6) { d /= 1e6; u = "MB" } else if (d >= 1e3) { d /= 1e3; u = "kB" }
        printf "%.1f%s", d, u }'
}
# Renseigne SYNTHESE, CONTENEURS, IMAGES, LISTE_VOLUMES et RESEAUX, avant puis après.
relever() {
    local nom tous attaches references retenues
    mesure system df --format '{{.Type}}|{{.TotalCount}}|{{.Size}}|{{.Reclaimable}}'; SYNTHESE="$REPONSE"
    mesure ps -a --filter status=exited --filter status=created --format '{{.ID}}  {{.Names}}  {{.Image}}'; CONTENEURS="$REPONSE"
    mesure images --filter dangling=true --format '{{.ID}}  {{.Size}}'; retenues="$REPONSE"
    mesure volume ls -q --filter dangling=true; LISTE_VOLUMES="$REPONSE"
    # Une image sans étiquette qu'un conteneur référence encore n'est pas inutilisée.
    mesure ps -a --format '{{.Image}}'; references=",${REPONSE//$'\n'/,},"
    IMAGES="$(awk -v refs="$references" 'NF && index(refs, $1) == 0' <<< "$retenues")"
    mesure network ls --format '{{.Name}}'; tous="$REPONSE"
    mesure ps -a --format '{{.Networks}}'; attaches=",${REPONSE//$'\n'/,},"
    RESEAUX=""
    while IFS= read -r nom; do
        case "$attaches" in *",$nom,"*) continue ;; esac
        protege "$nom" || RESEAUX="${RESEAUX}${RESEAUX:+$'\n'}$nom"
    done <<< "$tous"
}
bloc() {  # <titre> <liste> <espace récupérable>
    printf '\n%s\n  %s objet(s), espace récupérable : %s\n' "$1" "$(compter "$2")" "$3"
    [ -z "$2" ] || printf '%s\n' "$2" | sed 's/^/    /'
}
# Sonde bornée du démon : un démon muet se dit, et ne se confond pas avec une machine vide.
BORNE=()
if command -v timeout >/dev/null 2>&1; then BORNE=(timeout "$DELAI_SONDE"); fi
INJOIGNABLE=""; SONDE=0
if ! command -v docker >/dev/null 2>&1; then INJOIGNABLE="la commande « docker » est introuvable"
else
    SORTIE_VERSION="$("${BORNE[@]}" docker version --format '{{.Server.Version}}' 2>&1)" || SONDE=$?
    if [ "$SONDE" -ne 0 ] || [ -z "$SORTIE_VERSION" ]; then INJOIGNABLE="le démon Docker ne répond pas${SORTIE_VERSION:+ : $SORTIE_VERSION}"; fi
fi
if [ -n "$INJOIGNABLE" ]; then
    [ "$DRY_RUN" = "true" ] || die "$INJOIGNABLE — relancer avec --dry-run pour voir les opérations prévues." 1
    warn "Aucune mesure n'a pu être faite : $INJOIGNABLE."
    OPERATIONS="conteneurs arrêtés ; réseaux inutilisés, un par un ; images sans étiquette"
    [ "$AVEC_VOLUMES" != "true" ] || OPERATIONS="$OPERATIONS ; volumes inutilisés"
    info "[dry-run] Rien n'a été énuméré, rien ne sera supprimé. Les opérations seraient, dans cet ordre : $OPERATIONS."
    exit 0
fi
relever
NC="$(compter "$CONTENEURS")"; NR="$(compter "$RESEAUX")"; NI="$(compter "$IMAGES")"; NV="$(compter "$LISTE_VOLUMES")"
printf '\nNettoyage des ressources Docker inutilisées — relevé\n'
bloc "Conteneurs arrêtés" "$CONTENEURS" "$(champ "$SYNTHESE" Containers 4 'non fourni')"
bloc "Réseaux inutilisés" "$RESEAUX" "sans objet — un réseau ne porte pas de données"
[ -z "${SRV_DOCKER_RESEAUX_PROTEGES:-}${SRV_DOCKER_NETWORK:-}" ] || printf '    Jamais proposés, protégés par la configuration : %s %s\n' "${SRV_DOCKER_RESEAUX_PROTEGES:-}" "${SRV_DOCKER_NETWORK:-}"
printf '    Jamais proposés, prédéfinis du démon : %s\n' "${PREDEFINIS// /, }"
bloc "Images inutilisées — sans étiquette" "$IMAGES" "$(champ "$SYNTHESE" Images 4 'non fourni')"
bloc "Volumes inutilisés" "$LISTE_VOLUMES" "$(champ "$SYNTHESE" 'Local Volumes' 4 'non fourni')"
if [ "$AVEC_VOLUMES" = "true" ]; then printf '    Inclus par --supprimer-volumes.\n'
else printf '    Exclus : les inclure demande --supprimer-volumes, et une confirmation de plus.\n'; fi
info "Ce relevé décrit l'état à l'instant où il a été fait, et l'espace récupérable est celui annoncé par le démon, jamais un chiffre recalculé ici : une image qu'un conteneur arrêté retient encore n'y figure pas, et le devient une fois celui-ci parti."
if [ "$DRY_RUN" = "true" ]; then success "[dry-run] Aucune suppression — rien n'a été modifié."; exit 0; fi
# Les volumes exclus ne comptent pas dans le total : sans leur drapeau, il n'y a rien à en faire.
TOTAL=$((NC + NR + NI)); [ "$AVEC_VOLUMES" != "true" ] || TOTAL=$((TOTAL + NV))
if [ "$TOTAL" -eq 0 ]; then success "Rien à nettoyer dans les catégories retenues. Aucune confirmation n'est demandée."; exit 0; fi
# La confirmation nomme les totaux par catégorie ; celle des volumes, plus bas, ne porte que sur eux.
VOLUMES_QUESTION=""
[ "$AVEC_VOLUMES" != "true" ] || VOLUMES_QUESTION=", ainsi que $NV volume(s) et leurs données"
confirm "Supprimer $NC conteneur(s) arrêté(s), $NR réseau(x) inutilisé(s) et $NI image(s) sans étiquette${VOLUMES_QUESTION} ?" || { info "Nettoyage annulé : rien n'a été supprimé."; exit 0; }
if [ "$AVEC_VOLUMES" = "true" ] && [ "$NV" -gt 0 ]; then
    printf '\nVolumes dont les données seront définitivement perdues\n%s\n' "$LISTE_VOLUMES"
    if ! confirm "Détruire ces $NV volume(s) et les données qu'ils portent ?"; then
        AVEC_VOLUMES="false"; warn "Volumes conservés : leurs données ne sont pas touchées. Le reste du nettoyage se poursuit."
    fi
fi
# Chaque suppression part au journal avec sa sortie : c'est là que se lit la liste des objets réellement supprimés.
supprimer() { run_logged docker "$@" || die "« docker $* » a échoué : le nettoyage s'arrête là, les suppressions suivantes n'ont pas eu lieu." 1; }
[ "$NC" -eq 0 ] || supprimer container prune -f
# Un par un, par leur nom : une purge globale emporterait les réseaux protégés.
while IFS= read -r nom; do [ -z "$nom" ] || supprimer network rm "$nom"; done <<< "$RESEAUX"
[ "$NI" -eq 0 ] || supprimer image prune -f
[ "$AVEC_VOLUMES" != "true" ] || while IFS= read -r nom; do [ -z "$nom" ] || supprimer volume rm "$nom"; done <<< "$LISTE_VOLUMES"
# Récapitulatif de ce qui a RÉELLEMENT disparu : relu après coup, jamais repris du relevé.
AVANT="$SYNTHESE"; relever
info "Récapitulatif — conteneurs arrêtés : $((NC - $(compter "$CONTENEURS"))) supprimé(s), espace récupéré $(gain "$(champ "$AVANT" Containers 3 '0B')" "$(champ "$SYNTHESE" Containers 3 '0B')")"
info "Récapitulatif — réseaux inutilisés : $((NR - $(compter "$RESEAUX"))) supprimé(s), espace récupéré sans objet"
info "Récapitulatif — images sans étiquette : $((NI - $(compter "$IMAGES"))) supprimée(s), espace récupéré $(gain "$(champ "$AVANT" Images 3 '0B')" "$(champ "$SYNTHESE" Images 3 '0B')")"
info "Récapitulatif — volumes inutilisés : $((NV - $(compter "$LISTE_VOLUMES"))) supprimé(s), espace récupéré $(gain "$(champ "$AVANT" 'Local Volumes' 3 '0B')" "$(champ "$SYNTHESE" 'Local Volumes' 3 '0B')")"
success "Nettoyage terminé. La liste des objets supprimés est dans le journal."
