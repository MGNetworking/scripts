---
id: TASK-097
title: "Faire lire à lancer-agent.sh la clé d'API dans les variables utilisateur de Windows quand l'environnement ne la porte pas"
status: in_progress
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  lancer-agent.sh trouve la clé d'un profil dans l'environnement ; si elle y manque, il la
  lit dans les variables utilisateur de Windows. Le profil anthropic.env fonctionne ainsi
  depuis la session, où le harnais ne retransmet pas ANTHROPIC_API_KEY.
scope:
  - orchestration/outils/resoudre-cle.sh
  - orchestration/outils/lancer-agent.sh
  - tests/acceptance/TASK-097-cle.sh
out_of_scope:
  - créer, lire ou afficher un fichier de clés ; la clé reste où elle est
  - modifier orchestration/modeles/ ou limites.json
  - lancer un agent réel (les tests emploient de fausses clés et un faux powershell.exe)
acceptance_criteria:
  - resoudre-cle.sh NOM écrit sur stdout la valeur de la variable d'environnement NOM ; sinon celle de la variable utilisateur Windows lue par powershell.exe, retour chariot retiré ; sinon code 1 sans rien écrire
  - la variable d'environnement est prioritaire sur le registre ; un nom hors ^[A-Z][A-Z0-9_]*$ est refusé en code 2 sans appeler powershell.exe
  - lancer-agent.sh appelle resoudre-cle.sh au lieu de lire ${!VARIABLE_CLE} ; si la clé est introuvable il s'arrête en code 2 avec un message qui nomme la variable et les deux endroits cherchés, sans jamais afficher de valeur
  - le test prouve chaque cas avec de fausses valeurs, dont l'arrêt de lancer-agent.sh sur un dépôt jouet ; il rend 0
  - shellcheck -x rend 0 sur les trois fichiers ; resoudre-cle.sh fait 25 lignes au plus
validation:
  - "bash tests/acceptance/TASK-097-cle.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - constat du 2026-09-19 - ANTHROPIC_API_KEY est dans le registre utilisateur (108 caractères) mais absente du shell de la session ; le harnais définit lui-même ANTHROPIC_BASE_URL
  - orchestration/outils/ est fermé aux agents lancés - tâche conduite par l'orchestrateur, en direct, pour économiser les jetons
  - ordre de user du 2026-09-19 - option 2, aucun fichier de clés, aucun nouveau nom de variable
---

# TASK-097 — Clé d'API lue jusque dans les variables Windows

Numéro 097 : TASK-096, écartée avant tout travail, n'est pas réutilisée.
