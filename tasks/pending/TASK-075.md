---
id: TASK-075
title: "Écrire le cadrage de Linux/ à partir de l'état actuel des scripts"
status: pending
priority: medium
depends_on:
  - TASK-074
environment: host
human_approval_required: true
agent: orchestrateur
objective: |
  Linux/CADRAGE.md existe au modèle de la décision 49, ajusté par la validation du
  cadrage de Kubernetes/ : besoin du dossier, ensembles, scripts individuels, et un
  contrat par script qui décrit son comportement actuel, lu dans le code.
scope:
  - Linux/CADRAGE.md
out_of_scope:
  - modifier un script, un README ou un fichier de cas (un écart devient une ligne du registre)
  - Kubernetes/, déjà cadré
  - décrire un usage ou un serveur réel
acceptance_criteria:
  - chacun des scripts de Linux/System, Linux/Security et Linux/K3s a un contrat avec options et défauts, codes de retour, ce qu'il modifie, ce qu'il lit et son état
  - chaque option, code de retour et variable cité se retrouve par grep dans le script concerné
  - l'historique du cadrage porte une ligne datée « état initial » dont la colonne « Validé par user » reste vide jusqu'à sa validation
validation:
  - "bash orchestration/outils/verifier-liens.sh"
---

# TASK-075 — Cadrage de Linux/

Passe en `ready` quand user a validé le cadrage de Kubernetes/ (TASK-074). User relit
et valide ce cadrage avant la clôture.
