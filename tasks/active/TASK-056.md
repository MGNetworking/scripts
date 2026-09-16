---
id: TASK-056
title: "Écrire Kubernetes/Maintenance/pods-status.sh"
status: in_progress
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Afficher en lecture seule les pods de tous les namespaces, ou d'un seul désigné par
  --namespace (plan §7), par kubectl seul.
scope:
  - Kubernetes/Maintenance/pods-status.sh
  - tests/integration/pods-status.test.sh
out_of_scope:
  - redémarrage, suppression ou éviction de pod ; kubectl logs, exec, describe
  - verdict de santé par code de retour — diagnostics.sh (TASK-058)
  - --watch, filtres par label ou par statut, sortie JSON
  - l'affichage du kubeconfig ou de Secrets ; tout appel à « k3s kubectl »
acceptance_criteria:
  - sans option — pods de tous les namespaces (kubectl get pods -A -o wide)
  - --namespace <ns> — pods de ce seul namespace ; --namespace sans valeur rend 2
  - namespace inexistant → [ERROR] qui le nomme et rend 1 ; aucun pod dans un namespace existant → [INFO] et 0
  - kubectl absent ou apiserver injoignable → [ERROR] et 1, sans message brut « command not found »
  - un pod en échec ne change pas le code : liste affichée → 0 ; option inconnue → 2, seul autre cas de 2
  - --help documente options et codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/pods-status.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend la sortie et le vrai code ; il note ses arguments pour prouver -A ou -n <ns>
  - chaque appel kubectl borné par --request-timeout
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - existence du namespace vérifiée par kubectl get namespace <ns> avant la liste, kubectl ne signalant pas un namespace inconnu dans get pods
---

# TASK-056 — État des pods

Lecture seule. `kubectl get pods -n inconnu` rend 0 avec « No resources found » :
sans vérification préalable du namespace, une faute de frappe passerait pour un
namespace vide.
