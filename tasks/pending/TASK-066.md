---
id: TASK-066
title: "Écrire Kubernetes/Installation/install-metrics.sh"
status: pending
priority: low
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Vérifier la solution de métriques, metrics-server fourni par K3s (plan §5).
  Rédigé pour l'option recommandée ci-dessous — vérification seule.
scope:
  - Kubernetes/Installation/install-metrics.sh
  - tests/integration/install-metrics.test.sh
out_of_scope:
  - installer ou reconfigurer metrics-server, Prometheus ou tout autre outil de supervision
  - afficher la consommation par pod — c'est Kubernetes/Maintenance/resource-usage.sh
acceptance_criteria:
  - lecture seule — rien créé ni modifié dans le cluster ni sur la machine
  - kubectl absent ou cluster injoignable — rend 1 en le nommant (appels bornés par --request-timeout)
  - déploiement metrics-server de kube-system non Available — rend 1, rien installé
  - APIService v1beta1.metrics.k8s.io non Available — rend 1 en affichant sa raison
  - kubectl top nodes répond — sinon 1 ; métriques vides juste après démarrage signalées en [WARN] si le délai est dépassé
  - codes : 0 métriques disponibles, 1 absent ou anomalie, 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-metrics.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, sorties et codes réalistes ; aucun cluster réel
  - aucune boucle d'attente longue : une relecture bornée au plus
---

# TASK-066 — Vérifier metrics-server

K3s déploie metrics-server par défaut (Linux/K3s/README.md), sauf `--disable
metrics-server`, que configure-k3s.sh ne pose pas (décision 47).

**Décision attendue de user** : metrics-server étant fourni par K3s, quel objet pour ce script ?
1. **(recommandé)** vérification seule — fiche rédigée ainsi ;
2. installer metrics-server par son manifeste ou chart officiel s'il manque — `human_approval_required` passe à `true` ;
3. annuler la tâche.
