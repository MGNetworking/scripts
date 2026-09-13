---
id: TASK-033
title: "Écrire Docker/Diagnostics/list-containers.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
human_approval_required: true
objective: |
  Livrer l'inventaire des conteneurs de la machine, en lecture seule : nom,
  image, état, ports, réseaux et identifiant. Les conteneurs actifs par défaut,
  les conteneurs arrêtés sur demande. Le script reste lisible quand Docker est
  absent ou que le démon ne répond pas, et rend alors un code non nul en nommant
  la cause.
scope:
  - Docker/Diagnostics/list-containers.sh
  - tests/integration/list-containers.test.sh
  - Docker/README.md — la ligne du tableau pour ce script, et la création du fichier s'il n'existe pas encore
  - README.md — la ligne du tableau des scripts disponibles
out_of_scope:
  - toute écriture sur la machine — le dossier Docker/Diagnostics/ est en lecture seule sans exception (CLAUDE.md, frontière Diagnostics)
  - tout arrêt, démarrage, redémarrage ou suppression de conteneur
  - l'affichage des journaux d'un conteneur — c'est container-logs.sh, section 9 du plan
  - l'affichage détaillé d'un conteneur nommé — c'est inspect-container.sh, section 9 du plan
  - l'inventaire des images — c'est list-images.sh, section 9 bis du plan
  - le diagnostic de l'installation Docker elle-même — c'est check-docker.sh, tâche du lot A
  - les filtres par étiquette, par réseau ou par motif de nom, et le tri par colonne
  - la sortie JSON ou toute option --format exposée à l'appelant
  - l'ajout d'un paquet à l'image de test
  - toute opération Docker réelle pendant les validations
  - l'ajout d'une variable à config/server.env.example — ce script n'a besoin d'aucune configuration
acceptance_criteria:
  - le script s'exécute depuis n'importe quel répertoire et ne modifie rien — aucune écriture, aucun prune, aucun rm, aucune action sur un conteneur
  - sans option, seuls les conteneurs en cours d'exécution sont affichés
  - --all ajoute les conteneurs arrêtés et l'affichage distingue les deux catégories
  - chaque ligne affiche le nom, l'image, l'état, les ports, les réseaux et l'identifiant court du conteneur
  - les colonnes sont alignées et aucune valeur n'est tronquée — les ports et les réseaux, seuls champs de longueur imprévisible, sont les dernières colonnes
  - aucun conteneur à afficher n'est un cas nominal — le script le dit en clair et rend 0
  - l'absence de la commande docker rend 1 en nommant la dépendance, jamais 2
  - un démon qui ne répond pas rend 1 avec un message qui distingue cette cause de l'absence de la commande
  - un refus d'accès à la socket rend 1 avec un message qui nomme l'appartenance au groupe docker comme cause probable
  - une option inconnue rend 2, sur une seule ligne préfixée [ERROR], sans déverser l'aide
  - le script ne demande aucun privilège root — il fonctionne pour un utilisateur membre du groupe docker
  - --help documente les options, ce que chaque colonne contient et les codes de retour
  - le fichier de cas éprouve l'affichage, le cas vide, --all, l'option inconnue et les trois causes d'échec au moyen d'un faux docker placé en tête de PATH
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Diagnostics/list-containers.sh --help"
implementation_notes:
  - un seul appel à docker ps, avec un modèle --format à champs séparés par des tabulations, pour que le découpage soit déterministe
  - docker ps --format expose .Names .Image .State .Status .Ports .Networks .ID — vérifier .State sur la version cible, .Status est disponible partout
  - ne jamais écrire var="$(docker ps …)" en affectation nue — voir Linux/System/recensement-substitutions.md
  - les scripts de Linux/System alignent leurs colonnes avec printf ; ne pas supposer column(1) présent, il ne fait pas partie de l'image de test
---

# TASK-033 — Inventorier les conteneurs, sans rien toucher

## Où ce script vit, et pourquoi cela l'oblige

`Docker/Diagnostics/` est **en lecture seule, sans exception**. La frontière est
écrite dans [CLAUDE.md](../../CLAUDE.md) : *« Un script qui modifie quoi que ce
soit sur la machine n'y a pas sa place, même si sa sortie ressemble à un
rapport. »*

Conséquence directe : aucun `docker start`, `stop`, `restart`, `rm`, `prune`,
aucune écriture de fichier hors du journal que `lib/common.sh` tient de
lui-même. Le modèle est
[`Linux/System/check-services.sh`](../../Linux/System/check-services.sh), dont
l'en-tête énonce la lecture seule avant même le `set -Eeuo pipefail`, et dont
l'aide la répète. Reprendre cette forme.

Le script est décrit à la section **9 bis** de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) :
*« Nom, image, état, ports, réseaux et identifiant des conteneurs. Les
conteneurs actifs par défaut, les conteneurs arrêtés sur demande. »*

## Le domaine ignore les applications

Aucun nom d'application, de reverse proxy ni de base de données ne doit
apparaître dans ce script, ni dans son fichier de cas, ni dans sa
documentation. Un inventaire qui connaîtrait d'avance les conteneurs qu'il
s'attend à trouver ne serait plus un inventaire.

## Le piège central : il n'y a pas de démon Docker dans le conteneur de test

