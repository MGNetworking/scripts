# CLAUDE.md — MGNetworking/script

Bibliothèque personnelle de scripts d'administration, d'installation, de
configuration et de maintenance d'infrastructure Linux / K3s / Kubernetes /
Docker / Synology.

**Socle technique :** [docs/architecture-technique.md](docs/architecture-technique.md)
Chargement de `lib/common.sh`, configurations de contexte, journalisation,
rotation des logs. Référence durable — à lire avant d'écrire un script.

**Plan du chantier :** [docs/refactorisation-plan.md](docs/refactorisation-plan.md)
Arborescence cible, inventaire script par script, phases de développement.
Document temporaire, caduc une fois la refactorisation terminée.

**Guide dispatcher :** [docs/guide-dispatcher.md](docs/guide-dispatcher.md)
Patterns de parsing d'arguments et templates de CLI.

---

## Arborescence cible

```text
Linux/       System | Security | Docker | K3s
Kubernetes/  Installation | Configuration | Maintenance
Docker/      Installation | Maintenance | Cleanup
Synology/    Plex | Administration
lib/         fonctions communes (common.sh)
config/      un <contexte>.env par domaine ; seuls les .example sont versionnés
docs/        socle technique, plan, guides
```

Ne pas mélanger les couches : `Linux/` prépare l'OS, `Docker/` gère le moteur de
conteneurs, `Linux/K3s/` la distribution, `Kubernetes/` l'orchestration.
Les workloads gérés par Kubernetes ne s'administrent jamais via `docker restart`
ou équivalent.

## Conventions de script

En-tête obligatoire — les trois lignes de résolution fonctionnent à n'importe
quelle profondeur et quel que soit le dossier de déploiement :

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
```

Fonctions disponibles : `info` `warn` `error` `success` `die`, `require_root`
`require_cmd` `require_os` `detect_os`, `confirm`, `run_logged` (capture la
sortie d'une commande externe), `enable_full_logging` (capture tout le script)
et `load_config`. Ne jamais redéfinir localement ce que `common.sh` fournit déjà.

`lib/common.sh` assure la journalisation et les vérifications, rien d'autre. Il
ne charge aucune configuration de lui-même.

Un script qui a besoin d'une configuration expose `--config <nom>`, avec le nom
de son contexte par défaut, et appelle `load_config` **après** le parsing :

```bash
CONFIG="docker"
while [ "${1:-}" != "" ]; do
    case "$1" in
        --config) shift; CONFIG="$1"; shift ;;
        *) die "Option inconnue : $1" 2 ;;
    esac
done
load_config "$CONFIG"
```

Le nom du fichier peut ainsi différer d'une machine à l'autre sans modifier le
script : `./install-docker.sh --config docker-vps2` charge
`config/docker-vps2.env`.

- Nommage `verb-noun.sh` : `install-docker.sh`, `configure-ssh.sh`, `verify-k3s.sh`.
- Responsabilité unique. Séparer installation, configuration, vérification et
  maintenance en scripts distincts.
- Messages préfixés `[INFO]`, `[WARN]`, `[ERROR]`, `[SUCCESS]`.
- Idempotence dès que possible : lire l'état actuel, comparer à l'état souhaité,
  ne modifier que si nécessaire. Jamais d'ajout aveugle du type
  `echo "..." >> /etc/fichier`.
- `--dry-run` sur toute opération destructive.
- Aucune suppression de données sans confirmation explicite.
- Réutiliser `lib/common.sh` plutôt que dupliquer du Bash.

## Ordre des scripts d'installation

```text
arguments → privilèges → OS → architecture → ressources → dépendances
→ conflits → résumé des changements → confirmation → exécution → vérification
```

Ne jamais supposer qu'un logiciel est installé. Détecter OS et architecture avant
d'installer. Utiliser les mécanismes officiels d'installation — ne pas copier
d'installateur tiers dans le dépôt.

## Secrets

Le dépôt est public et doit pouvoir le rester. Ne jamais versionner : mots de
passe, tokens, clés privées, credentials de registry, kubeconfig, secrets
Kubernetes, certificats privés.

Utiliser à la place des variables d'environnement, des fichiers locaux ignorés
par Git, des secrets Kubernetes ou un gestionnaire de secrets.

Configuration séparée du code : un fichier par contexte dans `config/`, chargé
par `load_config <contexte>`. Les `*.env.example` sont versionnés, les `*.env`
réels jamais. Voir [config/README.md](config/README.md).

## Consignes de mise en oeuvre

- Ne pas créer de fonctionnalités non demandées.
- Ne pas introduire de dépendance inutile.
- Tester les commandes utilisées avant de les intégrer.
- Préserver l'exécution répétée : relancer un script ne doit rien casser.
- Documenter les effets et les risques de chaque script.

## Documentation

Chaque domaine porte son `README.md` : rôle, prérequis, scripts disponibles,
ordre d'utilisation, risques, systèmes supportés, commandes d'exécution.
Mettre à jour la doc dans le même commit que le script.
