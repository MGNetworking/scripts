---
id: TASK-037
title: "Écrire Docker/Cleanup/docker-cleanup.sh"
status: in_progress
priority: high
depends_on:
  - TASK-034
environment: container-debian
agent: deepseek
human_approval_required: true
objective: |
  Livrer l'orchestrateur de nettoyage des ressources Docker inutilisées. Il
  énumère d'abord, par catégorie et avec l'espace récupérable, ce qu'il
  supprimerait ; il ne supprime qu'après confirmation explicite ; il n'emporte
  jamais un volume par défaut, jamais une ressource en cours d'utilisation,
  jamais un réseau d'infrastructure déclaré en configuration ; et il laisse un
  journal de ce qu'il a réellement supprimé.
scope:
  - Docker/Cleanup/docker-cleanup.sh
  - tests/integration/docker-cleanup.test.sh
  - config/server.env.example — la variable listant les réseaux d'infrastructure protégés
out_of_scope:
  - le branchement de la notification d'échec — notify-failure.sh n'existe pas encore (TASK-024) ; l'appel se fera dans une tâche distincte
  - les quatre scripts de nettoyage spécialisés — cleanup-images.sh, cleanup-containers.sh, cleanup-networks.sh, cleanup-volumes.sh — que la section 10 du plan prévoit séparément
  - toute suppression de conteneur, d'image, de réseau ou de volume EN COURS D'UTILISATION, quelle que soit l'option passée
  - toute suppression dans /var/lib/docker par le système de fichiers — le script passe par le démon, jamais par rm
  - la suppression des journaux de conteneurs et la rotation des logs — c'est configure-docker.sh, tâche du lot A
  - une liste d'images protégées par nom ou par étiquette — la protection nommée porte sur les réseaux, pas sur les images
  - la planification du nettoyage dans /etc/cron.d — c'est configure-cron.sh, et la ligne y est vérifiée au caractère près
  - le nom d'une application, d'un reverse proxy ou d'une base de données, où que ce soit dans le script, son fichier de cas ou sa documentation
  - l'ajout d'un paquet à l'image de test
  - toute opération Docker réelle pendant les validations, et toute suppression réelle
acceptance_criteria:
  - sans --dry-run et sans --yes, aucune suppression n'a lieu avant une confirmation explicite qui rappelle les totaux par catégorie
  - --dry-run énumère par catégorie — conteneurs arrêtés, réseaux inutilisés, images inutilisées, volumes inutilisés — le nombre d'objets, leur identification et l'espace récupérable, et ne supprime rien
  - les volumes sont exclus de toute suppression par défaut ; ils apparaissent dans l'énumération, suivis de la mention du drapeau qui les inclurait
  - le drapeau qui inclut les volumes est distinct de --yes et de --dry-run, son nom dit ce qu'il détruit, et son emploi déclenche une confirmation supplémentaire qui nomme les volumes concernés
  - les réseaux listés par la variable de config/server.env ne sont jamais supprimés, ni proposés à la suppression, et leur exclusion est affichée
  - les réseaux prédéfinis de Docker ne sont jamais touchés
  - les réseaux sont supprimés un par un, par leur nom, jamais par une commande de purge globale — c'est ce qui rend la liste de protection effective
  - --yes se substitue à la confirmation, et l'aide dit que c'est le seul mode utilisable depuis une tâche planifiée
  - après suppression, le script affiche le récapitulatif de ce qui a été réellement supprimé et l'espace effectivement récupéré, catégorie par catégorie
  - le journal du script contient ce récapitulatif et la liste des objets supprimés, de sorte qu'on puisse répondre après coup à « qu'est-ce qui a disparu cette nuit ? »
  - sans démon joignable, --dry-run affiche les opérations qu'il effectuerait, avertit en [WARN] qu'aucune mesure n'a pu être faite, et rend 0 ; la même situation sans --dry-run rend 1
  - une machine sans rien à nettoyer affiche quatre catégories à zéro, ne demande aucune confirmation et rend 0
  - une option inconnue rend 2, sur une seule ligne préfixée [ERROR], sans déverser l'aide
  - --help documente les options, l'exclusion des volumes, la protection des réseaux, l'ordre des opérations et les codes de retour
  - le fichier de cas éprouve --dry-run, le refus par défaut des volumes, la protection d'un réseau nommé, la confirmation refusée et le cas sans démon, au moyen d'un faux docker placé en tête de PATH qui enregistre ses arguments
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Cleanup/docker-cleanup.sh --help"
  - "tests/env/run-in-container.sh -- bash Docker/Cleanup/docker-cleanup.sh --dry-run"
