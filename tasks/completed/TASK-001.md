---
id: TASK-001
title: "Mettre en place le harnais de validation du dépôt"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
objective: |
  Doter le dépôt d'un point d'entrée unique de validation, exécutable à la main
  comme par l'agent. Sans lui, aucune tâche ultérieure ne peut être prouvée.
scope:
  - tests/run.sh — point d'entrée unique, dispatcher de niveaux
  - tests/lint.sh — analyse statique de tous les .sh du dépôt
  - tests/README.md — conventions de test du dépôt
  - .claude/settings.json — autoriser l'exécution de tests/
out_of_scope:
  - tests unitaires de lib/common.sh (TASK-003)
  - environnement conteneurisé (TASK-002)
  - installation de shellcheck sur la machine hôte
  - toute modification des scripts existants
acceptance_criteria:
  - tests/run.sh lint exécute l'analyse statique et retourne 0 si tout passe
  - tests/lint.sh vérifie la syntaxe de tous les .sh par bash -n
  - tests/lint.sh exécute shellcheck sur tous les .sh lorsqu'il est disponible
  - lorsque shellcheck est absent, la sortie indique NON EXÉCUTÉ et le code de retour reste 0
  - le résultat de chaque fichier est affiché individuellement
  - un script en erreur fait échouer la commande avec un code non nul
  - les scripts du harnais respectent eux-mêmes les conventions du dépôt
validation:
  - "bash -n tests/run.sh"
  - "bash -n tests/lint.sh"
  - "tests/run.sh lint"
implementation_notes:
  - shellcheck, shfmt et bats sont absents de la machine hôte
  - bash -n fonctionne sous Git Bash et constitue le socle minimal garanti
  - les scripts du harnais chargent lib/common.sh comme tout script du dépôt
  - ne pas faire échouer le lint sur les deux scripts Synology hérités — les signaler en WARN, leur mise au standard est une tâche distincte
---

# TASK-001 — Harnais de validation

## Pourquoi en premier

L'audit ([docs/agent/project-audit.md](../../docs/agent/project-audit.md), §5)
constate qu'il n'existe aujourd'hui **aucune** validation exécutable dans le
dépôt : ni test, ni lint, ni CI. La règle « les tests produisent la preuve »
n'a donc rien sur quoi s'appuyer.

Tant que cette tâche n'est pas terminée, aucun validator n'a de commande à
lancer et toute déclaration de réussite serait une affirmation sans preuve.

## Forme attendue

```bash
tests/run.sh                 # tous les niveaux disponibles
tests/run.sh lint            # niveau 1 seul
tests/run.sh unit            # niveau 2 — non implémenté ici, doit sortir proprement
```

Un niveau non encore implémenté ne provoque pas d'erreur : il annonce qu'il
n'existe pas et n'est pas compté comme réussi.

## Sortie attendue

```text
[INFO] Analyse statique — 11 fichiers
[SUCCESS] lib/common.sh
[SUCCESS] Linux/System/system-info.sh
[WARN] Synology/Plex/update-plex.sh — script hérité, hors standard
[INFO] shellcheck absent : analyse approfondie NON EXÉCUTÉE
[SUCCESS] Analyse statique : 11 fichiers, 0 erreur
```

## Piège connu

`bash -n` ne détecte que les erreurs de syntaxe. Il ne voit ni les variables non
quotées, ni les `cd` sans garde, ni les `[ $a = $b ]` fragiles — d'où
l'importance de brancher shellcheck dès qu'il est disponible, et de ne jamais
présenter `bash -n` seul comme une analyse complète.
