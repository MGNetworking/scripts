---
id: TASK-098
title: "Donner à anthropic.env plusieurs modèles, choisis au lancement par --modele"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
agent: orchestrateur
objective: |
  Un seul profil anthropic.env, une seule clé, plusieurs modèles Claude avec leurs tarifs ;
  lancer-agent.sh choisit le modèle par --modele, et --dry-run montre ce qui serait lancé
  sans rien lancer ni dépenser.
scope:
  - orchestration/modeles/anthropic.env — modèles haiku, sonnet, opus, défaut, tarifs
  - orchestration/outils/lancer-agent.sh — options --modele et --dry-run
  - tests/acceptance/TASK-098-modeles.sh
  - orchestration/README.md — usage des deux options
out_of_scope:
  - créer un profil par modèle ; user les a refusés, un profil = un fournisseur
  - modifier deepseek.env : ses lignes MODELE et PRIX_* restent lues comme aujourd'hui
  - lancer un agent réel ou lire la valeur d'une clé
acceptance_criteria:
  - anthropic.env porte MODELE_DEFAUT=haiku et, pour haiku, sonnet et opus, une ligne MODELE_<alias>=<identifiant> et une ligne PRIX_<alias>=<entrée> <cache> <sortie> ; identifiants et tarifs relevés à la source le jour de la tâche, la règle « cache = 10 % de l'entrée » notée comme hypothèse à contrôler
  - lancer-agent.sh anthropic TASK-XXX --modele opus exporte ANTHROPIC_MODEL et les trois ANTHROPIC_DEFAULT_*_MODEL au modèle de l'alias, et le relevé agents.tsv porte cet identifiant ; sans --modele, l'alias MODELE_DEFAUT
  - un alias inconnu, ou --modele sur un profil qui n'en porte pas (deepseek), s'arrête en code 2 en listant les alias disponibles
  - --dry-run n'écrit rien, ne crée ni copie ni branche, ne lance rien, et affiche profil, identifiant du modèle, les trois tarifs et « clé=trouvée », jamais une valeur, et rend 0 ; si la clé manque, il s'arrête en code 2 avec le message habituel de lancer-agent.sh, sans rien lancer
  - le lancement de deepseek, avec ou sans option, se comporte exactement comme avant ; démontré par le test
  - le test prouve chaque cas sur un dépôt jouet avec un faux claude ; shellcheck -x rend 0 ; lancer-agent.sh reste à 150 lignes au plus
validation:
  - "bash tests/acceptance/TASK-098-modeles.sh"
  - "bash tests/acceptance/TASK-097-cle.sh"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "bash orchestration/outils/verifier-liens.sh"
implementation_notes:
  - ordre de user du 2026-09-19 - un seul anthropic.env avec accès à plus de modèles
  - tarifs de référence au 2026-06-24 (skill claude-api) - Haiku 4.5 1/5, Sonnet 5 2/10, Opus 5 5/25 dollars par million de jetons, à recontrôler
  - orchestration/outils/ est fermé aux agents lancés - tâche conduite en direct par la session, sans sous-agent, pour économiser les jetons
---

# TASK-098 — Plusieurs modèles dans anthropic.env

Première des deux tâches demandées par user le 2026-09-19. La seconde, TASK-099, en dépend.
