---
id: TASK-078
title: "Refondre tests/README.md en guide de 200 lignes au plus"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  tests/README.md redevient un guide : ce que le dossier prouve, lancer, écrire un
  fichier de cas, codes de retour, environnement conteneurisé. Chaque règle encore
  vraie est gardée en une phrase ; chaque récit de défaut passé est retiré.
scope:
  - tests/README.md
out_of_scope:
  - modifier un test, le harnais, assert.sh ou un script de tests/env
  - ajouter Molecule, Ansible ou une CI (TASK-080, TASK-081)
  - déplacer le contenu retiré vers un autre fichier : il existe déjà dans les rapports et Git
acceptance_criteria:
  - wc -l tests/README.md rend 200 au plus
  - le plan suit le §6 de docs/proposition-ansible-et-tests.md, dont les trois niveaux de preuve (simulé, conteneur, machine)
  - le rapport contient un tableau « règle du README au commit 2c1e965 → phrase du nouveau README, ou raison du retrait », qui couvre toutes les règles prescriptives de l'ancien fichier (tout ce qui dit « jamais », « toujours », « doit », « ne … pas »)
  - la règle des faux binaires citée par juger.sh et lien-ecrit.awk (A122) reste présente
  - chaque commande et chemin cité existe dans le dépôt
validation:
  - "bash orchestration/outils/verifier-liens.sh"
  - "bash tests/run.sh --liste"
---

# TASK-078 — Refonte de tests/README.md

Validée par user le 2026-09-17 (proposition, question 4 : « tout de suite »).
1 514 lignes au commit 2c1e965, devenues un journal.
