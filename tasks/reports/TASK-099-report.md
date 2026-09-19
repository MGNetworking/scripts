# TASK-099 — Rapport d'exécution

## Compte rendu

La relecture peut maintenant se faire par l'API, sans toucher à l'abonnement : `bash
orchestration/outils/lancer-agent.sh anthropic TASK-XXX --relecture` lance le sous-agent
`relecteur` en lecture seule (`Read`, `Grep`, `Glob`, ni `Bash` ni `Edit` ni `Write`) dans la
copie de la tâche, lui donne la consigne de relecture (et, si on lui en fournit un, le fichier
de vérifications déjà lancées), rend son verdict tel quel sur stdout et écrit lui-même sa
ligne dans `agents.tsv` — plus rien à recopier à la main. `orchestration/relecture.json` dit
qui relit : `api` (ce script) ou `abonnement` (le sous-agent `relecteur` d'aujourd'hui, décrit
dans `tache.md` étape 6), et quel modèle par défaut. Un mode inconnu s'arrête en code 2.

J'ai éprouvé le mécanisme sur lui-même : le réglage réel du dépôt est en mode `api`, modèle
`opus`. J'ai donc fait relire TASK-099 par ce que TASK-099 vient de construire — premher usage
réel, pas seulement simulé. Verdict : **FUSIONNABLE**, six critères tenus, aucun bloquant.
Coût réel : 0,406 $ (Opus 5, 10 tours, 160 s), écrit par le script lui-même dans `agents.tsv`.

Cinq mineurs relevés. Deux sont déjà couverts (longueur du script, renvoyée à TASK-095 qui
suit ; comptage de la ligne de mesure, verrouillé par les tests). Trois vont au registre :
le niveau de preuve du fichier de cas n'est pas nommé « simulé » (A188) ; la définition du
relecteur est lue dans la branche relue elle-même plutôt que dans le dépôt principal, ce qui
laisserait en théorie une branche redéfinir son propre juge (A189) ; un `modele` absent du
réglage retombe silencieusement sur Haiku, le moins cher, pour une relecture (A190). Le
`JUGE : ÉCHEC` que `verifier-travail.sh` a rendu n'est pas un défaut de ce travail : c'est
l'anomalie déjà connue A169 (`juger.sh` ne reconnaît aucun chemin sous `orchestration/`).

**Conduite.** Fiche à `agent: orchestrateur` : écrite en direct par la session, sans agent
délégué — `orchestration/outils/` est interdit en écriture aux agents lancés. Relecture par
l'API (Opus), comme le veut le changement de régime du 2026-09-19 : aucun sous-agent interne
sollicité, ni pour écrire ni pour relire.

## Statut

COMPLETED

## Objectif

La relecture d'une tâche peut se faire par Opus à l'API, hors du harnais, ou par le sous-agent
relecteur sur l'abonnement. Un réglage dit lequel, changeable en une ligne.

## Travail réalisé

- `orchestration/outils/lancer-agent.sh` (149 → 189 lignes) : option `--relecture`, lecture de
  `orchestration/relecture.json`, options `--agent relecteur --tools Read,Grep,Glob` en mode
  relecture, consigne dédiée, verdict rendu sur stdout, colonne `relecteur` dans `agents.tsv`.
- `orchestration/relecture.json` (nouveau) : `mode` (`api`/`abonnement`), `modele`.
- `.claude/commands/tache.md`, étape 6 : les deux modes distingués, mesure automatique en `api`.
- `orchestration/README.md` : lignes `relecture.json` et `--relecture` ajoutées au tableau.
- `tests/acceptance/TASK-099-relecture.sh` (141 lignes, 37 vérifications) : réglage réel du
  dépôt en `--dry-run`, dépôt jouet pour les deux modes, le refus d'un mode inconnu, l'absence
  de tout outil d'écriture dans les arguments reçus par un faux `claude`, la non-régression de
  l'exécution ordinaire.

## Fichiers modifiés

- `orchestration/outils/lancer-agent.sh`
- `orchestration/relecture.json` (nouveau)
- `.claude/commands/tache.md`
- `orchestration/README.md`
- `tests/acceptance/TASK-099-relecture.sh` (nouveau)

## Commandes exécutées

| Commande | Code | Durée |
|---|---|---|
| `bash tests/acceptance/TASK-099-relecture.sh` | 0 | quelques secondes |
| `bash tests/acceptance/TASK-098-modeles.sh` (non-régression) | 0 | quelques secondes |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 | ~1-2 min |
| `bash orchestration/outils/verifier-liens.sh` | 0 | < 1 s |
| `bash orchestration/outils/verifier-travail.sh TASK-099` | 1 (JUGE seul, A169) | quelques secondes |
| `bash orchestration/outils/lancer-agent.sh anthropic TASK-099 --relecture --modele opus` | 0 | 160 s, 0,406 $ |

## Validations

Les quatre commandes de la fiche sont vertes.

| Validation | Résultat |
|---|---|
| `bash tests/acceptance/TASK-099-relecture.sh` | PASS (37/37) |
| `bash tests/acceptance/TASK-098-modeles.sh` | PASS (29/29) |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | PASS (130 fichiers, 0 erreur) |
| `bash orchestration/outils/verifier-liens.sh` | PASS (aucun lien mort) |

## Erreurs rencontrées

`shellcheck` a d'abord signalé SC2054 sur `--tools Read,Grep,Glob` (virgules dans un tableau
non guillemeté) : corrigé en guillemetant la valeur, sans changer le comportement.

`verifier-travail.sh` a rendu `JUGE : ÉCHEC` — anomalie connue A169, pas un défaut de ce
travail : `juger.sh` ne reconnaît que les `.sh` sous `Docker/Linux/Kubernetes/Synology/` et
`tests/integration/*.test.sh`, jamais `orchestration/outils/` ni `tests/acceptance/*.sh`.

## Corrections automatiques

Aucune : verdict FUSIONNABLE au premier jet.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] `lancer-agent.sh anthropic TASK-XXX --relecture --modele opus` lance `claude -p` avec
      `--agent relecteur` et `--tools Read,Grep,Glob`, dans la copie, sans Bash/Edit/Write
- [x] la consigne envoyée est celle de la relecture, pas `/executer-tache`
- [x] la sortie du relecteur est rendue telle quelle sur stdout, ligne « relecteur » ajoutée à
      `agents.tsv` sans l'aide du conducteur
- [x] `orchestration/relecture.json` porte `mode` et `modele` ; mode inconnu refusé en code 2
- [x] `tache.md` étape 6 distingue les deux modes
- [x] le fichier de cas prouve les deux modes, le refus d'un mode inconnu, l'absence de tout
      outil d'écriture ; `shellcheck -x` rend 0

## Validation finale

PASS

## Git

Branche : `agent/TASK-099`
Commit : `54fa0ed` (travail)

## Réserves

- A188 : niveau de preuve non nommé « simulé » dans l'en-tête du fichier de cas.
- A189 : le relecteur lu depuis la branche relue elle-même, pas depuis le dépôt principal.
- A190 : repli silencieux sur Haiku si `modele` manque au réglage.

## Résumé

Fait, prouvé, fusionnable. TASK-095 (extraire `lib-agents.sh`) est la tâche `ready` suivante.
