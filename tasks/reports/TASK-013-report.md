# TASK-013 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Fermer le faux vert que TASK-012 avait laissé ouvert : un fichier de cas dont
l'environnement est indisponible sortait en 4, donc en 0 au bout de la chaîne,
alors que rien d'essentiel n'avait été prouvé.

## Le défaut, tel qu'il était mesuré

```text
DOCKER_HOST=tcp://127.0.0.1:1 bash tests/acceptance/TASK-011-analyse-statique.sh
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)   → 4
tests/run.sh acceptance                                          → 0
```

**72 % de la preuve évaporée, verdict vert.** Quelques cas de préflight, qui
n'ont besoin de rien, suffisaient à franchir le seuil « au moins une réussite ».

## Travail réalisé

`non_executes` garde son nom et son sens — il reste le total affiché — et se
scinde en `non_applicables` + `indisponibilites`.

| Fonction | Message | Compteur | Verdict |
|---|---|---|---|
| `saute` | `NON EXÉCUTÉ : …` | `non_applicables` | 4 |
| `saute_par_nature` | `NON EXÉCUTÉ (non applicable par nature) : …` | `non_applicables` | 4 |
| `saute_indisponible` | `NON EXÉCUTÉ (environnement indisponible) : …` | `indisponibilites` | **3** |

Ordre des gardes : échec, aucune réussite, **indisponibilité**, non applicable.

**26 sites d'appel relus et qualifiés un par un**, plus 11 venus du conteneur.
Ce n'était pas une transformation mécanique : pour chacun, *ce cas est-il hors
d'atteinte par nature, ou l'environnement a-t-il manqué ?*

La ligne de partage retenue : un environnement **conforme mais limité** — image
minimale, pas de systemd, pas de `CAP_SYS_ADMIN` — est une limite de nature ; un
environnement qui **a échoué** — démon mort, miroir apt injoignable — est une
indisponibilité.

`tests/run.sh` et `run-acceptance.sh` n'ont eu **aucun changement de logique** :
ils lisaient déjà le 3 sans le maquiller.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `tests/lib/assert.sh` | trois fonctions de saut, compteurs, bilan |
| `tests/acceptance/TASK-013-natures-de-saut.sh` | créé — 80 vérifications |
| `TASK-002`, `TASK-011`, `TASK-012`, `interne/TASK-011-cas-conteneur.sh` | sauts qualifiés |
| `tests/run.sh`, `tests/acceptance/run-acceptance.sh` | messages précisés |
| `tests/README.md`, `docs/points-en-suspens.md` | sémantique, point 3 traité, point 4 ouvert |

`lib/common.sh` intact. Aucune assertion existante modifiée.

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | **PASS** — 25 fichiers, 0 erreur |
| `tests/run.sh acceptance` | **PASS** — 64/0/0, 150/0/13, 59/0/2, 80/0/2 |
| `tests/acceptance/TASK-013-natures-de-saut.sh` | **PASS** — 80 réussites, 0 échec, code 4 admis par le critère 8 |

## La preuve que le faux vert est fermé

| Mesure | `master` | branche |
|---|---|---|
| `DOCKER_HOST=tcp://127.0.0.1:1 tests/run.sh acceptance` | **0** | **3** |
| `tests/run.sh acceptance`, démon vivant | 0 | 0 |
| `tests/run.sh unit` | 0 — 85/0/7 | 0 — 85/0/7 |
| `tests/run.sh integration` | 3 | 3 |

**Le relecteur a extrait `master` par `git archive` et reproduit le faux vert
lui-même**, plutôt que de s'appuyer sur le témoin fourni. Bilan démon coupé :

```text
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)
                 — dont 9 non applicable(s) par nature et 12 indisponibilité(s)  → 3
```

Le fichier de cas comporte de plus un **témoin** : il reproduit l'ancien bilan à
trois compteurs avec les mêmes chiffres (8/21 → 4 → 0), puis le montre fermé une
fois qualifiés (→ 3 → 3). Sans lui, rien ne dirait que c'est le garde ajouté qui
ferme la porte.

