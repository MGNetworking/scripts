---
id: TASK-040
title: "Ramener manage-users.sh et son fichier de cas à la sobriété visée"
status: completed
priority: low
depends_on:
  - TASK-025
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Raccourcir Linux/System/manage-users.sh (179 lignes) vers 150 et son fichier de
  cas (419 lignes) vers 250, sans changer aucun comportement ni perdre la preuve
  d'un seul critère de TASK-025 (registre TASK-039, A44).
scope:
  - Linux/System/manage-users.sh
  - tests/integration/manage-users.test.sh
out_of_scope:
  - tout changement de comportement, d'option, de message ou de code de retour
  - tests/lib/ et tout autre fichier de cas
acceptance_criteria:
  - le script fait 150 lignes au plus, le fichier de cas 250 au plus — ou la raison d'un dépassement est donnée
  - chacun des 15 critères de tasks/completed/TASK-025.md garde au moins une assertion qui le prouve
  - seules des assertions strictement redondantes disparaissent ; les messages de refus restent tous vérifiés
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/System/manage-users.sh --utilisateur essai --dry-run"
implementation_notes:
  - pistes de la relecture de TASK-025 — aide ramenée à ~14 lignes, commentaires qui répètent le code, blocs if/ok/ko de 5 lignes remplacés par une fonction d'une ligne, doublons du §8
  - lire tasks/completed/TASK-025.md pour la liste des critères
---

# TASK-040 — Sobriété de manage-users

Exception à la règle du fichier de cas figé : c'est l'objet même de la tâche. Toute
assertion retirée doit être redondante avec une autre qui reste.
