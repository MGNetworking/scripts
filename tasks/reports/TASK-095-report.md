# TASK-095 — Rapport d'exécution

## Compte rendu

`lancer-agent.sh` est redescendu de 189 à 150 lignes : tout ce qu'il avait de générique —
copie isolée par `git worktree`, plafond de durée, lecture d'un profil `.env`, relevé de
jetons dans le transcript de session, écriture d'une ligne de journal tabulé — vit maintenant
dans `orchestration/outils/lib-agents.sh` (128 lignes), sans rien connaître de ce dépôt : ni
chemin, ni nom de tâche, ni schéma de colonnes.

Cette tâche est la première conduite sous la décision 51 (prise juste avant, dans cette même
session) : `agent: deepseek`, pas `orchestrateur`, alors que le scope touche
`orchestration/outils/`. Coût réel : 0,185 $ (premier jet) + 0,122 $ (correction) = 0,307 $,
contre plusieurs dizaines de milliers de jetons d'API si la session l'avait écrite elle-même.

Premier jet : VERDICT PASSE côté agent. Relecture Opus (API, 0,509 $) : **FUSIONNABLE APRÈS
CORRECTIONS**, deux majeurs — `lib-agents.sh` enfermait encore le schéma à 11 colonnes
d'`agents.tsv` (contraire à sa propre promesse de généricité), et la preuve du chargement de
la bibliothèque par `lancer-agent.sh` n'était que simulée (faux `claude`), alors que la fiche
exigeait un lancement réel cité. DeepSeek a corrigé les deux, plus les deux mineurs
(`shellcheck -x` réellement exécuté, documentation signalée) en une relance, sans dépenser de
clé pour le lancement réel : la preuve tient sur un `--dry-run`, qui n'a besoin d'aucune clé.

L'agent a lui-même signalé, hors de son scope, que trois fichiers de cas déjà mergés
(TASK-097, 098, 099) copiaient l'ancien `lancer-agent.sh` sans `lib-agents.sh` dans leur dépôt
jouet — cassé sans correction. Corrigé par moi (une ligne par fichier), commit séparé sur la
même branche, scope de la fiche mis à jour en conséquence.

Documentation mise à jour à la clôture (décision 36) : `orchestration/README.md` et
`orchestration/architecture.md` §14 portent maintenant `lib-agents.sh`.

**Conduite.** Écriture et correction par `deepseek`, en arrière-plan. Relecture par l'API
(Opus, `--relecture`). Aucun sous-agent interne sollicité à aucune étape.

## Statut

COMPLETED

## Objectif

Les fonctions de `lancer-agent.sh` qui ne doivent rien à ce dépôt vivent dans
`orchestration/outils/lib-agents.sh`, réutilisable tel quel dans un autre projet.

## Travail réalisé

- `orchestration/outils/lib-agents.sh` (nouveau, 128 lignes) : `copie_isolee`,
  `plafond_duree`, `profil_lire`, `releve_jetons`, `journal_agents` (en-tête reçu en
  argument), `resultat_agent`.
- `orchestration/outils/lancer-agent.sh` (189 → 150 lignes) : charge `lib-agents.sh`
  (`source "$ici/lib-agents.sh"`), passe son en-tête à 11 colonnes à `journal_agents`.
- `tests/acceptance/TASK-095-lib-agents.sh` (nouveau, 145 lignes, 40 vérifications) : création
  et réutilisation d'une copie isolée, refus d'un profil inconnu, absence du schéma du projet
  dans la bibliothèque, `--dry-run` réel cité.
