---
id: TASK-071
title: "Écrire Kubernetes/Configuration/configure-registry.sh"
status: in_progress
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
  - FAIT VÉRIFIÉ (doc Kubernetes « Pull an Image from a Private Registry ») - la doc avertit que « kubectl create secret docker-registry --docker-password=… » expose le secret dans l'historique du shell et aux autres utilisateurs pendant l'exécution ; cette forme est INTERDITE, de même que tout identifiant en argument de n'importe quelle commande (curl, base64, sha256sum, printf externe…)
  - FAIT VÉRIFIÉ - type obligatoire kubernetes.io/dockerconfigjson, clé de data « .dockerconfigjson » ; contenu JSON {"auths":{"<serveur>":{"username":"…","password":"…","auth":"<base64 de username:password>"}}}
  - FAIT VÉRIFIÉ - manifeste apiVersion v1, kind Secret, metadata.name, metadata.namespace, type kubernetes.io/dockerconfigjson, data avec .dockerconfigjson égal au base64 du JSON ; un Pod l'utilise par « imagePullSecrets - [{name - <nom>}] » - à documenter dans --help ou le README, jamais appliqué (hors périmètre)
  - JSON et base64 construits localement (base64 -w0 de coreutils, lu sur l'entrée standard, jamais en argument) ; manifeste passé à « kubectl apply -f - » sur STDIN ; aucun fichier temporaire, ou alors umask 077 + mktemp + effacement par trap, et aucun fichier restant après exécution
  - valeurs du .env validées avant toute construction - serveur = nom d'hôte[:port] sans schéma, sans barre oblique ni espace, sinon 2 ; identifiant et jeton sans retour ligne ni caractère de contrôle, sinon 2 ; guillemets et antislashs échappés pour JSON, ou refusés en 2 - le choix est écrit dans --help
  - config/registry.env refusé en 1 si absent, droits différents de 0600 (stat -c %a) ou propriétaire différent de l'utilisateur courant (stat -c %u contre id -u), avant load_config ; modèle - le chargement de config/notify.env par Linux/System/notify-failure.sh, dont un défaut passé fut une URL secrète passée en argument de curl
  - set -x jamais actif pendant la construction ; aucune variable secrète dans un message, un die, un trap ERR ni un bilan ; stderr de kubectl apply jamais recopié tel quel s'il peut contenir le manifeste - résumer la cause
  - idempotence sans lire le Secret en clair - empreinte sha256 du JSON posée en annotation mgnetworking/empreinte, relue par jsonpath et comparée ; identique → aucun apply, « aucun changement » ; « kubectl diff » interdit (masquage des valeurs = connaissance de la session non vérifiée)
  - modèle voisin - Kubernetes/Configuration/configure-namespaces.sh (liste SRV_K8S_NAMESPACES validée RFC 1123, présence de chaque namespace vérifiée AVANT tout apply, bilan A78 en échec partiel, idempotence par deux exécutions)
  - chaque appel kubectl porte --request-timeout et est enveloppé par timeout (délai + 2) ; 124 nommé ; require_cmd kubectl timeout base64 sha256sum ; causes distinguées et nommées - NotFound, Forbidden, API injoignable, kubeconfig invalide, délai dépassé
  - --dry-run - aucun apply, nomme chaque Secret « à créer » ou « à mettre à jour » sans afficher manifeste ni valeur, rend 0 ; ASSUME_YES remise à false avant les options (décision 45) si une confirmation existe, testée sous pseudo-terminal (script -qec) ; aucune suppression
  - cas avec valeurs sentinelles uniques (identifiant et jeton) - le faux kubectl consigne argv, lit et garde l'entrée standard, et relève « ps -eo args » pendant l'appel ; la suite prouve l'absence des sentinelles dans la sortie, le journal (lancer, run_logged, logs/), les argv consignés, les ps relevés et tout fichier restant hors du .env ; elle prouve aussi que le manifeste reçu sur STDIN décode en JSON correct
  - cas obligatoires - registry.env en 0644 → 1 ; valeur piégée (guillemet, antislash, retour ligne) → 2 ou JSON correct ; namespace absent → 1 nommé sans apply ; deux exécutions → la seconde sans apply ; faux kubectl aux vrais codes et messages, état en fichier ; garde /.dockerenv avant tout trap
  - la suite doit échouer contre une copie jetable du script mutée (jeton passé en argument, contrôle des droits retiré, comparaison d'empreinte retirée)
---

# TASK-071 — Configurer l'accès au registry

Précédent : `config/notify.env` (décision 15) porte un secret dans un contexte dédié non
versionné. `SRV_K8S_NAMESPACES` est introduite par TASK-067.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
