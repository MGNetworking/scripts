---
id: TASK-086
title: "Outiller la vérification et la clôture d'une tâche, et donner à juger.sh sa branche documentaire (A172)"
status: ready
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  Les gestes mécaniques du conducteur — vérifier un périmètre, relancer les validations,
  clore une tâche — sont exécutés par deux scripts déterministes au lieu d'un modèle, et
  juger.sh cesse de rendre un échec sur une tâche purement documentaire.
scope:
  - orchestration/outils/verifier-travail.sh — périmètre contre le scope, commandes de validation, juger.sh, verdict compact
  - orchestration/outils/clore-tache.sh — fiche vers completed/, backlog, journal, agents.tsv, verifier-liens.sh
  - orchestration/outils/juger.sh — branche documentaire (A172)
  - .claude/commands/tache.md — étapes 5 et 8 appellent ces scripts
  - tests/acceptance/TASK-086-outillage.sh — preuve des deux scripts
out_of_scope:
  - automatiser la relecture Opus
  - modifier lancer-agent.sh ou limites.json
  - rejouer ou modifier une tâche déjà close
acceptance_criteria:
  - verifier-travail.sh rend 0 sur la branche de TASK-085 au commit de son premier jet, 1 si un fichier hors scope est ajouté à une copie jetable ; sorties citées au rapport
  - clore-tache.sh rejoue à l'identique la clôture de TASK-083 sur une copie jetable - fiche déplacée, ligne de backlog, ligne de journal, agents.tsv, liens à 0 ; diff avec la clôture réelle vide ou justifié
  - juger.sh rend 0 sur le périmètre documentaire de TASK-083 et 1 sur une fiche au scope vide ; les périmètres Bash et Ansible rendent le même verdict qu'avant (TASK-069, TASK-081)
  - les deux scripts font 150 lignes au plus chacun et passent shellcheck
  - tache.md appelle ces scripts aux étapes 5 et 8, sans décrire à nouveau les gestes qu'ils font
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash tests/acceptance/TASK-086-outillage.sh"
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - mesuré le 2026-09-18 - le conducteur a consommé 36 000 à 199 000 jetons par tâche, dont environ 70 % de gestes mécaniques
  - orchestration/ est interdit en écriture aux agents lancés (limites.json) - cette tâche revient au conducteur
---

# TASK-086 — Outillage de vérification et de clôture

Première tâche du plan [docs/plan-outil-preparation-serveurs.md](../../docs/plan-outil-preparation-serveurs.md),
validé par user le 2026-09-18. Elle réduit le coût de toutes les suivantes.
