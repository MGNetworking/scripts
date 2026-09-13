---
id: TASK-030
title: "Écrire Docker/Configuration/configure-docker.sh"
status: pending
priority: medium
depends_on:
  - TASK-029
environment: container-systemd
human_approval_required: true
objective: |
  Écrire /etc/docker/daemon.json de manière idempotente, avec pour motif premier
  la rotation des journaux de conteneurs : sans elle, un conteneur bavard remplit
  le disque d'un VPS. Le script contrôle ce qu'il va écrire avant de l'appliquer,
  conserve les clés qu'il ne gère pas plutôt que d'écraser le fichier, et ne
  redémarre le démon que si le contenu a réellement changé.
scope:
  - Docker/Configuration/configure-docker.sh
  - config/server.env.example — SRV_DOCKER_LOG_DRIVER, SRV_DOCKER_LOG_MAX_SIZE, SRV_DOCKER_LOG_MAX_FILE
  - tests/integration/configure-docker.test.sh
  - Docker/README.md — ligne du tableau des scripts et section « ordre d'utilisation »
  - README.md — ligne du tableau des scripts
out_of_scope:
  - le bloc « Architecture » de README.md — il est aligné par TASK-029
  - l'installation de Docker et tout appel à apt — TASK-029
  - create-network.sh et la moindre création de ressource Docker — TASK-032
  - check-docker.sh — TASK-031
  - data-root et storage-driver — les déplacer ou les changer détruit les images et les volumes existants ; cela se décide seul, avec une sauvegarde
  - registry-mirrors, insecure-registries et tout credential de registry
  - l'exposition du démon sur TCP, live-restore, userns-remap, les runtimes alternatifs et la configuration d'un nœud Swarm
  - la rotation des journaux du système, qui relève de Linux/System/configure-logging.sh
  - la purge des journaux des conteneurs déjà créés
  - la création d'un contexte config/docker.env — les valeurs de machine vivent dans config/server.env, chargé de lui-même par lib/common.sh
  - l'ajout d'un paquet à l'image de test, jq compris
  - toute modification d'un démon Docker réel pendant les validations
acceptance_criteria:
  - le script écrit /etc/docker/daemon.json avec le pilote de journalisation, la taille maximale d'un fichier de journal et le nombre de fichiers conservés
  - les trois valeurs sont lues dans config/server.env — SRV_DOCKER_LOG_DRIVER, SRV_DOCKER_LOG_MAX_SIZE, SRV_DOCKER_LOG_MAX_FILE — documentées avec leur défaut dans config/server.env.example, et surchargeables par option de ligne de commande, la ligne de commande primant
  - seuls les pilotes json-file et local sont acceptés ; toute autre valeur rend 2 avant la moindre écriture
  - une taille mal formée ou un nombre de fichiers non entier rendent 2, avant la moindre écriture
  - fichier absent — il est créé, avec les seules clés que le script gère
  - fichier présent et déjà conforme — rien n'est écrit, aucune sauvegarde n'est faite, le démon n'est pas redémarré, le script rend 0
  - fichier présent et divergent — les clés que le script ne gère pas sont conservées telles quelles, et l'original est sauvegardé horodaté à côté avant remplacement
  - la fusion avec un fichier existant exige jq ; sans jq, le script n'écrit rien, affiche le contenu qu'il aurait produit, nomme la dépendance manquante et rend 1
  - le contenu visé est écrit dans un temporaire et relu avant d'être mis en place ; un JSON invalide n'atteint jamais /etc/docker
  - le démon n'est redémarré que si le contenu a changé, et le redémarrage est annoncé puis confirmé, --yes valant réponse
  - si le démon ne revient pas après redémarrage, le fichier précédent est restauré et le script rend 1
  - --dry-run affiche le contenu visé et ce qui changerait, n'écrit rien, ne redémarre rien, et rend 0 y compris sur une machine où Docker n'est pas installé
  - hors --dry-run, l'absence de docker rend 1 en nommant la dépendance ; l'absence de privilège root rend 1 ; une option inconnue rend 2
  - --help documente les options, les variables lues, le fichier écrit, l'effet d'un redémarrage du démon sur les conteneurs en cours et les codes de retour
  - aucune modification d'un démon réel pendant les validations — le fichier de cas éprouve les chemins modifiants par de faux docker, systemctl et jq placés en tête de PATH
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Configuration/configure-docker.sh --help"
  - "tests/env/run-in-container.sh --profil systemd -- bash Docker/Configuration/configure-docker.sh --dry-run"
