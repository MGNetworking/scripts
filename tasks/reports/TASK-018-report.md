# TASK-018 — Rapport d'exécution

## Statut

COMPLETED — **au cinquième tour sur cinq**, après deux verdicts NON CONFORME.

## Objectif

TASK-016 avait supprimé le doublement du `trap ERR` sur `en_megaoctets`. Elle
avait corrigé **un cas là où il y avait un motif** : toute substitution de
commande dont le contenu peut échouer déclenche le trap deux fois, dans le
sous-shell puis pour l'affectation.

La consigne centrale était donc de **recenser avant de corriger**. C'est
exactement ce qui a échoué trois fois de suite.

## L'histoire de cette tâche, parce qu'elle est l'essentiel

| Tour | Ce que le recensement croyait couvrir | Ce qu'il manquait |
|---|---|---|
| 1 | les substitutions de `configure-swap.sh` et `configure-hostname.sh` | `configure-cron.sh` — quatre `$(stat …)` avec la garde `[ -f ]` que la tâche venait de récuser ailleurs |
| 2 | les substitutions contenant une commande externe | **toute fonction rendant sa valeur sur stdout** appelée en substitution nue — dont `fuseau_actuel`, qui rendait 0 malgré l'échec |
| 3 | les six sites nommés par la relecture | `system-info.sh` en entier, plus deux `$(hostname)` et un `wc \| tr` |
| 4 | tout, sauf six sites « hors du périmètre de ce tour » | rien — mais ces six-là étaient un **abandon déguisé**, pas un non-traitement motivé |
| 5 | tout | — |

Chaque tour a élargi ce qu'on croyait être le motif. Ce n'est pas de la
négligence : le motif n'est pas dans `$(stat …)`, ni dans les substitutions
contenant une commande externe. Il est dans **toute affectation** `var="$(…)"`,
y compris quand la substitution est noyée dans une chaîne et qu'aucun
`grep '="\$('` ne la trouve.

## La mesure qui a borné le travail

Trois sondes, en conteneur, faites après le troisième tour :

```bash
set -Eeuo pipefail
trap 'echo "TRAP ligne $LINENO" >&2' ERR
g() { /bin/false; }

f "$(false)"        # position d'argument : AUCUNE ligne, script poursuivi, code 0
v="$(g)"            # affectation        : TROIS lignes, code 1
```

**Seules les affectations doublent.** En position d'argument, la substitution en
échec ne déclenche rien et n'interrompt pas le script : le code d'une commande
simple est celui de la commande, pas de ses arguments. Sans cette borne, on
relève aussi les vingt substitutions en position d'argument de `system-info.sh`,
on ratisse trois fois trop large — et on manque celles qui comptent.

**Et voici pourquoi trois décomptes annoncés se sont révélés faux.** Le nombre de
lignes visibles dépend du **flux** sur lequel le trap écrit. Avec un trap
écrivant sur `stdout`, la même affectation n'en montre qu'une : les autres sont
produites dans le sous-shell, donc **capturées par la substitution elle-même** et
rangées dans la variable. Le trap de `lib/common.sh` écrit sur `stderr` — rien
n'est capturé, tout se voit.

Un décompte de lignes n'est donc jamais un invariant du motif. Il faut le
mesurer, à chaque site. C'est écrit dans le recensement.

## Travail réalisé

**Le recensement**, dans un document dédié :
[`Linux/System/recensement-substitutions.md`](../../Linux/System/recensement-substitutions.md).
**53 affectations**, les sept scripts du domaine, une par une, avec verdict et
raison — **y compris celles qui ne sont pas traitées**. Le relecteur l'a refait
indépendamment et a trouvé les mêmes 53, aux mêmes numéros de ligne.

| Verdict | Nombre |
|---|---|
| traité — contexte de condition ou fonction renseignant une globale | 29 |
| `sans objet` — en-tête de résolution, avant que le trap existe | 14 |
| éteint — `\|\| true` portant sur le pipeline entier | 10 |
| **nu** | **0** |

Le verdict « ouvert » — *forme nue, cause atteignable, hors du périmètre du
tour* — a été **retiré du barème** au cinquième tour. Un périmètre de tour n'est
pas une raison technique : il dit qui n'a pas fait le travail, pas pourquoi il
n'avait pas à être fait. Fermer la catégorie ferme la porte.

**Les corrections**, par fichier :

- `configure-swap.sh` — `dirname`, `df -T`, `df -BM`, `stat`, deux `awk` sur
  `/proc`, `sed` et `tr` d'`en_megaoctets`, `date` de la sauvegarde `fstab` ;
  plus une substitution **supprimée**, la boucle de suffixe rappelant `date` au
  lieu de réutiliser l'horodatage déjà lu ;
