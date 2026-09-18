---
id: TASK-085
title: "Exécuter l'outillage Ansible dans un conteneur jetable, comme le reste du dépôt"
status: ready
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: deepseek
objective: |
  ansible, ansible-lint, yamllint et molecule s'exécutent depuis un conteneur jetable
  lancé par tests/env/, comme tests/run.sh pour Bash. Aucune installation sur la machine
  de user n'est plus nécessaire pour valider un rôle.
scope:
  - tests/env/ — profil « ansible » (image, lancement, socket Docker pour les instances Molecule)
  - Ansible/README.md — la commande conteneurisée devient la commande de référence
  - .github/workflows/ci.yml — le travail Ansible passe par ce profil
out_of_scope:
  - modifier le rôle securite_base ou son scénario Molecule
  - désinstaller l'outillage du WSL de user
  - appliquer un rôle sur une machine réelle
acceptance_criteria:
  - une seule commande, documentée, lance ansible-lint, yamllint puis molecule test sur securite_base sans rien installer sur l'hôte ; codes réels au rapport
  - les instances Molecule créées portent le préfixe mgnet-test- et sont supprimées à la fin, prouvé par docker ps -a avant et après
  - l'image et les versions des outils sont épinglées, comme les linters de ci.yml
  - la CI utilise ce profil et reste verte ; lien du run au rapport
validation:
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - Molecule pilote Docker - le conteneur d'outillage a besoin du socket Docker de l'hôte (montage), il ne lance pas un Docker imbriqué
  - s'inspirer de tests/env/run-in-container.sh et assurer-docker.sh, sans les dupliquer
  - fait observé (TASK-080) - l'outillage a été installé dans WSL par pipx, écart au standard du dépôt que cette tâche referme
---

# TASK-085 — Outillage Ansible en conteneur jetable

Demandé par user le 2026-09-18 : la migration doit suivre le même mode opératoire que
l'implémentation — validation dans un conteneur jetable, rien sur la machine.
