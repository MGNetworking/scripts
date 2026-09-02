# TASK-015 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Trancher et mettre en œuvre trois défauts de `lib/common.sh` révélés par les
tests unitaires de TASK-003. Les arbitrages avaient été laissés ouverts : ils
ont été tranchés le 2026-09-02 par
[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md),
décisions 7 à 9. Cette tâche n'a donc rien arbitré — elle a mis en œuvre.

## Travail réalisé

**1. `load_config` exporte** (décision 7). Le `source` est encadré par
`set -a` / `set +a`. L'état antérieur d'`allexport` est relevé par
`case "$-" in *a*)` et rétabli tel quel, plutôt que forcé à « off » : un appelant
qui l'aurait activé lui-même le retrouve intact.

Le `source` est placé en contexte de condition (`|| code=$?`) pour que `set +a`
soit atteint quoi qu'il arrive. Sans cette précaution, tout ce que le script
déclare ensuite serait exporté à son insu.

**2. Un journal inaccessible n'interrompt plus le script** (décision 8).
L'écriture est extraite dans `_journaliser`, enveloppée dans un `if` — ce qui
neutralise `set -e` — avec la redirection portant sur le **groupe** et non sur le
`printf`, afin que `stderr` soit déjà détournée quand bash tente d'ouvrir le
fichier. C'est ce qui étouffe son message brut.

En cas d'échec, `_journal_hors_service` vide `LOG_FILE` — la convention déjà en
vigueur dans le socle pour « pas de journal » — et avertit une seule fois.
`run_logged` et `enable_full_logging` respectant cette convention, ils cessent
d'eux-mêmes d'utiliser un fichier mort.

**3. Le `trap ERR` nomme le fichier réellement fautif** (décision 9).
`${BASH_SOURCE[0]}` est évalué **dans la chaîne du trap**, jamais à l'intérieur
de `_on_error` — où il désignerait `common.sh`, le fichier de définition.

**4. Documentation.** `docs/architecture-technique.md` reçoit le contrat effectif
du socle et un nouveau §6 sur les codes de retour ; `config/README.md` précise
que les affectations nues atteignent désormais les fils ; `tests/README.md` cesse
de décrire les deux défauts comme « relevés, non corrigés ».

**5. Tests.** 103 → **161 assertions**. L'assertion `FILS_NUE=absente`, qui
épinglait l'ancien comportement, est retournée dans le même commit.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `lib/common.sh` | les trois corrections — zone protégée, autorisée par cette tâche |
| `tests/unit/common.test.sh` | +58 assertions, 1 retournée |
| `docs/architecture-technique.md` | contrat du socle, nouveau §6 codes de retour |
| `config/README.md` | conséquence du `set -a` |
| `tests/README.md` | hors du `scope` littéral — voir « Écarts de périmètre » |
| `tasks/backlog.md` | deux entrées transverses issues de cette tâche |

Aucun des sept scripts chargeant le socle n'a été modifié. C'était le critère :
s'ils avaient dû changer, la correction aurait été mauvaise.

## Commandes exécutées

