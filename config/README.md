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