Les validations du dépôt tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`, profils `Dockerfile.debian` et
`Dockerfile.systemd`). On n'installe pas Docker dans Docker, et **on n'ajoute
aucun paquet à l'image** — `tests/env/Dockerfile.debian` ne porte que
`ca-certificates`, `iproute2`, `procps` et `shellcheck`, et chaque ajout doit y
être justifié par écrit.

La preuve passe donc par un **faux `docker` placé en tête de `PATH`**, qui rend
exactement la sortie qu'on lui demande. C'est le montage que retient TASK-024
pour `curl`, et il est déjà employé partout dans le dépôt — voir
[tests/README.md](../../tests/README.md), « Les échecs qui ne sont pas fatals ».
`docker ps --format` est du texte tabulé : le simuler ne coûte rien, et c'est
justement ce qui permet d'éprouver le formatage et les cas limites qu'une vraie
machine ne présente jamais sur commande — zéro conteneur, un nom très long,
trois réseaux, une liste de ports à rallonge.

Deux précautions sur ce montage :

- le faux `docker` doit **enregistrer ses arguments**. C'est ce qui prouve le
  critère de lecture seule autrement que par la lecture du code : la trace ne
  doit contenir que des sous-commandes `ps`, jamais `rm`, `stop` ni `prune` ;
- `lib/common.sh` charge `config/server.env` **après** les trois lignes de
  résolution, et ce fichier peut redéfinir `PATH`. Le fichier de cas ne doit pas
  supposer que son `PATH` survit intact ; c'est la leçon du `dirname` de
  `configure-swap.sh`, allé et venu trois fois
  ([tests/README.md](../../tests/README.md), niveau `integration`).

## Trois échecs à ne pas confondre

Ils se ressemblent à l'usage et se diagnostiquent différemment. Chacun a son
message :

| Situation | Ce que le système montre | Code |
|---|---|---|
| `docker` n'est pas installé | `command -v docker` échoue | 1 |
| le démon ne répond pas | `docker ps` échoue, `Cannot connect to the Docker daemon` | 1 |
| la socket est là, l'utilisateur n'y a pas droit | `docker ps` échoue, `permission denied … /var/run/docker.sock` | 1 |

Les trois valent **1 et non 2** : la ligne de commande de l'appelant était
juste, c'est la machine qui ne suit pas. C'est la règle de
[docs/architecture-technique.md](../../docs/architecture-technique.md) §6, et
c'est le choix déjà fait par `check-services.sh` pour l'absence de `systemctl`.

Le troisième cas mérite son propre message : *« ajouter l'utilisateur au groupe
docker, ou relancer avec sudo »* fait gagner un quart d'heure à qui découvre la
machine. Ne pas le fondre dans le deuxième.

## Décisions que cette tâche tranche

**Pas de `require_root`.** Docker s'administre couramment par le groupe
`docker` ; exiger root ferait échouer le script sur les machines où il est le
mieux configuré. Le refus d'accès à la socket est diagnostiqué, pas prévenu.

**Aucune troncature.** Les ports et les réseaux sont les deux seuls champs de
longueur imprévisible ; ils passent en dernier, et s'affichent en entier.
Tronquer un mappage de ports produit une sortie qui ment discrètement — ce qui
est pire qu'une ligne qui déborde.

**Un seul appel à `docker ps`**, avec un modèle `--format` à champs séparés par
des tabulations. Enchaîner plusieurs appels — un pour les actifs, un pour les
arrêtés — ouvrirait une fenêtre pendant laquelle un conteneur change d'état, et
doublerait le coût de la simulation dans le fichier de cas. `--all` change le
drapeau passé à `docker ps`, pas le nombre d'appels.

**Le cas vide rend 0.** Une machine sans conteneur actif n'est pas en panne.
C'est le même raisonnement que l'inventaire de `check-services.sh`, qui rend 0
même lorsque des services sont en échec : un diagnostic rend compte, il ne juge
pas.

Ces quatre choix sont réversibles et locaux au sens d'[AGENTS.md](../../AGENTS.md)
§14 ; ils sont fixés ici pour ne pas être rediscutés pendant l'exécution, et à
consigner dans le rapport.

## Deux pièges de Bash que ce dépôt a déjà payés

**Les affectations par substitution doublent le `trap ERR`.** `var="$(docker ps
…)"` écrit deux lignes `Échec (code …)` quand `docker` échoue, et trois si la
substitution appelle une fonction. Le relevé complet, avec les formes sûres, est
dans [`Linux/System/recensement-substitutions.md`](../../Linux/System/recensement-substitutions.md)
— 54 sites, un verdict et une raison pour chacun. La leçon retenue au cinquième
tour : *« un site n'est pas inatteignable, il est pas encore atteint »*, et un
binaire homonyme en tête de `PATH` suffit à l'atteindre.

**`set -Eeuo pipefail` et les tubes.** `docker ps | while read` meurt sous
`pipefail` dès que `docker` échoue, avant qu'aucun message utile n'ait été
produit. Capturer d'abord, découper ensuite.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/list-containers.sh --help` | 0 |

`--help` doit donc sortir **avant tout préflight** : dans le conteneur de test,
`docker` n'existe pas, et une aide qui exigerait la commande serait illisible là
où on en a le plus besoin.

Le niveau `acceptance` n'est volontairement convoqué par aucune validation de
cette tâche : TASK-028 relève qu'il est rouge sur `master` pour une cause qui
lui est étrangère.

## Documentation

`Docker/README.md` est créé par le lot A (`install-docker.sh` et les trois
autres). S'il n'existe pas encore quand cette tâche s'exécute, **la créer** :
rôle du domaine, prérequis, systèmes supportés — Debian 12 et 13, Ubuntu 22.04
et 24.04 LTS par [ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 14 —, tableau des scripts, ordre d'utilisation et risques. Ne pas y
documenter les scripts du lot A : y ajouter la seule ligne de celui-ci.
