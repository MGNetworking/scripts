---
id: TASK-059
title: "Écrire Kubernetes/Maintenance/resource-usage.sh"
status: pending
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Afficher en lecture seule CPU et mémoire des nœuds et des pods « lorsque les métriques
  le permettent » (plan §7), et un repli défini quand l'API metrics est absente.
scope:
  - Kubernetes/Maintenance/resource-usage.sh
  - tests/integration/resource-usage.test.sh
out_of_scope:
  - installation ou réparation de metrics-server — Kubernetes/Installation/install-metrics.sh
  - seuils d'alerte, historique, export Prometheus
  - toute écriture sur le cluster ; l'affichage du kubeconfig ou de Secrets ; « k3s kubectl »
acceptance_criteria:
  - API metrics disponible — kubectl top nodes puis kubectl top pods -A (ou -n avec --namespace)
  - API metrics absente — [WARN] qui le dit, puis capacité et allocatable des nœuds ; code selon la décision ci-dessous
  - kubectl absent ou apiserver injoignable → [ERROR] et 1 ; option inconnue ou --namespace sans valeur → 2
  - --help documente les deux modes et les codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/resource-usage.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH ; « top » rend 1 et « error: Metrics API not available » dans le cas sans métriques, comme le vrai
  - chaque appel kubectl borné par --request-timeout
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - distinguer « metrics absente » de « apiserver injoignable » : tester l'apiserver d'abord, puis top
---

# TASK-059 — Consommation des ressources

K3s embarque metrics-server par défaut ; un cluster managé pas toujours.

**Décision attendue de user** : sans API metrics, le script rend-il
(a) **0 avec [WARN] et le repli capacité/allocatable** — recommandé, conforme au
« lorsque les métriques le permettent » du plan ; ou (b) 1 après le repli ?
