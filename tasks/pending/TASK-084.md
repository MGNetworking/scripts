---
id: TASK-084
title: "Apprendre à juger.sh à juger une tâche Ansible (A158)"
status: ready
priority: medium
depends_on: []
environment: host
human_approval_required: false
agent: deepseek
objective: |
  `orchestration/outils/juger.sh` rend 1 avec « aucun fichier de cas dans le périmètre »
  sur toute tâche qui ne livre pas de script Bash — TASK-080 et TASK-081 l'ont subi. Un
  rôle Ansible se prouve par un scénario Molecule ; l'outil doit le reconnaître, sans quoi
  son verdict se lit « sans objet » et ne vaut plus rien.
scope:
  - orchestration/outils/juger.sh
  - orchestration/README.md — description de l'outil, si elle décrit ce verdict
out_of_scope:
  - lancer Molecule depuis juger.sh, qui reste un juge statique et rapide
  - modifier les fiches TASK-080 et TASK-081, closes
acceptance_criteria:
  - une tâche dont le `scope` ne vise que `Ansible/` est jugée sur la présence d'un scénario Molecule (`molecule/<nom>/molecule.yml`, `converge.yml`, `verify.yml`) au lieu d'un fichier de cas
  - `juger.sh tasks/completed/TASK-081.md` rend 0, et son verdict nomme le scénario trouvé
  - une tâche Ansible sans scénario rend toujours 1, avec un message qui dit ce qui manque
  - une tâche Bash est jugée exactement comme avant — aucun changement de verdict sur trois fiches déjà closes, cité dans le rapport
validation:
  - "bash orchestration/outils/juger.sh tasks/completed/TASK-081.md"
  - "bash orchestration/outils/verifier-liens.sh"
---

# TASK-084 — juger.sh et les tâches Ansible

Née du registre A158, constatée deux fois (TASK-080, TASK-081).
