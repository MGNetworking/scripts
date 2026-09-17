---
id: TASK-081
title: "Pilote : écrire le rôle securite_base (SSH, ufw, fail2ban) et le comparer aux scripts Bash"
status: pending
priority: high
depends_on:
  - TASK-080
environment: host
human_approval_required: true
agent: orchestrateur
objective: |
  Le rôle Ansible securite_base garantit ce que garantissent configure-ssh.sh,
  configure-firewall.sh et configure-fail2ban.sh, prouvé par Molecule ; son bilan
  comparatif permet à user de décider de poursuivre ou non la migration.
scope:
  - Ansible/roles/securite_base/ — defaults, meta/argument_specs.yml, tasks, handlers, templates, molecule/default/
  - Ansible/playbooks/securite.yml
  - Ansible/CADRAGE.md — contrat du rôle
  - .github/workflows/ci.yml — étape Molecule
out_of_scope:
  - modifier ou déprécier les trois scripts Bash (décision de user après le bilan)
  - appliquer le rôle sans --check sur un serveur ; le --check --diff sur un VPS est fait par user
  - disable-root-login.sh et les autres scripts de Linux/Security
acceptance_criteria:
  - chaque clause des contrats de configure-ssh.sh, configure-firewall.sh et configure-fail2ban.sh (Linux/CADRAGE.md) est reprise par le rôle ou écartée avec sa raison dans un tableau du rapport
  - molecule test rend 0 sur Debian 12 et Ubuntu 24.04, étape idempotence comprise
  - un mutant (une tâche du rôle rendue non idempotente) fait échouer molecule test ; sortie citée
  - ansible-lint et yamllint rendent 0 ; la CI est verte sur le push
  - la preuve SSH garantit qu'aucune configuration ne coupe l'accès (sshd -t avant rechargement, port autorisé dans ufw avant activation)
  - le rapport se termine par le bilan (lignes, durée des tests, défauts du registre évités ou non, lisibilité) et rend BESOIN_USER pour le --check --diff sur un VPS et la décision de poursuivre
validation:
  - "bash orchestration/outils/verifier-liens.sh"
---

# TASK-081 — Pilote securite_base

Passe en `ready` à la clôture de TASK-080. Niveaux de preuve : conteneur (Molecule),
machine (`--check --diff` par user).
