---
id: TASK-065
title: "Écrire Kubernetes/Installation/install-cert-manager.sh"
status: pending
priority: high
depends_on:
  - TASK-062
  - TASK-063
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Installer cert-manager (décision 23, plan §5) par le chart Helm officiel jetstack, à une
  version obligatoire, CRD comprises, puis attendre ses déploiements et relire ses CRD.
scope:
  - Kubernetes/Installation/install-cert-manager.sh
  - tests/integration/install-cert-manager.test.sh
  - config/server.env.example — SRV_CERT_MANAGER_VERSION
out_of_scope:
  - ClusterIssuer, Let's Encrypt, domaine, Certificate — c'est configure-tls.sh (Kubernetes/Configuration)
  - mettre à niveau ou désinstaller un cert-manager présent ; supprimer des CRD ; CRD posées par kubectl apply
  - installer Helm ou kubectl ; installer cmctl ; lire /etc/rancher/k3s/k3s.yaml
acceptance_criteria:
  - aucun require_root ; helm et kubectl trouvent seuls KUBECONFIG ou ~/.kube/config ; aucune référence à k3s.yaml
  - helm ou kubectl absent, cluster injoignable — rend 1 en le nommant, renvoi vers TASK-063 / TASK-062
  - version cible obligatoire (--version prioritaire, sinon SRV_CERT_MANAGER_VERSION, forme vX.Y.Z) ; absente ou invalide — 1
  - release cert-manager présente — version affichée, rien modifié, 0 ; CRD cert-manager.io sans release Helm — refus en 1, rien modifié
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche version et commande helm prévues, sans rien installer, rend 0
  - chart jetstack/cert-manager depuis https://charts.jetstack.io, version épinglée, CRD installées par le chart, namespace cert-manager créé
  - déploiements cert-manager, cainjector et webhook attendus Available avec délai borné ; dépassement — 1 en nommant les non prêts, rien désinstallé
  - CRD certificates, issuers et clusterissuers relues après installation ; manquante — 1 ; codes 0 / 1 / 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-cert-manager.sh --help"
implementation_notes:
  - faux helm et kubectl en tête de PATH, aux vrais codes ; aucun dépôt ni cluster réel
  - KUBECONFIG hérité respecté tel quel, jamais fixé par le script
---

# TASK-065 — Installer cert-manager

Doutes : `crds.enabled=true` remplace `installCRDs` depuis cert-manager 1.15 (à vérifier
sur la version épinglée) ; noms exacts des trois déploiements à confirmer.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
