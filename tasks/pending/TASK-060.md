---
id: TASK-060
title: "Écrire Kubernetes/Maintenance/backup-resources.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Exporter en YAML une liste fixe de types de ressources du cluster (plan §7) dans un
  dossier local hors dépôt, créé en 0700, sans jamais écrire un Secret.
scope:
  - Kubernetes/Maintenance/backup-resources.sh
  - tests/integration/backup-resources.test.sh
  - config/server.env.example — SRV_K8S_BACKUP_DIR, facultative
out_of_scope:
  - export de Secrets sous quelque forme que ce soit, même chiffrés ou encodés en base64
  - tout type hors de la liste des critères, même sur demande en option
  - sauvegarde des données des volumes (PV, local-path) et d'etcd
  - restauration, rotation ou purge des anciennes sauvegardes, envoi distant
  - toute écriture sur le cluster ; « k3s kubectl » ; affichage du kubeconfig
acceptance_criteria:
  - destination — --output si donnée, sinon SRV_K8S_BACKUP_DIR, sinon /var/backups/kubernetes ; la retenue est affichée
  - types exportés, exactement — namespaces, deployments, statefulsets, daemonsets, cronjobs, services, ingresses, configmaps, persistentvolumeclaims, storageclasses
  - un sous-dossier horodaté par exécution, un fichier par namespace et par type ; dossiers créés en 0700, fichiers en 0600
  - "aucun objet de kind Secret dans les fichiers produits, prouvé par recherche de « kind: Secret » sur un cluster simulé qui en compte"
  - destination dans le dépôt (sous SCRIPTS_ROOT, chemin résolu) → refus en 1, rien écrit
  - --dry-run liste destination, namespaces et types sans rien écrire, rend 0
  - kubectl absent ou apiserver injoignable avant l'export → [ERROR] et 1, aucun dossier créé ; échec en cours d'export → 1 en nommant le dossier incomplet
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml ; [SUCCESS] avec le chemin produit ; option inconnue → 2
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/backup-resources.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend du YAML contenant un Secret si on le lui demande ; destination dans un mktemp du test
  - chaque appel kubectl borné par --request-timeout ; umask 077 avant toute écriture
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
  - jamais « kubectl get all » + ajouts — lister les types explicitement, Secret n'y figurant pas
---

# TASK-060 — Sauvegarder les manifests

Dépôt public (décision 24, CLAUDE.md « Secrets ») : l'export ne va jamais dans le dépôt.
Sans root, `/var/backups/kubernetes` n'est pas inscriptible : le script le dit et rend 1,
`--output` ou `SRV_K8S_BACKUP_DIR` servant alors de remède.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
