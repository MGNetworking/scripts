---
id: TASK-029
title: "Écrire Docker/Installation/install-docker.sh"
status: ready
priority: high
depends_on: []
environment: container-systemd
human_approval_required: true
objective: |
  Poser Docker Engine, le CLI, containerd, Buildx et le plugin Compose par les
  dépôts officiels Docker, sur Debian 12/13 et Ubuntu 22.04/24.04 LTS. Le script
  vérifie avant d'agir — OS, architecture, noyau, disque, mémoire, paquets
  conflictuels —, n'emporte jamais une installation existante sans confirmation,
  active le service et contrôle ce qu'il vient de poser.
  C'est la tâche qui ouvre le domaine : elle crée Docker/ et son README.
scope:
  - Docker/Installation/install-docker.sh
  - "Docker/README.md — créé par cette tâche : rôle du domaine, prérequis, les cinq sous-dossiers, tableau des scripts, ordre d'utilisation, risques, systèmes supportés, commandes d'exécution"
  - tests/integration/install-docker.test.sh
  - README.md — ligne du tableau des scripts, et le bloc « Architecture », qui annonce encore Docker/ en trois sous-dossiers et un Linux/Docker abandonné
out_of_scope:
  - verify-docker.sh — second script de la section 8 du plan, tâche distincte
  - configure-docker.sh et /etc/docker/daemon.json — TASK-030
  - create-network.sh et toute création de réseau, de volume ou de conteneur — TASK-032
  - check-docker.sh — TASK-031
  - la désinstallation de Docker, qui n'est pas au plan et n'a pas de script
  - l'ajout d'un utilisateur au groupe docker — donner le démon à un compte non privilégié équivaut à donner root, cela se décide à part
  - la configuration du démon, le pilote de stockage, le répertoire de données, un miroir de registre ou l'exposition du démon sur TCP
  - Docker Desktop, Docker Swarm, rootless mode, et toute famille RHEL — ADR-0003 décision 14
  - la création d'un contexte config/docker.env — ce script ne lit aucune configuration applicative
  - l'ajout d'un paquet à l'image de test
  - toute installation réelle de Docker pendant les validations
acceptance_criteria:
  - le script pose docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin et docker-compose-plugin depuis download.docker.com, et aucun installateur n'est copié dans le dépôt
  - la clé du dépôt est déposée dans /etc/apt/keyrings et référencée par signed-by dans /etc/apt/sources.list.d/docker.list ; apt-key n'est jamais appelé
  - l'URL du dépôt et le nom de code suivent l'OS détecté — linux/debian ou linux/ubuntu, VERSION_CODENAME lu sur la machine — et ne sont écrits en dur ni l'un ni l'autre
  - une distribution ou une architecture non supportée est refusée en 1, avec un message nommant ce qui a été détecté et ce qui est attendu ; seules amd64 et arm64 sont acceptées
  - le préflight contrôle version du noyau, espace libre sous /var et mémoire totale ; un espace insuffisant bloque en 1, une mémoire insuffisante n'émet qu'un [WARN]
  - les paquets conflictuels sont recherchés un par un par dpkg-query, listés à l'écran, et leur retrait n'a lieu qu'après confirmation explicite
  - une installation Docker déjà en place est constatée, sa version affichée, et le script rend 0 sans rien réinstaller, rien écraser et rien supprimer
  - --dry-run affiche le résumé des changements — dépôt, clé, paquets, service — sans écrire un seul fichier, sans appeler apt-get, et rend 0 sur une machine où Docker est absent
  - sans terminal et sans --yes, le script s'arrête avant de poser une question, sur un message qui nomme --yes, et rend 1
  - après installation, le service docker est activé et démarré, et la vérification finale lit la version du moteur, du plugin Compose et de Buildx
  - si apt-get update échoue faute de suite publiée pour le nom de code détecté, le script le dit, retire le fichier de dépôt qu'il vient d'écrire et rend 1
  - une option inconnue rend 2, l'absence de privilège root rend 1
  - --help documente les options, les systèmes supportés, ce qui est modifié sur la machine et les codes de retour
  - aucune installation réelle n'a lieu pendant les validations — le fichier de cas éprouve les chemins modifiants par de faux docker, systemctl, curl et apt-get placés en tête de PATH
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Installation/install-docker.sh --help"
  - "tests/env/run-in-container.sh --profil systemd -- bash Docker/Installation/install-docker.sh --dry-run"
implementation_notes:
  - require_os ne compare que ID — la version (12, 13, 22.04, 24.04) se contrôle sur OS_VERSION, que detect_os renseigne
  - die sans second argument rend 1 ; le 2 s'écrit explicitement, comme le fait check-services.sh
  - confirm lit stdin par read -r ; sans terminal, read échoue, errexit tue le script et le trap ERR écrit une ligne qui ne désigne rien. Contrôler [ -t 0 ] avant d'appeler confirm
  - -y/--yes exporte ASSUME_YES=true, comme update-system.sh ; export DEBIAN_FRONTEND=noninteractive avant tout apt-get
  - dpkg -l tronque les noms de paquets dans ses colonnes — interroger dpkg-query -W -f par paquet
  - run_logged capture la sortie des commandes externes ; enable_full_logging convient à un script d'installation
  - "l'ordre imposé par CLAUDE.md est : arguments, privilèges, OS, architecture, ressources, dépendances, conflits, résumé, confirmation, exécution, vérification"
  - le dépôt est déployé par git clone — SCRIPTS_ROOT donne le chemin réel, rien ne se déduit du répertoire courant
