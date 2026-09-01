# TASK-012 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Le harnais confondait deux situations sous le même code 3, et `tests/run.sh`
écrasait ce 3 en échec. Conséquence : toute tâche dont la suite comportait un
cas non applicable à son environnement était bloquée, quel que soit son travail.

## Travail réalisé

### La sémantique retenue

Ce que rend un fichier de cas ou un script de niveau :

| Code | Sens |
|---|---|
| 0 | tous les cas exécutés, tous réussis |
| 1 | au moins un cas en défaut |
| 2 | erreur d'usage |
| 3 | **aucun cas n'a pu être exécuté** — rien n'est prouvé |
| 4 | **nouveau** — cas réussis, certains non applicables : preuve partielle |

`tests/run.sh` rend 0, 1, 2, 3 — **jamais 4**. Il lit le 4, l'affiche, et le
traduit en 0. Son contrat reste lisible en une ligne : *0, la validation est
acquise*.

Le code 3 n'est pas supprimé : il garde son sens de TASK-001 — « niveau non
implémenté, rien n'est prouvé » — et s'y ajoute « aucun cas n'a pu être
exécuté ».

### Le garde central

**Le 4 exige au moins une réussite.** Le test `reussites -eq 0 → 3` est placé
**avant** `non_executes > 0 → 4`. Cet ordre est toute la garantie : sans lui,
un fichier qui saute tous ses cas sortirait en 4, donc en 0.

C'est ce qui rend impossible le scénario « tout est sauté, donc tout va bien ».

### Fichiers

- `tests/run.sh` — la boucle passe de `if bash "$script"` à
  `code=0; bash "$script" || code=$?` suivi d'un `case`. Quatre compteurs au
  lieu de deux : réussis, partiels, stériles, échecs ;
- `tests/acceptance/run-acceptance.sh` — quatre verdicts par fichier ; un
  fichier stérile n'est jamais racheté par le reste du lot ;
- `tests/README.md` — §2 réécrite, §5 complétée du modèle de bilan, §1
  arborescence à jour ;
- `tests/acceptance/TASK-012-semantique-codes.sh` — 58 vérifications.

**Hors `scope`, imposé par le changement de sémantique** — l'`out_of_scope` de
la tâche portait l'exception explicite « sauf ce qu'impose le changement de
sémantique » :

- `TASK-002-environnement-conteneurise.sh` et `TASK-011-analyse-statique.sh`,
  **bloc de bilan final uniquement** : `exit 3` → `exit 4`, plus l'insertion du
  garde. Aucune assertion touchée, vérifié ligne à ligne par le relecteur.

## Commandes exécutées

| Commande | Code | Durée |
|---|---|---|
| `bash -n` sur les 4 `.sh` modifiés | 0 | — |
| `tests/run.sh lint` | **0** | ~15 s |
| `run-in-container.sh -- tests/run.sh lint` | **0** — 17 fichiers, 0 erreur, 2 avertis | ~40 s |
| `tests/run.sh acceptance` | **0** | ~340 s |
| `tests/run.sh unit` | 3 | immédiat |
| `run-in-container.sh -- shellcheck TASK-012-semantique-codes.sh` | 0 | — |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | **PASS** |
| `tests/run.sh acceptance` | **PASS** — 272 réussites, 0 échec, 15 non applicables |
| `run-in-container.sh -- tests/run.sh lint` | **PASS** |

## Le garde, éprouvé trois fois

Le testeur et le relecteur l'ont vérifié **indépendamment**, chacun dans son
propre bac à sable hors du dépôt — le second n'a pas réutilisé le dispositif du
premier.

| Scénario | Fichier | Dispatcher | `tests/run.sh` |
|---|---|---|---|
| 0 réussite, 5 sauts | 3 | 3 | 3 |
| stérile parmi 3 fichiers verts | 3 | 3 | 3 |
| aucun fichier de cas | — | 3 | 3 |
| sans argument, `lint` vert + `acceptance` stérile | — | 3 | **3** |
| partiel (3 réussites, 7 sauts) | 4 | 4 | **0** |
| un échec, mêlé à partiel et stérile | 1 | 1 | 1 |

Le testeur a de plus prouvé que ses assertions **mordent**, par mutation de
copies hors dépôt : un dispatcher dont le bloc stérile rendrait `exit 0` fait
échouer ses cas ; un `run.sh` ramené à `bash "$script" && code=0 || code=1`
aussi.

## Erreurs rencontrées

**Un code 1 non reproductible.** Après avoir interrompu une exécution de la
suite par un dépassement de délai — ma faute, deux lancements consécutifs dans
le même appel —, l'exécution suivante a rendu **1 alors qu'aucun cas n'échouait**
et qu'aucun `[ERROR]` n'apparaissait dans la sortie.

Vérifications immédiates : aucun conteneur `mgnet-test-` résiduel, arbre Git
intact. Les deux exécutions propres suivantes ont rendu **0**.

Le fait est consigné plutôt qu'enterré : une suite qui rend 1 sans qu'aucun cas
n'échoue est un comportement à comprendre. Piste la plus probable — un état
transitoire laissé par l'interruption brutale. Le testeur avait signalé que les
exécutions concurrentes ne sont pas couvertes et que les assertions « aucun
conteneur résiduel » seraient fausses en parallèle.

## Corrections automatiques

**Tentative 1 — trois points du relecteur.**

