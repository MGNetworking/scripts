# MGNetworking Scripts

Bibliothèque personnelle de scripts d'administration, d'installation, de
configuration et de maintenance d'infrastructure.

> Le dépôt est en cours de refactorisation. Voir
> [le plan](docs/refactorisation-plan.md) pour l'état d'avancement.

## Architecture

```text
Linux/       System (10 scripts) | Security | K3s
Kubernetes/  Installation | Configuration | Maintenance   (à venir)
Docker/      Installation | Configuration | Maintenance | Cleanup | Diagnostics
Synology/    Plex | Administration
lib/         fonctions communes (common.sh)
config/      server.env (la machine) + un <contexte>.env par application
docs/        socle technique, plan, guides
```

`Linux/` prépare le système, `Docker/` gère le moteur de conteneurs,
`Linux/K3s/` la distribution Kubernetes, `Kubernetes/` tout ce qui s'adresse à un
cluster quelle que soit son origine.

## Scripts disponibles

Chaque domaine décrit ses scripts, leurs prérequis, leurs risques et leur ordre
d'utilisation dans son propre README.

| Domaine | Contenu | État |
|---|---|---|
| [Linux/](Linux/README.md) | système de base, sécurité, distribution K3s | `System` : 10 scripts ; `Security`, `K3s` à venir |
| [Docker/](Docker/README.md) | moteur Docker : installation, configuration, maintenance, nettoyage, diagnostic | 6 scripts |
| `Kubernetes/` | installation, configuration et maintenance d'un cluster | à venir |
| [Synology/](Synology/README.md) | NAS Synology : Plex, administration DSM | 2 scripts hérités |

Socle commun : [config/](config/README.md) pour les configurations,
[tests/](tests/README.md) pour les validations.

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

## Développement assisté par agent

Le dépôt se dote d'une couche permettant à un agent automatique de reprendre le
chantier : lire le backlog, écrire un script, le valider dans un conteneur
jetable, rendre compte.

**Pour s'en servir :** [orchestration/README.md](orchestration/README.md).
Deux commandes suffisent — `/backlog` pour le point de situation, `/tache
TASK-xxx` pour faire exécuter une tâche par l'agent désigné dans sa fiche.

| Fichier | Rôle |
|---|---|
| [orchestration/](orchestration/README.md) | **fonctionnement des agents**, règles, décisions, modèles, outils, mesures |
| [tasks/](tasks/README.md) | backlog exécutable, une tâche par fichier |
| [tests/](tests/README.md) | validations — analyse statique, tests unitaires et d'intégration |
| `.claude/commands/` | `/tache <ID>` orchestre une tâche, `/executer-tache` est la consigne de l'agent, `/backlog` fait le point |
| `.claude/agents/` | sous-agents `relecteur` et `redacteur-tache` |

Le moteur est Claude Code — aucun programme d'orchestration n'est écrit. Les
règles, le backlog et les preuves appartiennent au dépôt ; `.claude/` ne décrit
que **qui** fait le travail et **comment on le lance**.

## Journalisation

Chaque script écrit à l'écran et dans un fichier nommé d'après lui :
`/var/log/mgnetworking/<script>.log` en root, `logs/<script>.log` sinon.

La rotation est assurée par `logrotate`, configuré une fois par serveur.

## Sécurité

Le dépôt est public. Aucun mot de passe, token, clé privée, kubeconfig ou
certificat ne doit y figurer. Les configurations réelles (`config/*.env`) ne sont
jamais versionnées ; seuls les modèles `*.env.example` le sont.
