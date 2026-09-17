---
id: TASK-069
title: "Écrire Kubernetes/Configuration/configure-ingress.sh"
status: completed
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
  - redirect-https redirige HTTP vers HTTPS de façon permanente ; security-headers pose stsSeconds au plus 3600, stsIncludeSubdomains false, stsPreload false, contentTypeNosniff, frameDeny et browserXssFilter true, referrerPolicy strict-origin-when-cross-origin
  - --help montre l'annotation qu'un Ingress porte pour activer les deux Middlewares
  - seconde exécution → aucun changement annoncé (kubectl diff rend 0)
  - --dry-run affiche la différence et rend 0 ; sans terminal ni --yes, 1 si un changement est à faire
  - namespace cible (--namespace, défaut default) mal formé → 2, absent du cluster → 1, sans rien appliquer
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-ingress.sh --help"
implementation_notes:
  - "faits VÉRIFIÉS par la session sur la documentation officielle de Traefik : apiVersion traefik.io/v1alpha1, kind Middleware (groupe traefik.io, seul groupe visé ; pas de traefik.containo.us) ; redirection spec.redirectScheme.scheme https et spec.redirectScheme.permanent true (défaut false) ; en-têtes spec.headers avec stsSeconds, stsIncludeSubdomains, stsPreload, frameDeny, customFrameOptionsValue, contentTypeNosniff, browserXssFilter, referrerPolicy ; activation dans un Ingress par l'annotation traefik.ingress.kubernetes.io/router.middlewares: <namespace>-<nom>@kubernetescrd, plusieurs séparés par des virgules"
  - "NON VÉRIFIÉ : allowCrossNamespace (provider kubernetesCRD, défaut false) est documenté pour les IngressRoutes ; rien ne dit si une annotation d'Ingress peut viser un Middleware d'un autre namespace ni ce que K3s pose. Le script ne l'affirme pas ; le --help le signale et propose, si la référence est refusée, de créer les Middlewares dans le namespace du site (--namespace)"
  - "noms fixes redirect-https et security-headers ; stsSeconds 3600 (HSTS court, décision 48) ; manifeste généré par heredoc et passé sur stdin (kubectl diff -f - puis apply -f -)"
  - "CRD absente (Traefik non installé) : kubectl get crd middlewares.traefik.io → NotFound nommé, 1 ; namespace lu par kubectl get namespace, NotFound → 1 ; validé DNS-1123 (minuscules, chiffres, « - », pas de « - » en tête ni en fin, 63 caractères) avant tout appel → 2"
  - "idempotence : kubectl diff rend 0 sans différence (rien appliqué, aucun changement annoncé), 1 avec différence, plus de 1 en erreur ; --dry-run affiche le diff et n'appelle jamais apply ; aucune suppression (ni delete ni --prune)"
  - "garde /.dockerenv avant tout trap ou écriture ; require_cmd kubectl et timeout ; timeout externe = délai + 2, code 124 nommé ; --request-timeout sur chaque appel kubectl, prouvé par le journal du faux ; stderr tenu à part ; NotFound, Forbidden, injoignable, kubeconfig invalide et ressource inconnue de l'API (the server doesn't have a resource type) distingués"
  - "confirmation par confirm (ASSUME_YES, décision 45) testée sous pseudo-terminal (script -qec, comme install-cert-manager.test.sh) ; sans terminal ni --yes et changement à faire → 1"
  - "faux kubectl en tête de PATH aux vrais formats, codes et messages ; il vérifie le manifeste reçu sur stdin (apiVersion, kind, label, champs ci-dessus) ; aucun cluster réel. Des tests qui ne prouveraient que le faux lui-même sont refusés"
  - "modèles voisins : Kubernetes/Installation/install-ingress.sh (erreurs kubectl distinguées, timeout), Kubernetes/Installation/install-cert-manager.sh (écriture confirmée, --dry-run)"
---

# TASK-069 — Configurer l'ingress

HSTS court au départ : un `max-age` long, mal posé, rend un site injoignable en HTTP
pour la durée entière. Doute non levé par la documentation : un Ingress référençant un Middleware d'un autre namespace
peut exiger `allowCrossNamespace` côté Traefik — voir les notes.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
