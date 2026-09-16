---
id: TASK-050
title: "Écrire Linux/K3s/verify-k3s.sh"
status: in_progress
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Diagnostiquer en lecture seule un K3s mono-nœud (plan §4) — service, version, nœuds,
  pods, namespaces, événements — avec un code de retour qui porte le verdict, pour
  servir de vérification finale à install-k3s.sh et upgrade-k3s.sh.
scope:
  - Linux/K3s/verify-k3s.sh
  - tests/integration/verify-k3s.test.sh
out_of_scope:
  - toute écriture, tout redémarrage de service, tout kubectl apply/delete/rollout
  - l'affichage du kubeconfig, du jeton de nœud ou de tout Secret Kubernetes
  - Traefik, cert-manager et l'ingress — domaine Kubernetes/
acceptance_criteria:
  - root requis (1) : /etc/rancher/k3s/k3s.yaml n'est lisible que par root
  - K3s absent (ni binaire k3s ni unité k3s) — sortie complète sans message brut « command not found », rend 1
  - rubriques affichées dans l'ordre du plan — service k3s (systemctl is-active), version, nœuds, pods -A, namespaces, événements Warning
  - un nœud non Ready, ou un pod ni Running ni Succeeded, est signalé par [WARN] qui le nomme et rend 1
  - cluster sain rend 0 ; une option inconnue rend 2, seul cas de 2
  - les commandes kubectl passent par « k3s kubectl », jamais par un kubectl supposé installé
  - --help documente rubriques et codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/K3s/verify-k3s.sh --help"
implementation_notes:
  - faux k3s et systemctl en tête de PATH, qui rendent la sortie et le code demandés ; aucun vrai K3s en test
  - modèle direct : Docker/Diagnostics/check-docker.sh (verdict par code, rubriques)
  - chaque appel k3s kubectl borné par --request-timeout, pour qu'un apiserver muet ne fige pas le script
---

# TASK-050 — Diagnostiquer K3s

Premier du domaine (décision 16) : il ne modifie rien et ouvre `Linux/K3s/`.
Environnement `container-debian` comme TASK-045/046 : systemctl y est un faux
binaire, la preuve ne dépend pas d'un vrai systemd.

Piège : les événements d'un cluster sain comptent souvent des Warning anciens ;
ils s'affichent mais ne changent pas le code de retour.
