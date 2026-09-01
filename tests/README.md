# tests/ — validations du dépôt

Ce répertoire porte la **preuve**. Tant qu'une commande d'ici n'a pas réussi,
rien n'est démontré : ni par la lecture du code, ni par la conviction d'un
modèle, ni par le fait que « ça a marché sur le serveur ».

Point d'entrée unique :

```bash
tests/run.sh              # tous les niveaux implémentés
tests/run.sh lint         # un niveau précis
tests/run.sh --liste      # ce qui existe et ce qui manque
```

Un seul point d'entrée, pour que la commande de validation inscrite dans une
tâche soit exactement celle qu'un humain tape.

Sur la machine de développement, seule l'analyse statique s'exécute directement.
Tout le reste passe par un conteneur Debian jetable (§4) :

```bash
tests/env/run-in-container.sh -- tests/run.sh
```

---

## 1. Niveaux

| Niveau | Contenu | Environnement | État |
|---|---|---|---|
| `lint` | `bash -n` sur tous les `.sh`, `shellcheck` si disponible | hôte | **implémenté** |
| `unit` | fonctions de `lib/common.sh` | conteneur `debian` | **implémenté** |
| `integration` | exécution réelle, `--dry-run`, idempotence | conteneur `debian` | **implémenté** |
| `environment` | services, `systemctl`, état système | conteneur `systemd` | à écrire |
| `acceptance` | critères d'acceptation d'une tâche | selon la tâche | **implémenté** |

Un niveau s'ajoute en déposant son script au chemin annoncé par
`tests/run.sh --liste`. Aucune autre modification n'est nécessaire.

### Le niveau `unit`

Un fichier par sujet, nommé `tests/unit/<sujet>.test.sh`. `run-unit.sh` les
découvre — **en `maxdepth 1`**, comme l'acceptance — et agrège leurs verdicts.

```text
tests/unit/
├── run-unit.sh          le dispatcher
└── common.test.sh       les onze critères de TASK-003
```

`lib/common.sh` est le point de défaillance unique du dépôt : chaque script le
charge. Le tester impose trois précautions, toutes visibles en tête de
`common.test.sh` :

- **les fonctions qui appellent `exit`.** `die`, `require_root`, `require_cmd`,
  `require_os` et `load_config` tueraient le shell du harnais. Chaque cas est
  donc écrit dans un fichier jetable et exécuté par un **processus `bash`
  neuf**, dont on capture le code, `stdout`, `stderr` et le journal. Un
  sous-shell `( source … )` ne suffirait pas : il hérite de la variable
  `_COMMON_SH_CHARGE` du harnais, et la garde anti-double-chargement ferait de
  son `source` une opération nulle ;
- **le bac à sable.** `SCRIPTS_ROOT` étant résolu depuis l'emplacement de
  `lib/common.sh`, une **copie** de ce fichier dans un répertoire temporaire s'y
  enracine d'elle-même. Les `config/*.env` jetables y sont créés sans jamais
  écrire dans `config/`, et un éventuel `config/server.env` de la machine — que
  `common.sh` charge de lui-même — ne fausse rien. L'identité de la copie est
  prouvée par `cmp` ;
- **les journaux.** `common.sh` crée `LOG_DIR` et calcule `LOG_FILE` dès le
  `source`. `LOG_DIR` est redirigé vers un répertoire temporaire, remis à zéro
  avant chaque cas et supprimé à la fin.
  Un cas le détourne au contraire vers un chemin **non créable** : `LOG_FILE`
  reste alors vide, et c'est la seule façon d'exécuter la seconde branche de
  `run_logged` — celle qui n'emploie pas `tee`.

`require_root` demande en plus un utilisateur non privilégié, alors que le
conteneur tourne en `root`. Trois lanceurs sont **éprouvés** dans cet ordre —
`setpriv`, `runuser`, `chroot --userspec` — et le premier qui abaisse
réellement l'UID est retenu. Si aucun n'y parvient, les cas concernés sont
déclarés `NON EXÉCUTÉ`, jamais réussis.

Le `set -Eeuo pipefail` du harnais reste en place de bout en bout. Le retirer
pour faire passer un cas vaudrait échec de la tâche — [AGENTS.md](../AGENTS.md)
§12.

