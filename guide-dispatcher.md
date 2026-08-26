# Guide — Créer un CLI avec dispatcher en Bash

Ce guide explique comment construire un point d'entrée unique (dispatcher) qui
redirige vers les bons scripts selon la commande reçue — comme `git`, `docker` ou
`kubectl` le font.

---

## Concept

Un dispatcher est un script "chef d'orchestre" qui :
1. Lit le premier argument (`$1`) comme une **commande**
2. Redirige vers le bon script avec le reste des arguments (`$@`)
3. Affiche une aide si la commande est inconnue

```
./mon-cli <commande> [sous-commande] [options] [valeur]
    ↓
  case "$1"
    ↓
  script-cible.sh "$@"   ← transmet TOUT le reste intact
```

Exemple concret :
```bash
./mon-cli db backup  --env production
./mon-cli db restore --env production fichier.sql.gz
./mon-cli infra deploy --env staging --no-wait
```

---

## Les deux méthodes de parsing d'arguments

### Méthode 1 — while / case (simple, lisible)

Utilisée dans les projets d'infrastructure (nas-infrastructur). Recommandée pour
la plupart des scripts.

```bash
ENV=""
NO_WAIT="false"

while [ "${1:-}" != "" ]; do
    case "$1" in
        --env)
            shift                    # consomme "--env"
            ENV="$1"                 # $1 est maintenant la valeur
            shift                    # consomme la valeur
            ;;
        --no-wait)
            NO_WAIT="true"
            shift                    # flag sans valeur : un seul shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Option inconnue: $1" >&2
            exit 2
            ;;
    esac
done
```

**Mécanique de `shift` :**

```
Avant       →  $1="--env"   $2="production"   $3="--no-wait"
shift       →  $1="production"   $2="--no-wait"
ENV="$1"    →  ENV="production"
shift       →  $1="--no-wait"
```

### Méthode 2 — getopt (robuste, gère les formes courtes `-e prod`)

Utilisée dans `exemple_option.sh`. Recommandée quand tu veux supporter `-e prod`
et `--env prod` simultanément.

```bash
SHORT="he:n"
LONG="help,env:,no-wait"

PARSED=$(getopt -o "$SHORT" -l "$LONG" -n "$0" -- "$@") || exit 2
eval set -- "$PARSED"

while true; do
    case "$1" in
        -h|--help)   show_help; exit 0 ;;
        -e|--env)    ENV="$2"; shift 2 ;;
        -n|--no-wait) NO_WAIT="true"; shift ;;
        --)          shift; break ;;
        *)           echo "Erreur interne" >&2; exit 2 ;;
    esac
done
```

**Quand choisir quoi :**

| Critère | while/case | getopt |
|---|---|---|
| Lisibilité | Très lisible | Moins immédiat |
| Formes courtes (`-e`) | Non | Oui |
| Arguments positionnels mélangés aux options | Oui | Oui (après `--`) |
| Dépendances | Aucune | `getopt` (présent partout) |

---

## Structure de projet recommandée

```
mon-projet/
├── cli.sh                    ← dispatcher (point d'entrée unique)
├── commands/
│   ├── cmd-db.sh             ← groupe de commandes "db"
│   ├── cmd-infra.sh          ← groupe de commandes "infra"
│   └── cmd-backup.sh         ← groupe de commandes "backup"
├── lib/
│   └── common.sh             ← fonctions partagées (log, couleurs, etc.)
└── config/
    ├── production.env
    └── staging.env
```

---

## Template — lib/common.sh

Fonctions partagées entre tous les scripts. À sourcer en début de chaque script.

```bash
#!/bin/bash
# lib/common.sh — fonctions partagées

# Couleurs
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERREUR]${NC}  $*" >&2; }
die()         { log_error "$*"; exit 1; }

# Résolution de la racine du projet depuis n'importe quel script
# Usage : source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/common.sh"
resolve_project_root() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    echo "$(cd "$script_dir/.." && pwd)"
}
```

---

## Template — cli.sh (le dispatcher)

