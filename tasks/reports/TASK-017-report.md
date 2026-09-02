# TASK-017 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

`--file` acceptait n'importe quelle chaîne non vide comme chemin. Deux
conséquences : il avalait l'option qui le suivait, et il acceptait un chemin
relatif — avec `SRV_SWAP_SIZE` défini dans `server.env`, un fichier d'échange
serait né dans le répertoire courant.

## Travail réalisé

Une fonction `valider_fichier_swap`, appelée depuis la branche `--file` juste
après le contrôle de valeur vide existant. Un `case` en Bash pur, dont l'ordre
des motifs fait les deux contrôles :

| Motif | Traitement |
|---|---|
| `-*` | refus, code 2 — « une valeur commençant par un tiret est une option, pas un chemin » |
| `/*` | accepté |
| tout le reste | refus du chemin relatif, code 2 |

Elle affecte `FICHIER_SWAP` en fin de parcours plutôt que d'écrire sur `stdout` :
c'est le motif de `valider_horaire` dans `configure-cron.sh`, et celui adopté
pour `en_megaoctets` par TASK-016. C'est ce qui évite que le refus soit doublé
par le `trap ERR`.

**Le message de `--file` sans valeur a été délibérément laissé intact.** Le
rédacteur avait d'abord écrit « --file attend un chemin absolu. », puis est
revenu en arrière : une assertion existante porte sur la chaîne exacte, et la
modifier aurait fait rougir un test hors de son périmètre. La contrainte
d'absolu est dite ailleurs — aide, README, messages de refus.

**Effet de bord favorable** : le refus se produit pendant le parsing, donc avant
`afficher_etat`. Contrairement au cas `configure-swap.sh abc` signalé comme
incohérent dans le rapport de TASK-016, ces deux refus n'affichent pas seize
lignes d'état avant le diagnostic.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `Linux/System/configure-swap.sh` | `valider_fichier_swap`, aide |
| `Linux/System/README.md` | contrainte de chemin absolu, exemples de refus, bloc « Risques » |
| `tests/integration/linux-system.test.sh` | 162 → 197 assertions, aucune supprimée |

## Commandes exécutées

| Commande | Code |
|---|---|
| `tests/run.sh lint` (hôte) | 0 — **shellcheck absent**, seul `bash -n` a tourné |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — shellcheck présent : 0 erreur, 2 avertissements sur les Synology hérités, préexistants |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | **0** — 197 vérifications, 0 échec, 5 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | 0 — 161 vérifications, 0 échec |
| `tests/run.sh acceptance` (hôte, 11 conteneurs) | 0 — 150 vérifications, 0 échec |

**Réserve sur la commande littérale du champ `validation`.** `tests/run.sh lint`
sort en 0 sur l'hôte, mais n'y prouve que la syntaxe. La couverture réelle vient
du même niveau relancé **en conteneur**, où shellcheck est présent. C'est
l'angle mort de l'hôte déjà indexé au backlog.

## Vérification par mutation

Menée par le testeur, puis **indépendamment par le relecteur** sur une copie hors
dépôt.

| Mutation | Assertions rouges |
|---|---|
| validation entièrement retirée | 12 |
| branche `-*` neutralisée seule | 2 à 6 — uniquement celles du tiret |
| branche `/*` et `*` neutralisées | 6 — uniquement celles du relatif |
| fonction remise en substitution de commande | 8 — la ligne du trap réapparaît, et `FICHIER_SWAP` devient vide |

Les deux refus sont verrouillés **indépendamment** l'un de l'autre.

## Erreurs rencontrées

**La note du rédacteur sur le décompte de lignes était fausse.** Il annonçait
trois lignes `[ERROR]` pour les deux refus. Mesuré par le testeur, puis vérifié
une seconde fois par le relecteur : **quatre** pour le refus du tiret (trois
`error` puis le `die`), **trois** pour le refus du relatif. Les assertions
portent les valeurs mesurées, pas celles annoncées.

C'est le genre de chiffre qu'on recopie sans mesurer. Deux vérifications
indépendantes ont été nécessaires pour l'établir.

**Une assertion rouge pendant la rédaction des tests**, corrigée : le premier
relevé de répertoire employait `ls -a`, que shellcheck refuse (SC2012).
`tests/run.sh lint` en conteneur puis `acceptance` sont sortis en 1. Remplacé par
`find -printf`.

## Corrections automatiques

Une, après relecture : deux commentaires du fichier de tests **surestimaient ce
qu'ils prouvent**. Le testeur avait écrit « C'EST L'ASSERTION QUI MANQUAIT » à
propos du cas `2G --file /swapfile --dry-run`. Le relecteur a extrait
`configure-swap.sh` de `master` et l'a exécuté : ce cas y donnait **déjà**
`Mode --dry-run` et le code 0. L'ancien code ne consommait qu'un seul jeton ; le
défaut n'apparaissait que lorsque l'option **était** la valeur.

Ces deux cas sont donc des gardes de non-régression, pas la démonstration du
correctif — celle-ci est portée par le cas 5a. Les commentaires le disent
maintenant, en toutes lettres, pour qu'on ne s'y fie pas à tort.

