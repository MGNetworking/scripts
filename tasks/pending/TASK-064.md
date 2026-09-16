---
id: TASK-064
title: "Écrire Kubernetes/Installation/install-ingress.sh"
status: ready
priority: medium
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Vérifier sans rien installer l'Ingress Controller Traefik fourni par K3s (décision 23,
  plan §5), et signaler un conflit sur les ports 80/443.
scope:
  - Kubernetes/Installation/install-ingress.sh
  - tests/integration/install-ingress.test.sh
out_of_scope:
  - installer, mettre à niveau ou reconfigurer Traefik (HelmChartConfig) — configuration dans Kubernetes/Configuration/
  - installer un second contrôleur (ingress-nginx ou autre), créer un Ingress
  - arrêter le processus en conflit ; ouvrir 80/443 dans ufw
acceptance_criteria:
  - lecture seule, sans root (aucun require_root) — rien créé ni modifié dans le cluster ni sur la machine
  - kubectl absent ou cluster injoignable — rend 1 en le nommant (appels bornés par --request-timeout)
  - IngressClass traefik absente, ou déploiement traefik de kube-system non Available — rend 1 en nommant ce qui manque, rien installé
  - version de l'image Traefik et IngressClass par défaut affichées
  - une autre IngressClass présente — [WARN] la nommant (une seule solution, plan §5)
  - un Service LoadBalancer autre que traefik exposant 80 ou 443, ou une écoute hôte sur 80/443 (ss -ltn) — [WARN] nommant le port et l'occupant
  - codes — 0 Traefik prêt, 1 absent ou anomalie, 2 option inconnue ; le conflit de port seul ne change pas le code
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-ingress.sh --help"
implementation_notes:
  - faux kubectl et faux ss en tête de PATH, sorties et codes réalistes ; aucun cluster réel
  - sans root, ss ne nomme pas le processus — afficher le port seul dans ce cas
  - dépend de TASK-062 pour l'ordre et le motif de contrôle de kubectl, pas pour un appel
---

# TASK-064 — Vérifier l'Ingress Controller

À vérifier sur un vrai K3s : noms `traefik` (IngressClass, déploiement, namespace
`kube-system`) ; K3s l'installe par un HelmChart et un job `helm-install-traefik`. Doute :
servicelb (klipper) publie 80/443 par hostPort, sans socket visible dans `ss`.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
