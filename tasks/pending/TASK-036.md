---
id: TASK-036
title: "Écrire Docker/Maintenance/update-docker.sh"
status: ready
priority: medium
depends_on:
  - TASK-029
environment: container-systemd
agent: sonnet
human_approval_required: true
objective: |
  Livrer la mise à jour du moteur Docker et de ses composants — Engine, CLI,
  containerd, Buildx, greffon Compose — bornée à ce que le socle a réellement
  installé. Le script relève l'état avant et après, annonce l'interruption des
  conteneurs en cours et la fait confirmer, et ne touche jamais aux images
  applicatives.
scope:
  - Docker/Maintenance/update-docker.sh
  - tests/integration/update-docker.test.sh
out_of_scope:
  - toute mise à jour d'image applicative, tout docker pull — c'est TASK-035
  - la mise à jour des autres paquets du système — c'est Linux/System/update-system.sh, déjà écrit
  - l'installation de Docker sur une machine qui ne l'a pas, et l'ajout du dépôt officiel — c'est install-docker.sh, tâche du lot A
  - toute écriture dans /etc/docker/daemon.json, live-restore compris — c'est configure-docker.sh, tâche du lot A
  - le redémarrage du serveur, et l'arrêt ou le démarrage de conteneurs
  - l'installation d'une version précise, l'épinglage de version et le retour à une version antérieure
  - le nom d'une application, d'un reverse proxy ou d'une base de données, où que ce soit dans le script, son fichier de cas ou sa documentation
  - l'ajout d'un paquet à l'image de test
  - toute opération Docker réelle pendant les validations, toute installation réelle de paquet, tout accès à un miroir apt réel
acceptance_criteria:
  - le script relève et affiche, avant toute action, la version de chaque composant installé et l'état du service docker
  - seuls les composants réellement installés sont mis à jour ; un composant absent est signalé comme tel et n'est jamais installé au passage
  - aucun autre paquet du système n'est mis à jour — la commande employée est bornée à la liste des composants relevés
  - lorsqu'aucun composant Docker n'est installé, le script ne rafraîchit aucun index de paquets, avertit en nommant install-docker.sh, et rend 0 en --dry-run, 1 sinon
  - le script compte les conteneurs en cours d'exécution, annonce que la mise à jour du moteur les interrompra, et ne poursuit qu'après confirmation explicite
  - l'annonce d'interruption distingue le cas où live-restore est actif de celui où il ne l'est pas, sans jamais modifier /etc/docker/daemon.json
  - --yes se substitue à la confirmation, et l'aide dit que c'est le seul mode utilisable depuis une tâche planifiée
  - après mise à jour, le script relève à nouveau les versions et l'état du service, et affiche un avant/après composant par composant
  - un service docker qui n'est pas actif après la mise à jour rend 1 en nommant la commande de diagnostic à lancer
  - --dry-run affiche le relevé, les composants qui seraient mis à jour et les commandes qui seraient exécutées, sans rien installer ni redémarrer, et rend 0
  - l'absence d'apt-get, ou un système hors des cibles supportées, est refusée proprement avant toute action
  - une option inconnue rend 2, sur une seule ligne préfixée [ERROR], sans déverser l'aide
  - --help documente les options, la liste des composants pris en charge, l'interruption des conteneurs et les codes de retour
  - le fichier de cas éprouve le relevé, --dry-run, le cas « aucun composant installé », l'option inconnue et le chemin de confirmation, au moyen de faux docker, dpkg-query et apt-get placés en tête de PATH
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Maintenance/update-docker.sh --help"
  - "tests/env/run-in-container.sh -- bash Docker/Maintenance/update-docker.sh --dry-run"
  - "tests/env/run-in-container.sh --profil systemd -- bash Docker/Maintenance/update-docker.sh --dry-run"
implementation_notes:
  - les paquets du dépôt officiel sont docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin et docker-compose-plugin — confirmer la liste sur ce qu'install-docker.sh installe réellement
  - dpkg-query -W -f est la lecture qui dit si un paquet est installé, sans rien modifier
  - apt-get install --only-upgrade borne la mise à jour à une liste nommée, là où apt-get upgrade emporterait tout le système
  - DEBIAN_FRONTEND=noninteractive est indispensable : update-system.sh le pose pour la même raison, un dialogue apt bloquerait une tâche planifiée
  - ASSUME_YES est la variable lue par confirm() dans lib/common.sh ; update-system.sh l'exporte depuis -y|--yes
  - ne jamais écrire var="$(docker version …)" en affectation nue — voir Linux/System/recensement-substitutions.md
---

# TASK-036 — Mettre à jour le moteur, pas la machine

## L'énoncé

Section **9** de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) :
*« Mettre à jour le moteur et ses composants — Engine, CLI, `containerd`,
Buildx, Compose — selon ce que le socle a réellement installé. Vérifier l'état
avant et après. Ne touche pas aux images applicatives. »*

Trois bornes sont donc posées dès l'énoncé, et chacune a son critère :

