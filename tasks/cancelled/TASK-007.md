---
id: TASK-007
title: "Implémenter l'orchestrateur et la machine à états"
status: cancelled
priority: high
depends_on:
  - TASK-005
  - TASK-006
environment: host
human_approval_required: false
objective: |
  Fournir le programme qui contrôle le cycle de vie d'une tâche : sélection,
  planification, exécution, validation, correction limitée, review, rapport.
  Les transitions d'état lui appartiennent, jamais au modèle.
scope:
  - .agent/runtime/orchestrator.mjs — boucle et machine à états
  - .agent/runtime/backlog.mjs — lecture de tasks/, parseur du frontmatter restreint
  - .agent/runtime/validator.mjs — exécution des commandes du champ validation
  - .agent/runtime/llm/interface.mjs — contrat d'adaptateur, indépendant du fournisseur
  - .agent/config/agent.yaml — limites, retries, politique Git
  - .agent/config/validation.yaml — niveaux de validation
  - agent — commande de lancement (run, status, task, logs, report, validate, stop)
out_of_scope:
  - adaptateur d'un fournisseur LLM concret (TASK-008)
  - boucle multi-tâches — après validation de la première boucle complète
  - toute exécution réelle de tâche du backlog
acceptance_criteria:
  - agent status affiche la tâche en cours, sa phase, sa tentative et sa durée
  - agent run sélectionne une tâche ready dont les dépendances sont completed
  - une tâche blocked, pending ou à dépendance non satisfaite n'est jamais sélectionnée
  - le parseur lit le sous-ensemble YAML défini dans tasks/README.md et rejette explicitement ce qui en sort
  - les transitions interdites par la machine à états sont refusées
  - le validator exécute les commandes du champ validation et rend un résultat structuré
  - une validation non exécutable est rapportée NON EXÉCUTÉ, jamais PASS
  - la boucle de correction s'arrête à MAX_RETRIES = 5 et bascule en blocked
  - aucun appel direct à une API de fournisseur hors de llm/interface.mjs
  - une interruption laisse un état relisible
validation:
  - "tests/run.sh lint"
  - "tests/run.sh orchestrator"
  - "agent status"
implementation_notes:
  - Node avec la seule bibliothèque standard, conformément à ADR-0001 décision 1 — aucun package.json, aucune dépendance npm
  - modules .mjs, imports natifs
  - l'orchestrateur appelle les outils Bash et lit leur JSON — il n'exécute pas de commande directement
  - la machine à états est une table de transitions explicite, pas une suite de conditions dispersées
  - un statut de tâche se met à jour dans le fichier ET par déplacement de répertoire — les deux doivent rester cohérents
---

# TASK-007 — Orchestrateur

> **Annulée le 2026-08-28** — [ADR-0002](../../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md).
> Aucun orchestrateur n'est écrit. La boucle, la sélection de tâche, la
> délégation et la limite de tentatives vivent dans
> [.claude/commands/tache.md](../../.claude/commands/tache.md) — un fichier
> Markdown, pas un programme.
> Conservée pour mémoire de ce qui a été écarté.

## Ce qui appartient à l'orchestrateur et non au modèle

```text
IDLE → PLANNING → EXECUTING → VALIDATING → REVIEWING → REPORTING → COMPLETED
                                  ↓  ↑
                               FIXING
                                  ↓
                               BLOCKED
```

Le modèle propose ; l'orchestrateur constate et transite. Un agent ne se déclare
pas lui-même terminé : il produit des résultats, et c'est le validator qui
décide, sur des codes de retour.

C'est la différence entre `LLM + prompt` et un système agentique.

## Point d'attention — le parseur

Le sous-ensemble YAML est défini strictement dans
[tasks/README.md](../README.md) §2 pour qu'un parseur de quelques dizaines de
lignes suffise. La tentation d'accepter « un peu plus » de YAML au fil des
besoins conduit à réimplémenter un analyseur complet, mal.

Ce qui sort du sous-ensemble doit provoquer une erreur nette indiquant le
fichier et la ligne, jamais une interprétation approximative.

## Commande de lancement

```bash
agent run                # boucle sur les tâches prêtes
agent status             # vue synthétique
agent task TASK-001      # exécute une tâche précise
agent validate TASK-001  # rejoue seulement les validations
agent report TASK-001    # affiche le rapport
agent logs               # journal de la session
agent stop               # arrêt propre
```
