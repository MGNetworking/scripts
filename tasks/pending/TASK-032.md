---
id: TASK-032
title: "Écrire Docker/Configuration/create-network.sh"
status: ready
priority: medium
depends_on:
  - TASK-029
environment: container-systemd
human_approval_required: true
objective: |
  Créer un réseau Docker nommé, indépendant de tout fichier Compose, afin que
  plusieurs projets Compose distincts puissent se joindre sur un même réseau
  externe. Le nom est un argument, jamais une valeur codée en dur pour une
  application donnée. Idempotent : un réseau déjà présent et conforme n'est ni
  recréé ni modifié ; un réseau de même nom mais divergent fait refuser le
  script plutôt que détruire.
scope:
  - Docker/Configuration/create-network.sh
  - config/server.env.example — SRV_DOCKER_NETWORK, nom de réseau par défaut de la machine
  - tests/integration/create-network.test.sh
  - Docker/README.md — ligne du tableau des scripts et section « ordre d'utilisation »
  - README.md — ligne du tableau des scripts
out_of_scope:
  - la suppression d'un réseau, sa recréation et sa modification — cela appartient à cleanup-networks.sh, section 10 du plan
  - le raccordement d'un conteneur à un réseau, et toute écriture d'un fichier Compose
  - le nom d'une application, d'un reverse proxy ou d'une base de données — ce domaine ignore les applications
  - les réseaux overlay et tout ce qui suppose Swarm
  - la création de volumes, d'images ou de conteneurs
  - configure-docker.sh et /etc/docker/daemon.json — TASK-030
  - check-docker.sh et le diagnostic des réseaux existants — TASK-031
  - le bloc « Architecture » de README.md — il est aligné par TASK-029
  - la création d'un contexte config/docker.env — la valeur de machine vit dans config/server.env, chargé de lui-même par lib/common.sh
  - l'ajout d'un paquet à l'image de test
  - toute création réelle de réseau Docker pendant les validations
acceptance_criteria:
  - le nom du réseau est un argument positionnel ; à défaut, SRV_DOCKER_NETWORK de config/server.env ; sans l'un ni l'autre, le script rend 2 en disant les deux façons de le fournir
  - aucun nom d'application ni de réseau particulier ne sert de valeur par défaut — « proxy » n'apparaît nulle part ailleurs que comme exemple dans le texte de --help
  - la forme du nom est contrôlée avant tout appel à docker ; un nom que Docker ne pourrait pas porter rend 2
  - --driver est une option, bridge par défaut ; overlay est refusé en 2 en nommant Swarm ; toute autre valeur est transmise à Docker, dont le refus éventuel est relayé en 1
  - --subnet est une option, sans valeur par défaut ; une notation CIDR mal formée rend 2 avant tout appel à docker
  - réseau absent — il est créé par docker network create avec les seules options demandées, et le script rend 0
  - réseau présent et conforme — rien n'est créé ni modifié, un [INFO] le dit, le script rend 0
  - réseau présent mais divergent du pilote ou du sous-réseau demandé — l'écart est affiché, rien n'est modifié, rien n'est supprimé, et le script rend 1 en nommant cleanup-networks.sh comme le seul chemin de suppression
  - la chaîne docker network rm ne figure nulle part dans le script
  - la conformité est lue par docker network inspect avec un --format, jamais par un grep sur la sortie de docker network ls
  - --dry-run affiche la commande qui serait lancée, ne crée rien, et rend 0 y compris là où aucun démon ne répond
  - hors --dry-run, un démon injoignable rend 1 en le disant, et une option inconnue rend 2
  - deux exécutions consécutives ne créent qu'un seul réseau — le second passage n'appelle pas docker network create
  - --help documente les options, la variable de configuration, l'usage d'un réseau externe partagé entre projets Compose et les codes de retour
  - aucun réseau réel n'est créé pendant les validations — le fichier de cas éprouve les chemins modifiants par un faux docker en tête de PATH, qui enregistre ses arguments
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Configuration/create-network.sh --help"
  - "tests/env/run-in-container.sh --profil systemd -- bash Docker/Configuration/create-network.sh mgnet-test-reseau --dry-run"
