---
id: TASK-073
title: "Instituer le cadrage par grand dossier et la boucle de réflexion (décision 49)"
status: in_progress
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  Consigner la décision 49 validée par user le 2026-09-17 et la faire appliquer : un
  CADRAGE.md par grand dossier engage le contrat des scripts, et aucune fiche ne naît
  hors de la boucle de réflexion validée par user.
scope:
  - orchestration/decisions.md — décision 49
  - orchestration/architecture.md — étape « Besoin et cadrage » avant la création des tâches
  - orchestration/orchestration.html et orchestration/orchestration.png — même étape sur l'affiche
  - orchestration/regles.md — lire le cadrage avant d'écrire une fiche
  - .claude/commands/tache.md, .claude/commands/atomiser.md — vérifier la fiche contre le cadrage
  - .claude/agents/relecteur.md, .claude/agents/redacteur-tache.md — signaler ou refuser une fiche hors contrat
  - docs/refactorisation-plan.md — une phrase : le cadrage prend le relais pour les évolutions
  - docs/reprise-cadrage.md — supprimé une fois la décision consignée
out_of_scope:
  - écrire un CADRAGE.md (TASK-074 à TASK-077)
  - modifier un script ou un fichier de cas
acceptance_criteria:
  - decisions.md porte la décision 49 datée du 2026-09-17 et reprend les cinq choix du §3 et la proposition du §4 de docs/reprise-cadrage.md, dont le modèle de CADRAGE.md et la boucle en sept étapes
  - à l'étape 5 de la boucle, les questions ouvertes sont posées « en une seule série » (correction validée par user)
  - architecture.md et l'affiche montrent que user exprime un besoin, non une commande, et que la session applique /atomiser après validation du cadrage
  - regles.md, tache.md, atomiser.md, relecteur.md et redacteur-tache.md renvoient au CADRAGE.md du dossier concerné, et relecteur.md classe BLOQUANT une fiche qui sort du contrat validé
  - docs/reprise-cadrage.md n'existe plus et aucun lien n'y renvoie
validation:
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - un dossier sans CADRAGE.md encore écrit n'empêche pas une tâche de correction déjà au backlog ; le dire dans la décision
  - régénérer orchestration.png depuis orchestration.html par la même méthode que le commit 7a43ffe
---

# TASK-073 — Cadrage par grand dossier et boucle de réflexion

Source : `docs/reprise-cadrage.md` (commit 289d30e), validé par user le 2026-09-17
tel quel, avec la seule correction « questions posées en une seule série ».
