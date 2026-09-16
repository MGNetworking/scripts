---
id: TASK-063
title: "Écrire Kubernetes/Installation/install-helm.sh"
status: pending
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Installer Helm (plan §5) par le mécanisme officiel, après le préflight de CLAUDE.md,
  puis relire la version installée. Rédigé pour l'option recommandée ci-dessous.
scope:
  - Kubernetes/Installation/install-helm.sh
  - tests/integration/install-helm.test.sh
  - config/server.env.example — SRV_HELM_VERSION, facultative
out_of_scope:
  - mettre à niveau ou réinstaller un Helm présent ; installer des plugins
  - ajouter un dépôt de charts, installer une release — c'est install-cert-manager.sh
  - copier le script officiel dans le dépôt ; passer par apt ou snap
acceptance_criteria:
  - root requis (1) ; cibles de la décision 14, amd64 et arm64 seulement (1 sinon)
  - Helm déjà présent — version affichée, rien téléchargé, rend 0
  - version : dernière publiée si SRV_HELM_VERSION est absente, sinon l'épinglée, affichée dans le résumé
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche préflight et commande prévue, sans téléchargement, rend 0
  - script officiel téléchargé en HTTPS seul (curl --proto '=https' --tlsv1.2) dans un temporaire, exécuté puis retiré, jamais « curl | sh »
  - VERIFY_CHECKSUM, HELM_INSTALL_DIR, DESIRED_VERSION et USE_SUDO hérités neutralisés ; la somme sha256 reste vérifiée
  - version relue par helm version après installation ; absente ou différente de l'épinglée — 1
  - téléchargement ou installation en échec — 1 en nommant l'étape ; 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-helm.sh --help"
implementation_notes:
  - faux curl et helm en tête de PATH ; le faux curl dépose un faux script traceur, aucun téléchargement réel
  - garde /.dockerenv avant tout trap ou écriture si une racine de test est introduite ; modèle Linux/K3s/install-k3s.sh
---

# TASK-063 — Installer Helm

Helm n'est pas fourni par K3s. Helm n'utilise pas le kubeconfig de K3s par défaut :
à documenter pour install-cert-manager.sh.

**Décision attendue de user** : quel mécanisme et quelle version majeure ?
1. **(recommandé)** script officiel `get-helm-4` (raw.githubusercontent.com/helm/helm), qui vérifie lui-même la sha256, sans empreinte épinglée — comme la décision 47 ;
2. même chose avec `get-helm-3` ;
3. archive get.helm.sh et son `.sha256sum` vérifié par le script ;
4. dépôt apt officiel signé.

À vérifier avant de lancer : nom exact du script Helm 4 et variables qu'il honore
(celles citées viennent de `get-helm-3`), et fin de support de Helm 3.
