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
  S'assurer que le cluster dispose d'une StorageClass par défaut conforme à config/
  (plan §6), sans aucune suppression ni modification d'un volume existant.
scope:
  - Kubernetes/Configuration/configure-storage.sh
  - tests/integration/configure-storage.test.sh
  - config/server.env.example — variable retenue par la décision ci-dessous
out_of_scope:
  - supprimer ou recréer une StorageClass, un PV ou un PVC ; changer reclaimPolicy ou provisioner d'une classe existante
  - le chemin de stockage de local-path (configuration K3s, Linux/K3s/)
  - Longhorn, NFS, CSI, sauvegarde des volumes
acceptance_criteria:
  - kubectl absent ou API injoignable → 1 en nommant la cause ; appels bornés par --request-timeout
  - la classe désignée par config/ absente du cluster → refus en 1 en la nommant, rien n'est modifié
  - classe déjà seule par défaut → aucun changement annoncé ni appliqué, 0
  - une autre classe marquée par défaut → affichée, retrait de son annotation proposé dans le résumé ; --yes ou confirmation requis, sans terminal ni --yes 1
  - --dry-run affiche les annotations qui changeraient et rend 0
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Configuration/configure-storage.sh --help"
implementation_notes:
  - annotation storageclass.kubernetes.io/is-default-class posée par « kubectl annotate --overwrite », jamais par delete/replace
  - faux kubectl en tête de PATH aux codes du vrai ; garde /.dockerenv avant tout trap ; confirmation testée sous pseudo-terminal
  - nom de classe validé strictement (RFC 1123) avant tout appel ; mauvaise valeur → 2
---

# TASK-068 — Configurer le stockage

K3s fournit la classe `local-path`, marquée par défaut. Deux classes par défaut
rendent le choix imprévisible pour un PVC sans `storageClassName`.

**Décision attendue de user : que configure le script ?**
(a) recommandé — vérifier et fixer la classe par défaut seule (`SRV_K8S_STORAGECLASS`,
défaut `local-path`), rien d'autre ;
(b) créer en plus des StorageClass décrites dans config/.