## Corrections automatiques

**Trois tentatives, toutes sur des affirmations non fondées.** L'objet de cette
tâche étant l'honnêteté des verdicts, c'est le bon terrain de bataille.

### Tentative 1 — une nature affirmée sans avoir été relue

*Diagnostic* : le travail était fautif, pas les tests. L'ajout à `assert.sh`
était inerte sur les **verdicts** — vérifié — mais pas sur les **messages** : les
~70 sauts de `unit` et `integration` s'imprimaient soudain « non applicable par
nature » **sans avoir été relus**. Plusieurs n'en sont pas : `/etc/os-release`
illisible, `require_root` sous utilisateur non privilégié — des propriétés de la
machine.

Jugement du relecteur : *« ce n'est pas "pas encore requalifié", c'est
requalifié à tort par défaut, et affirmé à l'écran. Le silence de l'ancien
libellé valait mieux. »*

*Correction* : une **troisième fonction**, `saute_par_nature`. `saute` nu
n'affirme plus rien. **Le nom devient une signature** : l'écrire, c'est déclarer
qu'on a relu ce cas. Neuf assertions ajoutées pour que le contrat soit prouvé et
pas seulement écrit.

### Tentative 2 — une sur-affirmation introduite par la tâche elle-même

*Diagnostic* : le relecteur a trouvé ce que personne n'avait vu. **Le diff avait
ajouté l'affirmation là où elle n'était pas.**

| | avant | après |
|---|---|---|
| `tests/run.sh` | « cas non applicables à cet environnement » | « cas non applicables **par nature** » |

Sa preuve tenait sur un écran : `run-unit.sh`, non touché, disait neutre ;
`run.sh`, touché, disait « par nature ». Deux formulations côte à côte —
**celle restée neutre démontrait que le neutre suffisait.**

*Correction* : 4 messages d'exécution rendus neutres, plus le libellé du bilan.

**Le rédacteur a écarté la formulation proposée par le relecteur**, en lui
opposant son propre principe : `non_applicables` agrège `saute` et
`saute_par_nature`, donc « sans qualification de nature » aurait été la
symétrique de la faute. Retenu : `sans indisponibilité déclarée` — le complément
exact de `indisponibilites`.

Le relecteur a accepté : *« ma proposition était fausse sur une partie du lot. »*

Il a de plus trouvé un **7e appel que le relecteur avait manqué** — la branche
`SKIP)` de `TASK-011:386` — sans lequel le renommage aurait cassé les 11 sauts
conteneurisés.

### Tentative 3 — la même faute, déplacée dans les commentaires

Quatre commentaires d'en-tête décrivaient encore le code 4 comme « non
applicable **par nature** », alors qu'un `saute` nu produit aussi un 4. Corrigés.

Et un renvoi de `assert.sh` pointait vers une règle **absente** du README §5 —
dont `TASK-011` se prévaut. La règle y est désormais écrite en toutes lettres.

## Tentatives

3 / 5

## Critères d'acceptation

- [x] un saut se déclare avec sa nature — trois fonctions, plus `INDISPO` pour le relais conteneurisé
- [x] ≥ 1 indisponibilité → jamais 0 ni 4 — mesuré sur les quatre fichiers réels
- [x] que des non-applicables → 4 — TASK-011 (13), TASK-012 (2), TASK-013 (2)
- [x] **démon coupé → `tests/run.sh acceptance` en code non nul** — 3 mesuré
- [x] les deux natures affichées séparément
- [x] documenté dans `tests/README.md` §2 et §5
- [x] aucun cas existant ne change de verdict — comparaison directe `master` ↔ branche
- [x] le fichier de cas ne compte aucun échec, son 4 est admis

## Validation finale

PASS

## L'arbitrage des six contrôles de forme

Le point que l'énoncé signalait comme piège. Les six contrôles de forme du diff
de TASK-011, devenus `NON EXÉCUTÉ` après leur commit : nature ou indisponibilité ?

