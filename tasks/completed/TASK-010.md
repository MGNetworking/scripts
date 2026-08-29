---
id: TASK-010
title: "Mettre en place les sous-agents et la commande /tache"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
objective: |
  Doter le dépôt de son moteur d'exécution, sans écrire une ligne de programme :
  trois sous-agents Claude Code aux rôles distincts, et une commande qui les
  enchaîne sur une tâche du backlog.
scope:
  - .claude/agents/redacteur-script.md
  - .claude/agents/redacteur-tests.md
  - .claude/agents/relecteur.md
  - .claude/commands/tache.md
  - .claude/commands/backlog.md
  - docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md
  - annulation de TASK-005 à TASK-008
  - mise à jour de AGENTS.md, tasks/README.md, tasks/backlog.md, README.md
out_of_scope:
  - toute écriture de code d'orchestration
  - tout adaptateur ou abstraction multi-fournisseur
  - exécution réelle d'une tâche du backlog — c'est l'objet du premier essai
  - enchaînement automatique de plusieurs tâches sans humain
acceptance_criteria:
  - les trois sous-agents existent et déclarent un rôle, des outils et des règles
  - le relecteur n'a aucun outil d'écriture
  - la commande /tache couvre le cycle complet — contexte, préflight, plan, rédaction, tests, relecture, rapport, clôture Git
  - la limite de cinq tentatives figure dans la commande
  - les règles de refus figurent dans la commande — dépendance non satisfaite, arbre Git sale, Docker arrêté, périmètre dépassé
  - TASK-005 à TASK-008 sont annulées, conservées, et leur raison est écrite
  - la documentation ne promet plus d'orchestrateur ni de multi-LLM
  - aucun lien interne rompu
validation:
  - "tests/run.sh lint"
  - "vérification manuelle des liens internes des documents modifiés"
implementation_notes:
  - un sous-agent démarre sans mémoire de la conversation — la tâche et AGENTS.md doivent se suffire
  - le relecteur conserve Bash pour lancer les validations, l'interdiction d'écrire est portée par son prompt
  - ne pas multiplier les sous-agents : trois rôles, pas davantage
---

# TASK-010 — Moteur d'exécution

## Origine

Réorientation du 2026-08-28, actée par
[ADR-0002](../../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md).

Le plan initial prévoyait de construire un système agentique complet —
orchestrateur, outils, adaptateurs LLM. Un seul moteur étant accessible sur ce
projet, et Claude Code fournissant déjà la boucle, les outils et les limites, la
construction perdait son objet.

Ce qui restait à produire n'était pas du code, mais des **définitions** : qui
fait quoi, avec quels outils, sous quelles règles.

## Le point de conception

Le relecteur est en lecture seule, et c'est délibéré.

Un relecteur capable d'écrire finit toujours par corriger ce qu'il constate — et
un test « réparé » ne prouve plus rien. En le privant d'outil d'écriture, on rend
structurellement impossible le scénario le plus dangereux d'un agent : se donner
une bonne note en affaiblissant la vérification.

## Ce que la tâche ne fait pas

Elle ne démontre rien. Elle prépare.

La démonstration, c'est le premier passage réel de `/tache` sur une tâche du
backlog — et il révélera des règles mal formulées, comme toujours.
