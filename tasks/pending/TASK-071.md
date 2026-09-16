---
id: TASK-071
title: "Écrire Kubernetes/Configuration/configure-registry.sh"
status: pending
priority: medium
depends_on:
  - TASK-062
  - TASK-067
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Créer ou mettre à jour un Secret docker-registry dans chaque namespace de
  SRV_K8S_NAMESPACES (plan §6), identifiants lus dans config/registry.env (0600), jamais
  versionnés, affichés, journalisés ni passés en argument.
scope:
  - Kubernetes/Configuration/configure-registry.sh
  - tests/integration/configure-registry.test.sh
  - config/registry.env.example — adresse, identifiant, jeton, valeurs neutres
out_of_scope:
  - lier le Secret aux ServiceAccounts (imagePullSecrets), déployer ou redémarrer un workload
  - registries.yaml de K3s (spécifique K3s) ; docker login sur l'hôte ; plusieurs registries
  - jeton lu dans l'environnement du shell ; option --namespace ; supprimer un Secret ; créer un namespace (TASK-067)
acceptance_criteria:
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - config/registry.env absent ou de droits autres que 0600 → refus en 1 nommant le fichier, avant tout chargement
  - adresse, identifiant ou jeton absents → 2 nommant la variable, sans en afficher la valeur ; adresse mal formée → 2
  - SRV_K8S_NAMESPACES absente ou vide → 2 ; un de ses namespaces absent du cluster → 1 en le nommant, rien appliqué
  - après exécution, chaque namespace de SRV_K8S_NAMESPACES porte le Secret de type kubernetes.io/dockerconfigjson
  - Secret identique déjà présent → aucun changement annoncé ; seconde exécution idem
  - le jeton n'apparaît ni dans la sortie, ni dans le journal, ni dans la ligne de commande d'un processus (ps)
  - --dry-run nomme les Secrets à créer ou mettre à jour sans leur contenu et rend 0
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-registry.sh --help"
implementation_notes:
  - droits lus par stat avant load_config registry ; manifeste envoyé à « kubectl apply -f - » par l'entrée standard, jamais --docker-password ; jamais kubectl diff sur un Secret
  - comparaison par empreinte (annotation sha256 du dockerconfigjson), pas par lecture en clair ; run_logged interdit sur ces appels
  - faux kubectl en tête de PATH qui consigne ses arguments, pour prouver l'absence du jeton ; garde /.dockerenv ; --request-timeout
---

# TASK-071 — Configurer l'accès au registry

Précédent : `config/notify.env` (décision 15) porte un secret dans un contexte dédié non
versionné. `SRV_K8S_NAMESPACES` est introduite par TASK-067.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