- `tests/acceptance/TASK-097-cle.sh`, `TASK-098-modeles.sh`, `TASK-099-relecture.sh` : ajout de
  `lib-agents.sh` à la copie du dépôt jouet (correctif de l'orchestrateur, hors scope initial).
- `orchestration/README.md`, `orchestration/architecture.md` §14 : `lib-agents.sh` documenté.

## Fichiers modifiés

- `orchestration/outils/lib-agents.sh` (nouveau)
- `orchestration/outils/lancer-agent.sh`
- `tests/acceptance/TASK-095-lib-agents.sh` (nouveau)
- `tests/acceptance/TASK-097-cle.sh`, `TASK-098-modeles.sh`, `TASK-099-relecture.sh`
- `orchestration/README.md`, `orchestration/architecture.md`

## Commandes exécutées

| Commande | Code | Durée |
|---|---|---|
| `bash orchestration/outils/lancer-agent.sh deepseek TASK-095` (premier jet) | 0 | 634 s, 0,185 $ |
| `bash orchestration/outils/lancer-agent.sh anthropic TASK-095 --relecture` | 0 | 175 s, 0,509 $ |
| `bash orchestration/outils/lancer-agent.sh deepseek TASK-095 RETOURS-TASK-095.md` | 0 | 1540 s, 0,122 $ |
| `bash tests/acceptance/TASK-095-lib-agents.sh` | 0 | quelques secondes |
| `bash tests/acceptance/TASK-097-cle.sh`, `098`, `099` (non-régression) | 0, 0, 0 | quelques secondes |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 | ~1-2 min |
| `bash orchestration/outils/verifier-travail.sh TASK-095` | 1 (JUGE seul, A169) | quelques secondes |

## Validations

Les deux commandes de la fiche sont vertes.

| Validation | Résultat |
|---|---|
| `bash tests/acceptance/TASK-095-lib-agents.sh` | PASS (40/40) |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | PASS (132 fichiers, 0 erreur) |
| `shellcheck -x` (demandé par la relecture, en sus) | PASS (0, aucune sortie) |

## Erreurs rencontrées

`verifier-travail.sh` a rendu `JUGE : ÉCHEC` — anomalie connue A169, pas un défaut de ce
travail (`juger.sh` ne reconnaît aucun chemin sous `orchestration/` ni `tests/acceptance/`).

L'agent a signalé, sans la corriger (hors scope), une régression que son propre changement
aurait causée sur trois fichiers de cas déjà fusionnés (TASK-097, 098, 099) : ils copiaient
`lancer-agent.sh` sans `lib-agents.sh` dans leur dépôt jouet. Corrigée par l'orchestrateur.

## Corrections automatiques

Une relance sur retours de relecture (2 majeurs, 2 mineurs) : schéma du journal sorti de la
bibliothèque, preuve de lancement réel fournie (`--dry-run`), `shellcheck -x` exécuté,
documentation signalée puis traitée par l'orchestrateur.

## Tentatives

2 / 5 (premier jet + une relance sur retours de relecture)

## Critères d'acceptation

- [x] `lib-agents.sh` ne contient que le générique de l'inventaire TASK-094, aucune mention du
      dépôt — corrigé après relecture (le schéma d'`agents.tsv` est désormais un argument)
- [x] `lancer-agent.sh` charge la bibliothèque, mêmes arguments, VERDICT et ligne de mesure ;
      lancement réel cité (`--dry-run`, sans clé ni dépense)
- [x] chaque fonction prend ses paramètres en arguments, sans variable globale de l'appelant
- [x] le fichier de cas prouve création, réutilisation, refus d'un profil inconnu ; rend 0
- [x] `shellcheck -x` rend 0 sur les deux fichiers ; 150 lignes au plus chacun (128 et 150)

## Validation finale

PASS

## Git

Branche : `agent/TASK-095`
Commits : `057c1f0` (premier jet deepseek), `417b33d` (fix orchestrateur, cas jouet),
`7671376` (fix retours de relecture, deepseek)

## Résumé

Fait, prouvé, fusionnable. Première tâche conduite sous la décision 51 : écriture et
correction déléguées à `deepseek` pour 0,307 $, relecture par l'API pour 0,509 $ — aucun coût
d'écriture direct sur l'abonnement ni la session. Aucune tâche `ready` connue derrière ;
TASK-039 (registre) reste disponible en continu.
