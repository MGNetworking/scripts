---
id: TASK-060
title: "Écrire Kubernetes/Maintenance/backup-resources.sh"
status: pending
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Exporter en YAML les manifests importants du cluster (plan §7) dans un répertoire local
  hors dépôt, sans jamais écrire un Secret, pour pouvoir recréer les ressources.
scope:
  - Kubernetes/Maintenance/backup-resources.sh
  - tests/integration/backup-resources.test.sh
  - config/server.env.example — variable de destination seulement, si la décision la retient
out_of_scope:
  - export de Secrets sous quelque forme que ce soit, même chiffrés ou encodés en base64
  - sauvegarde des données des volumes (PV, local-path) et d'etcd
  - restauration, rotation ou purge des anciennes sauvegardes, envoi distant
  - toute écriture sur le cluster ; « k3s kubectl » ; affichage du kubeconfig
acceptance_criteria:
  - un sous-répertoire horodaté par exécution, un fichier par namespace et par type ; répertoire en 0700, fichiers en 0600
  - aucun objet de kind Secret dans les fichiers produits, prouvé par recherche de « kind: Secret » sur un cluster qui en compte
  - destination située dans le dépôt (sous SCRIPTS_ROOT) → refus en 1, rien écrit
  - --dry-run liste destination, namespaces et types sans rien écrire, rend 0
  - kubectl absent ou apiserver injoignable avant l'export → [ERROR] et 1, aucun répertoire créé ; échec en cours d'export → 1 en nommant le répertoire incomplet
  - chemin produit affiché en [SUCCESS] ; option inconnue → 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/backup-resources.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend du YAML contenant un Secret si on le lui demande ; destination dans un mktemp du test
  - chaque appel kubectl borné par --request-timeout ; umask 077 avant toute écriture
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - ne jamais passer par « kubectl get all » + ajouts : lister les types explicitement, Secret n'y figurant pas
---

# TASK-060 — Sauvegarder les manifests

Dépôt public (décision 24, CLAUDE.md « Secrets ») : l'export ne va jamais dans le dépôt.

**Décisions attendues de user** :
1. Destination par défaut : (a) **`SRV_K8S_BACKUP_DIR` dans server.env, sinon
   `/var/backups/kubernetes`**, surchargée par `--output` — recommandé ; (b) `--output` obligatoire.
2. Types exportés : (a) **namespaces, deployments, statefulsets, daemonsets, cronjobs,
   services, ingresses, configmaps, persistentvolumeclaims, storageclasses** — recommandé ;
   (b) la même liste sans configmaps, qui portent parfois des valeurs sensibles.