implementation_notes:
  - docker network prune supprime tout réseau sans conteneur attaché, y compris un réseau d'infrastructure vide — la commande est inutilisable ici, voir le corps
  - docker system prune n'emporte les volumes qu'avec --volumes ; s'appuyer sur ce défaut ne suffit pas, la tâche exige un drapeau nommé et une confirmation distincte
  - bridge, host et none sont les réseaux prédéfinis du démon ; Docker refuse de les supprimer, mais les afficher comme candidats serait déjà une faute d'affichage
  - ASSUME_YES est la variable lue par confirm() dans lib/common.sh ; update-system.sh l'exporte depuis -y|--yes
  - enable_full_logging capture tout le script, run_logged capture la sortie d'une commande externe — l'un des deux est nécessaire pour que le récapitulatif atterrisse dans le journal
  - load_config exporte depuis decisions.md décision 7 ; la variable des réseaux protégés vit dans config/server.env, chargé de lui-même par lib/common.sh
  - ne jamais écrire var="$(docker …)" en affectation nue — voir Linux/System/recensement-substitutions.md
---

# TASK-037 — Le seul script destructif du lot

## L'énoncé

Section **10** de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) :

```text
Images inutilisées : ...
Containers arrêtés : ...
Networks inutilisés : ...
Volumes inutilisés : ...
```

*« `--dry-run` obligatoire, confirmation avant toute suppression réelle, et
aucune suppression d'une ressource en cours d'utilisation. »* Et, en gras dans
le plan : *« **Les volumes sont exclus par défaut.** Ils portent les données ;
un nettoyage général ne les emporte jamais sans une intention explicitement
exprimée. »*

## `--dry-run` n'est pas un mode dégradé, c'est le mode principal

C'est le comportement le plus utile du script, et celui sur lequel il sera jugé.
Un `--dry-run` qui annonce « *des images seraient supprimées* » ne vaut rien :
il énumère **par catégorie**, avec le nombre d'objets, de quoi les identifier et
l'espace récupérable. C'est le relevé de
`Docker/Diagnostics/docker-disk-usage.sh` (TASK-034), et c'est pourquoi cette
tâche en dépend : *le nettoyage montre ce
qu'il va récupérer, et cette mesure est déjà écrite ailleurs.* Ne pas la
réécrire ; s'y conformer, y compris sur le point délicat qu'elle tranche —
**lorsque Docker ne fournit pas l'espace récupérable, la colonne porte une
mention explicite, jamais un zéro.** Un zéro se lit « il n'y a rien à
récupérer », soit l'inverse de la vérité.

## Trois protections, et pourquoi deux d'entre elles ne vont pas de soi

### Les volumes sont exclus par défaut — décision tranchée, pas option ouverte

Un volume porte des données ; une image se retélécharge, un conteneur se
recrée, un volume perdu est perdu. Le défaut est donc **l'exclusion**, et il ne
se discute pas.

Les inclure exige un drapeau **dédié et distinct**, dont le nom dit ce qu'il
détruit — pas un `--all` ni un `--force` qui se tapent par habitude. Son emploi
déclenche une **confirmation supplémentaire**, qui nomme les volumes concernés :
la confirmation générale porte sur le nettoyage, celle-ci porte sur les données.

Les volumes restent **affichés** dans l'énumération, suivis de la mention du
drapeau qui les inclurait. Les cacher reviendrait à laisser croire qu'il n'y a
rien là ; les proposer sans drapeau reviendrait à les offrir.

S'appuyer sur le fait que `docker system prune` n'emporte les volumes qu'avec
`--volumes` ne suffit pas : ce défaut appartient à Docker, pas à ce script, et
un jour où un rédacteur ajoutera une option « pour faire le ménage complet », il
n'y aura plus rien pour l'arrêter.

### Les réseaux d'infrastructure ne sont jamais emportés

C'est le piège le moins visible du script, et il vaut qu'on s'y arrête.

