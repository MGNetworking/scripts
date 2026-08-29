---
id: TASK-008
title: "Brancher un fournisseur LLM derrière l'interface commune"
status: cancelled
priority: medium
depends_on:
  - TASK-007
environment: host
human_approval_required: true
objective: |
  Rendre le raisonnement du système effectif, sans que le projet ne dépende
  d'un fournisseur. Un adaptateur concret est branché derrière l'interface
  définie en TASK-007 ; en changer ne doit toucher ni le backlog, ni les outils,
  ni les validations.
scope:
  - .agent/runtime/llm/adapters/ — un adaptateur concret
  - .agent/config/providers/ — configuration du fournisseur, sans secret
  - .agent/prompts/system.md, planner.md, executor.md, validator.md, reviewer.md
  - .agent/runtime/llm/README.md — comment ajouter un adaptateur
out_of_scope:
  - toute clé d'API dans le dépôt — lecture depuis l'environnement uniquement
  - plusieurs adaptateurs à la fois — un seul, jusqu'à ce que la boucle fonctionne
acceptance_criteria:
  - l'orchestrateur n'appelle jamais une API de fournisseur autrement que par llm/interface.mjs
  - l'adaptateur implémente generate, generate_structured et tool_call
  - les entrées et sorties sont normalisées et indépendantes du fournisseur
  - le fournisseur se choisit par configuration, sans modification de code
  - aucune clé d'API ne figure dans le dépôt, les logs, l'état ou un rapport
  - les prompts vivent dans le dépôt, pas dans la configuration d'un outil externe
  - un adaptateur factice permet d'exécuter la boucle sans appel réseau
validation:
  - "tests/run.sh lint"
  - "tests/run.sh llm"
implementation_notes:
  - la clé d'API se lit dans l'environnement et n'est jamais journalisée
  - l'adaptateur factice conditionne la testabilité de toute la chaîne — l'écrire en premier
  - une réponse de modèle est une donnée à valider, pas une instruction à exécuter
  - le choix du fournisseur concret et le budget associé demandent l'accord de Maxime
---

# TASK-008 — Interface LLM

> **Annulée le 2026-08-28** — [ADR-0002](../../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md).
> Le découplage multi-fournisseur est abandonné : un seul moteur est accessible
> sur ce projet. `AGENTS.md`, le backlog et les tests restent malgré tout des
> formats ouverts, lisibles par d'autres outils — mais rien ne sera construit
> pour eux.
> Conservée pour mémoire de ce qui a été écarté.

## Sens du découplage

```text
Orchestrateur → interface → adaptateur → fournisseur
```

Le backlog, les critères, les outils, les validations, l'état et les rapports
appartiennent au projet. Le modèle n'est qu'un moteur remplaçable.

Concrètement : un clone du dépôt doit permettre à n'importe quel moteur de
reprendre le travail, avec le même backlog, les mêmes preuves et le même format
de rapport.

## Pourquoi l'adaptateur factice d'abord

Sans lui, chaque essai de la boucle coûte un appel réseau et introduit du
non-déterminisme dans les tests. Un adaptateur qui rejoue des réponses fixes
rend l'orchestrateur testable et permet de vérifier la machine à états sans
dépendre d'un modèle.

## Accord humain requis

Cette tâche engage un fournisseur, un modèle et un coût. `human_approval_required`
est à `true` : l'agent prépare, Maxime tranche.
