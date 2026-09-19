---
id: TASK-089
title: "Écrire le rôle Ansible docker (dépôt officiel, moteur, daemon.json, réseau, mise à jour)"
status: pending
priority: medium
depends_on:
  - TASK-088
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Le rôle docker reprend Docker/Installation, Docker/Configuration et
  update-docker.sh : dépôt officiel, moteur installé, daemon.json, réseau, mise
  à jour du moteur — idempotent, prouvé par Molecule.
scope:
  - Ansible/roles/docker/
out_of_scope:
  - toucher aux scripts Bash Docker/Installation, Docker/Configuration, update-docker.sh
  - les workloads (Docker/Cleanup, Docker/Diagnostics restent en Bash, décision 50)
  - le rôle socle, k3s ou kubernetes ; la recette serveur-neuf.yml
acceptance_criteria:
  - chaque clause du contrat de Docker/CADRAGE.md couverte est reprise ou écartée avec sa raison, ligne « Prouvé par : » (décision 50)
  - meta/argument_specs.yml déclare chaque variable, son type et son défaut
  - molecule test vert sur Debian 12 et Ubuntu 24.04 ; idempotence : un second passage ne change rien
  - le démon Docker répond (docker info) dans le conteneur d'essai du scénario
  - ansible-lint et yamllint à 0 sur Ansible/roles/docker/
validation:
  - "tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh docker"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - valider-ansible.sh accepte déjà le nom du rôle en argument depuis TASK-088
  - même gabarit que securite_base (TASK-081) et socle (TASK-088)
---

# TASK-089 — Rôle `docker`

Seconde des quatre tâches. Plan : `docs/plan-outil-preparation-serveurs.md` §5.
