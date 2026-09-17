---
id: TASK-077
title: "Écrire le cadrage de Synology/ à partir de l'état actuel des scripts"
status: in_progress
priority: medium
depends_on:
  - TASK-074
environment: host
human_approval_required: true
agent: orchestrateur
objective: |
  Synology/CADRAGE.md existe au modèle de la décision 49, ajusté par la validation du
  cadrage de Kubernetes/ : besoin du dossier, ensembles, scripts individuels, et un
  contrat par script qui décrit son comportement actuel, lu dans le code.
scope:
  - Synology/CADRAGE.md
out_of_scope:
  - modifier un script, un README ou un fichier de cas (un écart devient une ligne du registre)
  - écrire un script Synology
  - décrire un usage ou un serveur réel
acceptance_criteria:
  - Synology/Plex/organize-series.sh et Synology/Plex/update-plex.sh ont chacun un contrat de script individuel avec options et défauts, codes de retour, ce qu'il modifie, ce qu'il lit et son état ; Synology/Administration/, sans script, est décrit par son seul besoin
  - chaque option, code de retour et variable cité se retrouve par grep dans le script concerné
  - l'historique du cadrage porte une ligne datée « état initial » dont la colonne « Validé par user » reste vide jusqu'à sa validation
validation:
  - "bash orchestration/outils/verifier-liens.sh"
---

# TASK-077 — Cadrage de Synology/

Passe en `ready` quand user a validé le cadrage de Kubernetes/ (TASK-074). User relit
et valide ce cadrage avant la clôture.
