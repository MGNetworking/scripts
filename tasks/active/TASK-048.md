---
id: TASK-048
title: "Consigner les jetons de relecture dès la fin de l'étape 6 de /tache"
status: in_progress
priority: medium
depends_on: []
environment: host
agent: orchestrateur
human_approval_required: false
objective: |
  Ne plus perdre les jetons de relecture quand une session s'interrompt entre la
  relecture et la clôture (registre A47).
scope:
  - .claude/commands/tache.md — étape 6
  - orchestration/mesures/journal.md — note de format si nécessaire
out_of_scope:
  - lancer-agent.sh, juger.sh, relecteur
acceptance_criteria:
  - l'étape 6 demande d'écrire les jetons du relecteur dans un fichier versionné de orchestration/mesures/ dès son retour
  - l'étape 8 reprend ce chiffre au lieu de le chercher dans la conversation
validation:
  - "bash orchestration/outils/verifier-liens.sh"
---

# TASK-048 — Jetons de relecture

Constaté sur TASK-045 : la session s'est arrêtée après la relecture ; à la
reprise, les jetons n'étaient écrits nulle part et le journal porte « non relevé ».
