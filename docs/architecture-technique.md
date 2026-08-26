# Architecture technique — socle commun

Ce document décrit le socle partagé par tous les scripts du dépôt : chargement
des fonctions communes, configurations de contexte, journalisation et rotation
des logs.

Contrairement à [refactorisation-plan.md](refactorisation-plan.md), qui décrit un
chantier et deviendra caduc une fois celui-ci terminé, ce document reste la
référence durable du fonctionnement interne des scripts.

---

## 1. Fins de ligne — `.gitattributes`

Les scripts sont écrits sous Windows mais exécutés sous Linux et sur Synology.
Un fichier enregistré avec des fins de ligne Windows (`CRLF`) provoque à
l'exécution :

```text
/usr/bin/env: bad interpreter: No such file or directory
```

Le shebang devient littéralement `#!/usr/bin/env bash\r`, et Linux cherche un
interpréteur nommé `bash\r`.

Le fichier `.gitattributes` à la racine impose donc :

```text
* text=auto eol=lf
```

Git normalise alors en `LF` au moment du commit et écrit du `LF` au checkout,
quelle que soit la machine et quel que soit l'éditeur. La règle étant versionnée,
elle suit le dépôt et ne dépend d'aucune configuration Git locale.

---

## 2. Chargement de `lib/common.sh`

Chaque script résout la racine du projet à l'exécution, sans chemin en dur :

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while [ ! -f "$_dir/lib/common.sh" ] && [ "$_dir" != "/" ]; do _dir="$(dirname "$_dir")"; done
source "$_dir/lib/common.sh"
```

`BASH_SOURCE[0]` donne le chemin du script en cours ; la boucle remonte
l'arborescence jusqu'à trouver `lib/common.sh`.

Conséquences :

- le dépôt fonctionne quel que soit son emplacement de déploiement
  (`/opt/mgnetworking/script`, `/volume1/development/scripts`, `~/dev/script`) ;
- la profondeur du script n'a pas d'importance — `Linux/System/` comme
  `Synology/Administration/backup/` utilisent les mêmes trois lignes ;
- aucune modification n'est nécessaire au déploiement.

Un `../../lib/common.sh` en dur aurait été plus court mais casse dès qu'un
script change de niveau dans l'arborescence.

`source` n'ouvre pas de sous-processus : le contenu de `common.sh` est inséré
dans le script appelant. Les variables sont donc partagées dans les deux sens.

---

## 3. Configuration de contexte

Deux natures de configuration coexistent, et une seule est chargée
automatiquement.

**`config/server.env` décrit la machine** : emplacement des journaux, nom
d'hôte, fuseau horaire, taille du fichier d'échange. C'est le seul fichier que
`lib/common.sh` charge de lui-même, parce que ces valeurs concernent le serveur
sur lequel tout s'exécute.

```bash
LOG_DIR="/var/log/mgnetworking"
SRV_HOSTNAME="k3s-master"
SRV_TIMEZONE="Europe/Paris"
SRV_SWAP_SIZE="2G"
```

Les variables portent le préfixe `SRV_` pour ne pas entrer en collision avec
celles de l'environnement — `HOSTNAME` existe déjà dans Bash, et l'écraser
produirait des effets difficiles à diagnostiquer. `LOG_DIR` fait exception, il
précède cette convention.

Un script lit d'abord son argument de ligne de commande et ne retombe sur la
variable qu'à défaut :

```bash
sudo ./configure-hostname.sh              # prend SRV_HOSTNAME
sudo ./configure-hostname.sh autre-nom    # l'argument l'emporte
```

**Les configurations applicatives** — Docker, K3s, Kubernetes, Synology — sont
chargées explicitement par le script qui en a besoin :

```bash
source "$_dir/lib/common.sh"

