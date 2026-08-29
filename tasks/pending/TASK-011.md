---
id: TASK-011
title: "Remettre le dépôt au niveau de l'analyse statique shellcheck"
status: ready
priority: high
depends_on: []
environment: container-debian
human_approval_required: false
objective: |
  Rendre « tests/run.sh lint » vert dans le conteneur, où shellcheck est
  disponible. Six fichiers échouent aujourd'hui — cinq scripts Linux/System et
  tests/lint.sh — pour trois causes distinctes, toutes identifiées.
scope:
  - tests/lint.sh — SC1073 et SC1072
  - Linux/System/configure-hostname.sh — SC2034, SC1087 x2
  - Linux/System/configure-swap.sh — SC2034, SC1087 x2
  - Linux/System/configure-logging.sh — SC2034
  - Linux/System/configure-timezone.sh — SC2034
  - Linux/System/update-system.sh — SC2034
out_of_scope:
  - toute modification de lib/common.sh — zone protégée
  - toute évolution fonctionnelle des scripts, aussi tentante soit-elle
  - les deux scripts Synology hérités, tolérés sur le style par tests/lint.sh
  - l'écriture de tests unitaires ou d'intégration, objet de TASK-003 et TASK-004
acceptance_criteria:
  - tests/run.sh lint exécuté dans le conteneur sort avec le code 0
  - aucun comportement de script n'est modifié — seule la forme change
  - chaque correction est justifiée dans le rapport, cause par cause
  - aucune règle shellcheck n'est désactivée globalement dans tests/lint.sh
  - une directive disable locale, si elle est employée, porte une justification écrite au-dessus
  - chacun des cinq scripts affiche toujours son aide avec --help et sort en 0
  - chacun des quatre scripts pourvus de --dry-run l'accepte toujours sans modifier le système
validation:
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- bash -c 'for s in Linux/System/*.sh; do \"$s\" --help >/dev/null || exit 1; done'"
  - "tests/run.sh acceptance"
implementation_notes:
  - l'outillage vient du travail de TASK-002 — partir d'une branche qui le contient, sinon aucun conteneur n'existe
  - SC2034 sur ASSUME_YES est un faux positif — la variable est lue par confirm() dans lib/common.sh, que shellcheck ne suit pas à travers le source
  - SC1087 vise des motifs de la forme $VAR[ dans une expression régulière — l'écriture ${VAR}[ lève l'ambiguïté sans changer le sens
  - SC1073 et SC1072 sur tests/lint.sh ligne 8 viennent d'un commentaire d'en-tête dont le premier mot est shellcheck — il est lu comme une directive malformée
  - ces cinq scripts tournent en production sans test automatisé — TASK-004 n'est pas faite. Prudence maximale, corrections minimales
---

# TASK-011 — Dette d'analyse statique

## Origine

Révélée par [TASK-002](../blocked/TASK-002.md), qui a livré un conteneur
embarquant `shellcheck` — outil absent de la machine de développement. Le lint
n'avait donc jamais analysé le dépôt en profondeur : il se contentait de
`bash -n` et l'annonçait à chaque exécution.

La dette est antérieure à TASK-002. Celle-ci l'a rendue visible, elle ne l'a pas
créée.

## Les trois causes

**SC2034 — `ASSUME_YES appears unused`** (5 fichiers, sévérité *warning*)

Faux positif. La variable est bien lue, mais par `confirm()` dans
`lib/common.sh`, et `shellcheck` ne suit pas le `source` dont le chemin est
résolu à l'exécution. Deux réponses possibles : `export ASSUME_YES` — qui a du
sens puisque la variable traverse une frontière de fichier — ou une directive
`disable` locale justifiée. Trancher et expliquer le choix.

**SC1087 — `Use braces when expanding arrays`** (4 occurrences, sévérité *error*)

`$VAR[` dans une expression régulière. Bash pourrait l'interpréter comme un
accès à un tableau. L'intention est ici une classe de caractères ; `${VAR}[`
lève l'ambiguïté sans rien changer au sens.

**SC1073 / SC1072 — directive illisible** (`tests/lint.sh` ligne 8)

Le commentaire d'en-tête aligne `#   shellcheck   analyse réelle : …` pour
présenter les deux outils. `shellcheck` lit son propre nom en début de
commentaire et tente d'analyser une directive.

Ironie utile : le fichier qui pilote l'analyse statique est le seul du harnais
à ne pas la passer. Reformuler le commentaire suffit.

## Prudence

Ces cinq scripts d'administration tournent sur un serveur réel et ne sont
couverts par aucun test automatisé — [TASK-004](TASK-004.md) n'est pas faite.

Toute correction doit être **minimale et de pure forme**. Une modification qui
change un comportement, même en apparence pour le mieux, sort du périmètre.
En cas de doute sur une correction, bloquer plutôt que risquer une régression
sur un script qui fonctionne.

## Ce que débloque cette tâche

[TASK-002](../blocked/TASK-002.md) reprendra ensuite sans que son énoncé soit
modifié : sa commande de validation redeviendra verte d'elle-même.
