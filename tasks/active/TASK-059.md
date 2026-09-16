---
id: TASK-059
title: "Écrire Kubernetes/Maintenance/resource-usage.sh"
status: in_progress
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Afficher en lecture seule CPU et mémoire des nœuds et des pods « lorsque les métriques
  le permettent » (plan §7) ; sans API metrics, [WARN] et capacité des nœuds, code 0.
scope:
  - Kubernetes/Maintenance/resource-usage.sh
  - tests/integration/resource-usage.test.sh
out_of_scope:
  - installation ou réparation de metrics-server — Kubernetes/Installation/install-metrics.sh
  - seuils d'alerte, historique, export Prometheus
  - toute écriture sur le cluster ; l'affichage du kubeconfig ou de Secrets ; « k3s kubectl »
acceptance_criteria:
  - API metrics disponible — kubectl top nodes puis kubectl top pods -A (ou -n avec --namespace)
  - API metrics absente — [WARN] qui le dit, puis capacité et allocatable des nœuds, et rend 0
  - kubectl absent ou apiserver injoignable → [ERROR] et 1 ; option inconnue ou --namespace sans valeur → 2
  - s'exécute sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml, kubectl résout seul KUBECONFIG puis ~/.kube/config
  - --help documente les deux modes et les codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/resource-usage.sh --help"
implementation_notes:
  - "faux kubectl en tête de PATH ; « top » rend 1 et « error: Metrics API not available » dans le cas sans métriques, comme le vrai"
  - chaque appel kubectl borné par --request-timeout
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - distinguer « metrics absente » de « apiserver injoignable » — tester l'apiserver d'abord, puis top
  - faux kubectl aux vrais formats de sortie et codes (kubectl top, describe nodes) ; « No resources found » sur stderr avec code 0 ; stderr tenu à part de la liste affichée
  - erreurs apiserver distinguées (NotFound, Forbidden, injoignable) ; une rubrique en échec interdit le [SUCCESS] final (A78)
  - timeout externe éventuel = délai + 2 s, avec require_cmd timeout ; aucun ok inconditionnel, chaque test échoue si le script est faux
---

# TASK-059 — Consommation des ressources

K3s embarque metrics-server par défaut ; un cluster managé pas toujours.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