---

# TASK-029 — Installer Docker Engine par les dépôts officiels

## Origine

Section « 8. Docker / Installation » de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md), et section
« 3. Linux / Docker — abandonnée » du même document. Cette seconde section
prévoyait `prepare-docker-host.sh`, `configure-docker-host.sh` et
`verify-docker-host.sh` : architecture, noyau, disque, mémoire. Elle a été
abandonnée le 2026-09-13 parce que le préflight d'`install-docker.sh` couvre
exactement le même besoin — l'ordre d'installation de `CLAUDE.md` le lui demande
déjà. **Ce préflight porte donc les deux héritages**, et c'est la raison pour
laquelle il compte autant de contrôles.

C'est la première tâche du domaine `Docker/`, quatrième domaine de l'ordre fixé
par [ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 16. Le répertoire `Docker/` n'existe pas encore : cette tâche le crée,
avec son `README.md` de domaine (plan, section 13).

## Le piège central : aucun démon Docker dans le conteneur de test

Les validations de ce dépôt tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`, profils `Dockerfile.debian` et
`Dockerfile.systemd`). On n'installe pas Docker dans Docker, et on n'ajoute
aucun paquet à l'image — les deux Dockerfile l'écrivent noir sur blanc :
*volontairement minimale, chaque paquet ajouté doit avoir une raison écrite ici*.

La preuve passe donc par un **faux `docker` en tête de `PATH`**, qui enregistre
ses arguments et rend le code qu'on lui demande. C'est le pattern que TASK-024
retient pour `curl`, et il est déjà employé partout dans le dépôt — voir
`tests/README.md`, « Les échecs qui ne sont pas fatals » : *un binaire homonyme
en tête de `PATH` est la mutation la moins coûteuse du dépôt*. Le même montage
vaut ici pour `systemctl`, `curl` et `apt-get`.

Ce que cela permet, sans qu'un seul paquet ne s'installe : éprouver le refus des
paquets conflictuels, l'activation du service, la constatation d'une
installation déjà en place, et l'échec d'`apt-get update` sur une suite
inexistante.

Ce que cela ne permet pas : prouver qu'un `docker run hello-world` fonctionne.
C'est assumé, et c'est aussi la raison pour laquelle `verify-docker.sh` — qui
lance un conteneur de test — reste une tâche distincte.

## Le niveau `integration` tourne sous le profil `debian`

`tests/run.sh integration` s'exécute dans le profil **`debian`**, qui n'a pas
d'init : `systemctl` n'y répond pas. `tests/README.md` l'écrit — *ne jamais
lancer le niveau `integration` sous le profil `systemd`*.

Deux conséquences pour le fichier de cas :

- tout ce qui touche `systemctl` passe par le **faux binaire**, jamais par le
  vrai. Sous le profil `debian`, il n'y a de toute façon rien à masquer ;
- un cas qui exigerait réellement un init se déclare `NON EXÉCUTÉ` **par
  nature**, jamais « environnement indisponible ». Le profil `debian` n'a pas
  systemd et ne l'aura jamais : c'est l'exemple canonique du `tests/README.md`
  §2. Une seule indisponibilité ferait sortir le niveau en 3, et la validation
  `tests/run.sh integration` cesserait d'être verte alors que rien ne serait
  cassé.

Le champ `environment` vaut malgré tout `container-systemd` : la cinquième
validation appelle `--dry-run` sous ce profil, et c'est là que le comportement
du script face à un init réel se constate.

## Pièges de l'installation par dépôt officiel

**L'URL dépend de la distribution.** `https://download.docker.com/linux/debian`
et `.../linux/ubuntu` sont deux dépôts distincts, avec deux clés et deux jeux de
suites. Le segment se déduit d'`OS_ID`, jamais d'une valeur écrite en dur.

**Le nom de code se lit, il ne se devine pas.** `VERSION_CODENAME` de
`/etc/os-release` donne `bookworm`, `trixie`, `jammy`, `noble`. Sur les dérivés
d'Ubuntu, c'est `UBUNTU_CODENAME` qu'il faut lire — nos cibles sont des Ubuntu
franches, la remarque vaut pour le jour où ce ne serait plus le cas.

**`apt-key` est déprécié.** La clé va dans `/etc/apt/keyrings`, lisible par
tous (`chmod a+r`), et la ligne de dépôt la désigne par `signed-by=`. Une clé
déposée dans `/etc/apt/trusted.gpg.d` vaudrait pour *tous* les dépôts de la
machine.

**`curl` et `ca-certificates` sont des prérequis du prérequis.** Ils ne sont pas
garantis sur un serveur neuf : le script les installe lui-même avant d'aller
chercher la clé. C'est ce que fait la documentation officielle, et c'est une
dépendance à annoncer dans le résumé des changements.

**`set -Eeuo pipefail` et les tubes.** La forme
`curl … | gpg --dearmor -o …` propage l'échec de `curl` par `pipefail`, mais
laisse un fichier tronqué derrière elle. Écrire dans un temporaire, contrôler,
puis déplacer.

**Un dépôt écrit puis inutilisable est pire que pas de dépôt du tout.** Si
`apt-get update` échoue parce que la suite n'existe pas pour ce nom de code, le
fichier `/etc/apt/sources.list.d/docker.list` doit être retiré : sinon *toute*
mise à jour ultérieure de la machine — `update-system.sh` compris — signalera
une erreur, longtemps après et loin de sa cause.

**Le fichier de cas partage un unique conteneur.** `tests/run.sh integration`
s'exécute dans un seul conteneur pour tous les fichiers de cas. Un
`docker.list` ou un keyring laissé derrière soi polluerait les autres. Le cas
nettoie ce qu'il a écrit, et le vérifie.

## Décisions que cette tâche tranche

Réversibles et locales au sens d'[AGENTS.md](../../AGENTS.md) §14, fixées ici
pour ne pas être rediscutées pendant l'exécution, et à consigner dans le
rapport.

**Aucun `--config`.** Ce script ne lit aucune configuration applicative :
tout ce dont il a besoin, il le détecte. `CLAUDE.md` emploie `install-docker.sh`
comme *illustration* du pattern `--config` ; ce n'est pas une exigence. Les
valeurs de machine appartiennent à `configure-docker.sh` (TASK-030), qui les lit
dans `config/server.env` — chargé de lui-même par `lib/common.sh`, donc sans
`--config` non plus.

**Architectures : `amd64` et `arm64`, rien d'autre.** `armhf` existe chez Docker
mais aucune machine du parc (ADR-0003 décision 17) n'en relève ; le refus est
propre et nommé plutôt qu'implicite.

**Le disque bloque, la mémoire avertit.** Un `/var` saturé fait échouer
l'installation à coup sûr ; une machine à 512 Mo installe Docker sans peine et
n'aura de difficulté qu'à l'usage. Seuil par défaut 2 Gio libres sous `/var`,
512 Mio de mémoire totale — deux valeurs basses, délibérément : elles servent à
attraper l'accident, pas à dicter un dimensionnement.

**Une installation déjà présente rend 0 sans rien faire.** C'est l'idempotence
attendue de tout script du dépôt. La réinstallation, la mise à jour et la
désinstallation ont chacune leur script au plan — `update-docker.sh`,
section 9 — et aucun n'est ici.

**Le refus « sans terminal » se prononce au moment de la question, pas avant.**
`--help` et `--dry-run` ne demandent jamais rien, et doivent donc rester
utilisables sans terminal — c'est même ainsi qu'ils s'exécutent dans le
conteneur de validation. Un contrôle de `[ -t 0 ]` placé en tête du script
rendrait les deux dernières validations insatisfaisables.

**Le retrait des paquets conflictuels est confirmé, jamais automatique.**
`docker.io` de Debian peut faire tourner des conteneurs en production : le
supprimer sans le dire les arrête. Le script liste ce qu'il a trouvé, dit ce que
le retrait implique, et demande. `--yes` vaut réponse.

## Ce dont je ne suis pas certain

**Le dépôt Docker pour Debian 13 (`trixie`).** ADR-0003 décision 14 inscrit
Debian 13 dans les cibles, mais je n'ai pas vérifié que `download.docker.com`
publie une suite `trixie`. C'est précisément pourquoi le critère « suite non
publiée » existe : le script ne tient **aucune liste de noms de code en dur**,
il lit celui de la machine, et si `apt-get update` ne trouve rien, il le dit et
se retire proprement. À constater à l'implémentation, et à écrire dans le
`README.md` du domaine.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 — 4 traduit en 0 par `tests/run.sh` si des cas sont sautés par nature |
| `run-in-container.sh -- bash …/install-docker.sh --help` | 0 |
| `run-in-container.sh --profil systemd -- bash …/install-docker.sh --dry-run` | 0, aucun fichier écrit, aucun appel à `apt-get` |

La dernière exige que `--dry-run` fonctionne **sur une machine où Docker est
absent** : le préflight y constate l'absence et décrit ce qu'il ferait, au lieu
de refuser. C'est le cas réel — on lance un installateur là où rien n'est encore
installé.

## Ce que la tâche laisse ouvert

À indexer au backlog, non atomisé ici : `verify-docker.sh` (section 8),
`update-docker.sh` (section 9), et la question de l'appartenance au groupe
`docker`, qui est une décision de sécurité et non un détail d'installation.
