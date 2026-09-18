---
id: TASK-093
title: "Rendre l'outillage capable de conduire une tâche documentaire (A177, A178)"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  Une tâche dont le livrable est un document se conduit sans arbitrage humain : juger.sh
  la reconnaît au lieu de la router vers le scénario Molecule, et limites.json laisse les
  agents écrire de la documentation là où leur tâche le demande.
scope:
  - orchestration/outils/juger.sh — A177, l'ordre des branches
  - orchestration/limites.json — A178, écriture documentaire
  - tests/acceptance/TASK-086-outillage.sh — cas de la branche documentaire sous Ansible/
out_of_scope:
  - ouvrir CLAUDE.md, orchestration/ ou config/*.env aux agents lancés
  - modifier lancer-agent.sh, verifier-travail.sh ou clore-tache.sh
  - corriger les autres lignes du registre
acceptance_criteria:
  - juger.sh rend 0 sur le scope de TASK-087 (Ansible/GUIDE.md seul) et continue de rendre 1 sur un scope Ansible/roles/<nom>/ sans scénario Molecule complet ; les verdicts de TASK-069, TASK-081 et TASK-083 sont inchangés
  - la règle appliquée est écrite dans le script - un scope sans .sh ni Ansible/roles/ est documentaire, quel que soit le dossier
  - un agent lancé peut écrire un fichier .md de son scope sous Ansible/, Linux/, Docker/, Kubernetes/, Synology/, tests/ et docs/, y compris un README ; démontré en conteneur ou par un lancement d'essai dont la sortie est citée
  - les interdictions qui protègent le dépôt restent - CLAUDE.md, orchestration/, config/*.env (hors .example), .git/ refusés ; démontré de la même façon
  - les nouveaux cas sont ajoutés à tests/acceptance/TASK-086-outillage.sh, qui rend 0 sur l'hôte
validation:
  - "bash tests/acceptance/TASK-086-outillage.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - fait observé le 2026-09-18 (TASK-087) - trois relances perdues, chacune sur un refus d'outillage et non sur le travail ; A177 et A178 au registre
  - décision 36 voulait que les README soient écrits par l'orchestrateur à la clôture ; cette tâche ne lève cette règle que pour un README explicitement inscrit au scope d'une fiche
---

# TASK-093 — Dette d'outillage sur les tâches documentaires

Demandé par user le 2026-09-18 : résoudre la dette d'outillage avant de reprendre le plan
[docs/plan-outil-preparation-serveurs.md](../../docs/plan-outil-preparation-serveurs.md).
Elle passe donc avant TASK-088.
