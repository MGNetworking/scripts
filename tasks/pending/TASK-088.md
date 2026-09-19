---
id: TASK-088
title: "Écrire le rôle Ansible socle (fuseau, hôte, journaux, swap, mises à jour, comptes, cron)"
status: ready
priority: medium
depends_on: []
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Le rôle socle reprend Linux/System/configure-*.sh et manage-users.sh : fuseau
  horaire, nom d'hôte, rotation des journaux, swap, mises à jour système, comptes
  et sudo, tâches cron — idempotent, prouvé par Molecule sur Debian 12 et Ubuntu 24.04.
scope:
  - Ansible/roles/socle/
  - tests/env/valider-ansible.sh — accepte un nom de rôle en argument, défaut securite_base
out_of_scope:
  - toucher aux scripts Bash Linux/System/*.sh, ni les déprécier (décision 50 : dépréciation seulement après bilan et décision de user)
  - le rôle docker, k3s ou kubernetes
  - la recette serveur-neuf.yml
acceptance_criteria:
  - chaque clause du contrat de Linux/CADRAGE.md couverte par le rôle est reprise ou explicitement écartée, avec sa raison, et porte une ligne « Prouvé par : » (décision 50)
  - meta/argument_specs.yml déclare chaque variable, son type et son défaut ; une variable inconnue ou mal typée est refusée
  - molecule test vert sur Debian 12 et Ubuntu 24.04 ; étape idempotence : un second passage ne change rien
  - un mutant non idempotent (ex. tâche sans état déclaratif) fait échouer le scénario
  - ansible-lint et yamllint à 0 sur Ansible/roles/socle/
validation:
  - "tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh socle"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - pilote de référence : Ansible/roles/securite_base (TASK-081) — même structure, même niveau de preuve
  - valider-ansible.sh codait en dur Ansible/roles/securite_base : généralise-le pour recevoir le nom du rôle en argument, sans changer son comportement par défaut ni la doc de securite_base
  - trois niveaux de preuve, toujours nommés (décision 50) : simulé, conteneur (Molecule), machine (--check --diff par user seul, hors scope)
---

# TASK-088 — Rôle `socle`

Première des quatre tâches qui suivent le pilote `securite_base` (bilan positif,
décision de `user` de poursuivre). Le plan complet est
`docs/plan-outil-preparation-serveurs.md` §5.
