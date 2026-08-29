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
| `unit` | fonctions de `lib/common.sh` | conteneur `debian` | à écrire — [TASK-003](../tasks/pending/TASK-003.md) |
| `integration` | exécution réelle, `--dry-run`, idempotence | conteneur `debian` | à écrire — [TASK-004](../tasks/pending/TASK-004.md) |
| `environment` | services, `systemctl`, état système | conteneur `systemd` | à écrire |
| `acceptance` | critères d'acceptation d'une tâche | selon la tâche | à écrire |

Un niveau s'ajoute en déposant son script au chemin annoncé par
`tests/run.sh --liste`. Aucune autre modification n'est nécessaire.

## 2. Codes de retour

| Code | Sens |
|---|---|
| 0 | tous les niveaux exécutés ont réussi |
| 1 | au moins un niveau a échoué |
| 2 | erreur d'usage — option ou niveau inconnu |
| 3 | un niveau demandé explicitement n'est pas implémenté |

Le code **3** est délibérément distinct de 0 et de 1. Sans lui,
`tests/run.sh unit` sortirait en 0 aujourd'hui et un validator conclurait que
les tests unitaires passent, alors qu'aucun n'existe. « Rien à exécuter » n'est
pas « tout va bien ».

C'est la traduction en code de retour de la règle d'[AGENTS.md](../AGENTS.md)
§10 : une validation non exécutée vaut `NON EXÉCUTÉ`, jamais `PASS`.

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
