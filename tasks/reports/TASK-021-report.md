# TASK-021 — Rapport d'exécution

## Statut

COMPLETED — **cycle léger** (ADR-0003, décision 5) : `check-disk.sh` est en
lecture seule, il n'écrit rien sur le système. Rédacteur, testeur, validations,
sans relecteur.

## Objectif

Écrire `Linux/System/check-disk.sh` — plan §1 : « diagnostic de `df`, partitions,
inodes et répertoires consommateurs ».

Contrat particulier de ce script : **lecture seule stricte**, aucun privilège, et
**code 0 même quand une information manque**. Un script de diagnostic qui meurt
parce que `df` a échoué ne rend aucun service.

## Ce que le script produit

Cinq blocs, à la mise en page de `system-info.sh` :

| Bloc | Source | Repli |
|---|---|---|
| paramètres et **leur origine** | — | — |
| systèmes de fichiers | `df -P -T -h` | « non disponible » |
| inodes | `df -P -T -i -h` | « ne déclare pas d'inodes » |
| périphériques | `lsblk` | `/proc/partitions` |
| répertoires consommateurs | `du` | section sautée |

Chaque paramètre est affiché **avec son origine** — `valeur par défaut`,
`config/server.env`, `ligne de commande` — pour qu'un seuil surprenant se
retrouve sans chercher.

## Le seuil, et pourquoi 85 %

Un seuil unique, appliqué aux blocs **comme aux inodes**, en comparaison
« atteint » (`-ge`) et non « dépasse ». Trois raisons, écrites dans le script et
dans le README :

- **il laisse de quoi travailler** : 15 % d'une racine de 40 Go font 6 Go, soit
  une mise à jour de paquets ou une image de conteneur d'avance ;
- **la dégradation précède le 100 % de `df`** : ext4 réserve 5 % des blocs à
  root, et son allocateur se fragmente nettement au-delà de ~85 % ;
- **plus bas, le signal devient du bruit** : un serveur sain vit entre 70 et
  80 %, et une alerte qui se déclenche à chaque passage n'est plus lue.

Le même seuil vaut pour les inodes, faute d'une raison de les traiter autrement —
et la panne y est plus déroutante : `No space left on device` avec 60 % d'espace
libre. Surchargeable par `SRV_DISK_SEUIL` puis `--seuil`.

## Le défaut de conception corrigé en cours de route

Le testeur a relevé une **asymétrie** que le rédacteur avait introduite en
appliquant son propre raisonnement à moitié. Il avait écrit qu'une valeur héritée
de `config/server.env` « ne reproche rien à la commande tapée » — et ne
l'appliquait qu'au répertoire :

| Valeur fautive venue de `server.env` | Avant | Après |
|---|---|---|
| `SRV_DISK_REPERTOIRE=/pas/la` | `[WARN]`, code 0 | inchangé |
| `SRV_DISK_SEUIL=abc` | **`[ERROR]`, code 2** | `[WARN]`, repli sur 85 %, **code 0** |

Un `server.env` mal saisi privait l'appelant de **tout** le diagnostic à cause du
seuil, mais pas à cause du répertoire.

**Tranché : un script de diagnostic doit toujours diagnostiquer.** Priver
quelqu'un de son tableau de disques parce qu'une variable de configuration est
mal saisie est disproportionné — d'autant qu'il ne l'a peut-être pas écrite, et
n'a peut-être pas le droit de la corriger. La règle ne dépend plus que de
l'**origine** :

```text
ligne de commande fautive  ->  [ERROR], code 2   (l'appelant s'est trompé en tapant)
config/server.env fautif   ->  [WARN], repli, 0  (la ligne de commande est juste)
```

Mesuré :

```text
[WARN] « abc » (config/server.env, SRV_DISK_SEUIL) n'est pas un entier :
[WARN] repli sur le seuil par défaut, 85 %.
  Seuil d'alerte         85 % (valeur par défaut, SRV_DISK_SEUIL refusé)
  …tableau produit normalement…                                      code 0
```

Second défaut corrigé : `section_peripheriques` affichait « aucun périphérique
bloc visible » **aussi bien** quand `awk` avait échoué que quand la table était
réellement vide. C'était le seul endroit du script où une ignorance était
présentée comme un constat. Un drapeau `lue` sépare désormais les deux.

## Ce que le testeur a trouvé dans ses propres assertions

**Deux de ses assertions étaient creuses**, et il les a trouvées en mutant :

- `assert_contient "$(montages…)" "/"` ne prouvait rien — `/` est une
  sous-chaîne de **tout** point de montage. La mutation qui ajoute `overlay` aux
  pseudo-systèmes filtrés laissait le test vert. **Le piège que la tâche nomme —
  un tableau vide en conteneur — n'était donc pas couvert** avant qu'il ne le
  corrige par une comparaison de ligne entière ;
- une garde du script (`[ -n "$POURCENTAGE_NUMERIQUE" ]`) n'était atteinte par
  aucun jeu de données : sa suppression ne faisait rougir personne. Il a ajouté
  un faux `df` écrivant `-` dans la colonne `Use%`, ce que font ZFS et certains
  FUSE.

## Vérification par mutation

Seize mutations. **Les six dernières vont par paires opposées** — chaque
correction est éprouvée dans les deux sens, ce qui interdit de la « simplifier »
d'un côté ou de l'autre :

| Paire | Mutation | Rouges |
|---|---|---|
| M10 / M11 | le drapeau `lue` neutralisé / les deux issues fondues | 2 / 1 |
| M12 / M13 | le seuil de configuration refusé de nouveau / le seuil de ligne de commande replié | 15 / 15 |
| M14 / M15 | le contrôle du tiret appliqué partout / supprimé | 12 / 2 |

