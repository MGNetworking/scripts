---
id: TASK-061
title: "Écrire Kubernetes/Maintenance/cleanup-resources.sh"
status: completed
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Supprimer uniquement les objets Kubernetes nommés un à un en argument (plan §7), après
  affichage de la liste exacte et confirmation, avec --dry-run.
scope:
  - Kubernetes/Maintenance/cleanup-resources.sh
  - tests/integration/cleanup-resources.test.sh
out_of_scope:
  - toute recherche de candidats par le script (pods Failed, Jobs terminés, ReplicaSets à 0)
  - toute suppression par label, par motif, --all ou d'un namespace entier
  - namespaces kube-system, kube-public, kube-node-lease ; nœuds, CRD, PV, Secrets
  - sauvegarde préalable — backup-resources.sh (TASK-060) ; tout appel à docker ou « k3s kubectl »
acceptance_criteria:
  - cibles désignées seulement par « -n <ns> <kind>/<nom> », une par objet ; aucune autre forme acceptée (2)
  - la liste de ce qui sera supprimé (namespace, kind, nom) est affichée avant toute suppression
  - une cible inexistante ou dans un namespace protégé → refus en 1, rien supprimé
  - ASSUME_YES remise à false avant les options (décision 45) ; seul --yes confirme ; sans terminal ni --yes, 1
  - --dry-run affiche la liste et rend 0 sans appeler kubectl delete
  - après suppression, chaque cible est relue absente, sinon 1 en nommant ce qui reste
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - kubectl absent ou apiserver injoignable → [ERROR] et 1 ; option inconnue ou aucune cible → 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/cleanup-resources.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend les vrais codes (get d'un objet absent → 1 « NotFound ») et note chaque delete
  - chaque appel kubectl borné par --request-timeout ; delete sans --force ni --grace-period=0
  - test — garde /.dockerenv avant tout trap ou écriture ; KUBECONFIG pointé vers un fichier vide
  - ASSUME_YES=true exportée sans --yes — refus prouvé sous pseudo-terminal (script -qec)
---

# TASK-061 — Nettoyer des ressources

**Destructif.** Le script ne choisit rien : il supprime ce qu'on lui nomme, et seulement cela.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
