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
  Créer ou mettre à jour un Secret kubernetes.io/dockerconfigjson d'accès à un registry
  privé (plan §6) dans les namespaces de config/, sans que les credentials soient jamais
  versionnés, affichés, journalisés ni passés en argument.
scope:
  - Kubernetes/Configuration/configure-registry.sh
  - tests/integration/configure-registry.test.sh
  - config/registry.env.example — adresse, identifiant, emplacement du jeton, valeurs neutres
out_of_scope:
  - lier le Secret aux ServiceAccounts (imagePullSecrets), déployer ou redémarrer un workload
  - registries.yaml de K3s (spécifique K3s) ; docker login sur l'hôte
  - supprimer un Secret, ou créer un namespace absent (TASK-067)
acceptance_criteria:
  - adresse, identifiant ou jeton absents → 2 nommant la variable, sans en afficher la valeur ; adresse mal formée → 2
  - config/registry.env lisible par d'autres que root → avertissement nommant le fichier
  - namespace cible absent du cluster → 1 en le nommant, sans rien appliquer ailleurs
  - Secret identique déjà présent → aucun changement annoncé ; seconde exécution idem
  - le jeton n'apparaît ni dans la sortie, ni dans le journal, ni dans la ligne de commande d'un processus (ps)
  - --dry-run nomme les Secrets à créer ou mettre à jour sans leur contenu et rend 0
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-registry.sh --help"
implementation_notes:
  - manifeste envoyé à « kubectl apply -f - » par l'entrée standard, jamais --docker-password ; jamais kubectl diff sur un Secret (masquage non vérifié)
  - comparaison par empreinte (annotation sha256 du dockerconfigjson), pas par lecture en clair ; run_logged interdit sur ces appels
  - faux kubectl en tête de PATH qui consigne ses arguments, pour prouver l'absence du jeton ; garde /.dockerenv ; --request-timeout
---

# TASK-071 — Configurer l'accès au registry

Précédent : `config/notify.env` (décision 15) porte un secret dans un contexte dédié non versionné.

**Décision attendue de user : source des credentials et namespaces cibles ?**
(a) recommandé — `config/registry.env` non versionné (`load_config registry`), un seul
registry, Secret posé dans chaque namespace de la liste de TASK-067 ;
(b) jeton dans une variable d'environnement du shell, namespaces par option `--namespace`.