implementation_notes:
  - lib/common.sh charge config/server.env de lui-même — aucun load_config, aucun --config
  - load_config et server.env exportent depuis ADR-0003 décision 7 ; les variables SRV_DOCKER_* atteignent tout processus fils
  - "jamais d'ajout aveugle à un fichier de /etc — CLAUDE.md : lire l'état, comparer à l'état souhaité, n'écrire que si nécessaire"
  - dockerd refuse les clés qu'il ne connaît pas dans daemon.json — ne jamais y déposer une marque de propriété maison
  - confirm lit stdin par read -r ; sans terminal, read échoue et errexit tue le script. Contrôler [ -t 0 ] avant d'appeler confirm
  - die sans second argument rend 1 ; le 2 s'écrit explicitement
  - "l'idempotence se prouve par empreinte, avec la garde P0 != A de tests/README.md : la première exécution doit avoir réellement modifié quelque chose"
---

# TASK-030 — Configurer le démon Docker, rotation des journaux en premier

## Origine

Section « 8 bis. Docker / Configuration » de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md) : *écrire
`/etc/docker/daemon.json` de manière idempotente, rotation des journaux de
conteneurs en premier lieu, afin qu'aucun conteneur ne fasse croître le disque
sans borne. Valider la configuration avant de l'appliquer, et ne redémarrer le
démon que si elle a réellement changé. Les valeurs propres à la machine viennent
de `config/server.env`.*

Le motif n'est pas cosmétique. Par défaut, le pilote `json-file` **n'a aucune
limite** : un conteneur qui écrit une ligne par requête remplit `/var/lib/docker`
jusqu'à saturation du disque, et c'est le serveur entier qui tombe, pas le
conteneur. C'est le défaut de configuration le plus coûteux d'un VPS Docker.

## Le piège central : aucun démon Docker dans le conteneur de test

Les validations tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`, profils `Dockerfile.debian` et
`Dockerfile.systemd`). On n'installe pas Docker dans Docker, et on n'ajoute
aucun paquet à l'image.

La preuve passe par un **faux `docker` en tête de `PATH`**, qui enregistre ses
arguments et rend le code qu'on lui demande — le pattern retenu par TASK-024
pour `curl`, déjà employé partout (`tests/README.md`, « Les échecs qui ne sont
pas fatals »). Le même montage vaut pour `systemctl` et pour `jq`.

Le fichier `/etc/docker/daemon.json`, lui, s'écrit **réellement** dans le
conteneur : c'est le propre du niveau `integration`, qui modifie le système sur
lequel il tourne. Trois précautions, toutes déjà en usage dans le dépôt :

- le fichier de cas ne modifie rien tant qu'il n'a pas reconnu un système
  jetable — `/.dockerenv`, cgroup de conteneur, ou `MGNET_TEST_JETABLE=1` ;
- il nettoie `/etc/docker` derrière lui : **tous les fichiers de cas du niveau
  partagent un unique conteneur**, et un `daemon.json` laissé en place changerait
  le verdict d'un autre ;
- l'idempotence se mesure avec la garde **`P0 != A`** de `tests/README.md` : une
  idempotence constatée à vide est un échec, pas un succès silencieux.

## Le niveau `integration` tourne sous le profil `debian`

Il n'y a pas d'init dans ce profil, donc pas de `systemctl`. Tout ce qui touche
au service passe par le faux binaire ; un cas qui exigerait un init réel se
déclare `NON EXÉCUTÉ` **par nature** — jamais « environnement indisponible », qui
ferait sortir le niveau en 3 et rougir la validation.

`environment: container-systemd` vaut pour la cinquième validation, où
`--dry-run` s'exécute face à un init réel.

## La difficulté réelle : fusionner du JSON en Bash

`daemon.json` appartient à l'administrateur de la machine autant qu'à ce script.
Conserver ce qu'on ne gère pas suppose de **lire** du JSON arbitraire — ce que
Bash ne sait pas faire, et ce qu'aucun `sed` ne fera correctement.

**Décision, réversible et locale, prise ici pour ne pas être rediscutée :**

```text
fichier absent              → écrit tel quel, rien à préserver
présent et déjà conforme    → rien : ni écriture, ni sauvegarde, ni redémarrage
présent et divergent, jq    → fusion : nos clés posées, les autres intactes
présent et divergent, sans jq → rien n'est écrit, le contenu visé est affiché,
                                jq est nommé, code 1