Un écart entre l'énoncé et le socle est relevé au passage, non corrigé :
`load_config` fait `. "$fichier"`, ce qui rend les variables disponibles dans le
shell appelant mais **n'exporte pas** une affectation nue vers les processus
fils. `common.test.sh` mesure les deux frontières, les nomme, et affiche un
`[WARN]` à chaque exécution. `lib/common.sh` est en zone protégée : la décision
— `set -a` dans `load_config`, ou reformulation du critère — relève d'une tâche
distincte.

Un second écart est mesuré et consigné de la même façon : sous `set -e`, un
appel à `info`, `warn`, `error`, `success` ou `run_logged` **interrompt le
script** si `LOG_FILE` est renseignée mais non inscriptible — le `printf >>`
de `_log` échoue et arme le `trap ERR`. Le cas ne se présente que si le
répertoire de journaux disparaît en cours d'exécution, `LOG_FILE` restant vide
lorsqu'il était déjà impossible à créer au chargement. Aucun cas de
`common.test.sh` n'échoue à ce titre : les onze critères portent sur la valeur
rendue par `run_logged`, observable seulement dans un contexte où `set -e` est
neutralisé (`|| code=$?`, `if …`). L'écart relève d'une tâche distincte.

### Le niveau `integration`

Un fichier par sujet, nommé `tests/integration/<sujet>.test.sh`.
`run-integration.sh` les découvre — **en `maxdepth 1`**, comme l'unit et
l'acceptance — et agrège leurs verdicts.

```text
tests/integration/
├── run-integration.sh        le dispatcher
└── linux-system.test.sh      les six scripts de Linux/System
```

**Ce niveau modifie le système sur lequel il tourne** : il réécrit `/etc/hosts`,
`/etc/localtime` et `/etc/logrotate.d`. Il n'a rien à faire sur une machine de
travail, et ne s'exécute que dans le conteneur jetable :

```bash
tests/env/run-in-container.sh -- tests/run.sh integration
```

Le fichier de cas se protège lui-même : il ne modifie rien tant qu'il n'a pas
reconnu un système jetable — `/.dockerenv`, un cgroup de conteneur, ou
`MGNET_TEST_JETABLE=1`. Ailleurs, les groupes modifiants sont `NON EXÉCUTÉ`.

**Conséquence sur l'hôte Windows :** aucun cas ne peut y tourner, le niveau
rend donc **3** et `tests/run.sh` sans argument rend 3 lui aussi. Ce n'est pas
un échec, c'est le sens exact du code — *rien n'est prouvé pour ce niveau*. La
commande de référence reste celle du §4 :
`tests/env/run-in-container.sh -- tests/run.sh`.

#### Comment l'idempotence est prouvée, et pourquoi « A == B » ne suffit pas

```text
empreinte P0 → exécution 1 → empreinte A → exécution 2 → empreinte B
```

Sur un système déjà conforme, les deux exécutions ne font rien, les trois
empreintes sont égales, et le test passe **sans rien prouver**. C'est
précisément ce que la règle « un conteneur neuf par cas » cherche à empêcher.
Chaque cas exige donc aussi **`P0 != A`** : le premier passage doit avoir
réellement modifié quelque chose. Une idempotence mesurée à vide devient un
échec, et non un succès silencieux.

Les deux assertions se contrôlent l'une l'autre : si l'empreinte était
constante, `P0 != A` tomberait ; si elle était bruitée, `A == B` tomberait. Le
dispositif a été éprouvé à l'envers — système mis d'avance dans l'état
conforme, la garde échoue comme attendu.

L'empreinte relève **tout `/etc`**, contenu compris, plus le nom d'hôte,
`/proc/swaps` et la taille de `/swapfile` — et non une liste de fichiers
arrêtée d'avance : un fichier inattendu se voit. `LOG_DIR` en est exclu,
`lib/common.sh` y écrivant un journal au seul chargement ; les écritures hors
journaux sont surveillées séparément, par `find -newer`.

Ce fichier tourne dans un **unique** conteneur — c'est là que
`tests/run.sh integration` est invoqué, et `docker` n'y est pas disponible pour
en créer d'autres. Trois dispositions remplacent le conteneur neuf par cas, et
sont vérifiées plutôt que supposées : les groupes non modifiants passent en
premier ; l'empreinte relevée juste avant le groupe « idempotence » est
comparée à celle du départ, et une dérive fait déclarer le groupe entier `NON
EXÉCUTÉ` ; les trois cas portent sur des fichiers **disjoints**.

#### Recouvrement avec `tests/acceptance/TASK-011-*`

