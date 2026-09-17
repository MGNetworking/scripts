---
id: TASK-072
title: "Faux binaires des fichiers de cas et relevé de jetons d'un agent bloqué (A122)"
status: ready
priority: medium
depends_on: []
environment: container-debian
agent: orchestrateur
human_approval_required: false
objective: |
  Empêcher qu'un fichier de cas remplace un vrai binaire du conteneur en écrivant son
  faux à travers un lien symbolique, et rendre juste le relevé d'agents.tsv quand un
  agent a passé l'essentiel de son temps bloqué.
scope:
  - tests/README.md — règle d'écriture des faux binaires
  - orchestration/outils/juger.sh — signalement d'un « cat > » vers un chemin de PATH factice lié
  - orchestration/outils/lancer-agent.sh — relevé de tours et de jetons
out_of_scope:
  - réécrire les fichiers de cas existants (leur défaut éventuel devient une ligne du registre)
  - changer le plafond de durée DUREE_MAX
acceptance_criteria:
  - tests/README.md dit qu'un faux binaire est un fichier ordinaire créé dans un répertoire du bac, jamais écrit à travers un lien, et qu'il n'appelle jamais le vrai binaire par son nom résolu dans le PATH factice
  - juger.sh signale un fichier de cas qui crée un lien symbolique puis écrit par « cat > » ou « > » vers le même chemin ; démontré sur une copie jetable du fichier de cas de TASK-071 au commit 6ad93f8
  - un lancement dont la sortie JSON de claude -p est incomplète ou incohérente (tours ≤ 1 pour une durée de plus de 600 s) porte une marque explicite dans agents.tsv au lieu de chiffres présentés comme justes
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash orchestration/outils/juger.sh tasks/completed/TASK-071.md"
implementation_notes:
  - fait observé (TASK-071, premier jet 6ad93f8) - la liste de liens symboliques du bac comprenait timeout ; « cat > $BAC/bin/timeout » a suivi le lien et remplacé /usr/bin/timeout du conteneur par le faux, dont le repli « exec timeout » s'appelait lui-même sans fin ; deux conteneurs sont restés bloqués plus de 30 minutes, les relances de mutants parallèles partageant ce binaire
  - fait observé - agents.tsv a relevé pour ce lancement 1 tour, 243 jetons d'entrée, 442 de sortie, 2269 s ; la relance, sans blocage, 97 tours et 1025 s. Cause du relevé faux non établie - sortie JSON d'une session interrompue par le plafond ou reprise ; à établir avant de corriger
---

# TASK-072 — Faux binaires et relevé d'un agent bloqué

Issue de TASK-071 (rapport `tasks/reports/TASK-071-report.md`, registre A122).