`docker network prune` supprime **tout réseau auquel aucun conteneur n'est
attaché**. Un réseau d'infrastructure créé par `create-network.sh` (lot A) pour
faire se joindre plusieurs projets Compose est, à l'instant où tous les projets
sont arrêtés, exactement cela : un réseau sans conteneur. Un nettoyage nocturne
l'emporte, et les projets ne redémarrent plus.

**Conséquence de conception, à ne pas négocier : la commande de purge globale
des réseaux est inutilisable ici.** Le script liste les réseaux inutilisés,
retire de cette liste les réseaux prédéfinis du démon et ceux que la
configuration protège, puis supprime les restants **un par un, par leur nom**.
C'est ce qui rend la liste de protection effective ; une purge globale la
rendrait décorative.

La liste vit dans `config/server.env` — le contexte de la machine, chargé de
lui-même par `lib/common.sh` — et son entrée commentée entre dans
`config/server.env.example`, avec la raison écrite. **Si la tâche du lot A qui
porte `Docker/Configuration/create-network.sh` a déjà introduit une variable
pour le même usage, la reprendre plutôt que d'en ajouter une seconde** : deux
listes de réseaux protégés qui divergent seraient pires qu'aucune.

### Rien de ce qui sert n'est supprimé

Docker refuse déjà de supprimer une ressource référencée, mais le script ne s'en
remet pas à ce refus : il n'en fait jamais la demande. Les conteneurs en cours
d'exécution, les images qu'ils utilisent, les réseaux auxquels ils sont
attachés et les volumes qu'ils montent sortent de l'énumération avant qu'aucune
suppression ne soit proposée.

## L'ordre des opérations change ce qui est supprimé

À connaître avant d'écrire la boucle. Supprimer les conteneurs arrêtés **libère
les images qu'ils référençaient** : ces images deviennent alors candidates, et
ne l'étaient pas au moment du relevé.

Deux exigences en découlent :

- l'ordre est fixé et documenté dans l'aide — conteneurs arrêtés, puis réseaux,
  puis images, puis volumes si le drapeau a été donné ;
- le `--dry-run` énumère **l'état à l'instant du relevé** et le **dit**. Sans
  cette phrase, la liste d'images annoncée serait plus courte que celle
  réellement supprimée, et un utilisateur qui a lu le `--dry-run` verrait
  disparaître des images qu'on ne lui avait pas montrées. C'est la différence
  entre une simulation utile et une simulation rassurante.

## Le journal doit répondre à une question précise

*« Qu'est-ce qui a disparu cette nuit ? »* — c'est la seule question qu'on pose
à un script de nettoyage après coup, et elle se pose souvent des semaines plus
tard.

Le journal contient donc le récapitulatif par catégorie **et** la liste des
objets supprimés, pas seulement des totaux. `lib/common.sh` fournit ce qu'il
faut : `enable_full_logging` capture tout le script, `run_logged` capture la
sortie d'une commande externe. Ne rien redéfinir localement.

## Le piège central : il n'y a pas de démon Docker dans le conteneur de test

