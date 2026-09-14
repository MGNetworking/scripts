---
id: TASK-038
title: "Remettre l'acceptance TASK-011 au vert après les scripts Docker"
status: ready
priority: high
depends_on: []
environment: container-debian
agent: orchestrateur
human_approval_required: false
objective: |
  Refaire passer tests/acceptance/TASK-011-analyse-statique.sh, cassé par deux
  écarts introduits par TASK-029 et TASK-030 et constatés pendant TASK-028.
scope:
  - Docker/Configuration/configure-docker.sh — lignes 91 et 141, directives et ASSUME_YES
  - Docker/Installation/install-docker.sh — ligne 145, directive et ASSUME_YES
  - tests/integration/configure-docker.test.sh — ligne 107, directive
  - lib/common.sh — seulement si la garde non interactive y est déplacée
out_of_scope:
  - tests/acceptance/TASK-011-analyse-statique.sh et la règle qu'il porte
  - les fichiers d'acceptance privés de démon Docker, sujet des points en suspens
acceptance_criteria:
  - chaque « shellcheck disable » est précédé d'un commentaire qui dit pourquoi — la justification AU-DESSUS de la directive, jamais en dessous
  - ASSUME_YES n'est lue que par lib/common.sh ; install-docker.sh et configure-docker.sh gardent leur refus clair sans terminal ni --yes
  - "tests/env/run-in-container.sh -- tests/run.sh acceptance ne signale plus aucun échec de TASK-011"
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh acceptance"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
implementation_notes:
  - trois des quatre directives ont leur justification juste en dessous : il suffit d'inverser les lignes
  - la garde « [ -t 0 ] || ASSUME_YES » avant confirm vit dans deux scripts ; la déplacer dans lib/common.sh (zone protégée) impose de revalider tout le dépôt — c'est pourquoi l'agent est l'orchestrateur
---

# TASK-038 — Deux écarts à la règle de TASK-011

Constaté le 2026-09-14 pendant TASK-028 : l'acceptance sort en 1 pour 4 directives
dont la justification manque ou est placée sous la directive, et parce que
`ASSUME_YES` est lue hors de `lib/common.sh`. Aucune relecture de TASK-029 ni de
TASK-030 ne l'a vu : `juger.sh` ne lance pas l'acceptance.
