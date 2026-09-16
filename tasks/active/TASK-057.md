---
id: TASK-057
title: "Écrire Kubernetes/Maintenance/events.sh"
status: in_progress
priority: medium
depends_on: []
environment: container-debian
agent: deepseek
human_approval_required: false
objective: |
  Afficher en lecture seule les événements Kubernetes triés du plus ancien au plus récent,
  tous namespaces ou un seul, avec un filtre sur les Warning (plan §7).
scope:
  - Kubernetes/Maintenance/events.sh
  - tests/integration/events.test.sh
out_of_scope:
  - --watch, suivi continu, export vers un fichier ou un collecteur
  - interprétation des événements et verdict par code de retour — diagnostics.sh (TASK-058)
  - filtres par objet, par raison ou par durée
  - l'affichage du kubeconfig ou de Secrets ; tout appel à « k3s kubectl »
acceptance_criteria:
  - sans option — événements de tous les namespaces, triés par horodatage croissant
  - --namespace <ns> limite à ce namespace ; namespace inexistant → [ERROR] et 1
  - --warnings ne garde que les événements de type Warning (field-selector côté serveur)
  - aucun événement → [INFO] qui le dit et 0 ; des Warning affichés ne changent pas le code (0)
  - kubectl absent ou apiserver injoignable → [ERROR] et 1 ; option inconnue ou --namespace sans valeur → 2
  - --help documente options, ordre de tri et codes de retour
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Kubernetes/Maintenance/events.sh --help"
implementation_notes:
  - faux kubectl en tête de PATH, qui rend la sortie et le vrai code ; il note ses arguments pour prouver --field-selector type=Warning et le tri
  - chaque appel kubectl borné par --request-timeout
  - test — garde /.dockerenv absent → sortie, avant tout trap ou écriture
---

# TASK-057 — Événements du cluster

Piège à vérifier sur un vrai kubectl avant d'écrire le tri : certains événements
(API events.k8s.io) n'ont pas de `lastTimestamp` mais un `eventTime` ;
`--sort-by=.lastTimestamp` les place alors en tête. Si le tri choisi en tient
compte, le dire dans `--help` ; ne pas l'inventer sans l'avoir constaté.

Les événements expirent (une heure par défaut côté apiserver) : liste vide ≠ panne.