Les validations du dépôt tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`). On n'installe pas Docker dans Docker, et **on
n'ajoute aucun paquet à l'image** — `tests/env/Dockerfile.debian` ne porte que
`ca-certificates`, `iproute2`, `procps` et `shellcheck`, et chaque ajout doit y
être justifié par écrit.

La preuve passe par un **faux `docker` placé en tête de `PATH`**, qui rend la
sortie qu'on lui demande et **enregistre ses arguments**. C'est le montage
retenu par TASK-024 pour `curl`, déjà employé partout dans le dépôt — voir
[tests/README.md](../../tests/README.md), « Les échecs qui ne sont pas fatals ».

Pour ce script-ci, l'enregistrement des arguments n'est pas un confort : c'est
**la seule preuve** que les protections tiennent. Quatre assertions en
dépendent, et aucune n'est vérifiable autrement :

- aucun appel de suppression ne porte sur un volume tant que le drapeau n'a pas
  été donné ;
- aucun appel ne porte sur un réseau protégé ni sur un réseau prédéfini ;
- les réseaux sont supprimés **un par un, par leur nom**, et non par une purge
  globale ;
- une confirmation refusée n'est suivie d'**aucun** appel de suppression.

Écrire ces assertions comme des **absences** demande une précaution que le dépôt
a payée : une assertion d'absence est facile à écrire creuse — sur une trace
vide ou mal capturée, elle passe sans rien prouver. Chacune est donc encadrée
d'une **garde de contraste** : la même exécution avec le drapeau, ou sans la
protection, doit produire l'appel attendu
([tests/README.md](../../tests/README.md), « Deux formes reviennent, et ce n'est
pas un hasard »).

Attention enfin à `PATH` : `lib/common.sh` charge `config/server.env`, lequel
peut le redéfinir. Et le fichier de cas **n'écrit jamais dans `config/`** —
`config/*.env` hors `.example` est en zone interdite
([regles.md](../../orchestration/regles.md) §5) ; le contexte d'essai se crée ailleurs, comme
le fait `tests/unit/common.test.sh` avec sa copie de `lib/common.sh`.

## Décision : `--dry-run` reste lisible sans démon

Transposition de ce que TASK-024 a tranché pour `notify-failure.sh` —
*« `--dry-run` doit rester utilisable sans configuration »*.

Sans `docker`, ou avec un démon muet, `--dry-run` affiche les opérations qu'il
effectuerait, **avertit en `[WARN]` qu'aucune mesure n'a pu être faite**, et rend
**0**. Sans `--dry-run`, la même situation rend **1**.

Le `[WARN]` est obligatoire et sa formulation compte : quatre catégories à zéro
sans explication se lisent « il n'y a rien à nettoyer », alors que la vérité est
« je n'ai rien pu mesurer ». C'est la même exigence que celle de TASK-034 sur
l'espace récupérable manquant.

## Ce que cette tâche ne branche pas

[décisions](../../orchestration/decisions.md)
décision 15 nomme `docker-cleanup.sh` parmi les **quatre appelants de
`notify-failure.sh`**, avec `update-system.sh`, `security-check.sh` et
`backup-resources.sh`.

`notify-failure.sh` n'existe pas encore : il fait l'objet de TASK-024, en
attente. Le branchement est donc **hors périmètre** ici, et le restera jusqu'à
ce qu'une tâche distincte s'en charge — la même qui reprendra la ligne de
`/etc/cron.d/mgnetworking`, vérifiée au caractère près par `configure-cron.sh`
et par son fichier de cas. Écrire dès maintenant un appel vers un script absent
produirait un code mort que rien ne peut éprouver.

Ce que cette tâche doit faire en revanche : **rendre un code de retour exact**,
pour que le `||` de la ligne planifiée ait quelque chose à lire le jour venu.

## Un piège de Bash que ce dépôt a déjà payé

`var="$(docker …)"` en **affectation nue** fait écrire deux lignes
`Échec (code …)` au `trap ERR` de `lib/common.sh` quand la commande échoue, et
trois si la substitution appelle une fonction. Formes sûres et relevé complet
dans
[`Linux/System/recensement-substitutions.md`](../../Linux/System/recensement-substitutions.md).
Sous `set -Eeuo pipefail`, un tube dont la tête échoue emporte le script avant
tout message : capturer d'abord, découper ensuite. Sur un script destructif,
mourir au milieu d'une boucle de suppression est la façon la plus coûteuse de
découvrir ce défaut.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/docker-cleanup.sh --help` | 0 |
| `run-in-container.sh -- bash …/docker-cleanup.sh --dry-run` | 0, aucune suppression, un `[WARN]` sur la mesure impossible |

`--help` sort **avant tout préflight** : dans le conteneur de test, `docker`
n'existe pas.

Le niveau `acceptance` n'est convoqué par aucune validation de cette tâche :
TASK-028 relève qu'il est rouge sur `master` pour une cause qui lui est
étrangère.

## Dépendance

TASK-034 (`Docker/Diagnostics/docker-disk-usage.sh`) porte la mesure que ce
script affiche avant de supprimer, et la règle d'affichage de l'espace
récupérable manquant. Ne pas démarrer avant qu'elle soit `completed`.

Cibles supportées : Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS —
[décisions](../../orchestration/decisions.md)
décision 14. La question ne se repose pas.

## Documentation

`Docker/README.md` est créé par le lot A. S'il n'existe pas encore, **la
créer**. Ce script y porte la section « risques » la plus fournie du domaine :
ce qu'il supprime, ce qu'il ne supprime jamais, et la phrase qu'il faut avoir
lue avant de le planifier — *un nettoyage automatique s'installe après avoir lu
son `--dry-run`, pas avant*.
