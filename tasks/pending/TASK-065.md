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
  Installer cert-manager (décision 23, plan §5) dans le namespace cert-manager, attendre
  ses déploiements et vérifier ses CRD. Rédigé pour l'option recommandée ci-dessous.
scope:
  - Kubernetes/Installation/install-cert-manager.sh
  - tests/integration/install-cert-manager.test.sh
  - config/server.env.example — SRV_CERT_MANAGER_VERSION
out_of_scope:
  - ClusterIssuer, Let's Encrypt, domaine, Certificate — c'est configure-tls.sh (Kubernetes/Configuration)
  - mettre à niveau ou désinstaller un cert-manager présent ; supprimer des CRD
  - installer Helm ou kubectl ; installer cmctl
acceptance_criteria:
  - helm ou kubectl absent, cluster injoignable — rend 1 en le nommant, renvoi vers TASK-063 / TASK-062
  - version cible obligatoire (--version ou SRV_CERT_MANAGER_VERSION, forme vX.Y.Z) ; absente ou invalide — 1
  - release cert-manager présente — version affichée, rien modifié, 0 ; CRD cert-manager.io sans release Helm — refus en 1, rien modifié
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche version et commande helm prévues, sans rien installer, rend 0
  - chart jetstack/cert-manager depuis https://charts.jetstack.io, version épinglée, CRD incluses (crds.enabled=true), namespace cert-manager créé
  - déploiements cert-manager, cert-manager-cainjector et cert-manager-webhook attendus Available avec délai borné ; dépassement — 1 en nommant les non prêts, rien désinstallé
  - CRD certificates, issuers et clusterissuers relues après installation ; manquante — 1 ; codes 0 / 1 / 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-cert-manager.sh --help"
implementation_notes:
  - faux helm et kubectl en tête de PATH, aux vrais codes ; aucun dépôt ni cluster réel
  - Helm ignore le kubeconfig de K3s : KUBECONFIG hérité respecté, sinon /etc/rancher/k3s/k3s.yaml s'il existe (0600, root en pratique)
---

# TASK-065 — Installer cert-manager

Doutes : `crds.enabled` remplace `installCRDs` depuis cert-manager 1.15 (à vérifier) ;
noms des trois déploiements à confirmer sur la version épinglée.

**Décision attendue de user** : quel mécanisme et quelle version ?
1. **(recommandé)** chart Helm officiel jetstack, version épinglée obligatoire, HTTPS seul sans vérification de provenance (`--verify`) ;
2. chart Helm, dernière version si non épinglée ;
3. manifeste officiel `cert-manager.yaml` des releases GitHub par kubectl apply — TASK-063 ne serait plus une dépendance.
