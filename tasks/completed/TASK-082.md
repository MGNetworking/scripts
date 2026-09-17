---
id: TASK-082
title: "Remettre au vert tests/acceptance/TASK-012 sur l'hôte (A149)"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  tests/acceptance/TASK-012-semantique-codes.sh ne rend plus d'échec sur l'hôte Windows :
  ses trois cas qui attendent 0 de tests/run.sh avec le niveau lint tiennent compte de
  A03 (lint rend 3 sans shellcheck), sans affaiblir ce qu'ils prouvent.
scope:
  - tests/acceptance/TASK-012-semantique-codes.sh
out_of_scope:
  - modifier tests/lint.sh, tests/run.sh ou tests/lib/assert.sh
  - corriger les renvois de section (A147)
acceptance_criteria:
  - la cause de chacun des trois échecs est établie par exécution et écrite dans le rapport
  - chaque cas modifié dit en quoi son attente était fausse ; aucune assertion retirée sans remplacement
  - bash tests/acceptance/TASK-012-semantique-codes.sh ne rend plus 1 sur l'hôte
validation:
  - "bash tests/acceptance/TASK-012-semantique-codes.sh"
---

# TASK-082 — TASK-012 rouge sur l'hôte

Constaté pendant TASK-078 (2026-09-17) : 56 réussites, 3 échecs, code 1 — « lint satisfait
+ acceptance partielle → 0 », « deux niveaux demandés, tous deux satisfaits → 0 »,
« tests/run.sh lint sur l'hôte → 0 » obtiennent 3. Registre : A149.
