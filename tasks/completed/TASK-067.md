---
id: TASK-067
title: "Écrire Kubernetes/Configuration/configure-namespaces.sh"
status: completed
priority: medium
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Créer les namespaces communs du cluster (plan §6) listés dans SRV_K8S_NAMESPACES de
  config/server.env, par kubectl apply, sans jamais en supprimer.
scope:
  - Kubernetes/Configuration/configure-namespaces.sh
  - tests/integration/configure-namespaces.test.sh
  - config/server.env.example — SRV_K8S_NAMESPACES, noms séparés par des virgules
out_of_scope:
  - supprimer, renommer ou relabelliser un namespace absent de la liste ou déjà présent
  - quotas, LimitRange, NetworkPolicy, RBAC, labels Pod Security Admission
  - contexte dédié config/kubernetes.env ou load_config ; installer kubectl (TASK-062) ; « k3s kubectl »
acceptance_criteria:
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - kubectl absent ou API injoignable → refus en 1 en nommant la cause ; chaque appel borné par --request-timeout
  - SRV_K8S_NAMESPACES absente ou vide → refus en 2 la nommant ; liste lue séparée par des virgules
  - un nom non conforme RFC 1123 (minuscules, chiffres, tiret, 63 au plus) → 2 sans rien'appliquer
  - les namespaces système (default, kube-*) sont refusés dans la liste, en 2
  - un namespace déjà présent n'est pas modifié ; une seconde exécution n'annonce aucun changement
  - --dry-run affiche les namespaces à créer et rend 0 sans appel en écriture
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-namespaces.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, aux codes du vrai (get d'un objet absent 1, NotFound sur stderr)
  - le test refuse de tourner hors conteneur (/.dockerenv) avant tout trap ou écriture ; --help sans cluster
  - manifeste envoyé à « kubectl apply -f - » par l'entrée standard ; non destructif, ASSUME_YES hérité admis (décision 45)
  - nom de namespace = label DNS-1123 — minuscules, chiffres, « - », 1 à 63 caractères, commence et finit par un alphanumérique ; liste mal formée (virgule finale, doublon, espaces, entrée vide, nom invalide, « -a », « kube-x ») → 2 avant tout appel kubectl
  - « kubectl create namespace X » échoue en « AlreadyExists » si X existe — lire l'existant (get) puis n'appliquer que les absents ; rien réappliqué à la seconde exécution
  - réservés, jamais créés ni touchés — kube-system, kube-public, kube-node-lease, default, et tout préfixe kube- (réservé par Kubernetes) → refus en 2
  - --request-timeout sur chaque appel, enveloppé par timeout (délai + 2, require_cmd timeout, 124 nommé) ; stderr de kubectl tenu à part et cité dans le message d'échec
  - échec partiel — pas de [SUCCESS], bilan créés / échoués / non tentés et code non nul (A78)
---

# TASK-067 — Configurer les namespaces

Premier script du domaine : `SRV_K8S_NAMESPACES` sert aussi à TASK-071 (registry).
`config/server.env` est chargé seul par `lib/common.sh` : pas de `--config`.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
