---
id: TASK-066
title: "Écrire Kubernetes/Installation/install-metrics.sh"
status: completed
priority: low
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Vérifier sans rien installer la solution de métriques, metrics-server fourni par K3s
  (plan §5).
scope:
  - Kubernetes/Installation/install-metrics.sh
  - tests/integration/install-metrics.test.sh
out_of_scope:
  - installer ou reconfigurer metrics-server, Prometheus ou tout autre outil de supervision
  - afficher la consommation par pod — c'est Kubernetes/Maintenance/resource-usage.sh
acceptance_criteria:
  - lecture seule, sans root (aucun require_root) — rien créé ni modifié dans le cluster ni sur la machine
  - aucune référence à /etc/rancher/k3s/k3s.yaml ; kubectl résout seul son kubeconfig
  - kubectl absent ou cluster injoignable — rend 1 en le nommant (appels bornés par --request-timeout)
  - déploiement metrics-server de kube-system non Available — rend 1, rien installé
  - APIService v1beta1.metrics.k8s.io non Available — rend 1 en affichant sa raison
  - kubectl top nodes répond — sinon 1 ; métriques vides juste après démarrage signalées en [WARN] si le délai est dépassé
  - codes — 0 métriques disponibles, 1 absent ou anomalie, 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-metrics.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, sorties et codes réalistes ; aucun cluster réel
  - aucune boucle d'attente longue — une relecture bornée au plus
  - "connaissance de l'orchestrateur, non vérifiée sur source (ne rien inventer au-delà) — sur K3s, metrics-server est le déploiement metrics-server du namespace kube-system, enregistré comme APIService v1beta1.metrics.k8s.io ; juste après un démarrage, l'API peut répondre « ServiceUnavailable » environ une minute : le script le nomme comme cause probable, sans attendre"
  - "messages réels déjà reconnus par Kubernetes/Maintenance/resource-usage.sh (modèle) — « Metrics API not available » (API absente) et « ServiceUnavailable » (metrics.k8s.io installée mais indisponible) ; modèle voisin de vérification seule — Kubernetes/Installation/install-ingress.sh"
  - "formats kubectl à imiter dans les faux — « Error from server (NotFound): … not found » et « Error from server (Forbidden): … » code 1 ; « The connection to the server … was refused - did you specify the right host or port? » ou « Unable to connect to the server: … » code 1 ; « error: error loading config file … » code 1 ; « error: the server doesn't have a resource type … » code 1"
  - garde /.dockerenv avant tout trap ou écriture ; require_cmd kubectl timeout ; tout appel kubectl porte --request-timeout et tourne sous timeout, 124 nommé comme dépassement ; stderr capturé à part de stdout
  - distinguer NotFound, Forbidden, API injoignable, kubeconfig invalide et ressource inconnue de l'API (messages distincts)
  - chaque rubrique en échec interdit le [SUCCESS] final (A78) ; aucune écriture sur le cluster — le faux kubectl trace ses arguments et le test prouve l'absence de tout apply, patch, delete, create, scale, edit, label, annotate
  - "faux binaires : fichiers ordinaires créés dans le bac, jamais écrits à travers un lien symbolique (tests/README.md, TASK-072) ; faux kubectl qui ne rend sa donnée que si l'expression -o attendue est reçue ; faux timeout déterministe, sans attente réelle, capable de rendre 124 ; aucun test qui ne prouve que le faux"
  - "tests non creux : une mutation du script dans une copie jetable (retirer une vérification, inverser un code) fait échouer la suite ; suite lancée 3 fois de suite, stable ; chaque exécution de test sous timeout"
---

# TASK-066 — Vérifier metrics-server

K3s déploie metrics-server par défaut (Linux/K3s/README.md), sauf `--disable
metrics-server`, que configure-k3s.sh ne pose pas (décision 47).

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