Plus, au tour précédent : `df` décidant sur le code au lieu du vide (5), `-ge`
devenu `-gt` (2), `overlay` filtré (5), validation déplacée après l'affichage
(5), `du` décidant sur le code (3), `die` sans code (2), garde des inodes réduite
(12).

`check-disk.sh` est resté intact — SHA-256 identique avant et après, vérifié par
`cmp` dans le conteneur à chaque tour.

## Fichiers

| Fichier | Nature |
|---|---|
| `Linux/System/check-disk.sh` | **créé** |
| `tests/integration/linux-system.test.sh` | 597 → **922 assertions**, groupe « 2 bis » |
| `Linux/System/README.md` | tableau des scripts, usage, section sur les seuils |
| `README.md` | ligne du script |
| `config/server.env.example` | `SRV_DISK_SEUIL`, `SRV_DISK_REPERTOIRE` |
| `docs/points-en-suspens.md` | §10 |

## Commandes exécutées

| Commande | Code |
|---|---|
| `tests/run.sh lint` | **0** |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | **0** |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | **0** — 922 + 194 vérifications, 0 échec |
| `tests/env/run-in-container.sh -- bash Linux/System/check-disk.sh` | **0** |
| `tests/env/run-in-container.sh -- bash Linux/System/check-disk.sh --help` | **0** |
| `tests/env/run-in-container.sh -- tests/run.sh lint unit integration environment` | **0** — 4 niveaux verts |

## Tentatives

1 / 5

## Critères d'acceptation

- [x] le script affiche systèmes de fichiers, inodes, périphériques et
      répertoires consommateurs
- [x] **lecture seule prouvée** — empreinte de tout `/etc` avant et après, plus
      un `find -newer` couvrant les quelque quarante exécutions du groupe, stubs
      et exécution sans privilège comprises
- [x] **code 0 sous n'importe quelle commande défaillante** — `df`, `du`,
      `lsblk`, `lsblk` absent, `awk`, `sort`, un par un, chaque fois avec un
      `[WARN]` nommant la cause et **aucune ligne `Échec (code …)`**
- [x] le tableau n'est pas vide en conteneur — `overlay` nommément, plus
      l'appartenance **exacte** de `/`
- [x] refus en 2 sur valeur fautive de **ligne de commande**, sans qu'aucune
      sortie de diagnostic ait été produite avant
- [x] seuil surchargeable, origine affichée, comparaison en « atteint »
- [x] idempotence — trois exécutions, même empreinte, même liste de montages

## Validation finale

PASS

## Écarts de périmètre

Le `scope` nommait `tests/integration/check-disk.test.sh` ; les assertions sont
allées dans `linux-system.test.sh`, sur ma consigne. Raison : ce fichier couvre
déjà les scripts du domaine et porte les outils que le nouveau groupe réemploie
— `dry_run_inoffensif`, `empreinte_fichier`, `lancer_depuis`, les décomptes de
lignes. Un fichier séparé les aurait dupliqués. C'est ma décision, pas un écart
du testeur.

`README.md` racine, `config/server.env.example` et `docs/points-en-suspens.md`
sont hors `scope` littéral : les deux premiers sont imposés par `CLAUDE.md`
(documenter dans le même commit), le troisième est le réceptacle prévu.

## Réserves

**La surcharge par un `config/server.env` réellement écrit n'est pas éprouvée.**
Les cas passent `SRV_DISK_SEUIL` et `SRV_DISK_REPERTOIRE` par l'environnement —
même variable exportée, `set -a` de `lib/common.sh` — mais **le chargement du
fichier n'est pas emprunté**. L'écrire supposerait de créer `config/server.env`
dans le dépôt monté, qui n'est pas un système jetable.

**Un système de fichiers réellement au-delà du seuil n'est pas atteignable** :
l'occupation de la racine du conteneur est celle de l'hôte. Le franchissement
n'est prouvé que par stub.

**Une erreur arithmétique reste invisible au contrat « code 0 ».** Le testeur l'a
mesuré : `[ "" -ge 85 ]` déverse `integer expression expected` sur `stderr` et le
script sort **quand même en 0**, l'expression étant en position de condition. Ni
`assert_code 0` ni le décompte `[ERROR]` ne le voient — seul l'invariant « aucun
message brut de bash » l'attrape. Le contrat de dégradation est donc robuste au
point de pouvoir masquer une faute, et c'est cet invariant qui le rend visible.

**`shellcheck` est absent de l'hôte.** Un premier `lint` y était passé alors que
le conteneur relevait un `SC2016` sur un stub. Seul le conteneur voit ce type
d'écart.

**Dette de tenue, à solder en fin de domaine** :
`Linux/System/recensement-substitutions.md` se dit exhaustif et ne couvre que
sept scripts ; `check-disk.sh` est le huitième, cinq autres arrivent. Le README
le signale. Je le reprendrai **une fois**, quand le domaine sera complet, plutôt
que six.

## Git

Branche : `agent/TASK-021`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

Le premier des trois scripts de diagnostic du domaine est écrit, et il tient le
contrat qui les définit tous : il dégrade au lieu de mourir, il dit d'où viennent
ses valeurs, et il sort en 0 même quand la moitié de ses sources manquent.

Le cycle léger a fonctionné comme prévu — pas de relecteur pour un script qui
n'écrit rien. Mais il n'a rien enlevé à la preuve : c'est le **testeur** qui a
trouvé le défaut de conception le plus sérieux, une asymétrie de traitement selon
l'origine d'une valeur, et qui a découvert que deux de ses propres assertions ne
prouvaient rien. La mutation reste le seul outil qui distingue une assertion
verte d'une assertion utile.
