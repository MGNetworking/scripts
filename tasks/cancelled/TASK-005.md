---
id: TASK-005
title: "Implémenter la couche d'outils de l'agent"
status: cancelled
priority: high
depends_on:
  - TASK-001
environment: host
human_approval_required: false
objective: |
  Donner à l'agent des capacités uniformes et traçables. Chaque outil est un
  script Bash autonome, appelable à la main, qui rend un résultat JSON sur sa
  sortie standard.
scope:
  - .agent/tools/filesystem.sh — read, write, edit, list, search
  - .agent/tools/shell.sh — execute, avec timeout et limite de sortie
  - .agent/tools/git.sh — status, diff, log, branch, checkout, add, commit
  - .agent/tools/testing.sh — lint, unit, integration, en enveloppant tests/run.sh
  - .agent/tools/lib/tool.sh — socle commun aux outils : sortie JSON, journalisation, erreurs
  - .agent/config/tools.yaml — outils exposés, commandes autorisées, limites
  - .agent/tools/README.md
out_of_scope:
  - outil docker et outil linux — après validation de la première boucle
  - orchestrateur, planner, executor (TASK-007)
  - toute modification de lib/common.sh, qui est le socle des scripts produits et non celui de l'agent
acceptance_criteria:
  - chaque outil s'exécute à la main et affiche une aide avec --help
  - chaque outil écrit sur stdout un objet JSON contenant status, resultat, erreur et duree
  - shell.sh applique un timeout et retourne stdout, stderr, exit_code et duree
  - shell.sh refuse toute commande absente de la liste autorisée de tools.yaml
  - shell.sh tronque une sortie dépassant la limite configurée en le signalant
  - git.sh refuse push, reset --hard, rebase et tout commit sur master
  - git.sh ne crée de branche que sous le préfixe agent/
  - filesystem.sh refuse toute écriture hors du dépôt et dans les zones interdites d'AGENTS.md
  - filesystem.sh refuse de lire config/*.env
  - toute invocation d'outil est journalisée dans .agent/logs/
validation:
  - "tests/run.sh lint"
  - "tests/run.sh tools"
implementation_notes:
  - outils en Bash, conformément à ADR-0001 décision 1
  - la sortie JSON est produite à la main : jq est absent de la machine, ne pas en faire une dépendance
  - échapper correctement les chaînes JSON — guillemets, antislashs, retours à la ligne, caractères de contrôle
  - le socle des outils est .agent/tools/lib/tool.sh, distinct de lib/common.sh
  - un outil ne décide jamais : il exécute, refuse ou rend compte
---

# TASK-005 — Couche d'outils

> **Annulée le 2026-08-28** — [ADR-0002](../../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md).
> Claude Code fournit déjà ces outils : lecture, écriture, shell, Git, avec
> leurs limites et leur traçabilité. Les réécrire en Bash n'apporterait rien.
> Conservée pour mémoire de ce qui a été écarté.

## Frontière à ne pas franchir

`lib/common.sh` est le socle des **scripts produits par le projet**. Il n'a pas
à connaître l'agent, ni à porter la moindre responsabilité agentique. Les outils
ont leur propre socle, `.agent/tools/lib/tool.sh`.

Confondre les deux ferait dépendre les scripts d'administration livrés sur un
serveur d'une machinerie qui n'a rien à y faire.

## Contrat de sortie

```json
{"status":"ok","outil":"shell","action":"execute","duree_ms":142,
 "resultat":{"stdout":"…","stderr":"","exit_code":0},"erreur":null}
```

En cas de refus :

```json
{"status":"refuse","outil":"git","action":"push",
 "erreur":"git push est interdit par AGENTS.md §8"}
```

Un refus **n'est pas une erreur** : c'est un résultat légitime, que
l'orchestrateur doit savoir distinguer d'un échec technique.

## Pourquoi le JSON à la main

`jq` est absent de la machine et l'ajouter contredirait la règle « pas de
dépendance inutile » du dépôt. L'échappement est le seul point délicat : il
mérite ses propres cas de test dans `tests/run.sh tools`.
