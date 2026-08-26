# config/

Un fichier par contexte, nommé `<contexte>.env`, chargé explicitement par le
script qui en a besoin :

```bash
load_config docker      # -> config/docker.env
load_config k3s         # -> config/k3s.env
```

## `log.env` — la seule exception

`config/log.env` est chargé automatiquement par `lib/common.sh`, sans
`load_config` : il définit `LOG_DIR`, l'emplacement des journaux, qui relève de
la responsabilité de `common.sh`.

```bash
cp config/log.env.example config/log.env
```

Sans ce fichier, l'emplacement par défaut s'applique : `/var/log/mgnetworking` en
root, `<racine>/logs` sinon. Le dépôt fonctionne donc sans configuration.

Toutes les autres configurations passent par `load_config`.

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
