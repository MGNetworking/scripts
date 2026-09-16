---
id: TASK-058
title: "Écrire Kubernetes/Maintenance/diagnostics.sh"
status: completed
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Rechercher en lecture seule les anomalies d'un cluster (plan §7) — nœuds NotReady, pods
  Pending ou CrashLoopBackOff ou en erreur, workloads indisponibles, événements Warning —
  avec un code de retour qui porte le verdict.
scope:
  - Kubernetes/Maintenance/diagnostics.sh
  - tests/integration/diagnostics.test.sh
out_of_scope:
  - toute correction — redémarrage, suppression de pod, rollout restart, cordon ou drain
  - kubectl logs, describe, ou affichage de manifests (-o yaml/json) : env et annotations peuvent porter des valeurs sensibles
  - l'affichage du kubeconfig ou de Secrets ; tout appel à « k3s kubectl » ou à systemctl
  - notification ntfy/webhook des anomalies (décision 15 vise les tâches planifiées)
acceptance_criteria:
  - chaque nœud non Ready est signalé par un [WARN] qui le nomme
  - chaque pod Pending, CrashLoopBackOff, Failed, en Error ou ImagePullBackOff est signalé par [WARN] namespace/nom et raison
  - chaque Deployment, StatefulSet ou DaemonSet dont les répliques prêtes sont inférieures aux désirées est signalé par [WARN]
  - les événements Warning sont affichés mais ne changent pas le code de retour
  - au moins une anomalie → 1 ; aucune → [SUCCESS] et 0 ; les pods Succeeded (Jobs terminés) ne sont pas des anomalies
  - kubectl absent ou apiserver injoignable → [ERROR] et 1 ; option inconnue → 2, seul cas de 2
  - --help documente les anomalies recherchées et les codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/diagnostics.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend la sortie et le vrai code ; chaque cas d'anomalie a sa garde de contraste (cluster sain → 0)
  - chaque appel kubectl borné par --request-timeout
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - CrashLoopBackOff n'est pas une phase mais une raison d'attente de conteneur — la lire dans la colonne STATUS ou via -o custom-columns, pas dans .status.phase
  - modèle : Docker/Diagnostics/check-docker.sh (verdict par code, rubriques)
---

# TASK-058 — Diagnostiquer le cluster

Pendant générique de `verify-k3s.sh` (TASK-050), sans rien de K3s : pas de service,
pas de `k3s kubectl`. Même piège qu'en TASK-050 : les Warning anciens d'un cluster
sain s'affichent sans faire échouer.
