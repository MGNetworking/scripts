---
id: TASK-074
title: "Écrire le cadrage de Kubernetes/ à partir de l'état actuel des scripts"
status: pending
priority: high
depends_on:
  - TASK-073
environment: host
human_approval_required: true
agent: orchestrateur
objective: |
  Kubernetes/CADRAGE.md existe au modèle de la décision 49 : besoin du dossier, ensemble
  « Gestion de Kubernetes », et un contrat par script qui décrit son comportement
  actuel, lu dans le code. Premier cadrage, il éprouve le modèle.
scope:
  - Kubernetes/CADRAGE.md
out_of_scope:
  - modifier un script, un README ou un fichier de cas, même si le code contredit sa documentation (l'écart devient une ligne du registre)
  - Linux/K3s/, qui relève du cadrage de Linux/
  - décrire un usage ou un serveur réel
acceptance_criteria:
  - chacun des 18 scripts de Kubernetes/Installation, Configuration et Maintenance a un contrat avec options et défauts, codes de retour, ce qu'il modifie, ce qu'il lit et l'état « actif »
  - chaque option, code de retour et variable SRV_K8S_* cité se retrouve par grep dans le script concerné
  - l'historique du cadrage porte une ligne datée « état initial » dont la colonne « Validé par user » reste vide jusqu'à sa validation
  - la tâche se clôt en BESOIN_USER : user relit et valide le cadrage avant tout autre cadrage
validation:
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - modèle et règles dans la décision 49 de orchestration/decisions.md
  - s'appuyer sur la décision 48 (accès au cluster, maintenance) et les README des trois sous-dossiers
---

# TASK-074 — Cadrage de Kubernetes/

Passe en `ready` à la clôture de TASK-073. Si le modèle se révèle inadapté, le dire
dans le rapport : TASK-075 à TASK-077 attendent sa validation.
