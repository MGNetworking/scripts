---
id: TASK-012
title: "Distinguer « rien de prouvé » de « cas non applicable » dans le harnais"
status: ready
priority: high
depends_on: []
environment: host
human_approval_required: false
objective: |
  Le harnais confond deux situations sous le même code 3, et tests/run.sh écrase
  ce 3 en échec. Conséquence : toute tâche dont la suite comporte un cas non
  applicable à son environnement est bloquée, quel que soit son travail.
scope:
  - tests/run.sh — propager le code de retour d'un niveau au lieu de le réduire à réussi/échoué
  - tests/acceptance/run-acceptance.sh — distinguer les deux natures de saut
  - tests/README.md — documenter la sémantique retenue
out_of_scope:
  - toute modification des fichiers de cas existants, sauf ce qu'impose le changement de sémantique
  - le profil de conteneur systemd, qui rendrait exécutables les cas aujourd'hui sautés
  - lib/common.sh — zone protégée
acceptance_criteria:
  - une suite dont tous les cas applicables réussissent sort en 0, même si des cas ont été déclarés non applicables
  - une suite dont aucun cas n'a pu être exécuté ne sort jamais en 0
  - un cas en échec fait toujours sortir en code non nul
  - le nombre de cas non applicables est affiché à chaque exécution et jamais masqué
  - tests/run.sh distingue les codes rendus par un niveau au lieu de traiter tout non-zéro comme un échec
  - tests/run.sh acceptance sort en 0 sur l'état actuel du dépôt
  - la sémantique de chaque code est documentée dans tests/README.md
validation:
  - "tests/run.sh lint"
  - "tests/run.sh acceptance"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
implementation_notes:
  - le piège est à tests/run.sh ligne 137 environ — « if bash "$script" » réduit tout code non nul à un échec
  - ne pas supprimer le code 3 : il garde son sens pour « niveau non implémenté », où rien n'est prouvé
  - un cas non applicable doit rester visible — le masquer rouvrirait la porte au faux vert que tout le harnais cherche à fermer
  - deux suites d'acceptation existent déjà et servent de banc d'essai : TASK-002 sans saut, TASK-011 avec sept
---

# TASK-012 — Sémantique des codes de retour

## Origine

Révélée par [TASK-011](../completed/TASK-011.md), et déjà entrevue lors de
[TASK-002](../completed/TASK-002.md).

TASK-001 avait introduit le code 3 pour une bonne raison : empêcher qu'un
`tests/run.sh unit` sorte en 0 alors qu'aucun test unitaire n'existe. « Rien à
exécuter » n'est pas « tout va bien ».

Mais ce même code sert aujourd'hui à deux situations très différentes :

| Situation | Sens réel | Code actuel |
|---|---|---|
| aucun cas exécuté | rien n'est prouvé — grave | 3 |
| 156 cas passés, 7 non applicables à cet environnement | l'essentiel est prouvé | 3 |

Et `tests/run.sh` aggrave la confusion en réduisant tout code non nul à un
échec : le 3 soigneusement produit par le dispatcher est perdu à l'étage
au-dessus.

## Pourquoi c'est bloquant pour la suite

Tant que ce point n'est pas réglé, **toute tâche dont la suite comporte un cas
non applicable à son environnement sera bloquée**, quelle que soit la qualité de
son travail. C'est déjà arrivé à TASK-011 : 156 vérifications au vert, tâche
refusée.

Le conteneur `debian` n'a pas `systemd` et ne peut pas `swapon`. Les tâches
à venir — TASK-003, TASK-004, TASK-009 — rencontreront toutes des cas
inaccessibles. Le piège se refermerait à chaque fois.

## L'équilibre à tenir

La tentation serait de faire sortir toute suite en 0 dès qu'aucune assertion
n'échoue. Ce serait rouvrir exactement la porte que le code 3 avait fermée : un
harnais qui affiche vert sans avoir rien prouvé.

La sémantique retenue doit donc rendre **impossible** le scénario « tout est
sauté, donc tout va bien », tout en cessant de punir « presque tout est prouvé,
trois cas ne s'appliquent pas ici ».

Le nombre de cas non applicables reste affiché à chaque exécution, et le rapport
de tâche les consigne. Un saut invisible serait pire que le problème d'origine.

## Défauts connexes, à traiter ou non selon le périmètre retenu

Relevés lors de TASK-002 et TASK-011, tous dans le harnais :

- `tests/lint.sh` sort en 0 en annonçant `NON EXÉCUTÉ` quand `shellcheck` est
  absent. Un validateur lira 0 et conclura `PASS` — c'est ce mécanisme qui a
  laissé la dette de TASK-011 invisible depuis le début du dépôt ;
- le message de démon Docker injoignable de `run-in-container.sh` tronque la
  cause réelle : `docker info | head -n 5` n'affiche que le bloc `Client:`.
  Constaté en conditions réelles le 2026-08-29.
