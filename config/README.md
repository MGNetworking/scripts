# config/

Un fichier par contexte, nommé `<contexte>.env`, chargé explicitement par le
script qui en a besoin :

```bash
load_config docker      # -> config/docker.env
load_config k3s         # -> config/k3s.env
```

## `server.env` — la seule exception

`config/server.env` décrit LA MACHINE : emplacement des journaux, nom d'hôte,
fuseau horaire, taille du fichier d'échange. Il est chargé automatiquement par
`lib/common.sh`, sans `load_config`.

```bash
LOG_DIR="/var/log/mgnetworking"
SRV_HOSTNAME="k3s-master"
SRV_TIMEZONE="Europe/Paris"
SRV_SWAP_SIZE="2G"
```

Les valeurs passées en ligne de commande priment toujours sur celles-ci.

```bash
cp config/server.env.example config/server.env
```

Sans ce fichier, les valeurs par défaut s'appliquent — `/var/log/mgnetworking` en
root, `<racine>/logs` sinon. Le dépôt fonctionne donc sans configuration.

Toutes les configurations applicatives passent par `load_config`.

## Nommer autrement selon la machine

Chaque script qui charge une configuration expose `--config <nom>` :

```bash
./Docker/Installation/install-docker.sh                        # config/docker.env
./Docker/Installation/install-docker.sh --config docker-vps2   # config/docker-vps2.env
```

Le dépôt reste identique sur tous les serveurs ; seul le nom passé au lancement
change. Sans l'option, c'est le nom du contexte qui s'applique.

## Versionnement

| Fichier | Versionné |
|---|---|
| `<contexte>.env.example` | oui — modèle, valeurs neutres |
| `<contexte>.env` | **non** — propre à chaque serveur |

Sur un serveur, à la mise en route :

```bash
cp config/docker.env.example config/docker.env
```

Ces fichiers sont chargés par `source` : uniquement des affectations, jamais de
commandes. Aucun secret ne doit y figurer en clair sur un dépôt public.

## Écriture : des affectations nues, exportées par le socle

La convention d'écriture ne change pas — une affectation par ligne, sans
`export` :

```bash
DOCKER_ROOT="/var/lib/docker"
```

`load_config` encadre son `source` par `set -a` / `set +a` : ces variables sont
donc **exportées**, et restent visibles des commandes que le script lance
ensuite, y compris `docker`, `kubectl` ou un script appelé. Écrire `export` dans
le fichier est inutile ; le faire n'est pas une erreur, simplement une
redondance.

Deux conséquences pratiques :

- une variable de contexte est visible de tout processus fils, même de ceux qui
  ne la demandent pas. Raison de plus pour n'y mettre **aucun secret** ;
- choisir des noms qui n'entrent pas en collision avec l'environnement — d'où le
  préfixe `SRV_` de `server.env`, `HOSTNAME` existant déjà dans Bash.

`config/server.env`, chargé directement par `lib/common.sh` et non par
`load_config`, ne bénéficie pas de cette exportation : ses variables alimentent
le script lui-même, pas ses processus fils.
