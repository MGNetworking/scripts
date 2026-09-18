---
id: TASK-087
title: "Documenter le fonctionnement de l'outil de préparation, à hauteur d'utilisateur"
status: in_progress
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Ansible/README.md explique le fonctionnement de l'outil à quelqu'un qui n'a jamais
  employé Ansible : le trajet du poste vers le serveur, ce qu'est un rôle, ce qu'est une
  recette, où vivent les informations confidentielles, et ce qui se passe le jour où un
  serveur existe.
scope:
  - Ansible/README.md
out_of_scope:
  - modifier un rôle, un playbook, la configuration des linters ou la CI
  - documenter des rôles qui n'existent pas encore (seul securite_base existe)
  - reprendre le contenu de Ansible/CADRAGE.md, qui engage les contrats
acceptance_criteria:
  - un schéma en texte montre le trajet poste → SSH → serveur, et dit qu'aucun agent ni dépôt n'est installé sur le serveur
  - aucun terme technique employé sans être expliqué à sa première apparition (rôle, playbook, inventaire, idempotence, Molecule, coffre)
  - une section dit où vivent inventaire, host_vars, clés SSH et secrets, et lesquels ne partent jamais sur GitHub ; elle correspond au .gitignore réel
  - les commandes du quotidien sont données telles quelles - validation en conteneur, --check --diff puis application avec --limit ; chacune existe et est citée sans invention
  - une section « le jour où vous aurez un serveur » énumère les gestes de user dans l'ordre
  - 200 lignes au plus
validation:
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - source du fond - docs/plan-outil-preparation-serveurs.md §1, §2 et §7, et la décision 50
  - écrire en français simple, pour user qui découvre Ansible ; le README explique, le CADRAGE engage
---

# TASK-087 — Documentation fonctionnelle de l'outil

Deuxième tâche du plan [docs/plan-outil-preparation-serveurs.md](../../docs/plan-outil-preparation-serveurs.md),
demandée par user le 2026-09-18 : « il faudra que tu documentes cette partie au niveau
fonctionnel pour que je puisse comprendre le fonctionnement ».
