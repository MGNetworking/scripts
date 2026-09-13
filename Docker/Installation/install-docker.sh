#!/usr/bin/env bash
set -Eeuo pipefail

# Installe Docker Engine, le CLI, containerd, Buildx et le plugin Compose depuis
# les dépôts officiels Docker. Ne configure pas le démon (TASK-030), ne crée
# aucun réseau (TASK-032) et n'ajoute personne au groupe docker : donner le démon
# à un compte non privilégié équivaut à donner root, cela se décide à part.

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"

DRY_RUN="false"
KEYRING="/etc/apt/keyrings/docker.asc"
LISTE="/etc/apt/sources.list.d/docker.list"
PAQUETS="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
CONFLITS="docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc"
MIN_DISQUE_MO=2048
MIN_MEMOIRE_MO=1024

usage() {
    cat <<'EOF'
install-docker.sh — installe Docker Engine depuis les dépôts officiels.

Usage : install-docker.sh [--dry-run] [-y|--yes] [--help]

  --dry-run   affiche les changements sans écrire ni appeler apt-get
  -y, --yes   ne pose aucune question (obligatoire hors terminal)

Systèmes supportés : Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS, sur amd64 ou
arm64. Toute autre distribution ou architecture est refusée.

Ce que le script modifie :
  /etc/apt/keyrings/docker.asc          clé du dépôt officiel
  /etc/apt/sources.list.d/docker.list   dépôt, référencé par signed-by
  paquets docker-ce, docker-ce-cli, containerd.io, buildx et compose
  service docker                        activé et démarré

Une installation déjà en place est constatée, jamais écrasée. Les paquets
conflictuels ne sont retirés qu'après confirmation explicite.

Codes de retour :
  0  Docker est installé, ou l'était déjà
  1  système non supporté, ressources insuffisantes, dépôt indisponible,
     privilège manquant, ou question impossible à poser
  2  option inconnue
EOF
}

while [ "${1:-}" != "" ]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        -y|--yes)  export ASSUME_YES="true"; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done

[ "$DRY_RUN" = "true" ] || require_root
[ "$DRY_RUN" = "true" ] || enable_full_logging

# --- OS et architecture ---------------------------------------------------
require_os debian ubuntu
case "$OS_ID $OS_VERSION" in
    "debian 12"|"debian 13"|"ubuntu 22.04"|"ubuntu 24.04") ;;
    *) die "Version non supportée : $OS_ID $OS_VERSION (attendu : Debian 12/13, Ubuntu 22.04/24.04)" ;;
esac

case "$OS_ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *) die "Architecture non supportée : $OS_ARCH (attendu : x86_64 ou aarch64)" ;;
esac

# VERSION_CODENAME est lu sur la machine : aucun nom de code n'est écrit en dur,
# sans quoi le script mentirait au premier Debian suivant.
CODENAME="$( . /etc/os-release && echo "${VERSION_CODENAME:-}" )"
[ -n "$CODENAME" ] || die "VERSION_CODENAME absent de /etc/os-release : dépôt indéterminable."
DEPOT="https://download.docker.com/linux/$OS_ID"

info "Système : $OS_ID $OS_VERSION ($CODENAME), architecture $ARCH."

# --- Installation déjà en place -------------------------------------------
if command -v docker >/dev/null 2>&1 && dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q "ok installed"; then
    success "Docker est déjà installé : $(docker --version 2>/dev/null || echo 'version illisible')"
    info "Ce script ne réinstalle rien. La configuration relève de Docker/Configuration/."
    exit 0
fi

# --- Ressources -----------------------------------------------------------
DISQUE_MO="$(df -Pm /var 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${DISQUE_MO:-}" ] && [ "$DISQUE_MO" -lt "$MIN_DISQUE_MO" ]; then
    die "Espace insuffisant sous /var : ${DISQUE_MO} Mo libres, ${MIN_DISQUE_MO} Mo requis."
