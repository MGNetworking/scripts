---
id: TASK-055
title: "Écrire Kubernetes/Maintenance/cluster-status.sh"
status: in_progress
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Afficher en lecture seule l'état d'un cluster Kubernetes quelconque (plan §7) — nœuds,
  versions, namespaces, pods, deployments, services — par kubectl seul, sans lien avec K3s.
scope:
  - Kubernetes/Maintenance/cluster-status.sh
  - tests/integration/cluster-status.test.sh
out_of_scope:
  - toute écriture sur le cluster (apply, delete, patch, scale, rollout, cordon)
  - verdict de santé par code de retour et recherche d'anomalies — diagnostics.sh (TASK-058)
  - l'affichage du kubeconfig, de Secrets ou de manifests complets (-o yaml/json)
  - tout appel à « k3s kubectl » ou à systemctl ; toute modification de Linux/K3s/verify-k3s.sh
acceptance_criteria:
  - rubriques affichées dans l'ordre du plan — nœuds (-o wide), versions client/serveur, namespaces, pods -A, deployments -A, services -A
  - kubectl absent → [ERROR] qui le dit et rend 1, sans message brut « command not found »
  - apiserver injoignable (kubectl rend non nul) → [ERROR] et 1, sans enchaîner les autres rubriques
  - cluster joignable → 0, quel que soit l'état des pods ; une option inconnue rend 2, seul cas de 2
  - root non requis : le kubeconfig est celui que kubectl résout lui-même (KUBECONFIG, ~/.kube/config)
  - --help documente rubriques, résolution du kubeconfig et codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/cluster-status.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend la sortie et le vrai code (1 si serveur injoignable) ; aucun vrai cluster en test
  - chaque appel kubectl borné par --request-timeout, pour qu'un apiserver muet ne fige pas le script
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - modèle direct : Linux/K3s/verify-k3s.sh et son test, en remplaçant « k3s kubectl » par kubectl
---

# TASK-055 — État du cluster

Ouvre `Kubernetes/Maintenance/` (décision 16 : lecture seule d'abord). Frontière
CLAUDE.md : ce script doit survivre au remplacement de K3s par un cluster managé,
donc `kubectl` seul, jamais `k3s kubectl` ni `/etc/rancher/k3s/k3s.yaml` en dur.

Aucune dépendance à install-kubectl.sh : le test fournit un faux kubectl.
