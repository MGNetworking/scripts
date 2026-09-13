---
id: TASK-034
title: "Écrire Docker/Diagnostics/docker-disk-usage.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
human_approval_required: true
objective: |
  Livrer le relevé de consommation de stockage de Docker, en lecture seule,
  distinguant images, conteneurs, volumes et cache de build, et affichant
  l'espace récupérable lorsque Docker le fournit. C'est cette mesure que
  docker-cleanup.sh présentera avant de supprimer quoi que ce soit.
scope:
  - Docker/Diagnostics/docker-disk-usage.sh
  - tests/integration/docker-disk-usage.test.sh
  - Docker/README.md — la ligne du tableau pour ce script, et la création du fichier s'il n'existe pas encore
  - README.md — la ligne du tableau des scripts disponibles
out_of_scope:
  - toute écriture sur la machine — le dossier Docker/Diagnostics/ est en lecture seule sans exception (CLAUDE.md, frontière Diagnostics)
  - toute suppression, tout prune, tout appel à docker system prune même en simulation
  - le nettoyage proprement dit — c'est TASK-037, qui consomme cette mesure
  - le diagnostic de stockage du système hors Docker — c'est Linux/System/check-disk.sh, déjà écrit
  - tout seuil d'alerte et tout code de retour conditionné à un volume occupé — ce script mesure, il ne juge pas
  - l'inventaire nominatif des images ou des conteneurs — ce sont list-images.sh et list-containers.sh
  - l'ajout d'un paquet à l'image de test
  - toute opération Docker réelle pendant les validations
  - l'ajout d'une variable à config/server.env.example — ce script n'a besoin d'aucune configuration
acceptance_criteria:
  - le script s'exécute depuis n'importe quel répertoire et ne modifie rien — aucune écriture, aucun prune, aucune suppression
  - la sortie distingue quatre catégories nommées — images, conteneurs, volumes locaux, cache de build — même lorsqu'une catégorie est vide
  - chaque catégorie affiche le nombre d'objets, le nombre d'objets actifs, la taille occupée et l'espace récupérable lorsque Docker le fournit
  - lorsque Docker ne fournit pas l'espace récupérable d'une catégorie, la colonne porte une mention explicite, jamais un zéro
  - le script affiche le répertoire de données du démon et l'occupation du système de fichiers qui le porte
  - la sortie dit en clair que la somme des quatre catégories peut différer de l'occupation réelle du répertoire de données, et pourquoi
  - --detail ajoute le relevé par objet, sans changer le relevé synthétique qui le précède
  - l'absence de la commande docker rend 1 en nommant la dépendance, jamais 2
  - un démon qui ne répond pas rend 1 avec un message qui distingue cette cause de l'absence de la commande
  - un refus d'accès à la socket rend 1 avec un message qui nomme l'appartenance au groupe docker comme cause probable
  - une option inconnue rend 2, sur une seule ligne préfixée [ERROR], sans déverser l'aide
  - une machine sans aucune image, ni conteneur, ni volume affiche quatre catégories à zéro et rend 0
  - le script ne demande aucun privilège root — il fonctionne pour un utilisateur membre du groupe docker
  - --help documente les options, le sens de chaque colonne et les codes de retour
  - le fichier de cas éprouve le relevé, le cas vide, --detail, l'option inconnue et les trois causes d'échec au moyen d'un faux docker placé en tête de PATH
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Diagnostics/docker-disk-usage.sh --help"
implementation_notes:
  - docker system df --format expose .Type .TotalCount .Active .Size .Reclaimable — un modèle à champs tabulés rend le découpage déterministe
  - la combinaison de -v et de --format n'est pas garantie sur toutes les versions : la vérifier avant de s'en servir, ou reprendre la sortie de docker system df -v telle quelle pour --detail
  - le répertoire de données se lit dans docker info ; df sur ce chemin est une lecture, pas une écriture
  - ne jamais écrire var="$(docker system df …)" en affectation nue — voir Linux/System/recensement-substitutions.md
  - les scripts de Linux/System alignent leurs colonnes avec printf ; ne pas supposer column(1) présent, il ne fait pas partie de l'image de test
---

# TASK-034 — Mesurer ce que Docker occupe, avant de parler d'en récupérer

## Pourquoi ce script vient avant le nettoyage

La section **10** de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) exige de
`docker-cleanup.sh` qu'il affiche un résumé **avant** toute suppression. Cette
mesure est celle de ce script-ci : c'est pourquoi TASK-037 en dépend, et
pourquoi celui-ci n'a aucune dépendance.

L'énoncé vient de la section **9 bis** du même plan :
*« Consommation de stockage, distinguant images, conteneurs, volumes et cache de
build, et l'espace récupérable lorsque Docker le fournit. »*

