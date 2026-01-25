#!/bin/sh
set -eu

STACK_DIR="/volume1/docker/docker-plex"
COMPOSE_FILE="docker-compose-nas.yml"
SERVICE_NAME="plex"
IMAGE="lscr.io/linuxserver/plex:latest"
LOG="/volume1/docker/scripts/logs/update-plex.log"

mkdir -p "$(dirname "$LOG")"

log() { echo "$(date '+%F %T') - $*" >> "$LOG"; }

log "===== Début update Plex ====="

# Vérifier que docker est dispo
if ! command -v docker >/dev/null 2>&1; then
  log "ERREUR: docker introuvable"
  exit 1
fi

# Pull de l'image
log "Pull image: $IMAGE"
if ! docker pull "$IMAGE" >> "$LOG" 2>&1; then
  log "ERREUR: docker pull a échoué, arrêt pour éviter une coupure"
  exit 1
fi

# Aller dans le dossier compose
cd "$STACK_DIR"

# Mettre à jour via compose (propre)
log "Redéploiement via docker compose"
if docker compose -f "$COMPOSE_FILE" up -d --pull always --no-deps "$SERVICE_NAME" >> "$LOG" 2>&1; then
  log "OK: service $SERVICE_NAME mis à jour"
else
  log "ERREUR: docker compose up a échoué"
  exit 1
fi

# Optionnel: nettoyage images inutilisées (prudent)
log "Prune images dangling"
docker image prune -f >> "$LOG" 2>&1 || true

log "===== Fin update Plex ====="
exit 0