- `configure-cron.sh` — les quatre `$(stat …)`, et surtout `nettoyer_temporaire`,
  dont le `return "$code"` armait le `trap ERR` sur **tout** diagnostic
  postérieur, les `die` préexistants compris ;
- `configure-timezone.sh` — les deux lectures de `/etc/timezone`, et la
  réécriture de `fuseau_actuel` ;
- `configure-hostname.sh` — `mktemp`, les deux `$(hostname)`, le `date` de la
  sauvegarde ;
- `system-info.sh` — `nproc`, deux `awk` sur `/proc/meminfo` ;
- `update-system.sh` — `wc` ;
- `configure-logging.sh` — `basename`.

## Le défaut le plus grave, et il n'était pas un doublement

`FUSEAU_ACTUEL="$(fuseau_actuel)"` : la fonction **rendait 0 malgré l'échec**, un
`return 0` final effaçant le code de `tr` ou de `readlink`. `FUSEAU_ACTUEL`
valait donc la chaîne vide, et le script **poursuivait** — il appliquait le
fuseau et comparait à une valeur fausse.

Le testeur l'a trouvé en laissant délibérément six assertions rouges, sans en
neutraliser aucune. Deux tours avaient écarté ce site en écrivant que « la
fonction rend 0 sur toutes ses branches » : c'est précisément ce qui rendait le
défaut invisible.

`fuseau_actuel` renseigne désormais une globale, propage son échec, et distingue
deux traitements — non fatal avant application (`inconnu`, jamais une chaîne
vide), fatal à la vérification : une vérification qui ne peut pas lire l'état
courant ne prouve rien.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `Linux/System/configure-swap.sh` | 8 sites, 1 supprimé, contrôle du répertoire d'accueil |
| `Linux/System/configure-cron.sh` | 4 sites, `nettoyer_temporaire` |
| `Linux/System/configure-timezone.sh` | 2 sites, réécriture de `fuseau_actuel` |
| `Linux/System/configure-hostname.sh` | 4 sites |
| `Linux/System/system-info.sh` | 3 sites |
| `Linux/System/update-system.sh` | 1 site |
| `Linux/System/configure-logging.sh` | 1 site |
| `Linux/System/recensement-substitutions.md` | **créé** — le recensement |
| `Linux/System/README.md` | périmètre réel, renvoi au recensement, corrections |
| `docs/points-en-suspens.md` | §7 traité, §8 ajouté |
| `tests/integration/linux-system.test.sh` | 104 → **597 assertions** |
| `tests/integration/configure-cron.test.sh` | 158 → **194 assertions** |
| `tests/README.md` | les enseignements du motif |

## Commandes exécutées

| Commande | Code |
|---|---|
| `tests/run.sh lint` (hôte) | 0 — **shellcheck absent**, syntaxe seule |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — shellcheck présent, 0 erreur |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | **0** — 597 + 194 vérifications, 0 échec, 12 + 5 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | 0 — 161 vérifications, 0 échec |

## Vérification par mutation

Chaque site remis en forme nue, un par un. Aux quatrième et cinquième tours,
**aucune mutation n'est restée sans effet** — une première dans ce chantier.

| Tour | Sites mutés | Assertions rouges |
|---|---|---|
| 4 | 6 (`hostname` ×2, `nproc`, `awk` ×2, `wc`) | 7 à 14 chacun, 42 ensemble |
| 5 | 7 (`dirname`, `sed`, `tr`, `basename`, `date` ×2, la boucle) | 2 à 6 chacun, 26 ensemble |

Le relecteur a vérifié **par sa propre mutation**, sur une copie hors dépôt, deux
des sept sites du dernier tour : 9 assertions rouges, code 1.

## Erreurs rencontrées

**Deux verdicts NON CONFORME**, tous deux pour le même motif — un fichier
manquant au recensement. Les deux étaient justes.

**Un chiffre annoncé faux, pour la quatrième fois du chantier.** J'avais écrit
dans une consigne que `dirname` en échec produit une ligne `[ERROR]`. Le testeur
a mesuré : **deux**, un `error` puis le `die`. Il ne l'a pas repris de mon
tableau.

**Deux affirmations rendues fausses par notre propre travail.**
`Linux/System/README.md` et `configure-cron.sh` justifiaient l'appel par
`/bin/bash` en écrivant que les scripts sont enregistrés en `100644` — ce que le
commit du bit d'exécution (ADR-0003, décision 11) a rendu faux le 2026-09-02.
`git ls-files -s Linux/System/*.sh` donne sept `100755`. Corrigé aux cinq
endroits ; la justification du `bash` tient toujours, mais pour une autre raison :
un déploiement par copie ou par archive perd le bit.

