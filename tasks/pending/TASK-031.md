---
id: TASK-031
title: "Écrire Docker/Diagnostics/check-docker.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
human_approval_required: true
objective: |
  Constater qu'une machine qu'on découvre possède un environnement Docker
  exploitable : présence et version du client et du moteur, état du service et
  réponse du démon, versions de Compose et de Buildx, répertoire et pilote de
  stockage. Lecture seule sans exception. Le script rend un code non nul quand
  l'environnement n'est pas exploitable, et reste lisible quand Docker est
  absent — c'est son cas d'usage principal.
scope:
  - Docker/Diagnostics/check-docker.sh
  - tests/integration/check-docker.test.sh
  - Docker/README.md — ligne du tableau des scripts ; si TASK-029 n'a pas encore créé le fichier, le créer selon la section 13 du plan
  - README.md — ligne du tableau des scripts
out_of_scope:
  - toute écriture, où que ce soit sur la machine — Docker/Diagnostics/ est en lecture seule, sans exception (CLAUDE.md)
  - le lancement d'un conteneur de test, fût-il hello-world — c'est le travail de verify-docker.sh, tâche distincte
  - le démarrage, l'arrêt, l'activation ou le redémarrage du service docker
  - l'installation ou la correction de ce que le diagnostic trouve en défaut
  - list-containers.sh, list-images.sh et docker-disk-usage.sh — les trois autres scripts de la section 9 bis, tâches distinctes
  - le diagnostic de Kubernetes, de K3s ou d'un conteneur applicatif nommé
  - l'espace disque consommé par Docker, qui appartient à docker-disk-usage.sh
  - le bloc « Architecture » de README.md — il est aligné par TASK-029
  - l'ajout d'un paquet à l'image de test
  - toute installation réelle de Docker pendant les validations
acceptance_criteria:
  - le script n'exécute que des lectures — docker version, docker info, docker compose version, docker buildx version, systemctl is-active, lecture de fichiers — et aucune commande modifiant un état
  - il affiche présence et version du client et du moteur, état du service docker, réponse du démon, versions du plugin Compose et de Buildx, répertoire de données et pilote de stockage
  - une rubrique dont l'information est introuvable s'affiche « non disponible » et n'interrompt pas le diagnostic
  - Docker absent — la sortie reste complète et lisible, aucun message brut de commande introuvable n'apparaît, et le script rend 1
  - Docker présent mais démon injoignable — le script dit lequel des deux manque et rend 1
  - l'état de /var/run/docker.sock — absent, présent, accessible — figure dans la sortie, ce qui distingue un démon arrêté d'un socket interdit à l'utilisateur
  - environnement exploitable — client, démon qui répond, service actif — le script rend 0
  - chaque interrogation de docker est bornée dans le temps, de sorte qu'un démon qui ne répond plus ne fige pas le diagnostic
  - le script ne requiert aucun privilège et n'expose ni --dry-run ni option d'action, n'ayant rien à simuler
  - une option inconnue rend 2, et c'est le seul cas de 2
  - --help documente les rubriques, la frontière avec verify-docker.sh et les codes de retour
  - le fichier de cas éprouve les trois issues — Docker absent, démon injoignable, environnement sain — par un faux docker en tête de PATH, sans qu'aucun démon ne soit nécessaire
  - une garde de contraste accompagne chaque cas à faux docker — le même appel sans le stub ne donne pas le même verdict
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Docker/Diagnostics/check-docker.sh --help"
implementation_notes:
  - check-services.sh est le modèle direct — un code de retour qui porte une réponse, et les quatre fonctions de présentation communes à check-disk.sh et check-memory.sh
  - toute interrogation d'une commande externe se place en contexte de condition — if ! sortie="$(docker …)" — sinon le trap ERR de lib/common.sh parle deux fois sans nommer la cause (TASK-018)
  - LC_ALL=C sur les commandes dont la sortie est analysée, pour que le résultat ne dépende pas de la locale
  - die sans second argument rend 1 ; le 2 s'écrit explicitement
  - require_cmd tue le script si la commande manque — ici l'absence de docker est le cas nominal, elle se constate et ne doit pas faire mourir le script
  - docker info écrit son diagnostic d'échec sur stderr et rend un code non nul — capturer les deux plutôt que de laisser filer un message brut
---

# TASK-031 — Diagnostiquer un environnement Docker, en lecture seule

## Origine

Section « 9 bis. Docker / Diagnostics » de
[docs/refactorisation-plan.md](../../docs/refactorisation-plan.md), premier des
quatre scripts du dossier. La responsabilité du dossier y est écrite en une
phrase : *lecture seule. Aucun script de ce dossier ne modifie l'état de la
machine.* `CLAUDE.md` vient d'inscrire la même frontière :

> `Diagnostics/` est en lecture seule, sans exception. Un script qui modifie
> quoi que ce soit sur la machine n'y a pas sa place, même si sa sortie
> ressemble à un rapport.

## Ce qui le sépare de `verify-docker.sh`

Les deux scripts existent, et ils ne se remplacent pas :

```text
verify-docker.sh   valide une installation qu'on VIENT DE FAIRE
                   → daemon, version, permissions, stockage, réseau,
                     et exécution d'un conteneur de test
check-docker.sh    diagnostique une machine qu'on DÉCOUVRE
                   → ce qui est là, ce qui manque, et dans quel état
```

