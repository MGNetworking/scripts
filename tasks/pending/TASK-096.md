---
id: TASK-096
title: "Lire les clés d'API dans un fichier hors du dépôt, avec repli sur l'environnement"
status: ready
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  lancer-agent.sh trouve la clé d'un profil dans ~/.config/mgnet/cles.env, hors du dépôt,
  et se rabat sur la variable d'environnement si le fichier ou la ligne manque. Un
  lancement ne dépend plus de l'ordre de démarrage du harnais.
scope:
  - orchestration/outils/lancer-agent.sh — résolution de la clé de VARIABLE_CLE
  - config/cles.env.example — modèle versionné, noms de variables sans valeur
  - tests/acceptance/TASK-096-cles.sh — preuve de la résolution et des refus
out_of_scope:
  - versionner un fichier de clés, ou en créer un dans le dépôt
  - écrire, lire ou afficher la valeur d'une clé réelle
  - modifier les profils de orchestration/modeles/, qui ne portent que des noms
  - lancer un agent réel (les tests emploient des clés factices)
acceptance_criteria:
  - la clé est cherchée dans l'ordre - ligne NOM=valeur du fichier désigné par MGNET_CLES, sinon ~/.config/mgnet/cles.env ; puis variable d'environnement de ce nom ; sinon arrêt avec code 2
  - le fichier est lu ligne à ligne et jamais exécuté (pas de source) ; une ligne vide ou commentée est ignorée ; une valeur entre guillemets est acceptée
  - aucune valeur de clé n'apparaît dans la sortie, les journaux, le relevé agents.tsv ni un message d'erreur ; le message d'échec nomme la variable et les deux endroits cherchés
  - le test prouve, avec de fausses clés, chacun des cas - fichier seul, environnement seul, fichier prioritaire sur l'environnement, aucun des deux, ligne commentée, valeur entre guillemets
  - config/cles.env.example liste DEEPSEEK_API_KEY et ANTHROPIC_API_KEY sans valeur, dit où placer le vrai fichier et qu'il ne se versionne jamais
  - shellcheck -x rend 0 sur lancer-agent.sh et le test ; la fonction ajoutée fait 25 lignes au plus
validation:
  - "bash tests/acceptance/TASK-096-cles.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - constat du 2026-09-19 - ANTHROPIC_API_KEY est dans le registre utilisateur Windows (108 caractères) mais absente du processus du harnais ; DEEPSEEK_API_KEY est visible
  - orchestration/outils/ est interdit en écriture aux agents lancés (limites.json) - cette tâche revient au conducteur
  - user écrit lui-même le vrai fichier ; ni un agent ni le conducteur ne le lisent ni ne le créent
  - passe avant TASK-094 - elle conditionne les profils api-haiku et api-sonnet
---

# TASK-096 — Clés d'API hors du dépôt

Demandée par user le 2026-09-19. Le fichier vit dans le dossier personnel, jamais dans
l'arborescence Git : impossible à commiter par accident, le dépôt étant public.