```bash
#!/bin/bash
# cli.sh — Point d'entrée unique du projet
#
# Usage:
#   ./cli.sh <commande> [sous-commande] [options]
#
# Commandes disponibles:
#   db      backup | restore         Opérations base de données
#   infra   deploy | restart | reset Gestion de l'infrastructure
#   help                             Afficher cette aide

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Chargement des fonctions communes
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# -------------------------------------------------------------------
# Aide globale
# -------------------------------------------------------------------
show_help() {
    cat <<EOF

Usage: $(basename "$0") <commande> [sous-commande] [options]

COMMANDES

  infra
    deploy   --env <env>              Déploie l'infrastructure
    restart  --env <env>              Redémarre tous les services
    reset    --env <env> [--keep-data] Réinitialise (destructif)

  db
    backup   --env <env>              Backup interactif
    restore  --env <env> <fichier>    Restaure depuis un fichier

  help                                Afficher cette aide

ENVIRONNEMENTS
  production | staging | local

EXEMPLES
  $(basename "$0") infra deploy  --env production
  $(basename "$0") infra restart --env staging
  $(basename "$0") db    backup  --env production
  $(basename "$0") db    restore --env production backup-2025-01-15.sql.gz

EOF
}

# -------------------------------------------------------------------
# Dispatcher principal
# -------------------------------------------------------------------
COMMAND="${1:-}"

# Pas d'argument → aide
[ -n "$COMMAND" ] || { show_help; exit 0; }
shift   # consomme la commande — $@ contient le reste

case "$COMMAND" in
    infra)
        exec "$SCRIPT_DIR/commands/cmd-infra.sh" "$@"
        ;;
    db)
        exec "$SCRIPT_DIR/commands/cmd-db.sh" "$@"
        ;;
    help|-h|--help)
        show_help
        exit 0
        ;;
    *)
        log_error "Commande inconnue: '$COMMAND'"
        echo ""
        show_help
        exit 2
        ;;
esac
```

> **`exec` remplace le processus courant** par le script cible au lieu d'en créer
> un sous-processus. C'est plus propre et plus efficace — le code de retour du
> script cible devient directement celui du dispatcher.

---

## Template — commands/cmd-infra.sh (sous-script avec sous-commandes)

```bash
#!/bin/bash
# commands/cmd-infra.sh — Commandes d'infrastructure
#
# Appelé par cli.sh : cli.sh infra <sous-commande> [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=../lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"

# -------------------------------------------------------------------
# Aide de la commande infra
# -------------------------------------------------------------------
show_help() {
    cat <<EOF
Usage: cli.sh infra <sous-commande> --env <env> [options]

SOUS-COMMANDES
  deploy   --env <env> [--no-wait]   Déploie l'infrastructure
  restart  --env <env>               Redémarre tous les services
  reset    --env <env> [--keep-data] Réinitialise (destructif)

EOF
}

# -------------------------------------------------------------------
# Dispatcher de la sous-commande
# -------------------------------------------------------------------
SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] || { show_help; exit 0; }
shift   # consomme la sous-commande

case "$SUBCOMMAND" in
    deploy)
        # Parsing des options propres à "deploy"
        ENV=""
        NO_WAIT="false"

        while [ "${1:-}" != "" ]; do
            case "$1" in
                --env)     shift; ENV="$1"; shift ;;
                --no-wait) NO_WAIT="true"; shift ;;
                -h|--help) show_help; exit 0 ;;
                *) die "Option inconnue: $1" ;;
            esac
        done

        [ -n "$ENV" ] || die "--env est obligatoire"

        log_info "Déploiement sur '$ENV' (no-wait=$NO_WAIT)..."
        # Appel du vrai script de déploiement :
        # exec "$PROJECT_ROOT/scripts/deploy.sh" --env "$ENV"
        ;;

    restart)
        ENV=""

        while [ "${1:-}" != "" ]; do
            case "$1" in
                --env) shift; ENV="$1"; shift ;;
                *) die "Option inconnue: $1" ;;
            esac
        done

        [ -n "$ENV" ] || die "--env est obligatoire"

        log_info "Redémarrage sur '$ENV'..."
        # exec "$PROJECT_ROOT/scripts/restart.sh" --env "$ENV"
        ;;

    reset)
        ENV=""
        KEEP_DATA="false"

        while [ "${1:-}" != "" ]; do
            case "$1" in
                --env)       shift; ENV="$1"; shift ;;
                --keep-data) KEEP_DATA="true"; shift ;;
                *) die "Option inconnue: $1" ;;
            esac
        done

        [ -n "$ENV" ] || die "--env est obligatoire"

        log_warning "Reset sur '$ENV' (keep-data=$KEEP_DATA)"
        # exec "$PROJECT_ROOT/scripts/reset.sh" --env "$ENV"
        ;;

    -h|--help)
        show_help
        exit 0
        ;;
    *)
        log_error "Sous-commande inconnue: '$SUBCOMMAND'"
        show_help
        exit 2
        ;;
esac
```

---

## Template — commands/cmd-db.sh (sous-script avec argument positionnel)

Exemple avec un argument positionnel en plus des options (`restore` attend un
nom de fichier après les options).

