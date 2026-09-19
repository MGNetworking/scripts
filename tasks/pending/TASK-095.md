---
id: TASK-095
title: "Extraire dans lib-agents.sh ce que lancer-agent.sh a de générique"
status: pending
priority: medium
depends_on:
  - TASK-094
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Les fonctions de lancer-agent.sh qui ne doivent rien à ce dépôt — copie isolée par
  git worktree, plafond de durée, relevé de jetons et de coût — vivent dans
  orchestration/outils/lib-agents.sh, réutilisable tel quel dans un autre projet.
scope:
  - orchestration/outils/lib-agents.sh
  - orchestration/outils/lancer-agent.sh
  - tests/acceptance/TASK-095-lib-agents.sh
out_of_scope:
  - créer un dépôt séparé pour cette bibliothèque
  - changer le comportement observable de lancer-agent.sh, ses arguments ou sa sortie
  - toucher verifier-travail.sh ou clore-tache.sh
acceptance_criteria:
  - lib-agents.sh ne contient que ce que l'inventaire de TASK-094 déclare générique, et aucune mention de ce dépôt - ni chemin, ni nom de tâche, ni règle propre au projet
  - lancer-agent.sh charge la bibliothèque et garde exactement les mêmes arguments, la même ligne VERDICT et la même ligne de mesure ; un lancement réel le démontre, sortie citée
  - chaque fonction extraite prend ses paramètres en arguments, sans variable globale du script appelant
  - tests/acceptance/TASK-095-lib-agents.sh prouve la création puis la réutilisation d'une copie isolée, et le refus d'un profil inconnu ; rend 0
  - shellcheck -x rend 0 sur les deux fichiers ; chacun fait 150 lignes au plus
validation:
  - "bash tests/acceptance/TASK-095-lib-agents.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - depuis la décision 51 (2026-09-19), orchestration/outils/ n'est plus interdit en écriture aux agents lancés : cette tâche revient à deepseek, comme tout script
  - conseil donné à user le 2026-09-19 - isoler dans un fichier du même dépôt, pas dans un dépôt séparé tant qu'un seul projet l'utilise
---

# TASK-095 — Bibliothèque des gestes génériques

Seconde des deux tâches demandées par user le 2026-09-19. Elle ne démarre qu'une fois
l'inventaire de TASK-094 écrit, qui dit quoi extraire.
