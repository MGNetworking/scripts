---
id: TASK-068
title: "Écrire Kubernetes/Configuration/configure-storage.sh"
status: pending
priority: medium
depends_on:
  - TASK-062
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Faire en sorte que le cluster ait exactement une StorageClass par défaut, local-path ou
  SRV_K8S_STORAGE_CLASS (plan §6), en ne touchant qu'à l'annotation par défaut.
scope:
  - Kubernetes/Configuration/configure-storage.sh
  - tests/integration/configure-storage.test.sh
  - config/server.env.example — SRV_K8S_STORAGE_CLASS, facultative, défaut local-path
out_of_scope:
  - créer, supprimer ou recréer une StorageClass, un PV ou un PVC ; changer reclaimPolicy ou provisioner
  - le chemin de stockage de local-path (configuration K3s, Linux/K3s/)
  - Longhorn, NFS, CSI, sauvegarde des volumes
acceptance_criteria:
  - sans root (aucun require_root) ; aucune référence à /etc/rancher/k3s/k3s.yaml
  - kubectl absent ou API injoignable → 1 en nommant la cause ; appels bornés par --request-timeout
  - classe cible (SRV_K8S_STORAGE_CLASS, sinon local-path) absente du cluster → refus en 1 en la nommant, rien modifié
  - classe cible déjà seule par défaut → aucun changement annoncé ni appliqué, 0
  - autres classes marquées par défaut → nommées dans le résumé ; leur marque retirée seulement après confirmation (--yes ou terminal), sans terminal ni --yes 1
  - après exécution, exactement une classe porte la marque par défaut, et c'est la cible ; le nombre de classes est inchangé
  - --dry-run affiche les annotations qui changeraient et rend 0
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-storage.sh --help"
implementation_notes:
  - annotation storageclass.kubernetes.io/is-default-class posée par « kubectl annotate --overwrite », jamais par delete/replace
  - faux kubectl en tête de PATH aux codes du vrai ; garde /.dockerenv avant tout trap ; confirmation testée sous pseudo-terminal
  - ASSUME_YES remise à false avant les options (décision 45) ; nom de classe validé RFC 1123 avant tout appel, sinon 2
---

# TASK-068 — Configurer le stockage

K3s fournit la classe `local-path`, marquée par défaut. Deux classes par défaut
rendent le choix imprévisible pour un PVC sans `storageClassName`.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
