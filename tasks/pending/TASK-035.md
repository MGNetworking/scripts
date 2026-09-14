---
id: TASK-035
title: "Écrire Docker/Maintenance/update-images.sh"
status: ready
priority: medium
depends_on:
  - TASK-029
environment: container-debian
niveau: N2
executor: deepseek-flash
effort: low
human_approval_required: true
objective: |
  Livrer la récupération des images d'un projet Compose désigné explicitement en
  argument. Le script récupère les images ; il ne redéploie rien, ne supprime
  rien, et ne parcourt jamais tous les projets de la machine. Il affiche ce qui
  va changer avant de changer quoi que ce soit, et porte --dry-run.
scope:
  - Docker/Maintenance/update-images.sh
  - tests/integration/update-images.test.sh
out_of_scope:
  - le redéploiement des services — le script récupère les images, il ne relance aucun conteneur ; voir « Deux actes, pas un »
  - tout parcours automatique des projets de la machine, toute découverte par balayage de /opt, /srv ou d'un répertoire de configuration
  - toute suppression d'image, y compris celle que la nouvelle vient de remplacer — c'est cleanup-images.sh, section 10 du plan
  - tout appel à docker compose down, rm, stop, ou à docker volume
  - la prise en charge de docker-compose v1, le binaire à tiret — voir « Compose v2, et rien d'autre »
  - l'authentification à un registre privé, docker login et le stockage d'identifiants
  - la mise à jour du moteur Docker lui-même — c'est TASK-036
  - le nom d'une application, d'un reverse proxy ou d'une base de données, où que ce soit dans le script, son fichier de cas ou sa documentation
  - l'ajout d'un paquet à l'image de test
  - toute opération Docker réelle pendant les validations, et tout accès à un registre
acceptance_criteria:
  - --project est obligatoire ; son absence rend 2 en nommant l'option, sans déverser l'aide
  - --project accepte un répertoire contenant un fichier Compose ou le chemin d'un fichier Compose ; un chemin inexistant ou sans fichier Compose rend 2 en nommant ce qui a été cherché
  - le script affiche, avant toute récupération, le projet retenu, le fichier Compose retenu et la liste des images qu'il va récupérer
  - la récupération ne commence qu'après confirmation explicite, sauf en présence de --yes
  - après récupération, le script indique pour chaque image si elle a changé ou non
  - le script termine en affichant la commande exacte de redéploiement, et avertit que les conteneurs en cours tournent toujours sur l'ancienne image tant qu'elle n'a pas été lancée
  - aucune commande exécutée par le script ne détruit un conteneur, un volume ou une image — la trace des appels ne contient que des sous-commandes de récupération et de lecture
  - --dry-run affiche le projet, le fichier Compose, la liste des images et les commandes qui seraient exécutées, sans rien récupérer, et rend 0
  - sans démon joignable, --dry-run affiche ce qu'il a pu établir, avertit en [WARN] que la liste des images n'a pas pu être résolue, et rend 0 ; la même situation sans --dry-run rend 1
  - l'absence de la commande docker rend 1 en nommant la dépendance ; l'absence du greffon Compose v2 rend 1 avec un message distinct
  - la présence du seul docker-compose v1 est refusée en 1 par un message qui nomme le greffon attendu
  - une option inconnue rend 2, sur une seule ligne préfixée [ERROR]
  - --help documente les options, la distinction entre récupération et redéploiement, et les codes de retour
  - le fichier de cas éprouve le chemin nominal, --dry-run, le refus de --project absent, l'absence de Compose et le cas sans démon, au moyen d'un faux docker placé en tête de PATH qui enregistre ses arguments
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Maintenance/update-images.sh --help"
  - "tests/env/run-in-container.sh -- bash -c 'mkdir -p /tmp/projet-essai && touch /tmp/projet-essai/compose.yaml && bash Docker/Maintenance/update-images.sh --project /tmp/projet-essai --dry-run'"
implementation_notes:
  - docker compose config --images rend la liste des images d'un projet sans contacter aucun registre
  - les quatre noms de fichier Compose reconnus par Compose v2 sont compose.yaml, compose.yml, docker-compose.yaml et docker-compose.yml, dans cet ordre de préséance
  - ASSUME_YES est la variable lue par confirm() dans lib/common.sh ; update-system.sh l'exporte depuis -y|--yes
  - ne jamais écrire var="$(docker compose …)" en affectation nue — voir Linux/System/recensement-substitutions.md
  - une image récupérée par étiquette mobile change sans prévenir : le dire dans le README, ce n'est pas un défaut du script
---