```bash
#!/bin/bash
# commands/cmd-db.sh — Commandes base de données

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/lib/common.sh"

show_help() {
    cat <<EOF
Usage: cli.sh db <sous-commande> --env <env> [options]

SOUS-COMMANDES
  backup   --env <env>              Backup interactif
  restore  --env <env> <fichier>    Restaure depuis un fichier

EOF
}

SUBCOMMAND="${1:-}"
[ -n "$SUBCOMMAND" ] || { show_help; exit 0; }
shift

case "$SUBCOMMAND" in
    backup)
        ENV=""

        while [ "${1:-}" != "" ]; do
            case "$1" in
                --env) shift; ENV="$1"; shift ;;
                *) die "Option inconnue: $1" ;;
            esac
        done

        [ -n "$ENV" ] || die "--env est obligatoire"
        log_info "Backup sur '$ENV'..."
        ;;

    restore)
        ENV=""
        FILE=""

        while [ "${1:-}" != "" ]; do
            case "$1" in
                --env) shift; ENV="$1"; shift ;;
                # Tout argument ne commençant pas par -- est le fichier
                *)
                    if [[ "$1" != --* ]]; then
                        FILE="$1"
                        shift
                    else
                        die "Option inconnue: $1"
                    fi
                    ;;
            esac
        done

        [ -n "$ENV"  ] || die "--env est obligatoire"
        [ -n "$FILE" ] || die "Nom du fichier backup obligatoire"
        [ -f "$PROJECT_ROOT/backups/$FILE" ] || die "Fichier introuvable: backups/$FILE"

        log_info "Restauration de '$FILE' sur '$ENV'..."
        ;;

    -h|--help)
        show_help; exit 0 ;;
    *)
        log_error "Sous-commande inconnue: '$SUBCOMMAND'"
        show_help; exit 2 ;;
esac
```

---

## Transmission des arguments avec `$@`

C'est le mécanisme clé qui rend le dispatcher transparent.

```bash
# Dans cli.sh, après shift sur la commande :
exec "$SCRIPT_DIR/commands/cmd-infra.sh" "$@"
```

```
Appel    : ./cli.sh infra deploy --env production --no-wait
$1       : "infra"     ← shift le consomme dans cli.sh
$@       : "deploy" "--env" "production" "--no-wait"
                  ↓ transmis tel quel à cmd-infra.sh
cmd-infra.sh reçoit : $1="deploy" $2="--env" $3="production" $4="--no-wait"
```

Règle : **toujours quoter `"$@"`**, jamais `$@` seul — sinon les arguments
avec des espaces seraient découpés.

---

## Rendre le CLI accessible partout (optionnel)

Pour appeler `mon-cli` depuis n'importe où sans `./` :

```bash
# Option 1 — lien symbolique dans /usr/local/bin
sudo ln -s /chemin/absolu/vers/cli.sh /usr/local/bin/mon-cli

# Option 2 — alias dans ~/.bashrc
echo 'alias mon-cli="/chemin/absolu/vers/cli.sh"' >> ~/.bashrc
source ~/.bashrc

# Après l'une ou l'autre :
mon-cli infra deploy --env production
```

---

## Récapitulatif des patterns

| Pattern | Rôle | Fichier |
|---|---|---|
| `COMMAND="${1:-}"; shift` | Lit et consomme la commande | dispatcher |
| `case "$COMMAND" in` | Redirige vers le bon script | dispatcher |
| `exec "$SCRIPT" "$@"` | Transmet le reste sans créer de sous-processus | dispatcher |
| `while [ "${1:-}" != "" ]` | Parse les options du sous-script | sous-script |
| `shift` / `shift 2` | Consomme 1 ou 2 arguments | sous-script |
| `source lib/common.sh` | Partage les fonctions de log | tous |
| `[ -n "$VAR" ] \|\| die "..."` | Valide les variables obligatoires | tous |

---

## Référence — projet nas-infrastructur

Le projet `nas-infrastructur` (swarm-iam-platform) applique ces mêmes patterns
sans dispatcher central. Chaque script est autonome et accepte `--env` :

```bash
# Pattern de chargement de config utilisé dans ce projet :
ENV_DIR="$PROJECT_ROOT/environments/$ENV_NAME"
set -a
for CONF_FILE in "$ENV_DIR/.env" "$ENV_DIR"/*.env; do
    source "$CONF_FILE"
done
set +a
```

Un dispatcher pour ce projet ressemblerait à :

```bash
# Exemple de ce que donnerait un cli.sh pour nas-infrastructur
./cli.sh infra  deploy  --env linux-server
./cli.sh infra  restart --env linux-server
./cli.sh infra  reset   --env linux-server --keep-data
./cli.sh db     backup  --env linux-server
./cli.sh db     restore --env linux-server CLUSTER-2025-12-28.sql.gz
```

Voir `docs/scripts-guide.md` et `docs/scripts-cheatsheet.md` dans ce projet
pour la documentation des scripts existants.