`TASK-011-analyse-statique.sh` éprouve déjà, dans onze conteneurs neufs, le
préflight, les `--dry-run` et l'idempotence de cinq de ces six scripts. Ses
assertions sont formulées autour des corrections d'analyse statique qu'elle
portait — `SC1087`, `export ASSUME_YES` — et disparaîtront avec elle : le
niveau `integration` est le domicile durable de ces preuves.

Le recouvrement est donc **assumé**, borné à un conteneur au lieu de onze. Les
groupes `preflight`, `dry-run`, `timezone`, `hostname` et `logging` de
TASK-011 pourraient être ramenés à leurs seules assertions propres aux
corrections SC1087 — cela relève d'une tâche distincte, pas d'un effet de bord.

Ce que le niveau `integration` apporte en propre :

- **`system-info.sh`**, que TASK-011 ne couvre que par `--help` : option
  inconnue, exécution sans privilège, lecture seule prouvée, deux exécutions ;
- la garde **`P0 != A`**, absente de TASK-011 ;
- l'empreinte de **tout `/etc`**, là où TASK-011 relève une liste de fichiers ;
- le cas **« le nom demandé est déjà un alias de la ligne `127.0.1.1` »**,
  chemin de `hosts_deja_conforme()` qu'aucun cas existant n'emprunte.

### Le niveau `acceptance`

Un fichier par tâche, nommé `tests/acceptance/TASK-0xx-<sujet>.sh`.
`run-acceptance.sh` les découvre et les exécute — **en `maxdepth 1`**, ce qui a
une conséquence :

```text
tests/acceptance/
├── run-acceptance.sh                    le dispatcher
├── TASK-002-environnement-conteneurise.sh   exécuté sur l'hôte
├── TASK-011-analyse-statique.sh             exécuté sur l'hôte
├── TASK-012-semantique-codes.sh             exécuté sur l'hôte
├── TASK-013-natures-de-saut.sh              exécuté sur l'hôte
└── interne/
    └── TASK-011-cas-conteneur.sh        exécuté DANS le conteneur, jamais sur l'hôte
```

Un fichier de cas destiné à tourner **dans** le conteneur se place dans
`interne/`. Le `maxdepth 1` du dispatcher l'ignore alors, et seul son pilote
— resté au premier niveau — décide quand et comment l'y lancer.

Sans cette séparation, un fichier écrit pour Debian serait exécuté sur l'hôte
Windows, où il échouerait pour de mauvaises raisons.

## 2. Codes de retour

Deux contrats, à ne pas confondre : celui des **niveaux et fichiers de cas**,
qui rendent compte du détail, et celui de **`tests/run.sh`**, qui prononce le
verdict global.

### Ce que rend un niveau ou un fichier de cas

| Code | Sens |
|---|---|
| 0 | tous les cas ont été exécutés et ont réussi |
| 1 | au moins un cas est en défaut |
| 2 | erreur d'usage |
| 3 | **rien n'est prouvé** : aucun cas n'a pu être exécuté, ou l'un d'eux n'a pas pu l'être faute d'environnement |
| 4 | les cas exécutés ont réussi, mais certains ne s'appliquaient pas **par nature** à cet environnement — la preuve est partielle, elle existe |

Le **3** et le **4** sont deux façons très différentes de ne pas tout vérifier,
longtemps confondues sous le même code :

```text
156 cas passés, 7 hors de portée du conteneur   →  4   l'essentiel est prouvé
aucun cas n'a tourné                            →  3   rien n'est prouvé
```

Le 4 n'ouvre pas la porte au faux vert que le 3 avait fermée : il exige **au
moins une réussite**. Une suite intégralement sautée retombe sur le 3, et un
fichier de cas teste donc « aucune réussite » *avant* « des cas sautés ».

#### Les deux natures de saut

« Au moins une réussite » ne suffisait pas. Mesuré, démon Docker rendu
injoignable (`DOCKER_HOST=tcp://127.0.0.1:1`, Docker Desktop jamais arrêté), le
fichier de cas de TASK-011 donnait :

```text
Bilan TASK-011 : 8 réussites, 0 échec, 21 NON EXÉCUTÉ(s)  → code 4
tests/run.sh acceptance                                    → code 0
```

72 % de la preuve avait disparu, le verdict global restait vert. Quelques cas de
préflight, qui n'ont besoin de rien pour tourner, suffisaient à franchir le
seuil.

TASK-013 a donc scindé le décompte des sauts en deux natures, que le seul
compteur `non_executes` confondait :

