---
id: TASK-080
title: "Poser le poste de contrôle Ansible, le squelette Ansible/ et la CI"
status: in_progress
priority: high
depends_on:
  - TASK-079
environment: host
human_approval_required: true
agent: orchestrateur
objective: |
  Depuis WSL Ubuntu 24.04, ansible, ansible-lint et molecule sont disponibles ; le dépôt
  porte un squelette Ansible/ sans rôle ; une CI GitHub Actions lance le lint et les
  tests Bash sur chaque push et pull request.
scope:
  - Ansible/README.md — installation du poste de contrôle par pipx, commandes, sécurité de l'inventaire
  - Ansible/ansible.cfg, Ansible/inventory.example.yml, Ansible/host_vars/*.example.yml, Ansible/playbooks/, Ansible/roles/
  - Ansible/CADRAGE.md — besoin et ensemble, aucun contrat encore
  - .gitignore — inventaire réel, host_vars réels, fichiers Vault en clair
  - .yamllint, .ansible-lint
  - .github/workflows/ci.yml
out_of_scope:
  - écrire un rôle (TASK-081)
  - toute connexion à un VPS ou au NAS
  - versionner une adresse, un nom d'utilisateur ou un secret réel
acceptance_criteria:
  - dans WSL, ansible --version, ansible-lint --version et molecule --version rendent 0 ; les versions sont notées dans le rapport
  - installation par pipx seul, décrite dans Ansible/README.md et rejouable
  - ansible-lint et yamllint rendent 0 sur Ansible/
  - git check-ignore confirme que Ansible/inventory.yml et Ansible/host_vars/vps1.yml sont ignorés
  - ci.yml lance shellcheck, yamllint, ansible-lint et tests/run.sh en conteneur ; un premier passage sur GitHub est vert, lien du run dans le rapport
validation:
  - "bash orchestration/outils/verifier-liens.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - accords de user du 2026-09-17 - pipx est installé par user lui-même (sudo), le conducteur installe le reste par pipx sans sudo ; le push de master pendant la tâche est autorisé pour prouver la CI ; regles.md §8 autorise désormais pipx, ansible, ansible-playbook, ansible-lint, yamllint et molecule
  - installer un outil dans WSL et pousser sur GitHub modifient hors du dépôt - annoncer dans le rapport ce qui a été installé
  - si le profil systemd ne tourne pas sur les runners GitHub, le dire et restreindre la CI au profil debian (ligne au registre)
---

# TASK-080 — Poste de contrôle, squelette et CI

Passe en `ready` à la clôture de TASK-079.
