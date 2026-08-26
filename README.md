# MGNetworking Scripts

Bibliothèque personnelle de scripts d'administration, d'installation, de
configuration et de maintenance d'infrastructure.

> Le dépôt est en cours de refactorisation. Seuls le socle commun et les scripts
> Synology existent à ce jour ; les domaines Linux, Docker et Kubernetes sont à
> développer. Voir [le plan](docs/refactorisation-plan.md).

## Architecture

```text
Linux/       System | Security | Docker | K3s      (à venir)
Kubernetes/  Installation | Configuration | Maintenance   (à venir)
Docker/      Installation | Maintenance | Cleanup   (à venir)
Synology/    Plex | Administration
lib/         fonctions communes (common.sh)
config/      un <contexte>.env par domaine
docs/        socle technique, plan, guides
```

`Linux/` prépare le système, `Docker/` gère le moteur de conteneurs,
`Linux/K3s/` la distribution Kubernetes, `Kubernetes/` tout ce qui s'adresse à un
cluster quelle que soit son origine.

## Installation sur un serveur

```bash
git clone git@github.com:MGNetworking/script.git /opt/mgnetworking
cd /opt/mgnetworking
cp config/<contexte>.env.example config/<contexte>.env   # selon les scripts utilisés
```

Le dépôt fonctionne quel que soit son emplacement : chaque script résout la
racine du projet à l'exécution.

## Conventions

Tout script commence par :

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
```

`lib/common.sh` fournit la journalisation (`info`, `warn`, `error`, `success`,
`die`, `run_logged`), les vérifications (`require_root`, `require_cmd`,
`require_os`), la confirmation interactive (`confirm`) et le chargement de
configuration (`load_config`).

Nommage `verb-noun.sh`. Idempotence dès que possible. `--dry-run` sur toute
opération destructive. Aucun secret versionné.

Détail des règles : [CLAUDE.md](CLAUDE.md).
Fonctionnement du socle : [docs/architecture-technique.md](docs/architecture-technique.md).

## Journalisation

Chaque script écrit à l'écran et dans un fichier nommé d'après lui :
`/var/log/mgnetworking/<script>.log` en root, `logs/<script>.log` sinon.

La rotation est assurée par `logrotate`, configuré une fois par serveur.

## Sécurité

Le dépôt est public. Aucun mot de passe, token, clé privée, kubeconfig ou
certificat ne doit y figurer. Les configurations réelles (`config/*.env`) ne sont
jamais versionnées ; seuls les modèles `*.env.example` le sont.
