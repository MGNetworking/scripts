# CLAUDE.md — MGNetworking/script

Bibliothèque personnelle de scripts d'administration, d'installation, de
configuration et de maintenance d'infrastructure Linux / K3s / Kubernetes /
Docker / Synology.

**Orchestration des agents :** [orchestration/](orchestration/README.md)
Fonctionnement des agents IA, règles de travail ([regles.md](orchestration/regles.md) :
périmètre, commandes, Git, validation, arrêt) et décisions en vigueur. Ce
document-ci dit *comment écrire un script* ; `orchestration/regles.md` dit
*comment conduire une tâche*. Backlog exécutable dans [tasks/](tasks/README.md).

**Socle technique :** [docs/architecture-technique.md](docs/architecture-technique.md)
Chargement de `lib/common.sh`, configurations de contexte, journalisation,
rotation des logs. Référence durable — à lire avant d'écrire un script.

**Plan du chantier :** [docs/refactorisation-plan.md](docs/refactorisation-plan.md)
Arborescence cible, inventaire script par script, phases de développement.
Document temporaire, caduc une fois la refactorisation terminée.

**Guide dispatcher :** [docs/guide-dispatcher.md](docs/guide-dispatcher.md)
Patterns de parsing d'arguments et templates de CLI.

**Registre des anomalies :** [tasks/pending/TASK-039.md](tasks/pending/TASK-039.md)
Seul lieu où consigner un défaut, une dette ou un point ouvert, plutôt que de
dévier du travail en cours. `docs/points-en-suspens.md` n'est plus qu'une archive.

---

## Arborescence cible

```text
Ansible/     roles | playbooks | inventory.example.yml | CADRAGE.md
Linux/       System | Security | K3s
Kubernetes/  Installation | Configuration | Maintenance
Docker/      Installation | Configuration | Maintenance | Cleanup | Diagnostics
Synology/    Plex | Administration
lib/         fonctions communes (common.sh)
config/      server.env (la machine) + un <contexte>.env par application
docs/        socle technique, plan, guides
```

Ne pas mélanger les couches : `Linux/` prépare l'OS, `Docker/` gère le moteur de
conteneurs, `Linux/K3s/` la distribution, `Kubernetes/` l'orchestration.
Les workloads gérés par Kubernetes ne s'administrent jamais via `docker restart`
ou équivalent.

Frontière `Linux/K3s/` ↔ `Kubernetes/` : si le script survivrait au remplacement
de K3s par un cluster managé, il va dans `Kubernetes/` ; sinon dans `Linux/K3s/`,
qui reste plat.

Frontière `Docker/Diagnostics/` ↔ le reste de `Docker/` : `Diagnostics/` est en
lecture seule, sans exception. Un script qui modifie quoi que ce soit sur la
machine n'y a pas sa place, même si sa sortie ressemble à un rapport.

Frontière `Ansible/` ↔ Bash ([décision 50](orchestration/decisions.md)) : installer
et configurer une machine relève d'un rôle Ansible ; diagnostiquer en lecture seule,
exploiter ponctuellement (sauvegarde, nettoyage, redémarrage, notification) et
`Synology/` restent en Bash. Un script remplacé par un rôle est déprécié avec une
date dans son cadrage, jamais supprimé sans décision de Maxime.

## Conventions minimales d'un rôle

- Contrat dans `meta/argument_specs.yml` : chaque variable, son type, son défaut ;
  état garanti et fichiers ou services touchés dans `Ansible/CADRAGE.md`.
- Idempotent : un second passage ne change rien (étape `idempotence` de Molecule).
- Scénario Molecule avec `verify.yml` ; `ansible-lint` et `yamllint` sans faute.
- Inventaire réel, `host_vars` réels et secrets hors Git : seuls les
  `*.example.yml` sont versionnés ; secrets par Ansible Vault.
- Application : `--check --diff`, puis sans `--check`, serveur par serveur (`--limit`).

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

`lib/common.sh` assure la journalisation et les vérifications. Le seul fichier
qu'il charge de lui-même est `config/server.env` (contexte de la machine) ;
toutes les autres configurations passent par `load_config`.

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
