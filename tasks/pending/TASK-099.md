---
id: TASK-099
title: "Rendre la relecture lançable par l'API, avec un interrupteur API ou abonnement"
status: pending
priority: high
depends_on:
  - TASK-098
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  La relecture d'une tâche peut se faire par Opus à l'API, hors du harnais, ou par le
  sous-agent relecteur sur l'abonnement. Un réglage dit lequel, et user le change en une
  ligne selon ce qu'il reste d'abonnement pour faire tourner le harnais.
scope:
  - orchestration/outils/lancer-agent.sh — option --relecture
  - orchestration/relecture.json — réglage du mode et du modèle
  - .claude/commands/tache.md — étape 6 lit le réglage
  - tests/acceptance/TASK-099-relecture.sh
  - orchestration/README.md
out_of_scope:
  - modifier .claude/agents/relecteur.md, ses consignes ou ses droits
  - toucher aux étapes de tache.md autres que la 6
  - lire l'usage restant de l'abonnement ; le réglage se change à la main
acceptance_criteria:
  - lancer-agent.sh anthropic TASK-XXX --relecture --modele opus lance claude -p avec --agent relecteur et --tools Read,Grep,Glob, dans la copie ../script-agents/TASK-XXX, sans Bash, Edit ni Write ; démontré par un faux claude qui consigne ses arguments
  - la consigne envoyée est celle de la relecture - fiche, critères, verdict en tête - et non /executer-tache
  - la sortie du relecteur est rendue telle quelle sur stdout, et une ligne « relecteur » est ajoutée à agents.tsv avec le modèle, les jetons et le coût au tarif du profil, sans l'aide du conducteur
  - orchestration/relecture.json porte mode (api ou abonnement) et modele (alias) ; un mode inconnu est refusé en code 2
  - tache.md, étape 6, dit - mode abonnement, sous-agent relecteur comme aujourd'hui ; mode api, lancer-agent.sh --relecture, puis la même ligne de mesure n'est plus écrite à la main
  - le test prouve les deux modes, le refus d'un mode inconnu et l'absence de tout outil d'écriture dans les arguments ; shellcheck -x rend 0
validation:
  - "bash tests/acceptance/TASK-099-relecture.sh"
  - "bash tests/acceptance/TASK-098-modeles.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - ordre de user du 2026-09-19 - abonnement pour la gestion du projet, jetons d'API pour exécuter, relecture Opus par l'API ou l'abonnement selon ce qui reste
  - le CLI offre --agent et --tools, vérifiés le 2026-09-19 ; le relecteur reste défini une seule fois, dans .claude/agents/relecteur.md
  - à établir avant de coder - si claude -p --agent relecteur applique bien la liste d'outils du fichier de l'agent ; sinon --tools la fixe explicitement
---

# TASK-099 — Relecture par l'API

Seconde tâche demandée par user le 2026-09-19. Elle passe après TASK-098, dont elle réutilise
l'option --modele, la lecture du profil et --dry-run.
