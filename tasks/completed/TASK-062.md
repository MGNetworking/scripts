---
id: TASK-062
title: "Écrire Kubernetes/Installation/install-kubectl.sh"
status: completed
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Vérifier kubectl sans rien installer (plan §5) — présence, architecture, versions client
  et serveur, kubeconfig, accès au cluster ; expliquer la copie de k3s.yaml s'il manque.
scope:
  - Kubernetes/Installation/install-kubectl.sh
  - tests/integration/install-kubectl.test.sh
out_of_scope:
  - télécharger ou installer kubectl, créer le lien /usr/local/bin/kubectl — K3s le pose (Linux/K3s/install-k3s.sh)
  - écrire, copier, afficher ou exporter un kubeconfig ; fixer KUBECONFIG ; lire /etc/rancher/k3s/k3s.yaml
  - diagnostic des nœuds et des pods — c'est Linux/K3s/verify-k3s.sh et Kubernetes/Maintenance/
acceptance_criteria:
  - lecture seule, sans root (aucun require_root) — aucun fichier écrit hors journal, rien installé
  - kubectl absent — rend 1 en renvoyant vers Linux/K3s/install-k3s.sh
  - KUBECONFIG vide et ~/.kube/config absent — rend 1 en affichant la copie à faire (k3s.yaml vers ~/.kube/config du compte, 0600)
  - architecture de la machine et version client affichées ; architecture hors amd64/arm64 — [WARN]
  - cluster injoignable ou kubeconfig illisible (appels bornés par --request-timeout) — rend 1 en nommant la cause
  - versions client et serveur affichées ; écart de plus d'une version mineure — [WARN] sans changer le code
  - aucun contenu de kubeconfig, jeton ou certificat dans la sortie ni le journal
  - codes — 0 kubectl présent et cluster joignable, 1 anomalie, 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-kubectl.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, aux vrais codes de retour ; HOME et KUBECONFIG pointés dans un mktemp ; aucun appel réseau réel
  - le message de copie cite le chemin k3s.yaml comme texte à exécuter par l'humain ; le script ne l'ouvre jamais
  - défauts connus du domaine (TASK-055 à 061) — faux kubectl aux vrais formats, codes et messages : `kubectl version --client -o yaml|json`, `kubectl version` serveur injoignable ; garde /.dockerenv avant tout trap ou écriture ; --request-timeout sur chaque appel au serveur, prouvé par test ; timeout externe = délai + 2, code 124 nommé ; require_cmd timeout ; stderr tenu à part de stdout
  - distinguer Forbidden, cluster injoignable, kubeconfig absent, KUBECONFIG vers un fichier absent ou illisible ; rubrique en échec suivie d'aucun [SUCCESS] (A78) ; `kubectl config view --raw` interdit ; chaque test doit pouvoir échouer contre le script, pas seulement prouver le faux
---

# TASK-062 — Vérifier kubectl

K3s pose déjà `kubectl` (lien vers `k3s`, Linux/K3s/README.md) et un `k3s.yaml` en
0600 (décision 47). Le compte d'administration le copie une fois dans `~/.kube/config`
(0600) ; les scripts de `Kubernetes/` tournent ensuite sans `sudo`. Écart kubectl : ±1 mineure.

**Décidé par `user` le 2026-09-16** : `orchestration/decisions.md`, décision 48.
