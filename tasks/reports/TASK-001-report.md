# TASK-001 — Rapport d'exécution

## Statut

COMPLETED

## Contexte d'exécution

Tâche menée en session assistée, avant la mise en place des sous-agents
([TASK-010](../../tasks/completed/TASK-010.md)). Le format de ce rapport est
celui défini par [tasks/README.md](../../tasks/README.md) §6 : la tâche sert
aussi de première épreuve de ce format.

## Objectif

Doter le dépôt d'un point d'entrée unique de validation, exécutable à la main
comme par l'agent. Sans lui, aucune tâche ultérieure ne peut être prouvée.

## Travail réalisé

- `tests/run.sh` — dispatcher des cinq niveaux de validation, avec un code de
  retour distinct pour « niveau non implémenté » ;
- `tests/lint.sh` — analyse statique de tous les `.sh` du dépôt, `bash -n`
  systématique, `shellcheck` lorsqu'il est disponible ;
- `tests/README.md` — niveaux, codes de retour, exclusions, règles d'écriture
  d'un test ;
- `.claude/settings.json` — autorisation d'exécuter le harnais.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `tests/run.sh` | créé |
| `tests/lint.sh` | créé |
| `tests/README.md` | créé |
| `.claude/settings.json` | modifié — 4 permissions ajoutées |

Aucun script d'administration existant n'a été touché.

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `bash -n tests/run.sh` | 0 | syntaxe correcte |
| `bash -n tests/lint.sh` | 0 | syntaxe correcte |
| `bash tests/run.sh lint` | 0 | 11 fichiers, 0 erreur |
| `bash tests/run.sh` | 0 | 1 niveau réussi, 4 ignorés |
| `bash tests/run.sh unit` | 3 | NON IMPLÉMENTÉ, correctement signalé |
| `bash tests/run.sh --nawak` | 2 | option refusée |
| `bash tests/run.sh perf` | 2 | niveau inconnu refusé |
| `bash tests/run.sh --liste` | 0 | 1 implémenté, 4 non implémentés |
| `bash tests/lint.sh <script cassé>` | 1 | erreur de syntaxe détectée et rapportée |

Le script cassé était un fichier temporaire hors dépôt, supprimé après essai.

## Validations

| Validation | Résultat |
|---|---|
| `bash -n tests/run.sh` | PASS |
| `bash -n tests/lint.sh` | PASS |
| `tests/run.sh lint` | PASS |
| analyse `shellcheck` du harnais lui-même | **NON EXÉCUTÉ** — outil absent de la machine |

## Erreurs rencontrées

Aucune.

## Corrections automatiques

Aucune.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] `tests/run.sh lint` exécute l'analyse statique et retourne 0 si tout passe
- [x] `tests/lint.sh` vérifie la syntaxe de tous les `.sh` par `bash -n`
- [~] `tests/lint.sh` exécute `shellcheck` lorsqu'il est disponible — **partiel.**
      Le branchement est écrit, et la branche « outil absent » est éprouvée ; la
      branche « outil présent » ne l'a pas été, faute de `shellcheck` sur la
      machine. Coché `[x]` dans la première version de ce rapport : corrigé sur
      remarque du relecteur, une case cochée ne peut pas contredire la règle
      « une validation non exécutée n'est jamais PASS »
- [x] shellcheck absent : sortie `NON EXÉCUTÉ`, code de retour 0
- [x] le résultat de chaque fichier est affiché individuellement
- [x] un script en erreur fait échouer la commande avec un code non nul
- [x] les scripts du harnais respectent les conventions du dépôt

## Validation finale

PASS, avec une réserve explicite : **l'intégration de `shellcheck` n'a pas pu
être vérifiée à l'exécution**, l'outil étant absent de la machine. Seul le
comportement de repli l'a été. La levée de cette réserve viendra avec
[TASK-002](../../tasks/pending/TASK-002.md), l'image de test embarquant
`shellcheck`.

Cette réserve est consignée plutôt que passée sous silence : un critère dont la
preuve est partielle ne se déclare pas acquis.

## Git

Branche : `agent/socle-agentique`.

Travail réalisé en session assistée, avant la mise en place du cycle `/tache` —
les commits sont donc regroupés à la fin de la session plutôt que produits tâche
par tâche.

## Relecture du 2026-08-28

Ce rapport a été soumis au sous-agent `relecteur` — premier usage réel du
mécanisme. Verdict : **CONFORME AVEC RÉSERVES**. Il a rejoué les trois
validations et sept vérifications de son cru, et relevé trois défauts :

1. **la documentation décrivait une intention, pas le comportement.**
   `tests/README.md` et la première version de ce résumé annonçaient les scripts
   Synology « signalés en `WARN` » à chaque passage. En réalité ils passent
   `bash -n` et s'affichent en `[SUCCESS]` ;
2. **un critère coché à tort** — le critère `shellcheck`, requalifié `[~]`
   ci-dessus ;
3. **défaut de conception non vu à l'écriture** : la tolérance accordée aux
   scripts hérités masquait *tout* problème sur ces fichiers, y compris une
   erreur de syntaxe. Un `organize-series.sh` devenu invalide serait passé en
   `WARN` avec un code de retour 0 — le harnais aurait affiché « 0 erreur » sur
   un dépôt cassé.

Les trois sont corrigés. `tests/lint.sh` distingue désormais la nature du
problème : la tolérance porte sur le style, jamais sur la syntaxe.

**Vérification du correctif** — impossible pour le relecteur, en lecture seule :
une erreur de syntaxe a été injectée dans `Synology/Plex/update-plex.sh`, le
lint a répondu `[ERROR]` et code 1, puis le fichier a été restauré et son
intégrité confirmée par `git status`.

## Résumé

Le dépôt dispose pour la première fois d'une validation exécutable. Onze
scripts passent l'analyse syntaxique, les deux scripts Synology hérités
compris — leur tolérance ne couvrant que le style, pas la syntaxe.

La limite du moment est nette : sans `shellcheck`, seule la syntaxe est
vérifiée, et `bash -n` ne voit ni variable non quotée, ni test fragile.

Le harnais affiche donc un avertissement à chaque exécution —
`analyse approfondie NON EXÉCUTÉE` — pour qu'un « 11 fichiers, 0 erreur » ne
soit pas lu comme un feu vert complet.
