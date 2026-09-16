---
id: TASK-070
title: "Écrire Kubernetes/Configuration/configure-tls.sh"
status: pending
priority: medium
depends_on:
  - TASK-062
  - TASK-065
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Créer les ClusterIssuers letsencrypt-staging et letsencrypt-production (plan §6,
  décision 23), HTTP-01, e-mail SRV_K8S_ACME_EMAIL, par kubectl apply, sans demander de certificat.
scope:
  - Kubernetes/Configuration/configure-tls.sh
  - tests/integration/configure-tls.test.sh
  - config/server.env.example — SRV_K8S_ACME_EMAIL
out_of_scope:
  - créer un Certificate, pour quelque domaine que ce soit ; variable de domaine
  - installer cert-manager (TASK-065) ; Middlewares Traefik (TASK-069)
  - solveur DNS-01 et certificats wildcard ; lire, exporter ou afficher les Secrets de clé ACME ; supprimer un issuer
acceptance_criteria:
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - kubectl absent, API injoignable, CRD ClusterIssuer absente ou webhook cert-manager non prêt → 1 en nommant la cause
  - SRV_K8S_ACME_EMAIL absente → 2 la nommant ; e-mail mal formé → 2 sans rien appliquer
  - letsencrypt-staging et letsencrypt-production existent après exécution, solveur HTTP-01 classe d'ingress traefik, et atteignent Ready dans le délai borné, sinon 1
  - aucun objet Certificate ni CertificateRequest créé par le script
  - seconde exécution → aucun changement (kubectl diff rend 0)
  - --dry-run affiche la différence et rend 0 ; sans terminal ni --yes, 1 si un changement est à faire
  - aucune clé privée ni contenu de Secret n'apparaît dans la sortie ni dans le journal
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-tls.sh --help"
implementation_notes:
  - kubectl wait --for=condition=Ready clusterissuer/<nom> --timeout ; le faux kubectl rend les codes du vrai (wait expiré 1)
  - garde /.dockerenv avant tout trap ; --request-timeout sur chaque appel ; confirmation sous pseudo-terminal
  - le Secret de clé du compte ACME est créé par cert-manager dans son namespace, jamais par le script
---

# TASK-070 — Configurer TLS

Un ClusterIssuer HTTP-01 n'a pas besoin du domaine ; le staging évite les limites de
débit de production. Chaque site demande son certificat dans son propre Ingress.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