- **selon ce que le socle a réellement installé** — le script relève l'existant,
  il ne travaille pas sur une liste supposée. Un composant absent est signalé,
  jamais installé au passage : installer est le métier de `install-docker.sh`
  (TASK-029), et `CLAUDE.md` sépare installation et maintenance ;
- **avant et après** — deux relevés, et un affichage qui les met en regard ;
- **pas les images applicatives** — aucun `docker pull`, aucun redéploiement.
  C'est TASK-035 qui en a la charge, et les deux ne se mélangent pas.

Le domaine ignore les applications : aucun nom d'application, de reverse proxy
ni de base de données ne doit apparaître dans le script, son fichier de cas ou sa
documentation.

## Ce que ce script ne fait pas, et qui lui ressemble

[`Linux/System/update-system.sh`](../../Linux/System/update-system.sh) met à jour
**tous** les paquets de la machine. Celui-ci en met à jour **cinq au plus**,
nommément désignés. La confusion serait coûteuse dans les deux sens : une tâche
planifiée qui croit mettre à jour le moteur et met à jour le noyau, ou un
administrateur qui croit avoir tout mis à jour alors qu'il n'a touché qu'à
Docker.

Conséquence pratique : la commande de mise à jour est **bornée à une liste
nommée** — `apt-get install --only-upgrade <les composants relevés>` — et jamais
`apt-get upgrade`. C'est un critère, et il se vérifie sur la trace du faux
`apt-get` du fichier de cas.

Reprendre en revanche d'`update-system.sh` deux dispositions éprouvées :
`DEBIAN_FRONTEND=noninteractive`, sans quoi un dialogue `apt` suspendrait
indéfiniment une exécution planifiée, et la forme `-y|--yes` qui exporte
`ASSUME_YES` pour `confirm()`.

## La mise à jour du moteur coupe les conteneurs

C'est le point qui justifie l'existence d'une confirmation, et le
`container-systemd` de cette tâche.

Mettre à jour le paquet du moteur entraîne un **redémarrage du démon** par le
paquet lui-même. Les conteneurs en cours s'arrêtent alors, **sauf** si le démon
tourne avec `live-restore`. Trois conséquences pour le script :

1. il **compte les conteneurs en cours** et l'annonce : « *N conteneurs seront
   interrompus* » est une phrase que l'utilisateur doit lire avant de dire oui,
   et non découvrir après ;
2. il **lit** l'état de `live-restore` — `docker info` le donne — et adapte son
   message. Il ne l'active jamais : `/etc/docker/daemon.json` appartient à
   `configure-docker.sh` (lot A), et une tâche qui écrirait dans un fichier
   qu'une autre gère de façon idempotente créerait un conflit silencieux ;
3. il **vérifie après coup** que le service est revenu — `systemctl is-active` —
   et rend 1 en nommant la commande de diagnostic s'il ne l'est pas. Un moteur
   mis à jour qui ne redémarre pas est le pire des deux mondes.

**Deux réserves à vérifier plutôt qu'à supposer**, et à consigner dans le
rapport : le comportement exact du redémarrage à l'installation du paquet, et la
portée réelle de `live-restore` — il protège d'un redémarrage du démon, pas
nécessairement d'un redémarrage de `containerd`. Le rédacteur doit mesurer ou,
à défaut, écrire ce qu'il n'a pas pu mesurer. Ce que la tâche exige sans réserve,
c'est que le script **annonce et fasse confirmer** ; c'est cela qui est
vérifiable en conteneur.

**Le script ne redémarre pas le démon lui-même** et ne redémarre jamais le
serveur. Il constate.

## Le piège central : il n'y a pas de démon Docker dans le conteneur de test