fi
MEMOIRE_MO="$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "")"
if [ -n "$MEMOIRE_MO" ] && [ "$MEMOIRE_MO" -lt "$MIN_MEMOIRE_MO" ]; then
    warn "Mémoire totale de ${MEMOIRE_MO} Mo : Docker fonctionnera, les compilations d'images souffriront."
fi
info "Noyau $(uname -r), ${DISQUE_MO:-?} Mo libres sous /var, ${MEMOIRE_MO:-?} Mo de mémoire."

# --- Paquets conflictuels -------------------------------------------------
# dpkg -l tronque les noms dans ses colonnes : on interroge paquet par paquet.
TROUVES=""
for paquet in $CONFLITS; do
    if dpkg-query -W -f='${Status}' "$paquet" 2>/dev/null | grep -q "ok installed"; then
        TROUVES="$TROUVES $paquet"
    fi
done

# --- Résumé des changements -----------------------------------------------
printf '\nChangements prévus\n'
printf '  Clé du dépôt           %s\n' "$KEYRING"
printf '  Dépôt apt              %s %s stable\n' "$DEPOT" "$CODENAME"
printf '  Paquets installés      %s\n' "$PAQUETS"
printf '  Service                docker, activé et démarré\n'
if [ -n "$TROUVES" ]; then
    printf '  Paquets RETIRÉS        %s\n' "${TROUVES# }"
fi
printf '\n'

if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] Aucun fichier écrit, aucun appel à apt-get."
    exit 0
fi

if [ -n "$TROUVES" ]; then
    warn "Des paquets en conflit avec Docker officiel sont installés :${TROUVES}"
    [ -t 0 ] || [ "${ASSUME_YES:-false}" = "true" ] \
        || die "Retrait à confirmer, et aucun terminal n'est disponible. Relancer avec --yes."
    confirm "Retirer ces paquets ?" || die "Installation abandonnée : les conflits subsistent."
    # shellcheck disable=SC2086
    # Découpage voulu : $TROUVES est une liste de noms de paquets sans espace.
    run_logged apt-get remove -y $TROUVES
fi

[ -t 0 ] || [ "${ASSUME_YES:-false}" = "true" ] \
    || die "Installation à confirmer, et aucun terminal n'est disponible. Relancer avec --yes."
confirm "Installer Docker depuis $DEPOT ?" || die "Installation abandonnée."

# --- Dépôt officiel -------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
run_logged apt-get update
run_logged apt-get install -y ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
run_logged curl -fsSL "$DEPOT/gpg" -o "$KEYRING"
chmod a+r "$KEYRING"

printf 'deb [arch=%s signed-by=%s] %s %s stable\n' "$ARCH" "$KEYRING" "$DEPOT" "$CODENAME" > "$LISTE"

# Une suite non publiée pour ce nom de code ferait échouer apt-get update et
# laisserait un dépôt cassé derrière nous : on le retire avant de rendre la main.
if ! run_logged apt-get update; then
    rm -f "$LISTE"
    die "Le dépôt $DEPOT ne publie pas la suite « $CODENAME » : fichier $LISTE retiré."
fi

# --- Installation ---------------------------------------------------------
# shellcheck disable=SC2086
# Découpage voulu : $PAQUETS est une liste de noms de paquets sans espace.
run_logged apt-get install -y $PAQUETS

run_logged systemctl enable docker
run_logged systemctl start docker

# --- Vérification ---------------------------------------------------------
printf '\nVérification\n'
printf '  Moteur                %s\n' "$(docker --version 2>/dev/null || echo 'non disponible')"
printf '  Compose               %s\n' "$(docker compose version --short 2>/dev/null || echo 'non disponible')"
printf '  Buildx                %s\n' "$(docker buildx version 2>/dev/null | cut -d' ' -f2 || echo 'non disponible')"
printf '  Service               %s\n' "$(systemctl is-active docker 2>/dev/null || echo inactive)"
printf '\n'

docker version >/dev/null 2>&1 || die "Docker est installé mais le démon ne répond pas."
success "Docker installé et opérationnel."
info "Configuration du démon : Docker/Configuration/configure-docker.sh."