| Nature | Exemple | Verdict |
|---|---|---|
| **non applicable par nature** | le profil `debian` n'a pas `systemd` et ne l'aura jamais ; `swapon` exige `CAP_SYS_ADMIN` ; un fichier de cas ne peut pas lancer le niveau dont il fait partie | **4** — la limite est assumée, ce qui a été prouvé le reste |
| **environnement indisponible** | le démon Docker ne répond pas, `git` est absent, le miroir `apt` est injoignable | **3** — la preuve existe, elle n'a pas pu être produite |

La première est une limite permanente de l'environnement de test ; la seconde un
accident, qui doit interrompre le verdict. **Une seule indisponibilité fait
sortir le fichier en 3**, quel que soit le nombre de cas réussis par ailleurs.

Un saut se déclare donc avec sa nature, et l'ordre des gardes du bilan devient :
échec, puis aucune réussite, puis indisponibilité, puis non applicable.

**Règle de prudence : dans le doute, indisponibilité.** Un rouge à tort se voit
et se corrige ; un vert à tort ne se voit pas. Deux qualifications méritent
d'être connues, parce qu'elles ne vont pas de soi :

- un outil **absent de l'image** — `setpriv`, `zoneinfo`, un paquet obsolète à
  mettre à jour — est *non applicable par nature* : l'image est minimale à
  dessein, elle fonctionne comme prévu, c'est une limite assumée. Un outil
  **installable mais non installé faute de réseau** est une *indisponibilité* :
  là, l'environnement a échoué ;
- les six contrôles de forme du diff de TASK-011 sont comptés *non applicables
  par nature* depuis que ses corrections sont commitées : sur un arbre propre,
  `git diff HEAD` ne produit rien. Rien n'a manqué — c'est l'objet de la
  comparaison qui a disparu. Mais **pas définitivement** : le diff redevient non
  vide dès qu'un de ces six fichiers est modifié sans être commité, c'est-à-dire
  exactement dans la situation où ce contrôle sert. Ce n'est donc pas une limite
  permanente comme l'absence de `systemd` du profil `debian` — c'est un cas
  **sans objet dans l'état courant du dépôt**, une troisième catégorie que ce
  harnais ne nomme pas. Il est rangé avec les non applicables faute de mieux :
  l'autre option ferait sortir le fichier en 3 sur un environnement pourtant
  complet. La justification complète est écrite sur place, dans le fichier de
  cas, et la réserve est consignée au §4 de
  [docs/points-en-suspens.md](../docs/points-en-suspens.md).

Un code 4 dit donc désormais **« rien d'atteignable n'a été manqué »** — mais
cette garantie ne vaut que ce que valent les qualifications : elle repose sur la
relecture, un saut à la fois, de celui qui les a écrites. Un saut ajouté sans
qualification réfléchie la ruine en silence. Le décompte des deux natures reste
affiché à chaque bilan — un saut invisible serait pire que le faux vert qu'on
cherche à empêcher.

### Ce que rend `tests/run.sh`

| Code | Sens |
|---|---|
| 0 | tous les niveaux exécutés ont réussi — les cas non applicables, s'il y en a, sont décomptés à l'écran |
| 1 | au moins un niveau a échoué |
| 2 | erreur d'usage — option ou niveau inconnu |
| 3 | rien n'est prouvé : un niveau demandé explicitement n'est pas implémenté, un niveau exécuté n'a rien pu vérifier, ou l'un de ses cas n'a pas pu être produit faute d'environnement |

`tests/run.sh` **ne rend jamais 4** : il lit ce code, l'affiche, et le traduit
en réussite. C'est le point d'entrée du dépôt, son contrat tient en une ligne —
*0, la validation est acquise ; autre chose, elle ne l'est pas*. Il ne réduit
plus pour autant le code d'un niveau à réussi/échoué : le 3 remonte en 3, et
n'est plus maquillé en échec.

Le code **3** reste délibérément distinct de 0 et de 1. Sans lui,
`tests/run.sh unit` sortirait en 0 aujourd'hui et un validator conclurait que
les tests unitaires passent, alors qu'aucun n'existe. « Rien à exécuter » n'est
pas « tout va bien ».

C'est la traduction en code de retour de la règle d'[AGENTS.md](../AGENTS.md)
§10 : une validation non exécutée vaut `NON EXÉCUTÉ`, jamais `PASS`.