load_config docker      # -> config/docker.env
```

`load_config` résout le chemin depuis `SCRIPTS_ROOT`, ce qui évite de réécrire
la résolution dans chaque script. Un fichier demandé mais introuvable **arrête
le script** : poursuivre sans la configuration attendue serait plus dangereux
que s'arrêter.

### Nommer autrement selon la machine

Le nom du contexte est écrit dans le script, donc identique sur tous les
serveurs. Pour qu'il puisse varier, chaque script qui charge une configuration
expose `--config <nom>` et appelle `load_config` **après** le parsing :

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

```bash
./install-docker.sh                        # config/docker.env
./install-docker.sh --config docker-vps2   # config/docker-vps2.env
```

L'option est gérée par le script, jamais par `common.sh` : un script sans
configuration n'a pas à la connaître. C'est ce qui distingue cette solution d'un
`--config` pris en charge par `common.sh`, qui aurait imposé la contrainte aux
cinquante scripts du dépôt.

### Versionnement

| Fichier | Versionné |
|---|---|
| `config/<contexte>.env.example` | oui — modèle, valeurs neutres |
| `config/<contexte>.env` | **non** — propre à chaque serveur |

Le `.gitignore` porte `config/*.env` et l'exception `!config/*.env.example`.

Sur un serveur, à la mise en route :

```bash
cp config/docker.env.example config/docker.env
```

Ces fichiers sont chargés par `source` : uniquement des affectations, jamais de
commandes. Les passer en `chmod 600` s'ils contiennent autre chose que des
chemins.

---

## 4. Journalisation

Chaque message part vers deux destinations :

- **l'écran** (`stderr`), coloré, sans horodatage ;
- **le fichier**, en texte brut horodaté — les codes couleur pollueraient la
  lecture.

Les couleurs ne sont émises que si la sortie est un terminal (`[ -t 2 ]`).

Le fichier est nommé d'après le script : `install-k3s.sh` écrit dans
`install-k3s.log`.

### Emplacement des journaux

Deux niveaux, dans cet ordre :

| Priorité | Origine | Valeur |
|---|---|---|
| 1 | `config/server.env`, s'il existe | `LOG_DIR` tel qu'il y est défini |
| 2 | valeur par défaut, écrite en dur | `/var/log/mgnetworking` en root, `<racine>/logs` sinon |

Le dépôt fonctionne donc sans aucune configuration, tout en permettant de
déplacer les journaux serveur par serveur :

```bash
cp config/server.env.example config/server.env
```

`config/server.env` est le **seul** fichier que `common.sh` charge de lui-même,
parce qu'il décrit la machine elle-même. Les configurations applicatives restent
à la charge des scripts, via `load_config` (section 3).

`configure-logging.sh` lit ce même `LOG_DIR` : le répertoire créé, celui où les
journaux sont écrits et celui que surveille `logrotate` sont toujours le même.
Le nom de la règle `logrotate` en découle — `LOG_DIR=/var/log/mgn-test` produit
`/etc/logrotate.d/mgn-test`.

### Pourquoi écrire des logs

| Lancement | Écran | Fichier |
|---|---|---|
| manuel | visible | permet de relire plusieurs semaines après |
| par `cron` | invisible | **seule** trace disponible |

`update-system.sh`, `security-check.sh`, `backup-resources.sh` et
`docker-cleanup.sh` sont destinés à tourner en tâche planifiée : sans fichier, un
échec nocturne passerait inaperçu.

### Sortie des commandes externes

Les fonctions `info` / `warn` / `error` / `success` n'enregistrent que les
messages du script. La sortie d'`apt`, `kubectl` ou `docker` demande un des deux
mécanismes suivants.

**`run_logged`** — ciblé et prévisible, à préférer :

```bash
run_logged apt-get upgrade -y
```

La commande est annoncée dans le log, sa sortie y est ajoutée, et son code de
retour est préservé via `PIPESTATUS[0]`.

**`enable_full_logging`** — capture l'intégralité de la sortie du script, y
compris ce qui échappe à `run_logged`. À appeler une fois, juste après le
`source`, dans les scripts d'installation :

```bash
source "$_dir/lib/common.sh"
enable_full_logging
```

La sortie n'étant alors plus un terminal, les couleurs sont désactivées.

---

## 5. Rotation des logs

Un log non entretenu grossit sans fin. `logrotate`, présent par défaut sur
Debian, Ubuntu et Synology DSM, s'exécute une fois par jour et prend en charge
renommage, compression et purge. Aucun code n'est nécessaire dans les scripts.

Configuration, dans `/etc/logrotate.d/mgnetworking` :

```text
/var/log/mgnetworking/*.log {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root adm
}
```

| Directive | Effet |
|---|---|
| `weekly` | rotation hebdomadaire |
| `rotate 8` | huit semaines d'historique conservées |
| `compress` | les anciens fichiers sont compressés |
| `delaycompress` | le plus récent reste lisible sans `zcat` |
| `missingok` | pas d'erreur si le fichier n'existe pas encore |
| `notifempty` | aucune rotation d'un log vide |
| `create 0640 root adm` | permissions du fichier recréé |

Le motif `*.log` couvre **automatiquement tout nouveau script**. Cette
configuration n'a donc jamais à être modifiée, quel que soit le nombre de
scripts ajoutés au dépôt.

Résultat :

```text
/var/log/mgnetworking/
├── update-system.log        # en cours
├── update-system.log.1      # semaine précédente
├── update-system.log.2.gz   # compressé
└── update-system.log.9.gz   # le plus ancien conservé
```

Vérification et simulation, sans rien modifier :

```bash
which logrotate && sudo logrotate -d /etc/logrotate.d/mgnetworking
```

La mise en place est assurée par `Linux/System/configure-logging.sh`, lancé une
fois par serveur.

### Choix de `/var/log/mgnetworking`

`/var/log/` est l'emplacement normalisé des journaux sous Linux (FHS) — `nginx`
écrit dans `/var/log/nginx/`, `apt` dans `/var/log/apt/`. Le sous-répertoire
`mgnetworking` reprend le nom de l'organisation et évite que les journaux du
dépôt se dispersent parmi ceux du système ; il permet de tout consulter, archiver
ou purger d'un seul geste, et rend possible la règle `logrotate` unique
ci-dessus.

---

## 6. Pièges Bash rencontrés

**`set -e` et les listes `&&`** — un fichier terminé par une ligne du type :

```bash
[ -z "$LOG_DIR" ] && LOG_DIR="/defaut"
```

retourne un code d'erreur lorsque la condition est fausse. Si c'est la dernière
instruction d'un fichier chargé par `source`, le script appelant s'arrête sous
`set -e`. Utiliser systématiquement un `if` explicite.

**Double chargement** — `lib/common.sh` commence par une garde
(`_COMMON_SH_CHARGE`) afin qu'un chargement répété reste sans effet.