**Un défaut du testeur, trouvé par ses propres assertions.** Son contrôle de
restitution échouait parce que le script produit sa sauvegarde par `cp -p`, qui
recopie la date de `/etc/hosts` : son `find -newer` ne voyait rien de plus
récent. Le chemin est maintenant lu dans la trace.

## Corrections automatiques

Quatre tours. Le détail est dans le tableau d'histoire ci-dessus.

## Tentatives

**5 / 5.** La limite a été atteinte, et le verdict est tombé conforme au dernier
tour.

## Critères d'acceptation

- [x] aucun échec en substitution ne produit deux fois le message du `trap ERR`
- [x] le motif est corrigé **partout où il apparaît**, pas seulement sur le cas
      connu — 53 sites relevés, 0 en forme nue
- [x] les codes respectent la convention — vérifié dans `en_megaoctets` : `die`
      sans code (donc 1) pour un `sed`/`tr` en échec, `die … 2` pour une taille
      réellement invalide, au même endroit
- [x] aucun comportement fonctionnel modifié, **hors l'exception actée**
- [x] le non-doublement est verrouillé par des assertions qui rougissent sous
      mutation
- [x] aucun site en forme nue avec une cause atteignable sans raison technique
      écrite — critère **ajouté au cinquième tour**, c'est lui qui a fermé les
      sept derniers sites

## Validation finale

PASS

## L'amendement du 2026-09-03

Le contrôle du répertoire d'accueil de `--file` — refus en code 2, avec
`ancetres_traversables` pour différer le seul cas d'ancêtre non traversable — est
une **évolution fonctionnelle**, que l'`out_of_scope` interdisait.

Elle a été **actée par amendement de la tâche** plutôt que retirée, pour une
raison : c'est le relecteur lui-même qui avait demandé son déplacement, la
doctrine du fichier voulant qu'un défaut constatable sans privilège soit reproché
en 2. La retirer aurait défait une correction juste.

**La contrepartie est inscrite, pas tue** : ce contrôle rend inatteignable le cas
« `df -T` en échec sur un répertoire existant », désormais déclaré `NON EXÉCUTÉ`.
Une correction du périmètre voit sa preuve affaiblie par une évolution hors
périmètre. C'est le prix de l'amendement.

Le relecteur a jugé que ce n'était pas une régularisation de complaisance :
l'amendement nomme l'évolution, inscrit sa contrepartie défavorable, resserre
`out_of_scope` sur « la seule exception actée » au lieu de le vider, et **ajoute**
un critère d'acceptation plus dur. Une complaisance aurait allégé les
validations ; c'est l'inverse qui a été fait.

## Réserves

**`shellcheck` est absent de l'hôte.** `tests/run.sh lint` sort en 0 sans avoir
exécuté l'analyse approfondie. La couverture réelle vient du même niveau relancé
en conteneur. C'est l'angle mort de l'hôte, indexé au backlog depuis TASK-002.

**Dix-sept `NON EXÉCUTÉ`**, tous motivés un par un. Aucun ne dit plus « forme nue
conservée, hors du périmètre du tour ». Restent : `df -T` et `df -BM` (rendus
inatteignables par l'évolution actée), les deux `awk` sur `/proc` et le `swapon`
réel (`CAP_SYS_ADMIN`), la seconde lecture `tr` de `configure-timezone.sh`, et
les limites du profil `debian`.

**`update-system.sh:133`** — le `|| true` empêche le doublement mais laisse une
chaîne vide au `[ "$restant" -gt 0 ]` qui suit. Réserve d'une autre nature, versée
au point n° 8 des points en suspens.

**Le relecteur n'a muté que deux des sept sites du dernier tour** ; les cinq
autres reposent sur la mesure du testeur et sur la facture des assertions.

## Git

Branche : `agent/TASK-018`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

Les sept scripts du domaine ne produisent plus de diagnostic doublé, et surtout :
**on sait pourquoi**, site par site, dans un document que le prochain lecteur
n'aura pas à refaire.

Ce qui mérite d'être retenu de cette tâche n'est pas la correction — 29
affectations mises en condition, c'est mécanique. C'est qu'un motif ne se voit
qu'en le cherchant partout, et que trois arbitrages de non-traitement ont été
démentis l'un après l'autre par la même mutation d'une ligne : un binaire
homonyme en tête de `PATH`.

D'où la règle inscrite en tête du recensement, qui vaut au-delà de ce sujet :
**un site est présumé atteignable tant qu'on n'a pas cherché la mutation qui
l'atteint.**