*Diagnostic* : aucun ne portait sur la sémantique elle-même, jugée saine. Deux
concernaient la documentation, un le code mort d'un fichier de test.

- limite du code 4 non documentée → `redacteur-script`, `tests/README.md` §2 ;
- arborescence sans `TASK-012-semantique-codes.sh` → même délégation ;
- fonction `verifier()` morte dans le fichier de test → `redacteur-tests`, qui a
  d'abord vérifié qu'elle n'était appelée nulle part avant de la retirer.

*Résultat* : `bash -n` et `shellcheck` passent, validations rejouées, toutes
vertes.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] une suite dont tous les cas applicables réussissent sort en 0, même avec des cas non applicables — mesuré
- [x] une suite dont aucun cas n'a pu être exécuté ne sort jamais en 0 — quatre variantes mesurées
- [x] un cas en échec fait toujours sortir en code non nul — y compris mêlé à un partiel et un stérile
- [x] le nombre de cas non applicables est affiché et jamais masqué — remonte aux trois étages
- [x] `tests/run.sh` distingue les codes au lieu de traiter tout non-zéro comme un échec
- [x] `tests/run.sh acceptance` sort en 0 sur l'état actuel
- [x] la sémantique de chaque code est documentée dans `tests/README.md`

## Validation finale

PASS

## Le défaut que cette tâche laisse ouvert

**Elle ferme « tout est sauté, donc tout va bien ». Elle ne ferme pas « presque
tout est sauté ».**

Mesuré par le testeur puis par le relecteur, démon Docker coupé — Docker Desktop
jamais arrêté :

```text
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)   → 4
tests/run.sh acceptance                                          → 0
```

72 % de la preuve évaporée, verdict vert. Sur `master` avant cette tâche, ce même
scénario rendait 3, donc 1 : **c'est une régression sur l'axe de l'honnêteté**,
consentie en échange de la levée d'un blocage qui frappait toutes les tâches.

La cause : les compteurs ne distinguent pas « non applicable par nature » — le
profil `debian` n'a pas `systemd` et ne l'aura jamais — de « environnement
indisponible » — la preuve existe mais n'a pas pu être produite. Quelques cas de
préflight suffisent à franchir le seuil.

Le remède impose de qualifier chaque appel `saute` de chaque fichier de cas, ce
que l'`out_of_scope` de cette tâche excluait nommément.

**Jugement du relecteur, retenu** : la tâche reste conforme — les sept critères
sont littéralement satisfaits, le remède est hors périmètre, et le travail ne
dissimule rien puisqu'il mesure et annonce lui-même la limite.

Consigné en trois endroits pour qu'il survive : `docs/points-en-suspens.md` §3,
[TASK-013](../completed/TASK-013.md), et `tests/README.md` §2.

## Réserves

- **le défaut ci-dessus**, principale limite de cette livraison ;
- **`tests/lint.sh` rend toujours 0 en annonçant `NON EXÉCUTÉ`** quand
  `shellcheck` manque. C'est exactement le faux vert que cette tâche combat,
  dans le seul niveau qui n'a pas reçu la nouvelle sémantique — il dispose
  pourtant désormais du code qui l'exprime. Hors `scope`, listé comme connexe ;
- **le décompte des sauts repose sur une convention, pas un mécanisme** : le
  dispatcher ne compte que des fichiers ; le nombre de cas ne survit que si
  l'auteur écrit la ligne `info "Bilan …"`. Vérifié structurellement, faute de
  mieux ;
- **aucune protection contre la récursion** du niveau `acceptance` : un fichier
  de cas qui appellerait `tests/run.sh acceptance` boucle sans fin, sans garde
  ni message. C'est la raison des bacs à sable ; un futur auteur tombera dans le
  même trou ;
- **le critère « `tests/run.sh acceptance` sort en 0 » ne peut pas être prouvé
  par le harnais** — récursion — et repose sur une vérification manuelle,
  déclarée `NON EXÉCUTÉ` dans le fichier de cas. La nouvelle sémantique
  s'illustre ainsi elle-même ;
- **la preuve la plus forte de TASK-011 s'est évaporée**, comme son testeur
  l'avait prédit : ses six contrôles de forme du diff reposaient sur
  `git diff HEAD` et sont passés en `NON EXÉCUTÉ` après le commit. Son bilan
  passe de 156/7 à **150/13**. Prédiction vérifiée, sans conséquence sur le
  verdict.

## Git

Branche : `agent/TASK-012`.

## Résumé

Le piège est désarmé. Une tâche dont la suite comporte des cas inaccessibles à
son environnement n'est plus refusée pour cette seule raison — c'était le sort
de TASK-011, refusée avec 156 vérifications au vert, et celui qui attendait
TASK-003, TASK-004 et TASK-009.

Le garde qui empêche l'abus tient : trois scénarios de stérilité éprouvés
indépendamment par deux sous-agents, chacun dans son propre bac à sable, et des
assertions vérifiées par mutation.

Reste une porte entrouverte, mesurée et documentée : un environnement qui tombe
en cours de campagne produit aujourd'hui un vert imméritée. C'est le prix payé
pour lever le blocage, et il est écrit noir sur blanc dans trois fichiers plutôt
que laissé à la mémoire de la conversation.

Le harnais s'est aussi appliqué à lui-même sa propre règle : `TASK-012` sort en
4, preuve partielle, parce qu'il ne peut pas se tester sans se rappeler
lui-même.
