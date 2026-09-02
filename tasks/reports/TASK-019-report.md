# TASK-019 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

TASK-017 contrôlait la **forme** du chemin donné à `--file`. Elle ne contrôlait
pas ce que ce chemin **désigne** :

- `configure-swap.sh 64M --file /etc/passwd` passait la validation, affichait
  `créer /etc/passwd (64 Mo)`, demandait confirmation, et le `rm -f` de la ligne
  342 **supprimait le fichier** ;
- un répertoire faisait mourir le script sur un `rm: Is a directory` doublé de la
  ligne du `trap ERR`. `--file /` affichait `créer / (64 Mo)`.

## Travail réalisé

`valider_fichier_swap` garde son contrôle de forme, puis enchaîne sur la nature :

| La cible | Traitement |
|---|---|
| lien symbolique | refus, code 2 |
| n'existe pas | acceptée — création, cas nominal |
| existe et n'est pas régulière (répertoire, périphérique, tube, socket, `/`) | refus, code 2, avec le type nommé |
| est un fichier d'échange reconnu | acceptée — redimensionnement, cas nominal |
| existe, régulière, non reconnue | **refus**, code 2, en disant que le fichier serait détruit |
| existe et n'est pas lisible | jugement **différé** — voir plus bas |

**Reconnaissance d'un fichier d'échange**, par deux preuves : `/proc/swaps` pour
un swap actif — même source que `swap_actif()`, déjà présente dans le script — et
la signature `SWAPSPACE2` pour un swap inactif, lue **à l'offset exact**
`pagesize - 10` pour cinq tailles de page. Lire à l'offset plutôt que chercher la
chaîne dans tout l'en-tête évite qu'un fichier la contenant par hasard soit pris
pour un swap. Aucune dépendance ajoutée : `dd`, `tr` et `awk` étaient déjà
employés.

**Deux ajouts non demandés, l'un et l'autre retenus après relecture :**

Le **refus des liens symboliques** — un `rm -f` y détruirait le lien en laissant
la cible occuper le disque, et l'espace annoncé ne serait pas celui qui est
occupé. Le relecteur l'a jugé défendable : le comportement antérieur était
pernicieux.

Un **second appel de validation après `require_root`**, pour le chemin par défaut
`/swapfile`, qui ne passait jamais par la fonction alors que le même `rm -f`
l'attend. Sans lui, `configure-swap.sh 2G` mourait toujours sur le message brut
de `rm` : le critère n'aurait été tenu qu'à moitié. Le relecteur l'a jugé
nécessaire, pas hors périmètre.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `Linux/System/configure-swap.sh` | `est_fichier_swap`, contrôle de nature, second appel, aide |
| `Linux/System/README.md` | les trois natures, méthode de reconnaissance, codes de retour |
| `tests/integration/linux-system.test.sh` | 197 → **335 assertions**, aucune supprimée |
| `tests/README.md` | section « Ce que `--file` refuse » — tenue documentaire, hors `scope` |

## Commandes exécutées

| Commande | Code | Décompte |
|---|---|---|
| `tests/run.sh lint` (hôte) | 0 | 25 fichiers, 0 erreur — **shellcheck absent**, syntaxe seule |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 | shellcheck présent : 0 erreur, 2 avertissements hérités |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | **0** | **335 réussites, 0 échec, 6 NON EXÉCUTÉ** |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | 0 | 161 / 0 / 0 |
| `tests/run.sh acceptance` (hôte) | 0 | TASK-011 : 150 / 0 / 7 |
| `… TASK-011-cas-conteneur.sh swap-fstab` | 0 | **8 PASS, 0 FAIL, 1 SKIP** |

**Mesure de non-régression, faite et non supposée** : le fichier de test de
`master` lancé contre le script de TASK-019 donne 197 réussites, 0 échec.
**Aucune assertion préexistante n'est cassée.**

## Vérification par mutation