Les validations du dépôt tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`, profils `Dockerfile.debian` et
`Dockerfile.systemd`). On n'installe pas Docker dans Docker, et **on n'ajoute
aucun paquet à l'image** — les deux Dockerfiles portent une justification écrite
par paquet, et `Dockerfile.systemd` annonce explicitement *« aucun service
applicatif — ni Docker, ni K3s, ni base de données »*.

La preuve passe par de **faux binaires placés en tête de `PATH`** : `docker`,
`dpkg-query` et `apt-get`, qui rendent la sortie qu'on leur demande et
**enregistrent leurs arguments**. C'est le montage retenu par TASK-024 pour
`curl`, déjà employé partout dans le dépôt — voir
[tests/README.md](../../tests/README.md), « Les échecs qui ne sont pas fatals »,
et le **stub sélectif**, qui ne refuse qu'une invocation précise, sans quoi le
second site d'une fonction reste hors d'atteinte.

Aucune installation réelle, aucun accès à un miroir `apt` réel, aucun appel à un
registre : [AGENTS.md](../../AGENTS.md) §8 borne ce que l'agent lance.

`lib/common.sh` charge `config/server.env`, lequel peut redéfinir `PATH` : le
fichier de cas ne doit pas supposer que son `PATH` survit intact.

## Décision : `--dry-run` reste lisible quand rien n'est installé

Transposition de ce que TASK-024 a tranché pour `notify-failure.sh` —
*« `--dry-run` doit rester utilisable sans configuration »*.

Sur une machine où **aucun composant Docker n'est installé** — c'est exactement
le cas des deux conteneurs de test —, le script :

- ne rafraîchit **aucun** index de paquets : il n'y a rien à planifier, et un
  `apt-get update` rendrait la validation dépendante d'un miroir joignable, que
  [tests/README.md](../../tests/README.md) range parmi les indisponibilités ;
- avertit en nommant `install-docker.sh` ;
- rend **0 en `--dry-run`** — la question posée était « que ferais-tu ? », elle a
  reçu sa réponse — et **1 sans `--dry-run`** — on a demandé une mise à jour de
  quelque chose qui n'est pas là.

Cette asymétrie est délibérée. Elle rend la validation satisfaisable dans le
conteneur tel qu'il est, et elle laisse le vrai cas d'erreur bruyant sur une
machine réelle.

Le rafraîchissement de l'index, lui, reste dans le chemin nominal — avec des
composants installés, une liste de mises à jour lue sur un index périmé ne vaut
rien, et c'est le même raisonnement qu'`update-system.sh`, dont le `--dry-run`
rafraîchit.

## Pourquoi `container-systemd`, et ce qu'on n'y lance pas

Le script interroge `systemctl` autour du redémarrage du démon ; la règle
d'[AGENTS.md](../../AGENTS.md) §7 envoie donc cette tâche sur le profil
`systemd`.

Deux limites du profil, à connaître avant d'écrire les validations :

- **ne jamais lancer `tests/run.sh integration` sous le profil `systemd`.**
  Plusieurs assertions de `tests/integration/linux-system.test.sh` sont vraies
  *parce que* systemd est absent, et rougiraient sans qu'aucun défaut n'existe
  ([tests/README.md](../../tests/README.md)). Le niveau `integration` reste
  l'affaire du profil `debian` ; la preuve qui exige systemd se prend par appel
  direct du script, comme le fait la dernière ligne de `validation` ;
- **l'image `systemd` n'a pas `shellcheck`** : aucune validation de cette tâche
  n'y lance le niveau `lint`.

Le fichier de cas vit donc dans `tests/integration/`, comme le demande le
`scope`, et ses groupes qui ont besoin d'un init réel **mesurent** leur condition
— `/proc/1/comm` vaut `systemd` — plutôt que de la supposer, et se déclarent
`NON EXÉCUTÉ` par nature ailleurs. C'est la règle du niveau `environment`, et
elle vaut ici pour la même raison : la garde éprouve systemd, jamais le nom du
profil.

## Un piège de Bash que ce dépôt a déjà payé

`var="$(docker version …)"` en **affectation nue** fait écrire deux lignes
`Échec (code …)` au `trap ERR` de `lib/common.sh` quand la commande échoue, et
trois si la substitution appelle une fonction. Ici, l'échec est **le cas
nominal** : sur une machine sans Docker, toutes ces lectures échouent, et elles
ne doivent ni tuer le script, ni parler deux fois. C'est précisément la famille
de sites décrite dans
[`Linux/System/recensement-substitutions.md`](../../Linux/System/recensement-substitutions.md),
et l'enseignement qui va avec : *« un site n'est pas inatteignable, il est pas
encore atteint »* — un binaire homonyme en tête de `PATH` suffit à l'atteindre.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/update-docker.sh --help` | 0 |
| `run-in-container.sh -- bash …/update-docker.sh --dry-run` | 0, relevé « aucun composant installé », aucun index rafraîchi |
| `run-in-container.sh --profil systemd -- bash …/update-docker.sh --dry-run` | 0, même relevé, systemd présent |

`--help` sort **avant tout préflight** : dans les deux conteneurs, `docker`
n'existe pas.

Le niveau `acceptance` n'est convoqué par aucune validation de cette tâche :
TASK-028 relève qu'il est rouge sur `master` pour une cause qui lui est
étrangère.

## Dépendance

TASK-029 (`Docker/Installation/install-docker.sh`, lot A) fixe **la liste des
paquets** que le socle installe par les dépôts officiels. Cette tâche ne
réinvente pas cette liste : elle la reprend. Ne pas démarrer avant que TASK-029
soit `completed` — un désaccord entre les deux listes produirait un composant
installé que personne ne met à jour.

Cibles supportées : Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS, `apt` et
`systemd` partout, aucune famille RHEL —
[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 14. La question ne se repose pas.

## Documentation

`Docker/README.md` est créé par le lot A. S'il n'existe pas encore, **la
créer** : rôle du domaine, prérequis, systèmes supportés, tableau des scripts,
ordre d'utilisation et risques — celui-ci portant le risque le plus visible du
dossier `Maintenance/`, l'interruption des conteneurs. Ne pas y documenter les
scripts du lot A.
