---
id: TASK-067
title: "Écrire Kubernetes/Configuration/configure-namespaces.sh"
status: pending
priority: medium
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Créer les namespaces communs du cluster (plan §6) à partir d'une liste lue dans config/,
  par kubectl apply, sans jamais en supprimer.
scope:
  - Kubernetes/Configuration/configure-namespaces.sh
  - tests/integration/configure-namespaces.test.sh
  - config/server.env.example — variable de liste retenue par la décision ci-dessous
out_of_scope:
  - supprimer, renommer ou relabelliser un namespace absent de la liste ou déjà présent
  - quotas, LimitRange, NetworkPolicy, RBAC, labels Pod Security Admission
  - installer kubectl (TASK-062), passer par « k3s kubectl » (frontière plan §5)
acceptance_criteria:
  - kubectl absent ou API injoignable → refus en 1 en nommant la cause ; chaque appel borné par --request-timeout
  - liste absente ou vide → refus en 2 nommant la variable ; un nom non conforme RFC 1123 (minuscules, chiffres, tiret, 63 au plus) → 2 sans rien appliquer
  - un namespace déjà présent n'est pas modifié ; une seconde exécution n'annonce aucun changement
  - --dry-run affiche les namespaces à créer et rend 0 sans appel en écriture
  - les namespaces système (default, kube-*) sont refusés dans la liste, en 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-namespaces.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, aux codes du vrai (get d'un objet absent 1, NotFound sur stderr)
  - le test refuse de tourner hors conteneur (/.dockerenv) avant tout trap ou écriture ; --help sans cluster
  - manifeste envoyé à « kubectl apply -f - » par l'entrée standard ; non destructif, ASSUME_YES hérité admis (décision 45)
---

# TASK-067 — Configurer les namespaces

Premier script du domaine : la liste qu'il fixe sert à TASK-071 (registry).

**Décision attendue de user : où vit la liste des namespaces ?**
(a) recommandé — `SRV_K8S_NAMESPACES` dans `config/server.env`, noms séparés par des
espaces, comme les `SRV_K3S_*` (décisions 17 et 47) ;
(b) un contexte dédié `config/kubernetes.env` chargé par `load_config kubernetes`.
Le choix vaut pour tout le domaine : à trancher avec les lots Installation et Maintenance.