| Mutation | Assertions rouges |
|---|---|
| `if ! est_fichier_swap` → `false` — le défaut d'origine | **35**, dont « `/etc/passwd` est intact, au contenu et à l'inode » |
| second appel du préflight supprimé | 7 — tout le groupe 3 ter |
| branche `avant-root` du jugement différé supprimée | 4 — exactement le cas de la régression |
| `[ ! -f "$chemin" ]` → `false` | 3 à 5 — les messages nommant le type |
| offset de la signature décalé | 3 — le cas `mkswap` seul |

**Sous la mutation du défaut d'origine, `/etc/passwd` a réellement été détruit
dans le conteneur**, entraînant au passage quatre assertions de
`configure-logging.sh` par dommage collatéral. C'est la preuve directe que le
contrôle sert à quelque chose.

Cette mutation-là n'était pas dans celles que j'avais demandées : **le testeur
l'a ajoutée de lui-même**, ayant constaté qu'aucune des trois autres ne touchait
les assertions d'intégrité de fichier. Sans elle, rien n'aurait établi qu'elles
ne sont pas creuses.

## Erreurs rencontrées

**Une régression de code de retour**, trouvée par le relecteur. Un appelant
**sans privilège** passant `--file <un fichier d'échange en mode 600>` recevait :

```text
[ERROR] Cible refusée pour --file : « … » n'est pas lisible.      code=2
```

là où `master` rendait **1**. La commande était juste — seul le privilège
manquait. Cela contredisait la convention que TASK-016 venait de graver :
« lancer sans `sudo` rend 1, la commande tapée étant juste ».

La cause : le premier appel de validation a lieu **avant** `require_root`. La
précaution décrite en commentaire n'était appliquée qu'au chemin par défaut.

**Deux pièges d'analyse statique**, rencontrés par le testeur et notés ici parce
qu'ils reviendront. `bash -c '[ -e "$1" ]' _ "$chemin"` déclenche SC2016 —
remplacé par `stat` et `cat` plutôt que par une directive de désactivation. Et le
commentaire expliquant ce remplacement, commençant par `# shellcheck signale…`,
a été lu **comme une directive** (SC1073/SC1072), rendant le fichier non
analysable.

C'est exactement le piège indexé au backlog depuis TASK-011 — « le piège du
commentaire commençant par `shellcheck` » — et le testeur y est retombé. Dans ce
dépôt, aucune ligne de commentaire ne doit commencer par `# shellcheck` sans être
une vraie directive.

## Corrections automatiques

Un tour, sur la régression ci-dessus. `valider_fichier_swap` prend un second
paramètre — `avant-root` ou `apres-root` — et **un seul verdict est différé** :
celui de la cible qui existe et n'est pas lisible. Tous les autres refus restent
rendus à l'analyse des arguments, en 2, avec ou sans `sudo` : les arguments se
vérifient avant les privilèges.

Le cas « lisible mais non reconnu » reste jugé au premier appel, donc en 2 même
sans `sudo`. C'est le bon arbitrage : il s'établit sans privilège, et la commande
tapée est bel et bien fautive.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] un chemin absolu désignant un répertoire est refusé en code 2, avant toute
      confirmation, sans message brut de `rm` — mesuré : exactement 4 lignes,
      toutes `[ERROR]`, aucune ligne `rm:`, aucune ligne `Échec (code …)`
- [x] un fichier régulier non reconnu n'est jamais supprimé — mieux que le
      critère : il est refusé d'emblée. `/etc/passwd` et un fichier jetable
      ressortent intacts, contenu, inode et mtime relevés avant et après
- [x] un fichier d'échange existant reste traité comme avant —
      `remplacer … (64 Mo -> 128 Mo)`, code 0, aucun refus
- [x] un chemin absolu inexistant reste accepté — `créer … (64 Mo)`, code 0
- [x] le refus n'est pas doublé par le `trap ERR` — 0 occurrence de
      `Échec (code` sur les cinq formes de refus
- [x] les refus rougissent sous mutation

## Validation finale

PASS

## Ce que j'avais annoncé et qui était faux

