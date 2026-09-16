---
id: TASK-049
title: "Enchaîner les tâches sans vidage ni « reprends », par un sous-agent jetable par tâche"
status: pending
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
out_of_scope:
  - lancer-agent.sh, juger.sh et le harnais de tests
  - le contenu des étapes de /tache (vérifier, relire, clore) : seule leur répartition change
  - toute boucle hors de Claude Code (cron, tâche planifiée Windows)
acceptance_criteria:
  - un sous-agent conducteur-tache conduit les étapes 1-5 et 7-8 d'une tâche et rend un résumé de moins de 30 lignes
  - la relecture (étape 6) reste lancée par la session orchestratrice, un sous-agent ne pouvant pas en lancer un autre
  - en mode automatique, la session enchaîne la tâche ready suivante sans message de user ; blocage, plafond ou mode manuel l'arrêtent
  - l'orchestrateur ne garde entre deux tâches que mode.json, le backlog et les résumés rendus
  - décision 46 amendée dans decisions.md par un avenant daté, validé par user
validation:
  - "bash orchestration/outils/verifier-liens.sh"
  - "enchaîner deux tâches ready réelles et constater dans le journal deux clôtures sans message de user entre elles"
implementation_notes:
  - un sous-agent Claude Code n'a pas l'outil Agent : il lance DeepSeek par Bash (lancer-agent.sh), pas le relecteur
  - SendMessage reprend le conducteur avec son contexte pour la correction après relecture, sans relancer un agent neuf
  - la compaction automatique de Claude Code borne la croissance de la session orchestratrice
---

# TASK-049 — Boucle d'exécution sans vidage

Demandée par `user` le 2026-09-16, pendant TASK-046 : le vidage imposé par la
décision 46 arrête la session, et chaque tâche exige un « reprends » manuel.

Le vidage servait à ne pas accumuler le contexte des tâches. Un sous-agent par tâche
atteint le même but : son contexte disparaît quand il rend son résumé, la session
orchestratrice reste légère et ne s'arrête plus.

**Décision attendue de `user`** avant `ready` : remplacer le vidage par ce découpage.