Le 3 et le 4 de `tests/env/run-in-container.sh` (§4) relèvent d'un autre
contrat — environnement indisponible, échec de construction — et ne se croisent
pas avec ceux-ci : le lanceur ne juge aucun cas, un niveau ne construit aucune
image. Une seule précaution : dans le conteneur, lancer `tests/run.sh` plutôt
qu'un script de niveau, pour que le code transmis reste celui d'un verdict
global.

## 3. Analyse statique

```bash
tests/lint.sh                       # tout le dépôt
tests/lint.sh Linux/System/*.sh     # une sélection
tests/lint.sh --strict              # les scripts hérités deviennent bloquants
```

Deux contrôles de portées très inégales :

- **`bash -n`** ne vérifie que la syntaxe. Toujours disponible, il ne voit ni
  une variable non quotée, ni un `cd` sans garde, ni un `[ $a = $b ]` fragile.
  Le présenter comme une analyse complète serait trompeur ;
- **`shellcheck`** fait le vrai travail. Il est **absent de la machine de
  développement** : dans ce cas le résultat est annoncé `NON EXÉCUTÉ` et
  l'analyse ne prétend pas à l'exhaustivité.

Pour l'installer :

```bash
winget install koalaman.shellcheck     # Windows
sudo apt install shellcheck            # Debian, Ubuntu
```

Il est de toute façon installé dans l'image de test conteneurisée (§4), qui
reste la référence :

```bash
tests/env/run-in-container.sh -- tests/run.sh lint
```

### Exclusions

`SC1090` et `SC1091` sont désactivés : `shellcheck` ne peut pas suivre
`source "$_dir/lib/common.sh"`, dont le chemin n'est résolu qu'à l'exécution.
C'est le mécanisme de chargement du dépôt, décrit dans
[docs/architecture-technique.md](../docs/architecture-technique.md) — pas un
défaut à corriger.

### Scripts hérités

`Synology/Plex/organize-series.sh` et `Synology/Plex/update-plex.sh` ne chargent
pas `lib/common.sh` et ne respectent pas les conventions. Leur mise au standard
est une tâche identifiée, pas un effet de bord d'un contrôle de routine.

**La tolérance dont ils bénéficient porte sur le style, jamais sur la syntaxe :**

| Problème détecté | Script courant | Script hérité |
|---|---|---|
| erreur de syntaxe (`bash -n`) | `ERROR`, bloquant | **`ERROR`, bloquant** |
| avertissement `shellcheck` | `ERROR`, bloquant | `WARN`, non bloquant |

Un script qui ne s'analyse plus est cassé, hérité ou non. Sans cette
distinction, l'un de ces fichiers pourrait devenir syntaxiquement invalide sans
que « 0 erreur » cesse de s'afficher — le contrôle mentirait.

Tant qu'ils passent `bash -n` et que `shellcheck` est absent de la machine, ces
deux fichiers s'affichent donc en `[SUCCESS]` comme les autres. Le `WARN`
n'apparaît qu'en cas de problème de style réellement détecté.

`--strict` supprime la tolérance et les rend bloquants sur tout, ce qui
permettra de constater le jour où ils seront à niveau.

## 4. Environnement de test conteneurisé

La machine de développement est sous Windows : elle n'a ni `apt`, ni
`systemctl`, ni `/etc/os-release`, et le premier `detect_os` y échoue. **Aucun
script d'administration ne s'exécute sur l'hôte.** Tout ce qui dépasse
l'analyse statique passe par un conteneur jetable.

```bash
tests/env/run-in-container.sh -- bash -c 'cat /etc/os-release'
tests/env/run-in-container.sh -- Linux/System/system-info.sh
tests/env/run-in-container.sh --profil debian -- tests/run.sh unit
tests/env/run-in-container.sh -- Linux/System/configure-swap.sh 512M --dry-run
```

Tout ce qui suit `--` est exécuté **tel quel** dans le conteneur, depuis la
racine du dépôt montée sur `/depot`. Le code de retour de la commande est
transmis fidèlement à l'appelant : `tests/env/run-in-container.sh -- false`
sort en 1.

### Ce que fait le script

1. vérifie que `docker` existe **et que le démon répond** — un démon arrêté
   produit un message explicite et le code 3, jamais un faux succès ;
2. construit l'image du profil si elle est absente ;
3. lance un conteneur neuf, dépôt monté en **lecture-écriture** sur `/depot`,
   répertoire de travail `/depot` ;