# TASK-035 — Récupérer les images d'un projet, et rien de plus

## L'énoncé

Section **9** de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) :
*« Mettre à jour les images d'un projet désigné explicitement, jamais de tous
les projets de la machine par défaut. Distinguer la récupération d'une image du
redéploiement d'un service, et préserver les données persistantes. »*

Et l'avertissement qui suit immédiatement, à ne pas perdre de vue : *« Ne pas
utiliser ces scripts pour modifier directement les workloads gérés par
Kubernetes. »* — la frontière des couches de [CLAUDE.md](../../CLAUDE.md).

## Deux actes, pas un — et le script n'en fait qu'un

Récupérer une image et redéployer un service sont deux opérations de natures
différentes :

```text
récupération   docker compose pull     aucune interruption, rien ne change pour
                                       les conteneurs en cours
redéploiement  docker compose up -d    les conteneurs sont recréés : coupure,
                                       et tout ce qui n'est pas dans un volume
                                       disparaît avec l'ancien conteneur
```

**Décision tranchée : ce script récupère, il ne redéploie pas.** Trois raisons,
à écrire dans le README pour qu'elles ne soient pas rediscutées :

- la récupération est sûre et peut tourner sans surveillance ; le redéploiement
  coupe le service et se décide, lui, à un moment choisi ;
- `CLAUDE.md` impose la responsabilité unique et la séparation entre
  installation, configuration, vérification et maintenance. Un script qui
  téléchargerait puis relancerait ferait deux métiers, dont l'un destructif ;
- c'est ce qui rend `--dry-run` honnête : il n'y a rien d'irréversible à
  annoncer, et l'appelant garde la main sur l'acte qui coupe.

Le script **affiche en fin d'exécution la commande exacte de redéploiement** et
avertit que, tant qu'elle n'a pas été lancée, les conteneurs tournent encore sur
l'ancienne image. Sans cette phrase, l'utilisateur croit avoir mis à jour son
service alors qu'il a seulement rempli son disque.

« Préserver les données persistantes » découle de là : le script n'exécute
jamais `down`, jamais `rm`, jamais rien qui touche à un volume. Ce n'est pas une
promesse, c'est un critère — le faux `docker` du fichier de cas **enregistre ses
arguments**, et la trace est vérifiée.

## Le projet est désigné, jamais deviné

`--project` est **obligatoire**. Pas de valeur par défaut, pas de répertoire
courant implicite, pas de balayage de `/opt` ou de `/srv`. Un script de
maintenance qui part à la recherche des projets d'une machine finit par en
trouver un qu'on ne voulait pas toucher.

Le domaine `Docker/` **ignore les applications** : aucun nom d'application, de
reverse proxy ni de base de données ne doit apparaître dans le script, dans son
fichier de cas, ni dans sa documentation. Les exemples du README emploient des
noms neutres.

`--project` accepte un répertoire — le script y cherche alors les quatre noms de
fichier Compose reconnus par Compose v2, dans l'ordre `compose.yaml`,
`compose.yml`, `docker-compose.yaml`, `docker-compose.yml` — ou directement le
chemin d'un fichier. Un chemin inexistant, ou un répertoire sans fichier
Compose, rend **2** : c'est une erreur de l'appelant, et le message nomme ce qui
a été cherché.

## Compose v2, et rien d'autre

`install-docker.sh` (TASK-029) installe le **greffon Compose** par les dépôts
officiels — section 8 du plan. La commande est donc `docker compose`, en deux
mots. Le binaire `docker-compose` à tiret est la version 1, en fin de vie, dont
les fichiers et la sémantique diffèrent.

Le script n'en prend pas la charge. S'il ne trouve que lui, il rend **1** avec
un message qui nomme le greffon attendu, plutôt que de tenter une compatibilité
qui ne serait éprouvée nulle part.

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
`docker compose config --images` rend une liste de lignes : la simuler ne coûte
rien, et c'est ce qui permet d'éprouver le tableau « avant / après » sans
toucher au moindre registre.

Deux précautions :

- **aucun accès réseau pendant les validations.** [AGENTS.md](../../AGENTS.md)
  §8 borne ce que l'agent lance ; un `pull` réel, même d'une image minuscule,
  sort du cadre. Le faux `docker` couvre tout ;
- `lib/common.sh` charge `config/server.env`, lequel peut redéfinir `PATH`. Le
  fichier de cas ne doit pas supposer que son `PATH` survit intact.

## Décision : `--dry-run` reste lisible sans démon

C'est la transposition de ce que TASK-024 a tranché pour `notify-failure.sh` —
*« `--dry-run` doit rester utilisable sans configuration »*.

