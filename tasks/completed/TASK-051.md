---
id: TASK-051
title: "Écrire Linux/K3s/install-k3s.sh"
status: completed
priority: high
depends_on:
  - TASK-050
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Installer K3s mono-nœud (décision 23) par l'installateur officiel get.k3s.io, après
  le préflight de CLAUDE.md (arguments → privilèges → OS → architecture → ressources
  → réseau → conflits), puis activer le service et vérifier par verify-k3s.sh.
scope:
  - Linux/K3s/install-k3s.sh
  - tests/integration/install-k3s.test.sh
  - config/server.env.example — variables SRV_K3S_* retenues par les décisions ci-dessous
out_of_scope:
  - copier l'installateur K3s dans le dépôt, ou écrire /etc/rancher/k3s/config.yaml — c'est configure-k3s.sh
  - agent, multi-nœud, désactivation de Traefik (décision 23), cert-manager, règles ufw
  - réinstaller ou mettre à niveau un K3s présent — c'est upgrade-k3s.sh
acceptance_criteria:
  - root requis (1) ; cibles de la décision 14, architectures amd64 et arm64 seulement (1 sinon)
  - espace libre sous /var/lib insuffisant bloque en 1 ; mémoire sous le minimum n'émet qu'un [WARN]
  - get.k3s.io injoignable, ou port 6443, 80 ou 443 déjà en écoute : refus en 1 en nommant la cause, rien installé
  - K3s déjà installé — version affichée, rend 0 sans rien réinstaller
  - résumé confirmé ; --yes seul le confirme (ASSUME_YES remise à false, décision 45) ; sans terminal ni --yes, 1
  - --dry-run affiche le préflight et la commande prévue, sans téléchargement, rend 0
  - version : canal stable si SRV_K3S_VERSION est absente, sinon la version épinglée, affichée dans le résumé ; installateur en HTTPS seul, sans empreinte épinglée (décision 47)
  - l'installateur est téléchargé dans un temporaire puis exécuté, jamais « curl | sh » ; échec → 1
  - le jeton /var/lib/rancher/k3s/server/node-token n'apparaît ni dans la sortie ni dans le journal
  - après installation, k3s est activé et verify-k3s.sh rend 0, sinon 1
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/K3s/install-k3s.sh --help"
implementation_notes:
  - faux curl, k3s, systemctl et ss en tête de PATH ; le faux curl dépose un faux installateur traceur, aucun téléchargement réel
  - modèle : Docker/Installation/install-docker.sh ; run_logged ne doit pas capturer de sortie contenant le jeton
---

# TASK-051 — Installer K3s

Pièges : le premier serveur héberge déjà un reverse proxy Docker (backlog §1) —
Traefik de K3s voudra 80/443, d'où le contrôle de conflit. ufw en `deny`
(décision 21) peut bloquer le trafic pods/services (10.42.0.0/16, 10.43.0.0/16) :
à documenter, pas à régler ici. Seuils de ressources à reprendre de la
documentation K3s (non vérifiés dans le dépôt).


**Décidé par `user` le 2026-09-16** : voir `orchestration/decisions.md`, décision 47.