`Docker/Diagnostics/` est **en lecture seule, sans exception**
([CLAUDE.md](../../CLAUDE.md), frontière `Diagnostics`). Ce script ne supprime
rien, ne simule aucune suppression, et n'appelle **jamais** `docker system
prune`, pas même avec `--dry-run` : la commande n'a pas de mode simulation, et
l'écrire ici serait une bombe à retardement à la première relecture distraite.

## La mesure ment un peu, et il faut le dire

`docker system df` ne relève que ce que le démon comptabilise. Ne s'y trouvent
pas : les journaux de conteneurs — sauf configuration contraire, ils vivent dans
le répertoire de données et peuvent y peser lourd, ce que `configure-docker.sh`
(lot A) borne par la rotation —, les résidus de couches d'un pilote de stockage,
et tout ce qu'un tiers a déposé sous `/var/lib/docker`.

Conséquence : la somme des quatre catégories **peut différer** de l'occupation
réelle du répertoire de données. Deux exigences en découlent, toutes deux
portées par des critères :

- le script affiche le **répertoire de données** du démon — lisible dans
  `docker info` — et l'occupation du système de fichiers qui le porte, par `df` ;
- il **écrit l'avertissement** plutôt que de le taire. Un chiffre présenté comme
  exhaustif quand il ne l'est pas fait chercher au mauvais endroit.

Ne pas confondre ce constat avec le travail de
[`Linux/System/check-disk.sh`](../../Linux/System/check-disk.sh), qui diagnostique
le stockage du système entier et porte un seuil d'alerte. Ici, pas de seuil,
pas de `[WARN]` conditionné à un volume : ce script **mesure**, il ne juge pas —
le même parti que l'inventaire de `check-services.sh`.

## « Lorsque Docker le fournit » n'est pas une formule de style

L'espace récupérable n'est pas toujours renseigné, et un champ absent doit
s'afficher comme tel. Un `0 B` là où Docker n'a rien dit se lit comme *« il n'y
a rien à récupérer »* — c'est l'inverse de ce qui est vrai, et c'est exactement
l'information sur laquelle TASK-037 s'appuiera. La colonne porte donc une
mention explicite, jamais un zéro par défaut.

## Le piège central : il n'y a pas de démon Docker dans le conteneur de test

Les validations du dépôt tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`). On n'installe pas Docker dans Docker, et **on
n'ajoute aucun paquet à l'image** — `tests/env/Dockerfile.debian` ne porte que
`ca-certificates`, `iproute2`, `procps` et `shellcheck`.

La preuve passe par un **faux `docker` placé en tête de `PATH`**, qui rend la
sortie qu'on lui demande. C'est le montage retenu par TASK-024 pour `curl`, déjà
employé partout dans le dépôt — voir
[tests/README.md](../../tests/README.md), « Les échecs qui ne sont pas fatals ».

`docker system df` est du texte tabulé dès qu'on lui passe un `--format` : le
simuler ne coûte rien, et c'est le seul moyen d'éprouver les cas limites qu'une
machine réelle ne présente pas sur commande — quatre catégories à zéro, un
espace récupérable manquant, une taille exprimée dans une unité inattendue.

Le faux `docker` doit **enregistrer ses arguments** : c'est ce qui prouve la
lecture seule autrement que par relecture du code. La trace ne doit contenir que
`system df` et `info`, jamais `prune`, `rmi` ni `rm`.

Attention enfin à `PATH` : `lib/common.sh` charge `config/server.env`, lequel
peut le redéfinir. Le fichier de cas ne doit pas supposer que son `PATH` survit
intact.

## Décisions que cette tâche tranche

**Deux niveaux de détail, pas trois.** Le relevé synthétique par défaut ;
`--detail` y ajoute le relevé par objet. Pas de `--json`, pas de `--format`
exposé à l'appelant : une sortie destinée à être lue par un humain et une sortie
destinée à être analysée par un programme sont deux besoins distincts, et le
second n'est pas demandé.

**`--detail` complète, il ne remplace pas.** Le synthétique reste affiché en
tête. Sans cela, l'appelant qui veut les deux doit lancer le script deux fois,
et les deux mesures ne portent plus sur le même instant.

**Aucun code de retour conditionné au volume occupé.** 0 dès que le relevé a pu
être produit, 1 quand il ne l'a pas pu, 2 pour une erreur d'usage. Un disque
plein est une information, pas un échec du script — et c'est
[`check-disk.sh`](../../Linux/System/check-disk.sh) qui porte les seuils.

**Pas de `require_root`.** Docker s'administre couramment par le groupe
`docker`. Le refus d'accès à la socket est diagnostiqué, pas prévenu — et il
mérite son propre message, distinct de « le démon ne répond pas ».

Ces quatre choix sont réversibles et locaux au sens d'[AGENTS.md](../../AGENTS.md)
§14 ; ils sont fixés ici pour ne pas être rediscutés pendant l'exécution, et à
consigner dans le rapport.

## Trois échecs à ne pas confondre

| Situation | Ce que le système montre | Code |
|---|---|---|
| `docker` n'est pas installé | `command -v docker` échoue | 1 |
| le démon ne répond pas | `Cannot connect to the Docker daemon` | 1 |
| la socket est là, l'utilisateur n'y a pas droit | `permission denied … docker.sock` | 1 |

Les trois valent **1 et non 2** : la commande de l'appelant était juste
([docs/architecture-technique.md](../../docs/architecture-technique.md) §6).

## Un piège de Bash que ce dépôt a déjà payé

`var="$(docker system df …)"` en **affectation nue** fait écrire deux lignes
`Échec (code …)` au `trap ERR` de `lib/common.sh` quand la commande échoue, et
trois si la substitution appelle une fonction. Le relevé complet des formes
sûres est dans
[`Linux/System/recensement-substitutions.md`](../../Linux/System/recensement-substitutions.md).
Et sous `set -Eeuo pipefail`, `docker system df | awk …` meurt avant d'avoir
produit le moindre message utile : capturer d'abord, découper ensuite.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/docker-disk-usage.sh --help` | 0 |

`--help` sort **avant tout préflight** : dans le conteneur de test, `docker`
n'existe pas.

Le niveau `acceptance` n'est convoqué par aucune validation de cette tâche :
TASK-028 relève qu'il est rouge sur `master` pour une cause qui lui est
étrangère.

## Documentation

`Docker/README.md` est créé par le lot A. S'il n'existe pas encore quand cette
tâche s'exécute, **la créer** : rôle du domaine, prérequis, systèmes supportés —
Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS par
[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 14 —, tableau des scripts, ordre d'utilisation et risques. Ne pas y
documenter les scripts du lot A : y ajouter la seule ligne de celui-ci.