implementation_notes:
  - lib/common.sh charge config/server.env de lui-même — aucun load_config, aucun --config
  - toute interrogation de docker se place en contexte de condition — if ! sortie="$(docker …)" — sinon le trap ERR de lib/common.sh parle deux fois sans nommer la cause (TASK-018)
  - une valeur d'option commençant par « - » est refusée et n'est pas consommée comme valeur (TASK-017) ; le nom positionnel suit la même règle
  - die sans second argument rend 1 ; le 2 s'écrit explicitement
  - la forme d'un nom de réseau Docker est documentée par Docker ; la constater à l'implémentation plutôt que la recopier de mémoire
  - AGENTS.md §8 réserve les opérations docker de l'agent aux objets préfixés mgnet-test- — d'où le nom employé dans la validation, alors même que --dry-run ne crée rien
---

# TASK-032 — Créer un réseau Docker partagé entre projets

## Origine

Section « 8 bis. Docker / Configuration » de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) :

```text
Compose applicatif ───┐
                      ├── réseau externe partagé
Compose reverse proxy ┘
```

Deux projets `docker compose` distincts ne se voient pas : chacun crée son
propre réseau. Les faire communiquer suppose un réseau **externe**, créé en
dehors des deux, et déclaré `external: true` de part et d'autre. C'est ce réseau
que ce script pose — et rien d'autre.

## Le domaine ignore les applications

C'est la contrainte structurante de cette tâche, et la plus facile à enfreindre
sans y penser.

Le script ne connaît ni reverse proxy, ni base de données, ni pile applicative.
Il ne connaît pas davantage le réseau `proxy` : celui-ci n'est qu'une **valeur
possible** de `SRV_DOCKER_NETWORK` dans `config/server.env`, sur une machine
donnée. Le plan l'écrit : *le nom est un argument, jamais une valeur codée en dur
pour une application donnée.*

La relecture de cette tâche portera là-dessus en premier : un nom d'application
apparu dans le script, dans son aide autrement que comme exemple, ou dans
`config/server.env.example` autrement qu'en commentaire, est un défaut
d'architecture, pas un détail de rédaction.

## Idempotent veut dire « refuser », pas « recréer »

Trois états, trois issues :

```text
absent                          → créé                              code 0
présent et conforme             → rien, un [INFO] le dit            code 0
présent, pilote ou subnet autre → l'écart est affiché, rien n'est
                                  touché, cleanup-networks.sh est
                                  nommé                             code 1
```

La troisième issue est celle qui compte. Un réseau Docker porte des conteneurs
attachés : le supprimer pour le recréer « conforme » couperait le réseau de tout
ce qui tourne, et Docker refuserait d'ailleurs de le supprimer tant qu'un
conteneur y est raccordé. **La suppression d'un réseau appartient à
`cleanup-networks.sh`** (section 10 du plan), qui n'existe pas encore, et la
chaîne `docker network rm` n'a rien à faire dans ce fichier — c'est un critère
d'acceptation vérifiable par un simple `grep`.

**Lire la conformité par `docker network inspect --format`, jamais par un `grep`
sur `docker network ls`.** La sortie tabulaire tronque, et un nom de réseau peut
en contenir un autre : `proxy` et `proxy-interne` se ressemblent trop pour
qu'une correspondance approximative soit acceptable.

## Le piège central : aucun démon Docker dans le conteneur de test

