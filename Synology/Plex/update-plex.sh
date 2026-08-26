#!/bin/bash
set -eu

###############################################################################
# update-plex.sh
# Mise à jour Plex (linuxserver) via Docker Compose + logs dans ./logs/
###############################################################################

# Dossier du script (important en tâche planifiée DSM)
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/update-plex.log"

# Dossier où se trouve le docker-compose-nas.yml (à adapter si besoin)
STACK_DIR="/volume1/docker/docker-plex"
COMPOSE_FILE="docker-compose-nas.yml"
SERVICE_NAME="plex"
IMAGE="lscr.io/linuxserver/plex:latest"

mkdir -p "$LOG_DIR"

log() {
  # Log horodaté
  echo "$(date '+%F %T') - $*" >> "$LOG_FILE"
}

# Redirige stdout+stderr vers le fichier log (en gardant l’horodatage via log())
# On garde aussi un en-tête clair à chaque exécution
{
  echo ""
  echo "================================================================================"
  echo "$(date '+%F %T') - START update-plex.sh"
  echo "SCRIPT_DIR=$SCRIPT_DIR"
  echo "STACK_DIR=$STACK_DIR"
  echo "COMPOSE_FILE=$COMPOSE_FILE"
  echo "SERVICE=$SERVICE_NAME"
  echo "IMAGE=$IMAGE"
  echo "================================================================================"
} >> "$LOG_FILE"

# Vérifications minimales
if ! command -v docker >/dev/null 2>&1; then
  log "ERREUR: commande 'docker' introuvable"
  exit 1
fi

if [ ! -d "$STACK_DIR" ]; then
  log "ERREUR: STACK_DIR introuvable: $STACK_DIR"
  exit 1
fi

if [ ! -f "$STACK_DIR/$COMPOSE_FILE" ]; then
  log "ERREUR: fichier compose introuvable: $STACK_DIR/$COMPOSE_FILE"
  exit 1
fi

log "Pull de l'image: $IMAGE"
if ! docker pull "$IMAGE" >> "$LOG_FILE" 2>&1; then
  log "ERREUR: docker pull a échoué -> arrêt pour éviter une coupure inutile"
  exit 1
fi

log "Redéploiement du service '$SERVICE_NAME' via docker compose"
cd "$STACK_DIR"

# NOTE: --pull always force la récup de l’image (même si déjà présente)
#       --no-deps évite de redémarrer les autres services du stack
if docker compose -f "$COMPOSE_FILE" up -d --pull always --no-deps "$SERVICE_NAME" >> "$LOG_FILE" 2>&1; then
  log "OK: mise à jour appliquée pour '$SERVICE_NAME'"
else
  log "ERREUR: docker compose up a échoué"
  exit 1
fi

# Nettoyage prudent (images "dangling" uniquement)
log "Nettoyage: docker image prune (dangling)"
docker image prune -f >> "$LOG_FILE" 2>&1 || true

log "FIN update-plex.sh"
exit 0
