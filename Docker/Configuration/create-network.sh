#!/usr/bin/env bash
set -Eeuo pipefail

# Crée un réseau Docker externe, indépendant de tout fichier Compose, afin que
# plusieurs projets Compose distincts s'y raccordent (external: true) au lieu
# de créer chacun le leur. Idempotent : un réseau conforme n'est ni recréé ni
# modifié ; un réseau divergent fait refuser le script plutôt que le détruire
# — la suppression relève de cleanup-networks.sh, absent à ce jour.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"
DRIVER="bridge"
SUBNET=""
NOM=""

usage() {
    cat <<'EOF'
create-network.sh — crée un réseau Docker externe, partagé entre plusieurs
projets Compose distincts (chacun le déclare "external: true" plutôt que de
créer le sien). Ne modifie ni ne supprime jamais un réseau existant.

Usage : create-network.sh [nom] [--driver <pilote>] [--subnet <cidr>]
                           [--dry-run] [--help]

  nom          nom du réseau ; à défaut, SRV_DOCKER_NETWORK de config/server.env
  --driver     pilote Docker, bridge par défaut ; overlay est refusé (suppose Swarm)
  --subnet     sous-réseau en notation CIDR (ex. 172.20.0.0/24) ; laissé à Docker par défaut
  --dry-run    affiche la commande docker sans rien créer
  --help       affiche cette aide

Exemple : create-network.sh proxy --subnet 172.20.0.0/24

Un réseau absent est créé. Un réseau déjà présent et conforme au pilote et au
sous-réseau demandés n'est ni recréé ni modifié. Un réseau de même nom mais
divergent fait refuser le script : sa suppression relève de cleanup-networks.sh.

Codes de retour :
  0  réseau créé, ou déjà présent et conforme
  1  démon injoignable, réseau divergent, ou refus de Docker
  2  argument ou option invalide
EOF
}

valider_subnet() {
    local ip="${1%/*}" prefixe="${1##*/}"
    local v4='^(25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2})(\.(25[0-5]|2[0-4][0-9]|[01]?[0-9]{1,2})){3}$'
    local v6='^[0-9A-Fa-f:]+$'
    if [ "$1" = "$ip" ] || [[ ! "$prefixe" =~ ^[0-9]{1,3}$ ]]; then
        return 1
    fi
    if [[ "$ip" =~ $v4 ]]; then
        [ "$prefixe" -le 32 ]
    elif [[ "$ip" == *:* ]] && [[ "$ip" =~ $v6 ]]; then
        [ "$prefixe" -le 128 ]
    else
        return 1
    fi
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --driver)
            shift
            if [ "${1:-}" = "" ] || [ "${1#-}" != "$1" ]; then
                die "Valeur manquante pour --driver." 2
            fi
            DRIVER="$1"; shift ;;
        --subnet)
            shift
            if [ "${1:-}" = "" ] || [ "${1#-}" != "$1" ]; then
                die "Valeur manquante pour --subnet." 2
            fi
            SUBNET="$1"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        -*) die "Option inconnue : $1" 2 ;;
        *)
            [ -z "$NOM" ] || die "Un seul nom de réseau est accepté (déjà « $NOM », puis « $1 »)." 2
            NOM="$1"; shift ;;
    esac
done

[ -n "$NOM" ] || NOM="${SRV_DOCKER_NETWORK:-}"
[ -n "$NOM" ] || die "Nom de réseau manquant : le donner en argument, ou définir SRV_DOCKER_NETWORK dans config/server.env." 2

NOM_REGEX='^[a-zA-Z0-9][a-zA-Z0-9_.-]*$'
[[ "$NOM" =~ $NOM_REGEX ]] || die "Nom de réseau invalide : « $NOM » (Docker attend un premier caractère alphanumérique, puis lettres, chiffres, « . », « _ » ou « - »)." 2

[ "$DRIVER" != "overlay" ] || die "Pilote overlay refusé : il suppose un Swarm initialisé, hors du périmètre de ce script." 2

[ -z "$SUBNET" ] || valider_subnet "$SUBNET" || die "Sous-réseau invalide : « $SUBNET » (notation CIDR attendue, ex. 172.20.0.0/24)." 2

CREATE_ARGS=(network create --driver "$DRIVER")
[ -z "$SUBNET" ] || CREATE_ARGS+=(--subnet "$SUBNET")
CREATE_ARGS+=("$NOM")

ETAT="trouve"
if ! SORTIE_INSPECT="$(docker network inspect --format '{{.Name}}|{{.Driver}}|{{range $i,$c := .IPAM.Config}}{{if $i}},{{end}}{{$c.Subnet}}{{end}}' "$NOM" 2>&1)"; then
    if printf '%s' "$SORTIE_INSPECT" | grep -qiE "no such network|network .* not found"; then
        ETAT="absent"
    else
        ETAT="indisponible"
    fi
elif [ "${SORTIE_INSPECT%%|*}" != "$NOM" ]; then
    # Docker a résolu un préfixe d'ID vers un autre réseau : sous ce nom exact, rien n'existe.
    ETAT="absent"
fi

case "$ETAT" in
    indisponible)
        if [ "$DRY_RUN" = "true" ]; then
            warn "État courant illisible : $SORTIE_INSPECT"
            info "[dry-run] docker ${CREATE_ARGS[*]}"
            exit 0
        fi
        die "Démon Docker injoignable : $SORTIE_INSPECT" 1
        ;;
    absent)
        if [ "$DRY_RUN" = "true" ]; then
            info "[dry-run] docker ${CREATE_ARGS[*]}"
            exit 0
        fi
        if ! SORTIE_CREATE="$(docker "${CREATE_ARGS[@]}" 2>&1)"; then
            die "Création du réseau refusée par Docker : $SORTIE_CREATE" 1
        fi
        success "Réseau « $NOM » créé (pilote $DRIVER${SUBNET:+, sous-réseau $SUBNET})."
        ;;
    trouve)
        DRIVER_ACTUEL="${SORTIE_INSPECT#*|}"; DRIVER_ACTUEL="${DRIVER_ACTUEL%%|*}"
        SUBNET_ACTUEL="${SORTIE_INSPECT##*|}"
        ECART=""
        [ "$DRIVER_ACTUEL" = "$DRIVER" ] || ECART="pilote actuel « $DRIVER_ACTUEL », demandé « $DRIVER » ; "
        if [ -n "$SUBNET" ]; then
            case ",$SUBNET_ACTUEL," in
                *",$SUBNET,"*) : ;;
                *) ECART="${ECART}sous-réseau actuel « $SUBNET_ACTUEL », demandé « $SUBNET » ; " ;;
            esac
        fi
        if [ -z "$ECART" ]; then
            info "Réseau « $NOM » déjà présent et conforme (pilote $DRIVER_ACTUEL)."
        else
            die "Réseau « $NOM » présent mais divergent : ${ECART}rien n'a été modifié ni supprimé — utiliser cleanup-networks.sh pour le recréer." 1
        fi
        ;;
esac
