#!/usr/bin/env bash
set -Eeuo pipefail

# Diagnostique un environnement Docker. Lecture seule : aucune commande de ce
# script ne modifie l'état de la machine. L'absence de Docker est le cas
# nominal, pas une erreur — elle se constate et vaut 1.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DELAI=5
SOCKET="${DOCKER_SOCKET:-/var/run/docker.sock}"

usage() {
    cat <<'EOF'
check-docker.sh — diagnostic d'un environnement Docker, en lecture seule.

Usage : check-docker.sh [--help]

Affiche le client et sa version, le plugin Compose, Buildx, l'état du socket,
celui du service systemd, puis la réponse du démon, sa version, son pilote de
stockage et son répertoire de données. Une information introuvable s'affiche
« non disponible » sans interrompre le diagnostic.

Ne lance aucun conteneur et n'installe rien : valider une installation qu'on
vient de faire est le travail de verify-docker.sh.

Codes de retour :
  0  le client est présent et le démon répond
  1  client absent, démon injoignable, socket interdit ou délai dépassé
  2  option inconnue — seul cas de 2

Un démon qui répond alors que docker.service est inactif vaut 0 : le service
peut être activé par socket, et DOCKER_HOST peut désigner une machine distante.
EOF
}

# Interroge une commande en bornant son temps. Renseigne REP, ne l'affiche pas :
# un appel en substitution perdrait la variable dans un sous-shell.
REP=""
lire() {
    REP=""
    if ! REP="$(LC_ALL=C timeout "$DELAI" "$@" 2>/dev/null)"; then
        REP=""
        return 1
    fi
    [ -n "$REP" ]
}

# Aligne sur 23 caractères — ${#..} compte des caractères, pas des octets,
# ce que « %-23s » ne fait pas sur des libellés accentués.
ligne() {
    local libelle="$1" valeur="${2:-non disponible}" remplissage
    remplissage=$(( 23 - ${#libelle} ))
    [ "$remplissage" -lt 1 ] && remplissage=1
    printf '  %s%*s%s\n' "$libelle" "$remplissage" "" "$valeur"
}

# Affiche ce que rend la commande, ou « non disponible » si elle n'a rien rendu.
rubrique() {
    local libelle="$1"; shift
    if lire "$@"; then ligne "$libelle" "$REP"; else ligne "$libelle"; fi
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

info "Diagnostic de l'environnement Docker."

# --- Client ---------------------------------------------------------------
printf '\nClient Docker\n'
if command -v docker >/dev/null 2>&1; then
    CLIENT="oui"
    rubrique "Version du client" docker --version
    rubrique "Plugin Compose" docker compose version --short
    # « docker buildx version » rend « github.com/docker/buildx v0.17.1 » :
    # la version est le second champ, pas le premier.
    if lire docker buildx version; then ligne "Buildx" "${REP#* }"; else ligne "Buildx"; fi
else
    CLIENT="non"
    ligne "Commande docker" "absente de cette machine"
    ligne "Plugin Compose"
    ligne "Buildx"
fi

# --- Socket ---------------------------------------------------------------
printf '\nSocket du démon\n'
ligne "Chemin" "$SOCKET"
if [ -S "$SOCKET" ]; then
    if [ -w "$SOCKET" ]; then
        ligne "État" "présent et accessible"
    else
        ligne "État" "présent mais interdit à l'utilisateur courant"
    fi
elif [ -e "$SOCKET" ]; then
    ligne "État" "présent mais ce n'est pas un socket"
else
    ligne "État" "absent — le démon ne l'a pas créé, il n'est donc pas démarré"
fi
if [ -n "${DOCKER_HOST:-}" ]; then ligne "DOCKER_HOST" "$DOCKER_HOST"; fi

# --- Service --------------------------------------------------------------
printf '\nService systemd\n'
if command -v systemctl >/dev/null 2>&1; then
    ligne "Exécution" "$(systemctl is-active docker 2>/dev/null || echo inactive)"
    ligne "Activation" "$(systemctl is-enabled docker 2>/dev/null || echo disabled)"
else
    ligne "Exécution" "non disponible — systemd absent"
    ligne "Activation"
fi

# --- Démon ----------------------------------------------------------------
printf '\nDémon Docker\n'
DEMON="non"
if [ "$CLIENT" = "oui" ] \
   && lire docker info --format '{{.ServerVersion}}|{{.Driver}}|{{.DockerRootDir}}' \
   && [ "${REP%%|*}" != "" ]; then
    DEMON="oui"
    IFS='|' read -r VERSION PILOTE RACINE <<<"$REP"
    ligne "Réponse" "le démon répond"
    ligne "Version du moteur" "$VERSION"
    ligne "Pilote de stockage" "${PILOTE:-non disponible}"
    ligne "Répertoire de données" "${RACINE:-non disponible}"
else
    ligne "Réponse" "aucune"
    ligne "Version du moteur"
    ligne "Pilote de stockage"
    ligne "Répertoire de données"
fi

# --- Verdict --------------------------------------------------------------
printf '\n'
if [ "$CLIENT" != "oui" ]; then
    error "Environnement NON exploitable : le client « docker » est absent."
    error "L'installation relève de Docker/Installation/install-docker.sh."
    exit 1
fi
if [ "$DEMON" != "oui" ]; then
    error "Environnement NON exploitable : le client est là, le démon ne répond pas."
    [ -S "$SOCKET" ] || error "Le socket $SOCKET est absent : le démon n'est pas démarré."
    exit 1
fi
[ "$(systemctl is-active docker 2>/dev/null || true)" = "active" ] \
    || warn "Le démon répond alors que docker.service n'est pas actif."
success "Environnement Docker exploitable."