4. détruit le conteneur — `--rm`, plus un filet de sécurité sur interruption.
   **Aucun état ne survit :** deux exécutions consécutives partent d'un état
   identique, condition sans laquelle un test d'idempotence ne prouve rien.

### Options

| Option | Effet |
|---|---|
| `--profil <nom>` | profil de conteneur, défaut `debian` |
| `--reconstruire` | reconstruire l'image sans cache et retélécharger l'image de base |
| `--dry-run` | afficher les commandes `docker` sans les exécuter |
| `-h, --help` | aide |

### Codes de retour

| Code | Sens |
|---|---|
| 0 | la commande exécutée dans le conteneur a réussi |
| 2 | erreur d'usage — option inconnue, profil inexistant, commande absente |
| 3 | environnement indisponible — `docker` absent ou démon arrêté, **rien n'a été exécuté** |
| 4 | échec de la construction de l'image, rien n'a été exécuté |
| autre | code de retour de la commande, transmis tel quel |

Les codes 2, 3 et 4 peuvent aussi venir de la commande elle-même : la
transmission fidèle du code de retour l'impose. Les messages `[ERROR]` lèvent
l'ambiguïté.

### Profils

| Profil | Image | Couvre | État |
|---|---|---|---|
| `debian` | `debian:12` | `lint`, `unit`, `--dry-run`, idempotence, `apt` | **implémenté** — `tests/env/Dockerfile.debian` |
| `systemd` | dérivée, `/sbin/init`, `--privileged` | `systemctl`, `timedatectl`, `hostnamectl`, `logrotate` | à écrire |

Un profil `<nom>` correspond au fichier `tests/env/Dockerfile.<nom>`. En déposer
un nouveau suffit à le rendre disponible — le script ne tient aucune liste en
dur. Le profil `systemd` demandera en plus `--privileged` et un point d'entrée
`/sbin/init`, que le script ne gère pas encore.

### L'image

`debian:12` officielle, volontairement minimale. Quatre paquets seulement, et
chacun a sa raison écrite dans le `Dockerfile` :

| Paquet | Pourquoi |
|---|---|
| `ca-certificates` | téléchargements HTTPS |
| `iproute2` | `ip`, lu par `system-info.sh` |
| `procps` | `free` et `uptime`, lus par `system-info.sh` |
| `shellcheck` | niveau `lint` à l'intérieur du conteneur |

La locale est `C.UTF-8`, fournie nativement par la glibc de Debian 12 : sans
elle, les libellés accentués seraient comptés en octets et l'alignement des
colonnes serait décalé.

Les listes `apt` sont supprimées de l'image : un script qui installe un paquet
doit faire son propre `apt-get update`, comme sur un serveur neuf.

Le dépôt **n'est pas copié** dans l'image, il est monté à l'exécution. L'image
ne contient donc jamais le code à tester, et une modification de script est
prise en compte sans reconstruction.

L'image se complète au fil des besoins. Tout paquet ajouté doit avoir sa
justification dans le `Dockerfile`.

### Nommage et nettoyage

Images et conteneurs sont préfixés `mgnet-test-`, sans exception :
[AGENTS.md](../AGENTS.md) §8 n'autorise les commandes Docker de l'agent que sur
ce préfixe. L'image est `mgnet-test-debian:latest`, le conteneur
`mgnet-test-debian-<pid>-<horodatage>`.

Pour vérifier qu'il ne reste rien après une exécution :

```bash
docker ps -a --filter 'name=mgnet-test-'
```

### Windows et Git Bash

Deux pièges propres à l'hôte, traités par le script :

- **réécriture des chemins par MSYS.** `-w /depot` deviendrait
  `-w C:/Program Files/Git/depot`. `MSYS_NO_PATHCONV=1` et
  `MSYS2_ARG_CONV_EXCL='*'` désactivent cette conversion ; les chemins de
  l'hôte sont alors passés à Docker sous leur forme Windows via `cygpath -w` ;
- **fins de ligne.** `.gitattributes` impose `eol=lf` : la copie de travail est
  déjà en LF et le montage transmet les octets tels quels. Le script contrôle
  `lib/common.sh` et avertit si des CRLF s'y sont glissés — dans ce cas les
  scripts échoueraient dans le conteneur avec un `bad interpreter` peu parlant.
  Correctif : `git add --renormalize .`.

Le bit exécutable dépend de la façon dont Docker Desktop expose le montage. Si
un `Permission denied` apparaît, lancer la commande via `bash` :

