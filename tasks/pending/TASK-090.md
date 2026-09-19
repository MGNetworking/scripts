---
id: TASK-090
title: "Écrire le rôle Ansible k3s (installation officielle, version épinglée, configuration, mise à jour, désinstallation)"
status: pending
priority: medium
depends_on:
  - TASK-088
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Le rôle k3s reprend Linux/K3s/ : installation par l'installateur officiel,
  version épinglée, configuration, mise à jour, désinstallation — idempotent,
  prouvé par Molecule.
scope:
  - Ansible/roles/k3s/
out_of_scope:
  - toucher aux scripts Bash de Linux/K3s/
  - le rôle socle, docker ou kubernetes ; la recette serveur-neuf.yml
acceptance_criteria:
  - chaque clause du contrat couvrant Linux/K3s/ (CADRAGE du dossier) reprise ou écartée avec sa raison, ligne « Prouvé par : » (décision 50)
  - meta/argument_specs.yml déclare chaque variable (version épinglée comprise), son type et son défaut
  - molecule test vert ; idempotence : une seconde exécution ne réinstalle rien
  - la version installée est exactement celle demandée par la variable
  - ansible-lint et yamllint à 0 sur Ansible/roles/k3s/
validation:
  - "tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh k3s"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - valider-ansible.sh accepte le nom du rôle en argument depuis TASK-088
  - même gabarit que securite_base (TASK-081) et socle (TASK-088)
---

# TASK-090 — Rôle `k3s`

Troisième des quatre tâches. Plan : `docs/plan-outil-preparation-serveurs.md` §5.