La conséquence pratique est nette : **`check-docker.sh` ne lance aucun
conteneur**. Un `docker run hello-world` tire une image, écrit dans
`/var/lib/docker` et crée un conteneur — trois modifications. C'est légitime
dans `Installation/`, jamais dans `Diagnostics/`.

## Le cas d'usage principal est « Docker n'est pas là »

Un diagnostic qui ne fonctionne que sur une machine saine ne sert à rien. Celui
qu'on lance en premier, sur un serveur qu'on ne connaît pas, doit répondre
proprement quand rien n'est installé.

D'où deux exigences qui se contredisent en apparence, et qu'il faut tenir
ensemble :

- **la sortie reste complète** — chaque rubrique est affichée, celles qu'on ne
  peut pas renseigner portent « non disponible ». `system-info.sh` est le modèle
  du dépôt : *sa nature est de dégrader, pas de mourir parce qu'un `nproc`
  manque* (`tests/README.md`) ;
- **le code de retour porte le verdict** — 1 quand l'environnement n'est pas
  exploitable. C'est ce qui permet d'enchaîner `check-docker.sh || install…`
  dans un script d'appelant.

`require_cmd docker` serait donc une faute ici : il tuerait le script sur le cas
qu'il doit précisément savoir traiter.

## Le piège central : aucun démon Docker dans le conteneur de test

Les validations tournent **elles-mêmes dans un conteneur**
(`tests/env/run-in-container.sh`, profils `Dockerfile.debian` et
`Dockerfile.systemd`). On n'installe pas Docker dans Docker, et on n'ajoute
aucun paquet à l'image.

La preuve passe par un **faux `docker` en tête de `PATH`**, qui enregistre ses
arguments et rend le code qu'on lui demande — le pattern retenu par TASK-024
pour `curl`, déjà employé partout (`tests/README.md`, « Les échecs qui ne sont
pas fatals »).

Ce script est le plus facile des quatre à éprouver, et c'est la raison de son
`depends_on: []` : n'ayant besoin d'aucune installation, il se valide
intégralement avec un faux `docker`. Les trois sorties d'un faux binaire — code
0 avec une version plausible, code non nul avec le message de socket injoignable,
et l'absence pure et simple du binaire — couvrent les trois issues du script.

**Chaque cas porte sa garde de contraste** : dans le conteneur, `docker` est
absent *par défaut*. Un cas « Docker absent » y serait vert sans rien prouver.
La garde consiste à vérifier que le même appel, avec un faux `docker` qui
répond, donne un verdict différent — faute de quoi l'assertion est creuse.

Le fichier de cas est découvert automatiquement par
`tests/integration/run-integration.sh`, qui balaie le répertoire en `maxdepth 1`
— aucun branchement à écrire.

## Un démon qui ne répond pas peut faire attendre longtemps

`docker info` interroge le socket ; si le démon est monté mais ne répond plus,
l'appel peut durer. Le dépôt a déjà rencontré la même famille de problème avec
`df` sur un montage réseau injoignable — point 10 de
[docs/points-en-suspens.md](../../docs/points-en-suspens.md).

Chaque interrogation est donc bornée dans le temps. `timeout` appartient à
`coreutils` et est présent partout, y compris dans l'image de test —
`run-in-container.sh` le vérifie déjà pour le profil `systemd`. Un dépassement
se traite comme une information non disponible assortie d'un `[WARN]`, pas comme
une erreur du script.

## Décisions que cette tâche tranche

**Trois codes, pas davantage.** `0` environnement exploitable, `1` environnement
non exploitable — Docker absent, démon injoignable, socket inaccessible —, `2`
erreur d'usage. C'est le contrat de `check-services.sh`, à ceci près qu'ici le
mode nominal lui-même porte un verdict : il n'y a pas d'« inventaire qui rend
toujours 0 », parce que la question posée est fermée.

**Aucune option d'action, et pas de `--dry-run`.** Un script qui ne modifie rien
n'a rien à simuler. En ajouter un laisserait croire qu'il existe un mode qui
modifie.

**Aucun privilège requis.** `docker version`, `docker info` et
`systemctl is-active` répondent à n'importe quel compte — l'accès au socket, lui,
peut manquer, et c'est justement une information que le diagnostic doit rendre
plutôt qu'un obstacle à contourner par `sudo`.

Ces choix sont réversibles et locaux au sens d'[AGENTS.md](../../AGENTS.md) §14 ;
ils sont fixés ici pour ne pas être rediscutés pendant l'exécution, et à
consigner dans le rapport.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 — 4 traduit en 0 par `tests/run.sh` si des cas sont sautés par nature |
| `run-in-container.sh -- bash …/check-docker.sh --help` | 0 |

La preuve que **le code porte le verdict** — `1` dans un conteneur sans Docker —
ne figure pas ici : elle appartient au fichier de cas, qui peut affirmer un code
attendu sans qu'une commande de validation ait à sortir en 1. Une validation
enveloppée dans un `bash -c` qui inverse `$?` serait une assertion déguisée en
commande ; `tasks/README.md` §2 veut des commandes exécutables telles quelles.

## Ce que la tâche laisse ouvert

`list-containers.sh`, `list-images.sh` et `docker-disk-usage.sh` — les trois
autres scripts de la section 9 bis — et `verify-docker.sh` de la section 8.
Aucun n'est atomisé ici : le backlog s'atomise par lot, pas d'un bloc.
