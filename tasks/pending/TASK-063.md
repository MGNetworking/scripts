---
id: TASK-063
title: "Écrire Kubernetes/Installation/install-helm.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Installer Helm 4 (plan §5) par le script officiel get-helm-4, qui vérifie lui-même la
  sha256, à la version SRV_HELM_VERSION si elle est posée, puis relire la version installée.
scope:
  - Kubernetes/Installation/install-helm.sh
  - tests/integration/install-helm.test.sh
  - config/server.env.example — SRV_HELM_VERSION, facultative
out_of_scope:
  - mettre à niveau ou réinstaller un Helm présent ; installer des plugins ; Helm 3
  - ajouter un dépôt de charts, installer une release — c'est install-cert-manager.sh
  - copier le script officiel dans le dépôt ; passer par apt, snap ou l'archive get.helm.sh
acceptance_criteria:
  - aucun require_root ; cibles de la décision 14, amd64 et arm64 seulement (1 sinon)
  - Helm déjà présent — version affichée, rien téléchargé, rend 0
  - version — dernière publiée si SRV_HELM_VERSION est absente, sinon l'épinglée, affichée dans le résumé
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche préflight et commande prévue, sans téléchargement, rend 0
  - get-helm-4 téléchargé en HTTPS seul (curl --proto '=https' --tlsv1.2) dans un temporaire, exécuté puis retiré, jamais « curl | sh »
  - variables héritées honorées par get-helm-4 neutralisées ; la vérification sha256 n'est jamais désactivée
  - version relue par helm version après installation ; absente ou différente de l'épinglée — 1
  - téléchargement ou installation en échec — 1 en nommant l'étape ; 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-helm.sh --help"
implementation_notes:
  - à vérifier par l'agent avant d'écrire — URL et nom exact de get-helm-4 (raw.githubusercontent.com/helm/helm) et variables qu'il honore (get-helm-3 lit VERIFY_CHECKSUM, HELM_INSTALL_DIR, DESIRED_VERSION, USE_SUDO) ; consigner le constat au rapport
  - élévation vers /usr/local/bin laissée au mécanisme sudo du script officiel, pas à require_root
  - faux curl et helm en tête de PATH ; le faux curl dépose un faux script traceur, aucun téléchargement réel
  - garde /.dockerenv avant tout trap ou écriture ; modèle Linux/K3s/install-k3s.sh
---

# TASK-063 — Installer Helm

Helm n'est pas fourni par K3s. Il lit `KUBECONFIG` puis `~/.kube/config`, comme kubectl :
aucun repli sur `k3s.yaml` (décision 48, accès au cluster).

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
