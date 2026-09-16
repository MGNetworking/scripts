---
id: TASK-064
title: "Écrire Kubernetes/Installation/install-ingress.sh"
status: pending
priority: medium
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Vérifier l'Ingress Controller retenu, Traefik fourni par K3s (décision 23, plan §5).
  Rédigé pour l'option recommandée ci-dessous — vérification seule.
scope:
  - Kubernetes/Installation/install-ingress.sh
  - tests/integration/install-ingress.test.sh
out_of_scope:
  - installer, mettre à niveau ou reconfigurer Traefik (HelmChartConfig) — configuration : Kubernetes/Configuration/
  - installer un second contrôleur (ingress-nginx ou autre), créer un Ingress
  - ouvrir 80/443 dans ufw
acceptance_criteria:
  - lecture seule — rien créé ni modifié dans le cluster ni sur la machine
  - kubectl absent ou cluster injoignable — rend 1 en le nommant (appels bornés par --request-timeout)
  - IngressClass traefik absente, ou déploiement traefik de kube-system non Available — rend 1 en nommant ce qui manque, rien installé
  - version de l'image Traefik et IngressClass par défaut affichées
  - une autre IngressClass présente — [WARN] la nommant (une seule solution, plan §5)
  - codes : 0 Traefik prêt, 1 absent ou anomalie, 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-ingress.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, sorties et codes réalistes ; aucun cluster réel
  - dépend de TASK-062 pour l'ordre et le motif de contrôle de kubectl, pas pour un appel
---

# TASK-064 — Vérifier l'Ingress Controller

À vérifier sur un vrai K3s : noms `traefik` (IngressClass, déploiement, namespace
`kube-system`) ; K3s l'installe par un HelmChart et un job `helm-install-traefik`.

**Décision attendue de user** : Traefik étant fourni par K3s, quel objet pour ce script ?
1. **(recommandé)** vérification seule de Traefik — fiche rédigée ainsi ;
2. installer Traefik par son chart officiel s'il manque (cluster managé) — `human_approval_required` passe à `true`, dépend de TASK-063 ;
3. annuler la tâche.