```

Refuser est ici une façon de préserver. Un script qui écraserait un
`daemon.json` contenant un `data-root` ou un `default-address-pools` ferait
perdre des images ou casser le réseau de la machine — un dommage bien plus cher
que le refus.

`jq` n'est pas dans l'image de test et n'y entrera pas : le chemin « sans `jq` »
et le chemin « fichier absent » s'éprouvent tels quels, le chemin de fusion
s'éprouve avec un **faux `jq`** qui rend un résultat connu. Le fichier de cas
prouve alors que le script *emploie* la sortie de `jq` et n'écrit pas quand le
résultat est identique à l'existant — pas que `jq` fusionne correctement, ce qui
n'est pas le travail de cette tâche.

**Ne jamais déposer de marque de propriété dans le fichier.** `dockerd` refuse
les directives qu'il ne connaît pas — *the following directives don't match any
configuration option* — et JSON n'a pas de commentaires. Il n'y a donc aucun
moyen de marquer « ce fichier est à nous », et il ne faut pas en inventer un.

## « Valider avant d'appliquer » : ce que cela veut dire, et ce que je n'ai pas vérifié

Trois gardes, dans cet ordre, de la moins chère à la plus chère :

1. **la forme des valeurs**, avant toute écriture : pilote dans une liste courte,
   taille du type `10m` / `512k` / `1g`, nombre de fichiers entier positif. C'est
   là que se trouvent 99 % des erreurs, puisque le JSON est produit par le script
   lui-même ;
2. **la relecture du fichier produit**, dans un temporaire, avant de le mettre en
   place — `jq empty` quand `jq` est là. Un fichier de `/etc/docker` invalide
   empêche le démon de démarrer, et l'erreur n'apparaît qu'au redémarrage
   suivant, parfois des semaines plus tard ;
3. **le filet du redémarrage** : sauvegarde horodatée de l'original, redémarrage,
   contrôle que le démon répond, restauration et code 1 sinon.

`dockerd --validate --config-file <fichier>` existerait et conviendrait mieux
que la garde 2. **Je n'ai pas vérifié à partir de quelle version elle est
disponible**, ni son comportement sur les versions que Debian 12 et Ubuntu 22.04
reçoivent des dépôts Docker. À l'implémentation : la constater plutôt que la
supposer, l'employer **en plus** des trois gardes si elle existe, et ne jamais
faire dépendre `--dry-run` de sa présence.

## Deux comportements de Docker à connaître, et à écrire dans le README

**La rotation ne s'applique qu'aux conteneurs créés ensuite.** Les `log-opts` de
`daemon.json` sont lues à la création d'un conteneur : ceux qui tournent déjà
gardent leur configuration jusqu'à leur recréation, et leurs fichiers de journal
existants ne sont ni tronqués ni supprimés. Le script doit le dire — sans quoi on
croira la rotation active sur une machine où le disque continue de se remplir.
Purger l'existant est hors périmètre, et relève du domaine `Cleanup`.

**Redémarrer le démon interrompt les conteneurs en cours.** `live-restore` n'est
pas activé par défaut ; ceux qui portent une politique de redémarrage
reviennent, les autres non. C'est pourquoi le redémarrage est annoncé, dénombré
quand le démon répond encore, et confirmé. `systemctl reload docker` ne recharge
qu'un sous-ensemble des directives ; **je n'ai pas vérifié** si `log-driver` et
`log-opts` en font partie, et la tâche ne repose pas sur ce chemin.

## Décisions que cette tâche tranche

**Pilotes acceptés : `json-file` et `local`, rien d'autre.** Un pilote distant
— `syslog`, `gelf`, `fluentd` — casse `docker logs`, suppose une infrastructure
tierce, et engage la machine entière : cela se décide à part, pas dans un script
de rotation.

**Défauts : `json-file`, `10m`, `3`.** Trente mébioctets par conteneur au
maximum, ce qui laisse de quoi diagnostiquer un incident de la veille sans
menacer un disque de VPS. Valeurs surchargeables, documentées dans
`config/server.env.example` avec la justification — comme le fait déjà
`SRV_DISK_SEUIL`.

**Le refus « sans terminal » se prononce au moment de la question, pas avant.**
`--help` et `--dry-run` ne demandent jamais rien et doivent rester utilisables
sans terminal — c'est ainsi qu'ils s'exécutent dans le conteneur de validation.
Un contrôle de `[ -t 0 ]` placé en tête du script rendrait les deux dernières
validations insatisfaisables.

**Aucun `--config`.** `config/server.env` est chargé par `lib/common.sh` de
lui-même. Créer un contexte `docker.env` pour trois variables de machine
ajouterait un fichier sans rien résoudre.

Ces choix sont réversibles et locaux au sens d'[AGENTS.md](../../AGENTS.md) §14 ;
ils sont fixés ici pour ne pas être rediscutés pendant l'exécution, et à
consigner dans le rapport.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 — 4 traduit en 0 par `tests/run.sh` si des cas sont sautés par nature |
| `run-in-container.sh -- bash …/configure-docker.sh --help` | 0 |
| `run-in-container.sh --profil systemd -- bash …/configure-docker.sh --dry-run` | 0, rien d'écrit, rien de redémarré |

La dernière exige que `--dry-run` reste utilisable **là où Docker n'est pas
installé** : c'est ce qui permet de lire la configuration visée avant de poser
le moteur, et c'est la seule forme satisfaisable dans un conteneur de test.

## Dépendance

`depends_on: TASK-029` : ce script configure ce que la précédente installe, et
sa ligne s'ajoute à un `Docker/README.md` que TASK-029 crée. La tâche reste
`pending` tant que TASK-029 n'est pas `completed`.
