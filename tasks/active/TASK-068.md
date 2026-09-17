---
id: TASK-068
title: "Écrire Kubernetes/Configuration/configure-storage.sh"
status: in_progress
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
  - marque par défaut = annotation storageclass.kubernetes.io/is-default-class à "true" ; la retirer = la poser à "false" ou supprimer l'annotation (« kubectl annotate storageclass X storageclass.kubernetes.io/is-default-class- ») — le script choisit l'une, s'y tient et le dit dans --help
  - écriture - « kubectl annotate storageclass <nom> storageclass.kubernetes.io/is-default-class=true --overwrite » ; lecture par jsonpath, point de la clé échappé - « {.metadata.annotations.storageclass\.kubernetes\.io/is-default-class} »
  - K3s fournit la classe local-path (provisioner rancher.io/local-path), marquée par défaut
  - connaissance de la session, non vérifiée sur source - K3s réapplique ses manifestes intégrés au démarrage, dont local-path ; lui retirer la marque peut être annulé au redémarrage de K3s. Le script n'y remédie pas ; --help et le README le signalent, la vérification finale le dit si l'état a dérivé
  - ordre sûr - marquer la cible AVANT de démarquer les autres, pour ne jamais passer par zéro classe par défaut (ou justifier l'ordre inverse dans le script) ; déjà seule par défaut → aucun annotate
  - aucun create, delete, apply, replace ni patch de storageclass - le journal du faux kubectl le prouve dans les cas
  - chaque appel porte --request-timeout, et est enveloppé par timeout (délai + 2) ; 124 nommé ; require_cmd timeout ; stderr de kubectl tenu à part de stdout
  - causes distinguées et nommées par echec() - NotFound, Forbidden, API injoignable, kubeconfig invalide, délai dépassé (modèle - configure-namespaces.sh, configure-ingress.sh)
  - échec partiel (une annotation posée, une autre refusée) → bilan de ce qui a changé et de ce qui reste (A78), code non nul, pas de [SUCCESS]
  - vérification finale relue sur le cluster - exactement une classe par défaut, la cible, nombre de classes inchangé ; sinon 1 en nommant l'écart
  - faux kubectl aux vrais codes et messages, qui mémorise les annotations dans un état de fichier, pour deux exécutions enchaînées (idempotence démontrée) ; confirmation et refus sans terminal testés sous pseudo-terminal (script -qec) ; --dry-run - journal sans annotate
  - la suite doit échouer contre une copie jetable du script mutée (ordre inversé, annotate retiré, garde de confirmation retirée)
---

# TASK-068 — Configurer le stockage

K3s fournit la classe `local-path`, marquée par défaut. Deux classes par défaut
rendent le choix imprévisible pour un PVC sans `storageClassName`.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