J'avais demandé au testeur d'épingler, sous root, le message « Vérifier les
droits de lecture sur ce chemin » pour une cible en mode 600 non reconnue.
**C'est faux, et il l'a mesuré plutôt que de l'écrire sur ma parole** : root lit
un fichier en 600, `[ ! -r ]` y est donc faux, et c'est la branche ordinaire qui
tranche — `« … » existe et n'est pas un fichier d'échange`, code 2.

Il a essayé quatre montages pour rendre cette branche atteignable sous root —
mode 600, `setpriv --bounding-set`, `capsh --drop`, `capsh --caps=` — tous
mesurés, tous en échec (`id -u` → 0, `[ -r ]` → 0). Le cas est déclaré
`saute_par_nature` avec ces quatre mesures en raison, ce qui fait passer le
bilan de 5 à 6 `NON EXÉCUTÉ`.

Le message n'est pas mort dans l'absolu — NFS `root_squash`, refus MAC — mais
rien de cela n'est à portée du profil `debian`.

## Réserves

**Une assertion n'est pas discriminante et c'est assumé.** « Fichier ordinaire
intact » (cas a) ne rougit sous aucune mutation : ce cas tourne hors conteneur,
donc sans `-y`, et un script régressé s'arrêterait de toute façon à la
confirmation. L'armer aurait signifié qu'un jour de régression, le test lui-même
créerait un swap et compléterait `/etc/fstab` **sur la machine de l'appelant**.
Le discriminant est le cas `/etc/passwd`, gardé `JETABLE`, qui ne tourne qu'en
conteneur — c'est-à-dire systématiquement dans l'environnement de validation.

**Fragilité d'environnement du groupe `swap-fstab`.** Il passe parce que
`/proc/swaps` annonce `/dev/sdc`, nœud absent du conteneur : `truncate` y crée un
fichier ordinaire, reconnu par la branche `/proc/swaps`. Sur un hôte où ce nœud
existerait dans le conteneur, le nouveau contrôle le refuserait comme
périphérique bloc et le groupe rougirait. Le risque naît de cette tâche.

**Non couvert** : les natures spéciales autres que le répertoire — bloc,
caractère, tube nommé, socket ; le comportement sur une architecture à page
différente de 4 Kio, l'offset y étant simulé et non produit par un vrai `mkswap` ;
la création, l'activation et l'inscription réelles, `swapon` exigeant
`CAP_SYS_ADMIN`.

**`est_fichier_swap` ne déséchappe pas `/proc/swaps`.** Un fichier d'échange
actif dont le chemin contient une espace y figure en `\040` et ne sera pas
reconnu par cette branche — il retombera sur la signature, donc sans faux refus.
Défaut **préexistant** dans `swap_actif()`, signalé pour mémoire.

## Changement de comportement, documenté

Un fichier d'échange interrompu entre `fallocate` et `mkswap` est un fichier
ordinaire sans signature : le lancement suivant le refuse en 2 et demande à
l'utilisateur de le supprimer, là où le script le recréait avant.

Le relecteur a vérifié que le cas est **plus étroit qu'annoncé** : le
`trap nettoyer_fichier_incomplet EXIT`, posé avant `fallocate`, efface déjà le
fichier sur toute sortie ordinaire, `die` et `trap ERR` compris. Le résidu ne
survit qu'à un `SIGKILL`, un plantage ou une coupure de courant. Documenté dans
`Linux/System/README.md`.

## Git

Branche : `agent/TASK-019`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

`configure-swap.sh` ne détruit plus ce qu'il ne reconnaît pas. Un fichier
ordinaire, un répertoire, `/`, un lien symbolique sont refusés en code 2 avant
toute confirmation ; un chemin inexistant et un fichier d'échange existant
passent comme avant.

Deux moments de cette tâche méritent d'être retenus, et ils vont dans le même
sens. Le testeur a ajouté une mutation que je n'avais pas demandée, et c'est la
seule qui prouvait quelque chose. Puis il a mesuré une affirmation que j'avais
écrite dans sa consigne, l'a trouvée fausse, et a refusé de l'épingler — en
donnant les quatre mesures qui l'établissent.

Un sous-agent qui contredit son donneur d'ordre avec des mesures à l'appui est
précisément ce qu'on attend de ce dispositif.
