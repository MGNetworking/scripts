---
id: TASK-049
title: "Enchaîner les tâches sans vidage ni « reprends », par un sous-agent jetable par tâche"
status: completed
priority: high
depends_on: []
environment: host
agent: orchestrateur
human_approval_required: true
objective: |
  Une session orchestratrice qui dure enchaîne les tâches prêtes seule : chaque tâche
  est conduite par un sous-agent neuf qui porte le contexte lourd (fiche, diffs,
  validations) et ne rend qu'un résumé court. Plus de vidage ni de « reprends »
  entre deux tâches ; décision 46 amendée.
scope:
  - .claude/agents/conducteur-tache.md
  - .claude/commands/tache.md
  - orchestration/decisions.md
  - orchestration/regles.md
  - orchestration/README.md
  - orchestration/mode.json
out_of_scope:
  - lancer-agent.sh, juger.sh et le harnais de tests
  - le contenu des étapes de /tache (vérifier, relire, clore) : seule leur répartition change
  - toute boucle hors de Claude Code (cron, tâche planifiée Windows)
acceptance_criteria:
  - un sous-agent conducteur-tache conduit les étapes 1-3 et 5-8 d'une tâche, relecture comprise, et rend des réponses de 30 lignes au plus
  - seul le lancement de l'agent (étape 4, jusqu'à une heure) reste à la session, en arrière-plan ; le conducteur est repris par SendMessage
  - en mode automatique, la session enchaîne la tâche ready suivante sans message de user ; blocage, plafond ou mode manuel l'arrêtent
  - l'orchestrateur ne garde entre deux tâches que mode.json, le backlog et les résumés rendus
  - décision 46 amendée dans decisions.md par un avenant daté, validé par user
validation:
  - "bash orchestration/outils/verifier-liens.sh"
  - "enchaîner deux tâches ready réelles et constater dans le journal deux clôtures sans message de user entre elles"
implementation_notes:
  - vérifié le 2026-09-16 : un sous-agent dispose de l'outil Agent et en lance un autre ; SendMessage le reprend avec son contexte ; un Bash au premier plan est plafonné à 10 minutes
  - la compaction automatique de Claude Code borne la croissance de la session orchestratrice
---

# TASK-049 — Boucle d'exécution sans vidage

Demandée par `user` le 2026-09-16, pendant TASK-046 : le vidage imposé par la
décision 46 arrête la session, et chaque tâche exige un « reprends » manuel.

Le vidage servait à ne pas accumuler le contexte des tâches. Un sous-agent par tâche
atteint le même but : son contexte disparaît quand il rend son résumé, la session
orchestratrice reste légère et ne s'arrête plus.

**Principe validé par `user` le 2026-09-16.** Première version relue par Opus : la relecture restait à la session sur une hypothèse fausse (sous-agent sans outil Agent), réfutée par essai ; la répartition a été simplifiée en conséquence.