Qualifiés **non applicables par nature**. L'argument : sur un arbre propre,
`git diff HEAD` ne peut plus rien produire — rien n'a manqué, c'est l'**objet**
de la comparaison qui a disparu.

Le relecteur valide l'arbitrage mais **refuse la formulation** : l'analogie
« comme le profil `debian` n'aura jamais systemd » est fausse, `git diff HEAD`
redevenant non vide dès qu'un fichier est modifié sans être commité. Le rédacteur
l'a mesuré plutôt que de le croire, et l'a retirée. C'est une **troisième
catégorie que le harnais ne nomme pas** : sans objet tant que l'arbre est propre.

Le relecteur note en outre que l'arbitrage **ne change rien au scénario démon
coupé** — TASK-011 y compte déjà 12 indisponibilités et sort en 3 dans les deux
cas. Il ne joue que sur le vert nominal.

Trois voies de sortie sont consignées au **point 4 de
`docs/points-en-suspens.md`**, aucune décidée.

## Réserves

- **le faux vert reste ouvert un étage plus bas** : les niveaux `unit` et
  `integration` ne sont pas requalifiés — hors périmètre. Leurs ~70 sauts
  restent en `saute` nu : ils n'affirment plus rien, mais leur nature n'est pas
  établie. Premier candidat à une tâche de suite ;
- **`docker info` sans borne de temps** dans `TASK-002:181`, `TASK-011:145` et
  `TASK-012:589`. Un Docker Desktop *en cours de démarrage* laisse l'appel
  suspendu — constaté, plus de dix minutes. Un fichier de cas peut donc
  suspendre le niveau indéfiniment. Seul le fichier de TASK-013 borne sa sonde à
  `timeout 30` ;
- **`saute` reste le nom court et rend 4** : qui ajoutera un saut sans y penser
  obtiendra le verdict permissif. La règle de prudence est écrite, rien ne la
  force. Fermé dans `TASK-002/011/012`, où plus aucun `saute` nu ne subsiste —
  un saut non qualifié y échouerait bruyamment ;
- **`saute_par_nature` est signataire pour `TASK-011:224`**, le cas des six
  contrôles de forme, dont la documentation dit qu'il est « rangé avec les non
  applicables faute de mieux ». Le nom affirme un peu plus que ce que la doc
  concède. Réserve écrite en trois endroits concordants ;
- **la branche `INDISPO)` du relais n'a jamais été exécutée en vrai** : le
  conteneur a du réseau. Le §9 vérifie *structurellement* que le relais existe ;
  le chemin de bout en bout n'est pas emprunté ;
- `shellcheck` absent de l'hôte : `lint` ne vérifie que la syntaxe. Le passage
  conteneur couvre l'analyse approfondie ;
- le relecteur n'a pas relancé `integration` ni `run-in-container.sh` au
  troisième passage — mesures reprises du passage précédent, inchangées.

## Git

Branche : `agent/TASK-013`.

## Résumé

Le faux vert est fermé, et la preuve n'est pas une déclaration : le même
scénario rend 0 sur `master` et 3 sur la branche, mesuré par le relecteur sur
une extraction indépendante.

Ce qui distingue cette tâche des précédentes, c'est que **les trois tours de
correction ont tous porté sur des affirmations non fondées**, jamais sur du code
en défaut. Une nature affirmée sans avoir été relue ; une sur-affirmation que le
diff avait introduite dans la tâche censée les retirer ; la même faute réfugiée
dans les commentaires.

Le dispositif s'est appliqué à lui-même. Le rédacteur a signalé de lui-même le
défaut déplacé d'un cran plutôt que de le taire ; le relecteur a reconnu que sa
propre formulation de rechange était fausse ; et le rédacteur a trouvé un appel
que le relecteur avait manqué.

Reste ce que la tâche n'a pas couvert et qui est écrit : un étage plus bas,
`unit` et `integration` gardent 70 sauts dont la nature n'est pas établie. Ils
n'affirment plus rien — c'est déjà mieux qu'avant — mais le trou n'est pas
refermé partout.
