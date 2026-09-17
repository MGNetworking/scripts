---
id: TASK-079
title: "Consigner la décision 50 : Ansible pour installer et configurer, cadre de test"
status: ready
priority: high
depends_on:
  - TASK-078
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  La proposition docs/proposition-ansible-et-tests.md, validée par user le 2026-09-17,
  devient la décision 50 et s'applique aux documents qui guident le travail.
scope:
  - orchestration/decisions.md — décision 50
  - CLAUDE.md — arborescence cible (Ansible/), frontière Ansible ↔ Bash, conventions minimales d'un rôle
  - orchestration/regles.md, orchestration/architecture.md — validation d'un rôle, niveaux de preuve
  - .claude/agents/relecteur.md — niveau de preuve nommé, ligne « Prouvé par : » à partir de son introduction
  - docs/proposition-ansible-et-tests.md — supprimé une fois la décision consignée
out_of_scope:
  - créer Ansible/, un rôle, une CI ou installer un outil (TASK-080)
  - déprécier un script Bash : cela se fait rôle par rôle, après le pilote
  - ajouter les lignes « Prouvé par : » aux cadrages existants
acceptance_criteria:
  - decisions.md porte la décision 50, datée, avec les réponses de user - répartition du §2 validée, harnais Bash actuel conservé (pas de bats-core), pilote securite_base, refonte du README d'abord
  - la décision reprend §3 à §5 de la proposition - poste de contrôle WSL, application par --check --diff puis --limit, inventaire réel hors Git, contrat d'un rôle par meta/argument_specs.yml, script remplacé déprécié selon la décision 49, trois niveaux de preuve, CI obligatoire
  - la décision dit que le pilote se clôt par un bilan comparatif et que user décide seul de poursuivre la migration
  - CLAUDE.md liste Ansible/ dans l'arborescence cible
  - docs/proposition-ansible-et-tests.md n'existe plus et aucun lien n'y renvoie
validation:
  - "bash orchestration/outils/verifier-liens.sh"
---

# TASK-079 — Décision 50

Source : `docs/proposition-ansible-et-tests.md` (commit 2c1e965), validée telle quelle.
