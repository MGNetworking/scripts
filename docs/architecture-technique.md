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
que s'arrêter. Un fichier présent mais **syntaxiquement invalide** arrête le
script de la même façon : `source` rend alors un code non nul, que `load_config`
transforme en `die`.

En revanche, une **commande en échec au milieu du fichier n'arrête plus le
script**. Le `source` poursuit jusqu'au bout et rend le code de sa dernière
commande — le plus souvent 0 —, si bien que la garde de `load_config` ne se
déclenche pas. C'est la contrepartie assumée du `set +a` rétabli quoi qu'il
arrive (voir plus bas) : placer le `source` dans un contexte de condition
suspend `errexit` pendant son exécution. Le risque reste théorique, parce que
[`config/README.md`](../config/README.md) prescrit des fichiers faits
d'affectations et **jamais de commandes**.

### Les variables chargées atteignent les processus fils

`load_config` encadre son `source` par `set -a` / `set +a`. Toute variable
affectée par le fichier est donc exportée, et reste visible des commandes que le
script lance ensuite :

```bash
# config/docker.env — affectation nue, aucun « export »
DOCKER_ROOT="/var/lib/docker"
```

```bash
load_config docker
printenv DOCKER_ROOT      # la valeur est visible : le processus fils l'a reçue
```

Sans cette exportation, un `.env` écrit en affectations nues — la forme que
`config/README.md` prescrit — n'aurait alimenté que le shell du script lui-même.
Les fichiers de configuration n'ont donc **pas** à écrire `export` : c'est le
socle qui s'en charge.

Deux conséquences à connaître :

- des variables sont exposées à des commandes qui ne les demandent pas. C'est la
  contrepartie assumée du choix ; elle est acceptable parce qu'un fichier de
  contexte ne contient **aucun secret** ;
- `set +a` est rétabli quoi qu'il arrive, y compris si le `source` échoue. Sans
  cela, tout ce que le script déclarerait ensuite se retrouverait exporté à son
  insu. Si l'appelant avait lui-même activé `allexport`, son état est préservé.

`config/server.env`, chargé directement par `common.sh` et non par
`load_config`, n'est pas concerné : ses variables alimentent le script courant,
pas ses processus fils. `SCRIPTS_ROOT` et les `OS_*` de `detect_os` sont, eux,
exportés explicitement.

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

### Un journal inaccessible n'interrompt pas le script

Deux moments distincts, deux comportements — aucun des deux n'est fatal.

| Moment | Situation | Comportement |
|---|---|---|
| au chargement | `LOG_DIR` non créable | `LOG_FILE` reste vide, aucun message |
| en cours d'exécution | le fichier devient inécrivable | **un** avertissement sur `stderr`, puis poursuite sans journal |

Le second cas survient quand le répertoire de journaux disparaît, que le disque
est plein ou que les droits ont changé pendant que le script tourne :

```text
[WARN] Journal inaccessible : /var/log/mgnetworking/update-system.log — poursuite sans journalisation.
```

L'avertissement est émis **une seule fois par exécution**, quel que soit le
nombre d'appels à `info` qui suivent : le socle vide `LOG_FILE`, ce qui est déjà
sa convention pour « pas de journal ». `run_logged` bascule alors de lui-même
sur sa branche sans `tee`, plutôt que de relancer `tee` sur un fichier mort.

Un script d'administration qui meurt parce qu'il n'a pas pu écrire sa trace est
un mauvais comportement — a fortiori lancé par `cron` à quatre heures du matin.
Le message d'écran, lui, part sur `stderr` et n'est jamais perdu.

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

## 6. Codes de retour et diagnostic des échecs

### Deux codes, deux natures d'échec

```text
2  erreur d'usage      option inconnue, argument manquant, valeur invalide
1  échec d'exécution   privilège insuffisant, dépendance absente, opération échouée
0  succès
```

La distinction se lit ainsi : le **2 reproche quelque chose à l'appelant**, qui
n'a qu'à corriger sa ligne de commande ; le **1 constate que le travail n'a pas
pu être fait**, alors que la demande était recevable.

```bash
die "Option inconnue : $1" 2       # erreur d'usage
die "Configuration introuvable…"   # échec d'exécution, code 1 par défaut
```

`require_root` sort en **1**, délibérément : un privilège insuffisant n'est pas
une faute d'invocation, la commande était juste. Il en va de même de
`require_cmd` et de `require_os`.

Un script vérifie donc ses arguments **avant** ses privilèges : lancée sans
`sudo` et avec une option inconnue, la commande sort en 2, parce que c'est le
reproche le plus utile à celui qui l'a tapée.

