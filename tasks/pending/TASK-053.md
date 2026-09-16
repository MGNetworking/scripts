---
id: TASK-053
title: "Écrire Linux/K3s/upgrade-k3s.sh"
status: ready
priority: medium
depends_on:
  - TASK-050
  - TASK-051
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Mettre K3s à niveau par l'installateur officiel (plan §4) : afficher versions actuelle
  et cible, exiger un cluster sain, confirmer, mettre à niveau, puis vérifier nœuds et
  pods par verify-k3s.sh.
scope:
  - Linux/K3s/upgrade-k3s.sh
  - tests/integration/upgrade-k3s.test.sh
out_of_scope:
  - system-upgrade-controller, retour arrière automatique vers l'ancienne version
  - toute modification de config.yaml, de Traefik ou des workloads
  - mise à niveau des paquets du système
acceptance_criteria:
  - root requis (1) ; K3s absent → refus en 1 en renvoyant vers install-k3s.sh
  - versions actuelle et cible affichées ; identiques → rend 0 sans rien télécharger
  - cible inférieure à l'actuelle, ou sautant plus d'une version mineure, refusée en 1
  - verify-k3s.sh en échec avant la mise à niveau → refus en 1 sans rien modifier
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche versions et commande prévue, sans téléchargement, rend 0
  - installateur téléchargé comme dans install-k3s.sh ; verify-k3s.sh après ; échec → 1, en affichant la version en place
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/K3s/upgrade-k3s.sh --help"
implementation_notes:
  - faux curl, k3s et systemctl en tête de PATH ; aucun téléchargement réel
  - reprendre le mécanisme de téléchargement d'install-k3s.sh une fois écrit, sans le dupliquer davantage que nécessaire
---

# TASK-053 — Mettre K3s à niveau

Kubernetes ne supporte qu'une version mineure à la fois (politique d'écart de
versions) ; K3s s'y conforme. Le jeton de nœud ne s'affiche jamais.


**Décidé par `user` le 2026-09-16** : voir `orchestration/decisions.md`, décision 47.