Les validations tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`, profils `Dockerfile.debian` et
`Dockerfile.systemd`). On n'installe pas Docker dans Docker, et on n'ajoute
aucun paquet à l'image.

La preuve passe par un **faux `docker` en tête de `PATH`**, qui enregistre ses
arguments et rend le code qu'on lui demande — le pattern retenu par TASK-024
pour `curl`, déjà employé partout (`tests/README.md`, « Les échecs qui ne sont
pas fatals »). C'est ce montage, et lui seul, qui permet d'éprouver les trois
états ci-dessus : le faux binaire répond à `network inspect` ce que le cas veut
qu'il réponde.

C'est aussi lui qui prouve l'**idempotence** : le fichier de cas lit les
arguments enregistrés et vérifie qu'un second passage n'a **pas** appelé
`network create`. La garde `P0 != A` de `tests/README.md` s'exprime ici sous
cette forme — le premier passage doit avoir réellement appelé la création, faute
de quoi l'idempotence serait mesurée à vide.

Le niveau `integration` s'exécute sous le profil **`debian`**, sans init : tout
cas qui exigerait un `systemctl` réel se déclare `NON EXÉCUTÉ` **par nature**,
jamais « environnement indisponible » — une indisponibilité ferait sortir le
niveau en 3 et rougir la validation alors que rien ne serait cassé.

## `--dry-run` doit fonctionner sans démon

Sur une machine sans Docker — le conteneur de test en est une —, `--dry-run`
affiche la commande qu'il lancerait, signale par un `[WARN]` qu'il n'a pas pu
lire l'état courant, et **rend 0**. C'est ce qui rend la cinquième validation
satisfaisable, et c'est aussi le comportement utile : on veut pouvoir lire ce
qui serait fait avant d'avoir posé le moteur. C'est le même arbitrage que le
`--dry-run` sans configuration de TASK-024.

Hors `--dry-run`, un démon injoignable rend 1 : là, le script avait un travail à
faire et n'a pas pu.

## Décisions que cette tâche tranche

**Le nom est positionnel.** `create-network.sh mon-reseau`, et non
`--name mon-reseau` : c'est l'unique argument obligatoire, le rendre positionnel
évite une option qu'on oublierait. `SRV_DOCKER_NETWORK` sert de valeur par défaut
de la machine ; sans argument ni variable, code 2.

**`--driver` n'a pas de liste blanche, sauf pour `overlay`.** Dupliquer la
validation que Docker fait déjà produirait une liste à tenir à jour. Seul
`overlay` est refusé en propre, parce qu'il suppose un Swarm initialisé et
qu'aucun message de Docker ne le dirait aussi clairement. Tout autre pilote
inconnu est refusé par Docker lui-même, et son message est relayé avec le code 1.

**`--subnet` n'a pas de valeur par défaut.** Laisser Docker choisir dans ses
pools est le bon comportement par défaut ; imposer un sous-réseau est une
décision de topologie, qui s'exprime explicitement quand elle a lieu d'être. La
forme CIDR est contrôlée avant tout appel à `docker`.

Ces choix sont réversibles et locaux au sens d'[AGENTS.md](../../AGENTS.md) §14 ;
ils sont fixés ici pour ne pas être rediscutés pendant l'exécution, et à
consigner dans le rapport.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 — 4 traduit en 0 par `tests/run.sh` si des cas sont sautés par nature |
| `run-in-container.sh -- bash …/create-network.sh --help` | 0 |
| `run-in-container.sh --profil systemd -- bash …/create-network.sh mgnet-test-reseau --dry-run` | 0, aucun réseau créé |

Le nom `mgnet-test-reseau` n'est pas anodin : [AGENTS.md](../../AGENTS.md) §8
réserve les opérations `docker` de l'agent aux objets préfixés `mgnet-test-`.
`--dry-run` ne crée rien, mais la validation reste dans le cadre même si elle
était un jour lancée ailleurs qu'en conteneur.

## Dépendance

`depends_on: TASK-029` : sans moteur installé, ce script n'a pas d'objet, et sa
ligne s'ajoute à un `Docker/README.md` que TASK-029 crée. La tâche reste
`pending` tant que TASK-029 n'est pas `completed`.