Une **valeur d'argument invalide** relève du 2 au même titre qu'une option
inconnue : taille de swap illisible, fuseau horaire inexistant, nom d'hôte mal
formé, horaire de cron à quatre champs. La demande était mal formulée, rien n'a
été tenté.

### Deux façons de perdre le code ou le message

**`${1:?message}` n'est pas un contrôle d'argument.** L'expansion écrit sur
`stderr` un message brut, sans préfixe `[ERROR]` ni journalisation, et sort
en 1 — donc à la fois hors convention de forme et hors convention de code :

```text
configure-swap.sh: line 57: 1: --file attend un chemin
```

Le contrôle s'écrit explicitement :

```bash
--file)
    shift
    [ -n "${1:-}" ] || die "--file attend un chemin." 2
    FICHIER_SWAP="$1"; shift
    ;;
```

**`die` appelé dans une substitution de commande double le diagnostic.** Une
fonction de validation qui rend sa valeur sur `stdout` s'exécute dans un
sous-shell : son `die` n'en fait sortir que le sous-shell, et le code non nul
remonté au shell principal déclenche le `trap ERR`, qui ajoute un second message
sans rapport avec la faute :

```text
[ERROR] Taille invalide : « abc » (exemples : 2G, 512M, 2048).
[ERROR] Échec (code 2) à la ligne 143 de configure-swap.sh.
```

La validation se fait donc **hors substitution de commande** : la fonction
renseigne une variable au lieu d'écrire sur `stdout`, et son `die` s'applique
alors au script entier.

```bash
TAILLE_MO=""
en_megaoctets() { … TAILLE_MO="$nombre" … }
en_megaoctets "$TAILLE_DEMANDEE"       # et non "$(en_megaoctets …)"
```

`valider_horaire` dans `configure-cron.sh` et `en_megaoctets` dans
`configure-swap.sh` suivent cette forme.

### Un diagnostic n'est pas un manuel

Un argument obligatoire manquant se signale en deux ou trois lignes, terminées
par un renvoi vers `--help` — jamais par un `show_help >&2`, dont les vingt-huit
lignes noieraient le diagnostic qu'elles étaient censées éclairer.

```text
[ERROR] Nom d'hôte manquant.
[ERROR] Le passer en argument, ou définir SRV_HOSTNAME dans config/server.env.
[ERROR] Aide complète : configure-hostname.sh --help
```

### Le message d'échec nomme le fichier fautif

`lib/common.sh` installe un `trap ERR` qui annonce le code, la ligne et le
fichier :

```text
[ERROR] Échec (code 1) à la ligne 78 de common.sh.
```

Le fichier vient de `BASH_SOURCE`, évalué dans la chaîne du `trap`, et non de
`$0` : les deux repères désignent ainsi la même unité que `$LINENO`. Avec `$0`,
un échec survenu dans le socle était attribué au script appelant — « à la ligne
78 de mon-script.sh » alors que la ligne 78 était celle de `common.sh`,
diagnostic trompeur au pire moment.

---

## 7. Pièges Bash rencontrés

**`set -e` et les listes `&&`** — un fichier terminé par une ligne du type :

```bash
[ -z "$LOG_DIR" ] && LOG_DIR="/defaut"
```

retourne un code d'erreur lorsque la condition est fausse. Si c'est la dernière
instruction d'un fichier chargé par `source`, le script appelant s'arrête sous
`set -e`. Utiliser systématiquement un `if` explicite.

**Double chargement** — `lib/common.sh` commence par une garde
(`_COMMON_SH_CHARGE`) afin qu'un chargement répété reste sans effet.

**Une redirection qui échoue est fatale sous `set -e`** — `printf … >> "$FIC"`
sort en erreur si le fichier ne peut pas être ouvert, et le script s'arrête. Un
contexte de condition neutralise `set -e` :

```bash
if { printf '%s\n' "$ligne" >> "$FIC"; } 2>/dev/null; then
```

La redirection `2>/dev/null` porte sur le **groupe**, pas sur le `printf` :
c'est ce qui étouffe le message brut de bash, celui-ci étant émis au moment où
l'ouverture du fichier échoue — donc avant qu'une redirection propre à la
commande ait pu s'appliquer.

**`set -a` et le retour à l'état antérieur** — une option de shell activée
autour d'un `source` doit être rétablie même quand le `source` échoue. Placer
celui-ci dans un `|| code=$?` garantit que la ligne de rétablissement est bien
atteinte.
