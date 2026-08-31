# TASK-014 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Une assertion de TASK-012 encodait l'absence du niveau `unit` comme un
invariant. TASK-003 l'a implémenté, l'assertion est devenue fausse, et tout le
niveau `acceptance` est passé au rouge.

## Travail réalisé

Un seul fichier, `tests/acceptance/TASK-012-semantique-codes.sh`, §5 : les
lignes 424-425 remplacées par un bloc de 41 lignes.

**Avant** — le nom du niveau écrit en dur :

```bash
lancer bash "$RUN" unit
assert_code 3 "tests/run.sh unit sur le dépôt réel → 3 (niveau non implémenté)"
```

**Après** — le niveau est *lu* dans la sortie de `--liste` :

```bash
premier_niveau_absent() {
    awk '$2 == "NON" && vu == 0 { print $1; vu = 1 }' "$1"
}
```

Trois branches, dans cet ordre : le premier niveau annoncé `NON IMPLÉMENTÉ` sur
le dépôt réel ; à défaut — dépôt entièrement implémenté — repli sur le bac à
sable, qui ne porte que `lint` et `acceptance` ; à défaut encore, `saute`.

**Deux assertions au lieu d'une** : le code 3 *et* la présence du motif
`NON IMPLÉMENTÉ` dans la sortie. Sans la seconde, un 3 venu d'un niveau exécuté
n'ayant rien pu prouver satisferait le cas — ce n'est pas ce qu'on vérifie.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `tests/acceptance/TASK-012-semantique-codes.sh` | modifié — §5 uniquement |
| `tasks/active/TASK-014.md` → `completed/` | déplacé, statut |
| `tasks/backlog.md` | modifié |

`tests/run.sh`, `run-acceptance.sh` et le niveau `unit` intacts.

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `bash -n` sur le fichier | 0 | — |
| `run-in-container.sh -- shellcheck …` | 0 | — |
| `bash tests/acceptance/TASK-012-semantique-codes.sh` | 4 | 59 réussites, 0 échec, 2 non exécutés |
| **`tests/run.sh acceptance`** | **0** | TASK-002 64/0/0, TASK-011 150/0/13, TASK-012 59/0/2 |
| `tests/run.sh lint` | 0 | 20 fichiers, 0 erreur |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | **PASS** |
| `tests/run.sh acceptance` | **PASS** — le rouge est levé |

## Le pouvoir discriminant, éprouvé deux fois

Le risque propre à ce genre de correction : **rendre le dépôt vert en vidant le
test de sa substance**. Une assertion qui ne peut plus échouer ne vaut rien.

Quatre mutants, joués par le rédacteur puis **rejoués intégralement par le
relecteur** sur sa propre copie du dépôt :

| Mutation dans `tests/run.sh` | Attendu | Observé par le relecteur |
|---|---|---|
| garde `executes -eq 0` : `exit 3` → `exit 0` | échec ciblé | conforme — 57/2/2 |
| message `NON IMPLÉMENTÉ` → `absent` | échec ciblé | conforme — 58/1/2, seule la 2ᵉ assertion tombe |
| dépôt rendu entièrement implémenté | PASS par le repli | conforme — 59/0/2, code 4 |
| entièrement implémenté **+** `exit 3` → `exit 0` | échec sur le repli | conforme — 57/2/2 |

Les deux branches mordent. Le troisième mutant prouve directement le critère
« implémenter un niveau supplémentaire ne fait plus échouer la suite », y
compris dans le cas extrême où il n'en resterait aucun.

## Erreurs rencontrées

Aucune.

## Corrections automatiques

Aucune — le relecteur n'a rien trouvé à corriger dans le code.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] `tests/run.sh acceptance` sort en 0 sur le dépôt courant
- [x] la vérification subsiste, reformulée — **renforcée** : deux assertions au lieu d'une
- [x] elle ne dépend plus de l'état d'implémentation d'un niveau particulier —
      sur le dépôt réel, elle a choisi `integration` d'elle-même
- [x] implémenter un niveau supplémentaire ne fait plus échouer la suite — mutant 3
- [x] le cas ne déclenche plus l'exécution d'une suite complète — le niveau retenu
      étant non implémenté, `tests/run.sh` sort avant toute exécution

## Validation finale

PASS

## Écart de procédure assumé

**La branche part de `agent/TASK-003`, non de `master`**, contrairement à
l'étape 3 de `/tache`.

L'écart est imposé par la tâche elle-même : sur `master`, le niveau `unit`
n'existe pas encore, et l'assertion corrigée y échouerait en sens inverse. La
correction ne peut être vérifiée que sur une branche contenant TASK-003.

Conséquence : **`agent/TASK-014` porte les deux tâches** et doit être fusionnée
d'un bloc.

## Neutralisation

Contrôlé par le relecteur : aucun `|| true`, aucun `set +e`, aucune assertion
commentée, aucune validation retirée de la tâche. Le nombre d'assertions du §5
passe de 1 à 2 — la vérification est plus stricte après correction qu'avant.

## Réserves

- **la branche `saute` est inatteignable en pratique** — le bac à sable porte
  toujours trois niveaux absents. Ce n'est pas un affaiblissement, mais si
  `--liste` venait à échouer, le cas se dégraderait en `NON EXÉCUTÉ` au lieu
  d'échouer. Risque théorique : le `cmp` du §1 virerait au rouge bien avant ;
- **le §4 code encore `unit` en dur** (`lancer_run unit`, lignes ~397-401).
  Jugé **acceptable** par le relecteur, et ce n'est pas le même défaut : ces
  assertions portent sur le `run.sh` du bac à sable, où `tests/unit/` n'existe
  pas *par construction*. L'ancien §5 dépendait d'un état du dépôt que n'importe
  quelle tâche pouvait changer ;
- **le chemin de code prouvé n'est pas celui qu'on croit** : pour un unique
  niveau absent demandé explicitement, la sortie 3 vient du garde
  `executes -eq 0`, pas du garde `EXPLICITE && absents > 0`. Ce second garde
  reste couvert par `lancer_run lint unit` au §4 ;
- **redondance mineure** : `--liste` est appelé deux fois, le code du second
  appel n'étant pas vérifié. Le rédacteur l'a préféré à une réutilisation qui
  aurait couplé son bloc à l'effet de bord d'une assertion voisine ;
- **un conteneur tué (code 137) pendant la baseline du relecteur**, artefact de
  contention Docker sans rapport avec le §5. Nouveau signe que les exécutions
  concurrentes ne sont pas maîtrisées — déjà consigné lors de TASK-012.

## Git

Branche : `agent/TASK-014`, partant de `agent/TASK-003`.

## Résumé

Le dépôt est de nouveau vert. La correction ne s'est pas contentée de faire
passer le test : elle a supprimé la cause. L'assertion vérifiait un comportement
en s'appuyant sur un état du dépôt ; elle lit désormais cet état au lieu de le
présumer.

Le mécanisme se prouve lui-même : sur le dépôt réel, le cas a choisi
`integration` sans qu'on le lui dise, `unit` n'étant plus disponible.

Et il est plus strict qu'avant — deux assertions là où il n'y en avait qu'une.
Une correction qui rend un test vert en le désarmant aurait été la neutralisation
que le contrat interdit ; c'est l'inverse qui s'est produit, et le relecteur l'a
vérifié en rejouant les quatre mutants plutôt qu'en croyant le rapport.
