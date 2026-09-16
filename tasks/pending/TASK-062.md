---
id: TASK-062
title: "Écrire Kubernetes/Installation/install-kubectl.sh"
status: pending
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Vérifier kubectl (plan §5) : présence, architecture, version client et serveur, accès
  au cluster. Rédigé pour l'option recommandée ci-dessous — vérification seule.
scope:
  - Kubernetes/Installation/install-kubectl.sh
  - tests/integration/install-kubectl.test.sh
out_of_scope:
  - télécharger ou installer kubectl, créer le lien /usr/local/bin/kubectl — K3s le pose (Linux/K3s/install-k3s.sh)
  - écrire, copier, afficher ou exporter un kubeconfig ; fixer KUBECONFIG
  - diagnostic des nœuds et des pods — c'est Linux/K3s/verify-k3s.sh et Kubernetes/Maintenance/
acceptance_criteria:
  - lecture seule — aucun fichier écrit hors journal, aucun paquet ni binaire installé
  - kubectl absent — rend 1 en renvoyant vers Linux/K3s/install-k3s.sh
  - architecture de la machine et version client affichées ; architecture hors amd64/arm64 — [WARN]
  - cluster injoignable ou kubeconfig illisible (appels bornés par --request-timeout) — rend 1 en nommant la cause
  - versions client et serveur affichées ; écart de plus d'une version mineure — [WARN] sans changer le code
  - aucun contenu de kubeconfig, jeton ou certificat dans la sortie ni le journal
  - codes : 0 kubectl présent et cluster joignable, 1 anomalie, 2 option inconnue
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Installation/install-kubectl.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, aux vrais codes de retour ; aucun appel réseau réel
  - le script laisse kubectl résoudre son kubeconfig ; il ne lit pas /etc/rancher/k3s/k3s.yaml lui-même
---

# TASK-062 — Vérifier kubectl

K3s pose déjà `kubectl` (lien vers `k3s`, Linux/K3s/README.md) ; sur K3s le
kubeconfig est en 0600 (décision 47), d'où `sudo` en pratique — à documenter, pas
à exiger. Politique d'écart kubectl : ±1 mineure.

**Décision attendue de user** : quel objet pour ce script, kubectl étant fourni par K3s ?
1. **(recommandé)** vérification seule, sans rien installer — fiche rédigée ainsi ;
2. installer kubectl depuis dl.k8s.io, sha256 vérifiée, s'il manque (cluster managé, poste) — `human_approval_required` passe à `true` ;
3. annuler la tâche (`verify-k3s.sh` suffit).
