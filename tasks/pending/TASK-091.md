---
id: TASK-091
title: "Écrire le rôle Ansible kubernetes (kubectl, Helm, cert-manager, metrics-server, Traefik, manifestes versionnés)"
status: pending
priority: medium
depends_on:
  - TASK-090
environment: host
human_approval_required: false
agent: deepseek
objective: |
  Le rôle kubernetes reprend Kubernetes/Installation et Kubernetes/Configuration :
  kubectl, Helm, cert-manager, metrics-server, Traefik, puis namespaces,
  StorageClass, Middlewares, ClusterIssuers, secret de registry — appliqués par
  des manifestes versionnés avec la collection kubernetes.core, jamais générés
  à la volée.
scope:
  - Ansible/roles/kubernetes/
out_of_scope:
  - toucher aux scripts Bash de Kubernetes/Installation, Kubernetes/Configuration
  - Kubernetes/Maintenance, qui reste en Bash (diagnostics, décision 50)
  - le rôle socle, docker ou k3s ; la recette serveur-neuf.yml
acceptance_criteria:
  - chaque clause du contrat de Kubernetes/CADRAGE.md couverte est reprise ou écartée avec sa raison, ligne « Prouvé par : » (décision 50)
  - meta/argument_specs.yml déclare chaque variable, son type et son défaut
  - molecule test vert sur un cluster k3s de test (rôle k3s de TASK-090 comme dépendance du scénario) ; idempotence : un second passage ne change rien
  - les manifestes appliqués sont des fichiers versionnés du rôle, jamais générés en ligne
  - ansible-lint et yamllint à 0 sur Ansible/roles/kubernetes/
validation:
  - "tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh kubernetes"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - valider-ansible.sh accepte le nom du rôle en argument depuis TASK-088
  - dépend de k3s (TASK-090) : le scénario Molecule a besoin d'un cluster pour appliquer les manifestes
  - même gabarit que securite_base (TASK-081)
---

# TASK-091 — Rôle `kubernetes`

Dernière des quatre tâches de rôle. Plan : `docs/plan-outil-preparation-serveurs.md` §5.
TASK-092 (recette `serveur-neuf.yml`) suit, une fois les quatre rôles terminés.