Sans `docker`, ou avec un démon muet, `--dry-run` affiche ce qu'il a pu établir
— projet retenu, fichier Compose retenu, commandes qui seraient exécutées —,
**avertit en `[WARN]` que la liste des images n'a pas pu être résolue**, et rend
**0**. Sans `--dry-run`, la même situation rend **1** : on ne peut pas récupérer
ce qu'on ne sait pas nommer.

Deux bénéfices : on lit ce que le script ferait sur une machine avant d'y poser
Docker, et la validation de `--dry-run` est satisfaisable dans le conteneur de
test tel qu'il est. Le `[WARN]` est obligatoire : un `--dry-run` qui afficherait
une liste vide sans dire pourquoi mentirait par omission.

## Décisions que cette tâche tranche

**Confirmation avant récupération, `--yes` pour s'en passer.** Un `pull`
consomme de la bande passante et du disque ; sur un VPS, ce n'est pas neutre.
`confirm()` de `lib/common.sh` lit `ASSUME_YES` — `update-system.sh` montre la
forme exacte, `-y|--yes` qui exporte la variable.

**Pas de `--service`.** Restreindre la récupération à un service du projet est
un besoin réel, mais distinct ; l'ajouter ici double les cas à éprouver pour un
gain qui n'est pas demandé.

**Le script ne supprime jamais l'ancienne image.** Une image remplacée reste sur
le disque, référencée par les conteneurs qui tournent encore dessus. La
récupérer est le travail de `cleanup-images.sh` (section 10 du plan), et la
confusion entre « image `dangling` » et « image simplement inutilisée » y est
traitée — la seconde catégorie est bien plus large.

Ces trois choix sont réversibles et locaux au sens d'[AGENTS.md](../../AGENTS.md)
§14 ; ils sont fixés ici pour ne pas être rediscutés pendant l'exécution, et à
consigner dans le rapport.

## Ce que le README doit dire, et que le script ne peut pas empêcher

Une image récupérée par **étiquette mobile** change de contenu sans que
l'étiquette change. Le tableau « avant / après » du script le montre — c'est
justement à cela qu'il sert — mais rien n'empêche la version récupérée d'être
plus récente que voulu. C'est une propriété des étiquettes, pas un défaut à
corriger : à écrire dans le README, comme TASK-024 a écrit qu'un en-tête passé à
`curl` reste visible dans la table des processus.

## Un piège de Bash que ce dépôt a déjà payé

`var="$(docker compose …)"` en **affectation nue** fait écrire deux lignes
`Échec (code …)` au `trap ERR` de `lib/common.sh` quand la commande échoue, et
trois si la substitution appelle une fonction. Formes sûres et relevé complet
dans
[`Linux/System/recensement-substitutions.md`](../../Linux/System/recensement-substitutions.md).
Sous `set -Eeuo pipefail`, un tube dont la tête échoue emporte le script avant
tout message utile : capturer d'abord, découper ensuite.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/update-images.sh --help` | 0 |
| `run-in-container.sh -- bash -c '… --project /tmp/projet-essai --dry-run'` | 0, aucune récupération, un `[WARN]` sur la liste d'images non résolue |

La dernière ligne crée un projet minimal dans `/tmp` — un fichier
`compose.yaml` vide suffit à franchir le contrôle de chemin — puis éprouve le
chemin « `--dry-run` sans démon ». Elle ne touche ni `config/`, ni le dépôt
monté : `AGENTS.md` §5 place `config/*.env` en zone interdite, et un fichier de
cas ne doit pas y écrire.

`--help` sort **avant tout préflight** : dans le conteneur de test, `docker`
n'existe pas.

Le niveau `acceptance` n'est convoqué par aucune validation de cette tâche :
TASK-028 relève qu'il est rouge sur `master` pour une cause qui lui est
étrangère.

## Dépendance

TASK-029 (`Docker/Installation/install-docker.sh`, lot A) fixe ce que le socle
installe réellement — moteur, CLI, `containerd`, Buildx et **greffon Compose**.
C'est cette liste qui détermine que la commande est `docker compose` et non
`docker-compose`. Ne pas démarrer cette tâche avant qu'elle soit `completed`.

## Documentation

`Docker/README.md` est créé par le lot A. S'il n'existe pas encore, **la
créer** : rôle du domaine, prérequis, systèmes supportés — Debian 12 et 13,
Ubuntu 22.04 et 24.04 LTS par
[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 14 —, tableau des scripts, ordre d'utilisation et risques. Ne pas y
documenter les scripts du lot A.
