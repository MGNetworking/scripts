# Docker

Installation, configuration, maintenance, nettoyage et diagnostic du **moteur
Docker** sur une machine Linux — Engine, client, `containerd`, plugins Compose
et Buildx.

`Docker/` s'arrête au moteur. Les workloads gérés par Kubernetes ne
s'administrent jamais d'ici : cela relève de `Kubernetes/`. Le domaine ne
connaît aucune application déployée — ni son nom, ni son fichier Compose.

## Arborescence

```text
Docker/
├── Installation/   poser le moteur, vérifier ce qu'on vient de poser
├── Configuration/  daemon.json, réseaux partagés entre projets
├── Maintenance/    mise à jour du moteur et des images
├── Cleanup/        récupération des ressources inutilisées
└── Diagnostics/    LECTURE SEULE, sans exception
```

**`Diagnostics/` est en lecture seule, sans exception** — frontière posée par
[CLAUDE.md](../CLAUDE.md). Elle exclut le lancement d'un conteneur de test, fût-il
`hello-world` : tirer une image écrit dans `/var/lib/docker`.

## Prérequis

Debian 12 ou 13, Ubuntu 22.04 ou 24.04 LTS. Les scripts de diagnostic
s'exécutent sans privilège ; ceux qui modifient le système demandent root.

## Scripts

| Script | Rôle | Privilège | Modifie |
|---|---|---|---|
| [`Installation/install-docker.sh`](Installation/install-docker.sh) | pose Engine, CLI, containerd, Buildx et Compose depuis les dépôts officiels | root | **oui** |
| [`Configuration/configure-docker.sh`](Configuration/configure-docker.sh) | écrit `/etc/docker/daemon.json` : rotation des journaux de conteneurs, clés existantes conservées | root | **oui** |
| [`Configuration/create-network.sh`](Configuration/create-network.sh) | crée un réseau Docker nommé, partageable par plusieurs projets Compose ; ne supprime jamais | root | **oui** |
| [`Maintenance/update-images.sh`](Maintenance/update-images.sh) | récupère les images d’un projet Compose désigné par `--project` ; ne redéploie rien, affiche avant/après et la commande de redéploiement | groupe docker | **oui** |
| [`Maintenance/update-docker.sh`](Maintenance/update-docker.sh) | met à jour les composants Docker installés, et eux seuls ; relevé avant/après, annonce de la coupure des conteneurs | root | **oui**, redémarre le démon |
| [`Diagnostics/check-docker.sh`](Diagnostics/check-docker.sh) | diagnostique une machine qu'on découvre : client, socket, service, démon, versions, stockage | aucun | non |
| [`Diagnostics/list-containers.sh`](Diagnostics/list-containers.sh) | inventaire des conteneurs : nom, image, état, identifiant, ports, réseaux — actifs par défaut, tous avec `--all` | aucun | non |
| [`Diagnostics/docker-disk-usage.sh`](Diagnostics/docker-disk-usage.sh) | stockage consommé par Docker : images, conteneurs, volumes, cache de build, espace récupérable ; `--detail` pour le détail | aucun | non |
| [`Cleanup/docker-cleanup.sh`](Cleanup/docker-cleanup.sh) | nettoie conteneurs arrêtés, réseaux inutilisés hors infrastructure et images orphelines ; volumes sur `--supprimer-volumes` | groupe docker | **oui**, destructif |

## Ordre d'utilisation

```bash
./Docker/Diagnostics/check-docker.sh          # que porte cette machine ?
./Docker/Installation/install-docker.sh --dry-run
./Docker/Installation/install-docker.sh --yes
./Docker/Configuration/configure-docker.sh --dry-run
./Docker/Configuration/configure-docker.sh --yes   # redémarre le démon si le fichier change
./Docker/Configuration/create-network.sh proxy       # réseau externe partagé, idempotent
./Docker/Diagnostics/check-docker.sh          # et maintenant ?
```

### `install-docker.sh`

Écrit `/etc/apt/keyrings/docker.asc` et `/etc/apt/sources.list.d/docker.list`,
installe les cinq paquets officiels, active et démarre le service.

Le nom de code de la suite apt est lu dans `/etc/os-release` : aucun n'est écrit
en dur, sans quoi le script mentirait au premier Debian suivant. Si le dépôt ne
publie pas encore cette suite, `apt-get update` échoue, le fichier de dépôt est
**retiré** et le script rend 1 — il ne laisse pas un apt cassé derrière lui.

Une installation déjà en place est constatée et rend 0 : rien n'est réinstallé,
écrasé ni supprimé. Les paquets en conflit (`docker.io`, `podman-docker`,
`containerd`…) ne sont retirés qu'après confirmation explicite.

Hors terminal, `--yes` est obligatoire : sans lui le script s'arrête **avant**
de poser sa question plutôt que de mourir sur un `read` impossible.

N'ajoute personne au groupe `docker` : donner le démon à un compte non
privilégié équivaut à donner root, cela se décide à part.

### `check-docker.sh`

Codes : `0` le client est présent et le démon répond — `1` client absent, démon
injoignable, socket interdit ou délai dépassé — `2` option inconnue.

L'absence de Docker n'est pas une erreur du script mais un constat, ce qui
permet d'enchaîner `check-docker.sh || install-docker.sh`.

Un démon qui répond alors que `docker.service` est inactif vaut `0`, assorti
d'un `[WARN]` : le service peut être activé par socket, et `DOCKER_HOST` peut
désigner une machine distante. C'est la réponse du démon qui fait foi.

Chaque interrogation est bornée à 5 secondes, pour qu'un démon qui ne répond
plus ne fige pas le diagnostic.

## Risques

`install-docker.sh` modifie le système : il écrit deux fichiers dans `/etc/apt`,
installe cinq paquets et active un service. Il ne retire rien sans confirmation
explicite, et `--dry-run` montre tout cela sans rien écrire.

`docker-cleanup.sh` est **destructif** : il supprime les conteneurs arrêtés, les
réseaux sans conteneur et les images orphelines, après avoir tout listé et demandé
confirmation. Les volumes, qui portent les données, n'en font partie qu'avec
`--supprimer-volumes` et une seconde confirmation. Les réseaux d'infrastructure
listés dans `SRV_DOCKER_RESEAUX_PROTEGES` (et `SRV_DOCKER_NETWORK`) ne sont jamais
touchés, et `docker network prune` n'est jamais employé. `--dry-run` montre tout
sans rien supprimer ; `--yes` est le seul mode planifiable.
