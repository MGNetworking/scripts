---
id: TASK-069
title: "Écrire Kubernetes/Configuration/configure-ingress.sh"
status: ready
priority: medium
depends_on:
  - TASK-062
  - TASK-064
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Poser deux Middlewares Traefik réutilisables (plan §6, décision 23) — redirection HTTPS
  et en-têtes de sécurité à HSTS court — par kubectl apply, sans suppression.
scope:
  - Kubernetes/Configuration/configure-ingress.sh
  - tests/integration/configure-ingress.test.sh
out_of_scope:
  - redirection globale ou HelmChartConfig (spécifique K3s) ; remplacer ou désactiver Traefik (décision 23)
  - créer ou modifier des Ingress ou IngressRoute applicatifs pour y activer les Middlewares ; certificats et ClusterIssuer (TASK-070)
  - supprimer un Middleware existant non géré par le script ; toute variable nouvelle dans config/
acceptance_criteria:
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - kubectl absent, API injoignable ou CRD Middleware de Traefik absente → 1 en nommant la cause
  - exactement deux Middlewares existent après exécution, label app.kubernetes.io/managed-by=mgnetworking
  - le premier redirige HTTP vers HTTPS de façon permanente ; le second pose HSTS (stsSeconds au plus 3600, sans preload ni includeSubDomains) et nosniff
  - --help montre l'annotation qu'un Ingress porte pour activer les deux Middlewares
  - seconde exécution → aucun changement annoncé (kubectl diff rend 0)
  - --dry-run affiche la différence et rend 0 ; sans terminal ni --yes, 1 si un changement est à faire
  - namespace cible (--namespace, défaut default) mal formé → 2, absent du cluster → 1, sans rien appliquer
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-ingress.sh --help"
implementation_notes:
  - groupe d'API détecté par « kubectl api-resources » — traefik.io (Traefik v3) ou traefik.containo.us (v2) selon la version livrée par K3s ; à vérifier
  - kubectl diff rend 0 sans différence, 1 avec différence, plus de 1 en erreur ; le faux kubectl reproduit ces codes
  - garde /.dockerenv avant tout trap ; confirmation testée sous pseudo-terminal ; --request-timeout sur chaque appel
---

# TASK-069 — Configurer l'ingress

HSTS court au départ : un `max-age` long, mal posé, rend un site injoignable en HTTP
pour la durée entière. Doute : un Ingress référençant un Middleware d'un autre namespace
peut exiger `allowCrossNamespace` côté Traefik — à vérifier.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