```bash
tests/env/run-in-container.sh -- bash Linux/System/system-info.sh
```

## 5. Écrire un test

Les tests suivent les mêmes conventions que le reste du dépôt : en-tête en trois
lignes, chargement de `lib/common.sh`, messages préfixés, français.

Trois règles propres aux tests :

1. **un test qui ne peut pas s'exécuter le dit.** Il ne se contente jamais de
   passer silencieusement ;
2. **un test d'idempotence part d'un environnement neuf.** Un conteneur
   réutilisé entre deux exécutions invalide le résultat ;
3. **on ne corrige jamais un test pour le faire passer.** Neutraliser une
   assertion, ajouter `|| true` ou retirer `set -e` vaut échec de la tâche —
   voir [AGENTS.md](../AGENTS.md) §12.

### `tests/lib/assert.sh`

Les assertions communes vivent là : `titre`, `ok`, `ko`, `saute`,
`saute_par_nature`, `saute_indisponible`, `assert_code`, `assert_code_non_nul`,
`assert_egal`, `assert_non_vide`, `assert_contient`, `assert_absent`, et `bilan`
— qui applique le modèle ci-dessous et sort avec le code qui convient.

```bash
source "$SCRIPTS_ROOT/tests/lib/assert.sh"

titre "1. Journalisation"
assert_code 1 "$CODE" "die sort en 1 par défaut"
saute "cas non exécuté" "la raison, sans qualification"
saute_par_nature "cas systemd" "le conteneur n'a pas systemd"
saute_indisponible "lint conteneurisé" "le démon Docker ne répond pas"
bilan "lib/common.sh"
```

Trois fonctions de saut, qui ne se remplacent pas l'une l'autre :

| Fonction | Ce qu'elle affiche | Compteur | Verdict |
|---|---|---|---|
| `saute` | `NON EXÉCUTÉ : …` | `non_applicables` | 4 |
| `saute_par_nature` | `NON EXÉCUTÉ (non applicable par nature) : …` | `non_applicables` | 4 |
| `saute_indisponible` | `NON EXÉCUTÉ (environnement indisponible) : …` | `indisponibilites` | 3 |

`saute` et `saute_par_nature` rendent le **même verdict** : seul le message
diffère, et avec lui ce que le harnais affirme. La distinction est là parce que
**la qualification d'un saut se relit, elle ne s'obtient pas par défaut**.

- `saute` est le libellé **neutre** : le cas n'a pas tourné, le harnais n'en dit
  pas plus. C'est ce que servent les quelque soixante-dix sauts de `tests/unit/`
  et `tests/integration/`, qui n'ont pas été examinés un par un — et dont
  plusieurs tiennent à une propriété de la **machine** (`/etc/os-release`
  illisible sur cet hôte, harnais lancé sous `root`) et non à une limite de
  nature ;
- `saute_par_nature` est une **signature** : l'employer, c'est déclarer qu'on a
  examiné ce cas précis et conclu qu'aucune exécution ne le rendra jamais
  atteignable ici.

Le compteur, lui, reste **commun aux deux** : `non_applicables` agrège les sauts
relus et ceux qui ne le sont pas. Il est conservé tel quel pour qu'**aucun
verdict existant ne change** tant que la relecture n'a pas eu lieu — le partage
du compteur est un écart assumé, qui se referme saut par saut, en remplaçant
`saute` par la fonction qui convient.

Ce partage a une conséquence sur l'affichage : la ligne de bilan de
`tests/lib/assert.sh` ne peut pas nommer la nature de ce qu'elle décompte, et ne
la nomme donc pas — elle annonce `N sans indisponibilité déclarée`, ce que le
compteur sait, et rien de plus. Même règle pour les dispatchers de niveau et
pour `tests/run.sh`, qui ne comptent que des fichiers ou des niveaux : ils
parlent de « cas non applicables à cet environnement », sans qualifier une
nature que personne ne leur a transmise. Sous-affirmer ne produit jamais de faux
vert ; sur-affirmer, si. Voir §2 — et la règle de prudence qui l'accompagne.

Bash pur, aucun framework : `bats` est absent de la machine de développement et
ne se justifie pas pour ce volume. La bibliothèque ne pose ni
`set -Eeuo pipefail` ni `trap` — les deux s'appliqueraient au shell appelant —
et ne redéfinit rien de ce que `lib/common.sh` fournit déjà.