Correction faite directement : le relecteur avait nommé les deux blocs et la
formulation exacte, et il ne s'agissait d'aucune assertion.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] `--file` suivi d'une valeur commençant par un tiret est refusé en code 2,
      avec un message nommant la valeur
- [x] `--dry-run` et `-y` ne sont plus consommés par `--file` — voir la réserve
      sur la portée de ces assertions
- [x] `--file` suivi d'un chemin relatif est refusé en code 2
- [x] un chemin absolu reste accepté, comportement nominal inchangé
- [x] aucun message du `trap ERR` ne s'ajoute à ces refus — aucune ligne
      `Échec (code …)`, aucun message brut de `dirname:`
- [x] les trois refus rougissent sous mutation, indépendamment

## Validation finale

PASS

## Le cas grave est-il fermé ?

Oui, mais **pas par l'assertion qu'on croirait**. Le testeur l'a signalé de
lui-même et le relecteur l'a confirmé : l'assertion « aucun fichier créé dans le
répertoire courant » **ne peut pas rougir**. Si la contrainte de chemin absolu
tombe, le script crée bien `./2G`, puis son propre
`trap nettoyer_fichier_incomplet EXIT` l'efface quand `swapon` échoue. Le relevé
après coup reste vert.

C'est exactement la même protection accidentelle que l'ancien garde-fou
`dirname` — elle disparaîtrait sur une machine où `swapon` réussit.

Ce qui ferme réellement le cas, sous mutation : `assert_code 2` et l'absence
d'`Opérations prévues`. Les deux assertions insensibles sont redondantes, pas
trompeuses, et leur limite est écrite dans le fichier de test.

## Réserves

**Deux assertions gardent une non-régression sans démontrer le correctif** —
celles du `--dry-run` et du groupe `-y`. Documenté sur place après relecture.

**L'activation réelle du swap n'est pas éprouvée.** `swapon` exige
`CAP_SYS_ADMIN`, refusé au conteneur. Le groupe 3 bis parcourt tout le chemin
jusqu'à `swapon` et s'arrête là. Un `assert_code 1` y a été posé en garde : si ce
code passait un jour à 0, le swap aurait été réellement activé et le saut du
groupe 5 aurait cessé d'être vrai.

**`FICHIER_SWAP` n'est jamais contrôlé non vide après validation.** La mutation
« retour en substitution » l'a révélé : la variable reste vide et le script
poursuit sur un chemin vide (`dirname ""` → `.`) jusqu'à `fallocate`. Le motif
« variable globale + appel hors substitution » n'a aucun filet propre ; seules
les assertions de contenu le voient.

**Non couvert, hors critères** : valeur contenant des espaces ou finissant par
`/`, répertoire parent inexistant, `--file` sur btrfs ou ZFS.

**`tests/README.md` est en retard** sur la couverture réelle : il décrit les
groupes « 1 bis » et « 1 ter » de TASK-016 mais ignore la section 5 et le groupe
3 bis. Hors `scope`, non touché.

## Ce que la tâche a révélé, sans le corriger

**`--file` ne contrôle que la forme du chemin, jamais ce qu'il désigne.** Porté
en **TASK-019**, et c'est le défaut le plus sérieux trouvé jusqu'ici :

```bash
rm -f "$FICHIER_SWAP"        # ligne 342
```

`configure-swap.sh 64M --file /etc/passwd` passe la validation, affiche
`créer /etc/passwd (64 Mo)`, demande confirmation, et **supprime le fichier**.
L'utilisateur n'est pas aveugle — la cible est annoncée — mais c'est une
destruction de données derrière un simple oui.

Un cas mineur du même mécanisme : un chemin absolu désignant un **répertoire**
fait mourir le script sur un `rm: Is a directory` doublé de la ligne du trap.
Rien n'est détruit, le `rm -f` n'étant pas récursif. `--file /` affiche
`créer / (64 Mo)`.

Le relecteur a écarté le rattachement à TASK-018 : là-bas la cause est le trap
sur les substitutions de commande ; ici c'est **une validation absente**, et
corriger le trap ne ferait que rendre le message plus propre sans empêcher la
suppression.

**Le doublement du trap subsiste bien ailleurs**, comme prévu :
`--file /nope/x` produit toujours deux fois
`[ERROR] Échec (code 1) à la ligne 247` — la substitution `df`. C'est l'objet de
TASK-018, laissé intact ici.

## Git

Branche : `agent/TASK-017`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

`--file` ne se laisse plus donner n'importe quoi : une option est refusée comme
telle, un chemin relatif aussi, et le refus arrive avant que le script n'ait
affiché quoi que ce soit.

Le plus instructif n'est pas la correction, qui tient en un `case`. C'est que
deux vérifications indépendantes aient été nécessaires pour établir un simple
décompte de lignes, et qu'elles aient toutes deux conclu que la note du rédacteur
était fausse. Et c'est que le relecteur, en cherchant la portée réelle de deux
assertions, soit tombé sur un `rm -f` capable d'effacer `/etc/passwd`.
