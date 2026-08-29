---
id: TASK-006
title: "Mettre en place l'état persistant, les logs et les rapports"
status: cancelled
priority: high
depends_on:
  - TASK-005
environment: host
human_approval_required: false
objective: |
  Permettre à l'agent de reprendre son travail sans reconstituer le contexte,
  et rendre chaque exécution retraçable après coup.
scope:
  - .agent/state/current-task.json — tâche en cours, phase, tentative, dernière action
  - .agent/state/session.json — session, horodatages, tâches traitées
  - .agent/logs/ — un fichier par session, une ligne JSON par événement
  - .agent/reports/ — un rapport Markdown par tâche
  - .agent/tools/state.sh — lecture et écriture de l'état
  - .agent/tools/report.sh — génération d'un rapport à partir de l'état et des logs
  - .gitignore — ignorer .agent/state/ et .agent/logs/
out_of_scope:
  - orchestrateur consommant cet état (TASK-007)
  - toute donnée sensible dans l'état ou les logs
acceptance_criteria:
  - current-task.json contient l'id, le statut, la phase, la tentative, la dernière action, le dernier résultat, la dernière erreur, la prochaine action et les validations effectuées
  - l'état survit à l'arrêt du processus et se relit intégralement
  - un état corrompu est détecté et signalé, jamais interprété au jugé
  - chaque événement de log porte timestamp, task_id, phase, action, outil, commande, resultat, exit_code et duree
  - les logs sont ignorés par Git, les rapports sont versionnés
  - aucune variable dont le nom contient TOKEN, PASSWORD, SECRET, KEY ou CREDENTIAL n'apparaît dans un log ou un état
  - le contenu de config/*.env n'apparaît jamais dans un log, un état ou un rapport
  - un rapport est produit pour une tâche terminée comme pour une tâche bloquée
validation:
  - "tests/run.sh lint"
  - "tests/run.sh state"
implementation_notes:
  - les logs sont ignorés par Git, les rapports versionnés — un rapport est la trace durable d'une décision
  - ne pas confondre .agent/logs/ (journal de l'agent) et logs/ (sorties des scripts administrés)
  - format de rapport imposé par tasks/README.md §6
  - un filtre de rédaction s'applique avant toute écriture de log, pas après
---

# TASK-006 — État, logs, rapports

> **Annulée le 2026-08-28** — [ADR-0002](../../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md).
> L'état et les journaux techniques sont tenus par Claude Code. Seuls les
> **rapports** sont conservés : ils restent produits par la commande `/tache`,
> dans `.agent/reports/`, au format de [tasks/README.md](../README.md) §6.
> Conservée pour mémoire de ce qui a été écarté.

## Trois natures d'information, trois traitements

| | Destinataire | Versionné | Durée de vie |
|---|---|---|---|
| **état** | l'agent lui-même | non | la session en cours |
| **logs** | diagnostic technique | non | quelques sessions |
| **rapports** | l'humain | **oui** | permanente |

Les mélanger produirait soit un dépôt pollué de traces techniques, soit une
perte de mémoire à chaque redémarrage.

## Sécurité — le dépôt est public

Le filtre de rédaction s'applique **au moment de l'écriture**, jamais en
nettoyage a posteriori. Un secret écrit puis effacé reste dans l'historique Git
si le fichier est versionné, et dans le fichier de log s'il ne l'est pas.

`config/*.env` n'est ni lu, ni journalisé, ni recopié — cette règle vaut pour
l'état et les rapports au même titre que pour les logs.

## Reprise après interruption

L'état doit répondre à une seule question : « que faisais-je, où en étais-je,
et quelle était la prochaine action ? » S'il ne permet pas de répondre sans
relire les logs, il est incomplet.