> **Ne jamais créer `tests/lib/common.sh`.** La résolution en trois lignes des
> scripts du dépôt cherche `<candidat>/lib/common.sh` en remontant
> l'arborescence : depuis `tests/`, le premier candidat testé est justement
> `tests/lib/common.sh`. Tant qu'il n'existe pas, la remontée se poursuit
> jusqu'à la racine. Le jour où il existerait, tous les scripts de `tests/`
> chargeraient ce fichier-là au lieu du socle du dépôt.

Les trois premiers fichiers de `tests/acceptance/` définissent encore leurs
assertions localement — TASK-013 y a ajouté `saute_indisponible` à l'identique
plutôt que de les réécrire. Leur saut qualifié s'y nomme `saute_par_nature`,
comme ici, et non `saute` : leurs quelques appels ont été relus un par un, et le
nom le dit. Aucun `saute` neutre n'y est défini — un saut ajouté sans
qualification échouera bruyamment au lieu d'hériter d'une nature que personne ne
lui a donnée.
`TASK-002-environnement-conteneurise.sh` n'en déclare aucun, ses onze sauts
étant tous des indisponibilités. `TASK-013-natures-de-saut.sh`, lui, s'appuie
sur cette bibliothèque. Uniformiser les autres est une tâche en soi, pas un
effet de bord.

### Le bilan d'un fichier de cas

Trois compteurs de verdict — réussites, échecs, non exécutés — dont le dernier
se scinde en deux natures — `non_applicables` et `indisponibilites`, dont il
reste le total. Et un bilan qui les traduit en code de retour, **dans cet
ordre** :

```bash
info "Bilan TASK-0xx : $reussites vérification(s) réussie(s), $echecs échec(s), $non_executes NON EXÉCUTÉ(s) — dont $non_applicables non applicable(s) par nature et $indisponibilites indisponibilité(s) d'environnement"

if [ "$echecs" -gt 0 ]; then
    die "TASK-0xx : $echecs critère(s) en défaut." 1
fi

if [ "$reussites" -eq 0 ]; then
    warn "TASK-0xx : aucune vérification n'a pu être exécutée — rien n'est prouvé."
    exit 3
fi

if [ "$indisponibilites" -gt 0 ]; then
    warn "TASK-0xx : $indisponibilites cas n'ont pas pu être produits faute d'environnement — rien n'est prouvé de fiable."
    exit 3
fi

if [ "$non_executes" -gt 0 ]; then
    warn "TASK-0xx : $non_executes vérification(s) NON EXÉCUTÉE(s) — les critères correspondants ne sont pas prouvés."
    exit 4
fi

success "TASK-0xx : tous les critères vérifiés ($reussites vérifications)."
```

L'ordre n'est pas décoratif : un échec prime sur tout, « aucune réussite » se
teste **avant** « des cas non applicables », et une indisponibilité
d'environnement **avant** eux aussi. Sans le premier de ces ordres, une suite
intégralement sautée — démon Docker arrêté, par exemple — sortirait en 4,
c'est-à-dire en réussite partielle, sans avoir rien prouvé. Sans le second, une
suite dont il ne reste que le préflight en sortirait de même : c'est le faux
vert mesuré au §2, fermé par TASK-013.

La ligne `info` du bilan n'est pas facultative : c'est elle qui rend visible le
nombre de cas sautés, et la nature de chacun. Le dispatcher, lui, ne compte que
des fichiers ; le détail vient d'ici.

**Règle de qualification du bilan.** Un fichier de cas dont tous les sauts sont
qualifiés — chaque appel étant `saute_par_nature` ou `saute_indisponible`, aucun
`saute` neutre — peut nommer la nature des sauts dans son propre bilan, et
employer le libellé « non applicable(s) par nature » du modèle ci-dessus. C'est
le cas des trois fichiers de `tests/acceptance/` qui déclarent leurs assertions
localement : leurs appels ont été relus un par un, le fichier sait donc ce qu'il
décompte. Il suffit qu'un seul `saute` neutre y apparaisse pour que ce libellé
redevienne illégitime.

Un fichier qui s'appuie sur `tests/lib/assert.sh` n'a pas ce choix : il hérite
du libellé neutre de sa bibliothèque, `N sans indisponibilité déclarée`. La
bibliothèque ignore, de ses appelants, lesquels ont été relus — elle ne peut
donc pas qualifier ce qu'elle décompte, et ne le fait pas.