| Commande | Code |
|---|---|
| `tests/run.sh lint` (hôte) | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` (shellcheck présent) | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | **0** — 161 réussites, 0 échec, 0 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — 104 vérifications |
| `tests/env/run-in-container.sh -- bash -c 'for s in Linux/System/*.sh; do "$s" --help; done'` | 0 — 7 scripts |
| `tests/run.sh acceptance` (hôte) | 0 |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | PASS — avec réserve : `shellcheck` absent de l'hôte, seule la syntaxe y est prouvée. L'analyse approfondie a été lancée séparément **en conteneur**, où `shellcheck` est présent : code 0 |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | PASS |
| `--help` des scripts `Linux/System` | PASS |
| `tests/run.sh acceptance` | PASS |

## Vérification par mutation

Huit mutations de `lib/common.sh`, chacune devant faire rougir au moins une
assertion :

| Mutation | Assertions rouges |
|---|---|
| `set -a` retiré | 1 |
| `set +a` retiré | 4 |
| `_JOURNAL_AVERTI` retiré | 2 |
| `$0` rétabli dans le `trap` | 2 |
| `2>/dev/null` déplacé sur le `printf` | 3 |
| garde `if` retirée de `_journaliser` | 17 |
| `PIPESTATUS[0]` → `$?` | 2 |
| `\|\| code=$?` retiré de `load_config` | **11** |

`lib/common.sh` a été restauré après chaque mutation, vérifié par empreinte et
par `git diff`.

## Erreurs rencontrées

**Une régression de couverture, trouvée et fermée par le testeur lui-même.** Les
deux cas dits « discriminants » de `run_logged` faisaient échouer `tee` pour
prouver que la fonction rend bien `PIPESTATUS[0]`. Or `run_logged` appelle
désormais `info` en premier, qui constate le journal mort et vide `LOG_FILE` :
`tee` n'était plus atteint, et ces assertions restaient vertes **sans plus rien
prouver**. Contre-épreuve, sous mutation `PIPESTATUS[0]` → `$?` :

```text
ANCIENNE formulation, cmd 42 (attendu CODE=42) : CODE=42   <- verte, ne prouve rien
NOUVELLE formulation, cmd 42 (attendu CODE=42) : CODE=1    <- rouge
```

Remplacée par un faux `tee` en tête de `PATH`, plus quatre gardes vérifiant que
la branche à `tee` est bien empruntée.

**Une affirmation fausse dans la documentation**, trouvée par le relecteur.
`docs/architecture-technique.md` annonçait : « Un fichier présent mais dont le
chargement échoue arrête le script de la même façon. » Mesuré en conteneur, avec
un `.env` contenant `A=1`, une commande absente, puis `B=2` :

| Socle | Comportement |
|---|---|
| `master` (`. "$fichier"` nu) | script tué, code **127** |
| cette branche | `Configuration chargée`, `A=1 B=2`, code **0** |

Le `|| code=$?` suspend `errexit` **à l'intérieur** du fichier sourcé : le
`source` va au bout et rend le code de sa dernière commande. La garde
`die "Configuration illisible"` ne joue donc que sur une erreur de **syntaxe**.

C'est la contrepartie assumée du `set +a` garanti — le relecteur a éprouvé
l'alternative `local -`, qui produit un `pop_var_context` de bash sur le chemin
d'abandon et n'est pas meilleure. Ce qui n'était pas acceptable, c'est que la
documentation prétende le contraire.

## Corrections automatiques

Un tour, sur l'écart documentaire ci-dessus. `docs/architecture-technique.md` dit
maintenant ce qui est vrai, et la même mise en garde figure en commentaire de
`load_config` — un lecteur du code apprend la limite sans ouvrir la doc.

Ce comportement était documenté sans être épinglé. Un cas de neuf assertions l'a
donc figé : sans lui, quelqu'un qui « corrigerait » un jour le `|| code=$?` pour
rétablir la sévérité casserait la garantie du `set +a` **en silence**. La
mutation le confirme dans les deux sens : elle fait tomber les 7 assertions du
nouveau cas *et* les 4 du chemin `bancale.env`.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] `load_config` rend ses variables visibles d'un processus fils, pour un
      `.env` écrit en affectations nues
- [x] `set +a` est rétabli même lorsque le `source` du fichier échoue — avec une
      exception mesurée, voir « Réserves »
- [x] un journal devenu inécrivable n'interrompt plus le script : un
      avertissement sur `stderr`, une seule fois, puis l'exécution se poursuit
- [x] le message du `trap ERR` nomme le fichier réellement fautif, y compris
      quand l'échec vient de `lib/common.sh`
- [x] `tests/run.sh unit` sort en 0 après correction
- [x] les assertions qui épinglaient l'ancien comportement sont retournées dans
      le même commit
- [x] les scripts du dépôt sont revalidés — `--help` et niveau `integration`
- [x] la documentation reflète le contrat effectif du socle

## Validation finale

PASS

## Écarts de périmètre

`tests/README.md` n'est pas dans le `scope` littéral de la tâche. Sa
modification était nécessaire — le fichier décrivait les deux défauts comme
« relevés, non corrigés » — et `AGENTS.md` §11 impose la documentation dans le
même commit. Zone libre, mais l'écart est tracé ici plutôt que constaté après
coup.

`tasks/completed/TASK-003.md`, pourtant autorisé, n'a pas été touché : son
critère « `load_config` … exporte ses variables » devient exact sans retouche.

## Réserves

**`set +a` n'est pas rétabli quand le `source` avorte le shell.** Un `.env`
référençant une variable non définie sous `set -u` tue le shell avant `set +a` :
le piège `EXIT` s'exécute alors avec `allexport` armé. Le critère tient pour les
échecs qui *rendent un code*, pas pour ceux qui *tuent le shell*. Exposition
limitée aux variables déclarées dans un handler de nettoyage. Porté au backlog.

**Asymétrie `server.env` / `load_config`.** `lib/common.sh` charge
`config/server.env` par un `source` nu, sans `set -a`, alors que `load_config`
exporte désormais. Deux fichiers écrits selon la même convention n'ont plus le
même effet. Sans conséquence aujourd'hui — tous les `SRV_*` sont lus par le
script lui-même — mais c'est un piège pour la suite. Hors périmètre, porté au
backlog.

**`enable_full_logging` reste sans couverture.** Hors périmètre, explicitement
exclu par l'`out_of_scope`. Il teste `LOG_FILE` à l'appel puis installe
`exec > >(tee -a …)` : si le journal meurt ensuite, l'échec se produit dans la
substitution de processus, hors de portée de `_journaliser`. Rien ne dit ce qui
se passe alors.

**Ce qui n'a pas pu être éprouvé.** L'inécrivabilité par droits modifiés — le
conteneur tourne en `root`, qui contourne les permissions ; seul « répertoire
disparu » est couvert. Le disque plein non plus. Et le comportement sur un
serveur réel n'est éprouvé que par simulation.

## Git

Branche : `agent/TASK-015`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

Le socle tient un contrat plus clair qu'avant : la configuration atteint les
processus fils, un journal perdu ne tue plus un script d'administration, et un
message d'erreur ne désigne plus le mauvais fichier.

Deux choses méritent d'être retenues au-delà du résultat. Le testeur a fermé
lui-même une régression de couverture qu'il aurait pu laisser passer sans que
rien ne devienne rouge — c'est le contraire d'un affaiblissement. Et le relecteur
a trouvé une documentation qui affirmait le contraire de ce que le code fait :
défaut invisible aux tests, puisque les tests ne lisent pas la prose.

Le cycle complet a donc payé une fois de plus, sur une tâche qui touchait le
fichier le plus chargé du dépôt.
