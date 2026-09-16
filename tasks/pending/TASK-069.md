---
id: TASK-069
title: "Écrire Kubernetes/Configuration/configure-ingress.sh"
status: pending
priority: medium
depends_on:
  - TASK-062
  - TASK-064
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Poser les règles HTTP/HTTPS communes de Traefik (plan §6, décision 23) sous forme de
  Middlewares réutilisables, appliqués par kubectl apply, sans suppression.
scope:
  - Kubernetes/Configuration/configure-ingress.sh
  - tests/integration/configure-ingress.test.sh
  - config/server.env.example — namespace des Middlewares, si la décision ci-dessous en retient un
out_of_scope:
  - remplacer ou désactiver Traefik (décision 23) ; HelmChartConfig et manifests K3s (spécifiques K3s)
  - créer des Ingress ou IngressRoute applicatifs ; certificats et ClusterIssuer (TASK-070)
  - supprimer un Middleware existant non géré par le script
acceptance_criteria:
  - kubectl absent, API injoignable ou CRD Middleware de Traefik absente → 1 en nommant la cause
  - les Middlewares retenus par la décision existent après exécution, portant le label app.kubernetes.io/managed-by=mgnetworking
  - seconde exécution → aucun changement annoncé (kubectl diff rend 0)
  - --dry-run affiche la différence et rend 0 ; sans terminal ni --yes, 1 si un changement est à faire
  - un namespace cible mal formé ou absent du cluster → 2 ou 1, sans rien appliquer
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-ingress.sh --help"
implementation_notes:
  - groupe d'API détecté par « kubectl api-resources » — traefik.io (Traefik v3) ou traefik.containo.us (v2) selon la version livrée par K3s ; à vérifier
  - kubectl diff rend 0 sans différence, 1 avec différence, plus de 1 en erreur ; le faux kubectl doit reproduire ces codes
  - garde /.dockerenv avant tout trap ; confirmation testée sous pseudo-terminal ; --request-timeout sur chaque appel
---

# TASK-069 — Configurer l'ingress

« Règles HTTP/HTTPS communes » n'est pas défini par le plan. Une redirection HTTPS
globale se pose dans la configuration statique de Traefik (HelmChartConfig, propre à
K3s) : hors de ce domaine par la frontière du plan §5.

**Décision attendue de user : quelles règles ?**
(a) recommandé — deux Middlewares dans un namespace de config/ : redirection HTTP→HTTPS
permanente et en-têtes de sécurité (HSTS, nosniff), à référencer par annotation dans chaque Ingress ;
(b) redirection HTTPS seule ;
(c) redirection globale via HelmChartConfig, le script passant alors dans `Linux/K3s/`.
