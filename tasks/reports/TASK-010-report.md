# TASK-010 — Rapport d'exécution

## Statut

COMPLETED

## Contexte d'exécution

Réorientation décidée en conversation le 2026-08-28. Tâche menée en session
assistée : c'est elle qui met en place le moteur, elle ne peut donc pas être
exécutée par lui.

## Objectif

Doter le dépôt de son moteur d'exécution, sans écrire une ligne de programme :
trois sous-agents aux rôles distincts, et une commande qui les enchaîne sur une
tâche du backlog.

## Travail réalisé

**Décision d'architecture**

- `ADR-0002` — Claude Code devient le moteur ; abandon de l'orchestrateur sur
  mesure et du découplage multi-fournisseur ;
- `ADR-0001` marqué partiellement remplacé, conservé intact.

**Moteur**

- `.claude/agents/redacteur-script.md` — écrit le script et sa documentation ;
- `.claude/agents/redacteur-tests.md` — écrit les tests ;
- `.claude/agents/relecteur.md` — vérifie et rend un verdict, **sans outil
  d'écriture** ;
- `.claude/commands/tache.md` — cycle complet en 10 étapes ;
- `.claude/commands/backlog.md` — point de situation.

**Backlog**

- TASK-005 à 008 annulées, déplacées dans `tasks/cancelled/`, chacune portant la
  raison de son abandon ;
- répertoire `tasks/cancelled/` créé et documenté ;
- index, chemin critique et section « Terminé » mis à jour.

**Documentation alignée**

- `AGENTS.md` — §5, §8, §18, §19 : plus d'orchestrateur, plus d'adaptateurs ;
  le §19 distingue désormais ce qui appartient au projet de ce qui appartient au
  moteur ;
- `tasks/README.md` — répertoire `cancelled/`, mentions de l'orchestrateur
  retirées ;
- `README.md` — tableau de la couche agentique ;
- `docs/agent/project-audit.md` — note en tête signalant que les sections 16 à
  18 décrivent une solution abandonnée. Le document n'est pas réécrit : un audit
  est daté.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md` | créé |
| `.claude/agents/redacteur-script.md` | créé |
| `.claude/agents/redacteur-tests.md` | créé |
| `.claude/agents/relecteur.md` | créé |
| `.claude/commands/tache.md` | créé |
| `.claude/commands/backlog.md` | créé |
| `tasks/completed/TASK-010.md` | créé |
| `tasks/cancelled/TASK-005.md` … `TASK-008.md` | déplacés, statut et note d'annulation |
| `docs/agent/decisions/ADR-0001-socle-agentique.md` | modifié — statut |
| `docs/agent/project-audit.md` | modifié — note en tête |
| `AGENTS.md` | modifié — 5 sections |
| `tasks/README.md` | modifié |
| `tasks/backlog.md` | modifié |
| `README.md` | modifié |
| `tasks/reports/TASK-001-report.md` | modifié — lien vers une tâche déplacée |

Aucun script d'administration touché. Aucune ligne de `lib/common.sh` modifiée.

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `bash tests/run.sh lint` | 0 | 11 fichiers, 0 erreur |
| vérification des liens internes (1re passe) | — | 3 liens rompus détectés |
| vérification des liens internes (2e passe) | — | 0 lien rompu |
| contrôle cohérence répertoire ↔ `status` | — | 10 tâches, 0 écart |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | PASS |
| liens internes de tous les documents | PASS |
| cohérence répertoire ↔ statut des 10 tâches | PASS |
| `.claude/agents/` et `.claude/commands/` chargés par Claude Code | **NON EXÉCUTÉ** |

## Erreurs rencontrées

Trois liens rompus après le déplacement des tâches annulées : deux dans
`tasks/backlog.md`, un dans le rapport de TASK-001. Détectés par la vérification
automatique, corrigés, revérifiés.

## Corrections automatiques

1. `tasks/backlog.md` §3 — deux entrées d'index renvoyaient à des tâches
   annulées ; remplacées par des entrées à jour ;
2. `tasks/reports/TASK-001-report.md` — renvoi vers `TASK-007`, déplacée en
   `cancelled/` ; redirigé vers `TASK-010`.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] les trois sous-agents existent et déclarent rôle, outils et règles
- [x] le relecteur n'a aucun outil d'écriture — `tools: Read, Grep, Glob, Bash`
- [x] `/tache` couvre le cycle complet, en 10 étapes
- [x] la limite de cinq tentatives figure dans la commande
- [x] les règles de refus figurent dans la commande
- [x] TASK-005 à 008 annulées, conservées, raison écrite
- [x] la documentation ne promet plus d'orchestrateur ni de multi-LLM
- [x] aucun lien interne rompu

## Validation finale

PASS, avec une réserve : **le chargement effectif des sous-agents et des
commandes par Claude Code n'a pas été vérifié**. Il le sera au premier usage
réel de `/tache`.

## Git

Branche : `agent/socle-agentique`.

Travail réalisé en session assistée : c'est cette tâche qui met en place le
cycle `/tache`, elle ne peut donc pas être passée par lui.

## Complément du 2026-08-28

Question de Maxime après remise du rapport : que se passe-t-il si les tests
échouent ?

La boucle de correction existait bien (étape 7), mais elle ne disait pas **qui**
corrige ni **quoi**. Or un test qui échoue a deux causes possibles — script
fautif ou test fautif — et sans règle, la seconde est toujours choisie : elle
est plus rapide et fait passer le verdict au vert, en laissant le bug.

**Rapports déplacés.** Sur remarque de Maxime : `.agent/` ne contenait plus que
`reports/`, ses autres sous-dossiers ayant tous été abandonnés avec l'ADR-0002.
C'était un vestige de l'architecture écartée. Les rapports décrivent l'état du
travail — ils rejoignent `tasks/reports/`, et `.agent/` disparaît.

**Messages de commit retirés des rapports.** Ils avaient un sens tant qu'aucun
commit n'était fait ; une fois l'historique Git en place, ils le contredisent.

`.claude/commands/tache.md` étape 7 complétée :

- schéma explicite de la boucle ;
- **présomption que le script est fautif** ; modifier un test exige un
  diagnostic écrit dans le rapport ;
- redélégation au sous-agent concerné plutôt que correction improvisée ;
- interdiction de corriger `lib/common.sh` en cours de boucle — zone protégée,
  la tâche se bloque.

## Résumé

Le dépôt a désormais un moteur, et il ne contient pas une ligne de code
d'orchestration. Ce qui devait être un programme est devenu cinq fichiers
Markdown.

Le point de conception qui compte : le relecteur travaille sans outil
d'écriture. Il ne peut donc pas neutraliser un test pour obtenir un verdict
favorable — le scénario le plus dangereux d'un agent devient structurellement
impossible, au lieu d'être seulement déconseillé.

Rien n'est démontré pour autant. La preuve viendra du premier passage réel de
`/tache` sur une tâche du backlog, et il révélera des règles mal formulées.
