---
id: TASK-094
title: "Ajouter à architecture.md la vue d'exécution, les couches, le registre des agents et l'inventaire des capacités"
status: in_progress
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: anthropic
objective: |
  orchestration/architecture.md répond à quatre questions qu'il laisse ouvertes : quel
  programme tourne et depuis où, ce qui relève du modèle, du harnais, des scripts et des
  consignes, quels agents existent avec quel modèle et quelles permissions, et quels
  scripts d'outillage sont génériques ou propres au projet.
scope:
  - orchestration/architecture.md
out_of_scope:
  - modifier un script, limites.json, regles.md ou decisions.md
  - extraire du code dans une bibliothèque (TASK-095)
  - réécrire les sections 1 à 10 existantes, hors renvois rendus nécessaires
acceptance_criteria:
  - une section « Vue d'exécution » avec un schéma Mermaid montre les trois cas - session, sous-agent dans le même processus, agent externe lancé par lancer-agent.sh - avec pour chacun le dossier de travail et l'API contactée
  - une section « Les quatre couches » distingue modèle, harnais, scripts et consignes, dit ce qui est interchangeable, et énonce le contrat minimal attendu d'un harnais - lire et écrire des fichiers, exécuter une commande shell, parler à un modèle
  - une section « Registre des agents » donne pour chacun - conducteur-tache, relecteur, redacteur-tache, profils de orchestration/modeles/ - où il est défini, son modèle, ses permissions, son coût moyen lu dans agents.tsv, et ce qu'il ne peut pas faire
  - une section « Inventaire des capacités » liste chaque script de orchestration/outils/ avec ce qu'il sait faire et la mention générique ou propre au projet, justifiée en une ligne
  - chaque chemin, option et chiffre cité est vérifié dans le dépôt ; les coûts viennent de orchestration/mesures/agents.tsv
  - les schémas Mermaid sont syntaxiquement valides, dans le style des quatre schémas déjà présents
validation:
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - le fichier fait 310 lignes et porte déjà 4 schémas - acteurs, lieux, artefacts, vue d'ensemble, cycle, états, du besoin au push, contrôles, arrêts, écarts
  - vocabulaire de référence pour les couches et le contrat minimal - docs/reprise-2026-09-18.md §4 et 4 bis
  - regles.md §19 donne la politique de choix du modèle et les tarifs
---

# TASK-094 — Vues manquantes d'architecture.md

Demandé par user le 2026-09-19 : comprendre l'organisation du projet, et d'où les agents
sont lancés. Première des deux tâches ; la seconde (TASK-095) extrait ce que l'inventaire
aura désigné comme générique.
