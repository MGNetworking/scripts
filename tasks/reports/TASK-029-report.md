# TASK-029 — Rapport

**Statut** : `completed` — 2026-09-14
**Script** : `Docker/Installation/install-docker.sh`, 176 lignes
**Cas** : `tests/integration/install-docker.test.sh`, 105 lignes — 26 vérifications

Première tâche menée sous [ADR-0004](../../docs/agent/decisions/ADR-0004-sobriete.md) :
écrite directement, sans `redacteur-script` ni `redacteur-tests`.

## Validations

| Commande | Code attendu | Code réel |
|---|---|---|
| `tests/run.sh lint` | 0 | **0** |
| `run-in-container.sh -- tests/run.sh lint` | 0 | **0** |
| `run-in-container.sh -- tests/run.sh integration` | 0 | **0** |
| `run-in-container.sh -- bash …/install-docker.sh --help` | 0 | **0** |
| `run-in-container.sh --profil systemd -- bash …/install-docker.sh --dry-run` | 0 | **0** |

Le fichier de cas seul rend **4** — un cas sauté par nature : l'installation
réelle et le retrait des paquets conflictuels supposeraient un réseau vers
`download.docker.com` et un `dpkg` réel, qu'`AGENTS.md` §8 exclut. Les chemins
qui y mènent sont éprouvés jusqu'à la confirmation.

## Ce qui a été produit

`install-docker.sh` suit l'ordre imposé par `CLAUDE.md` : arguments, privilèges,
OS, architecture, ressources, dépendances, conflits, résumé, confirmation,
exécution, vérification.

Pose `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin` et
`docker-compose-plugin` depuis `download.docker.com`. Clé dans
`/etc/apt/keyrings/docker.asc`, référencée par `signed-by` — `apt-key` n'est
jamais appelé.

`Docker/README.md` complété — deux scripts, ordre d'utilisation, risques.
`README.md` racine : bloc « Architecture » aligné sur les cinq sous-dossiers de
`Docker/` et la disparition de `Linux/Docker`, plus la ligne du tableau.

## Décisions tranchées

**Le nom de code vient de `/etc/os-release`, jamais du script.** Une assertion du
fichier de cas vérifie qu'aucun `bookworm`, `jammy` ni `noble` n'apparaît dans le
source. C'est ce qui répond à l'incertitude laissée ouverte à l'atomisation : on
ne sait pas si `download.docker.com` publie déjà Debian 13 (`trixie`), et le
script n'a pas besoin de le savoir.

**Un dépôt qui ne publie pas la suite est retiré.** Si `apt-get update` échoue
après l'écriture de `docker.list`, le fichier est supprimé avant de rendre 1 : le
script ne laisse pas un `apt` cassé derrière lui. C'est le filet qui rend
l'inconnue ci-dessus sans conséquence.

**`[ -t 0 ]` contrôlé avant chaque `confirm`.** Sans terminal et sans `--yes`, le
script s'arrête sur un message nommant `--yes` et rend 1. Sans ce contrôle,
`confirm` lirait un stdin fermé, `errexit` tuerait le script et le `trap ERR`
écrirait une ligne qui ne désigne rien — le motif de TASK-018. Une assertion
vérifie l'absence de « Échec (code » dans cette sortie.

**Seuils : 2 048 Mo sous `/var` bloquent, 1 024 Mo de mémoire avertissent.** Le
disque est une impossibilité, la mémoire une gêne — Docker fonctionne avec peu,
ce sont les compilations d'images qui souffrent.

**Deux `shellcheck disable=SC2086` justifiés en commentaire**, sur
`apt-get install $PAQUETS` et `apt-get remove $TROUVES` : le découpage par
espaces est voulu, ce sont des listes de noms de paquets. TASK-028 rappelle
qu'une directive nue est refusée.

## Reste ouvert

`verify-docker.sh`, second script de la section 8 du plan, n'est pas atomisé.
La distinction est écrite dans le `--help` de `check-docker.sh` : celui-ci
diagnostique une machine qu'on découvre, `verify-docker.sh` validera une
installation qu'on vient de faire, conteneur de test à l'appui.

`TASK-030` et `TASK-032` sont débloquées par cette tâche, ainsi que `TASK-035` et
`TASK-036`.

## Correction après relecture Opus — 2026-09-14

Relue par Opus avec la grille appliquée à TASK-030 : *fusionnable après
corrections*, 2 défauts majeurs et 5 mineurs. Tous corrigés.

| Défaut | Correction |
|---|---|
| MAJEUR — noyau affiché, jamais contrôlé | refus en 1 sous 3.10, minimum historique de Docker Engine |
| MAJEUR — chemins modifiants non testés | retrait des conflits, `enable`/`start`, échec d'`apt-get update` et échec de la clé éprouvés par faux binaires |
| `MIN_MEMOIRE_MO=1024` au lieu de 512 | aligné sur la fiche |
| `apt-get remove` avant `DEBIAN_FRONTEND` | export déplacé avant le premier `apt-get` |
| clé écrite directement par `curl` | temporaire, contrôle de non-vacuité, puis `mv` |
| `df` illisible passé sous silence | `[WARN]` |
| échec d'`apt-get update` attribué à la seule suite | message élargi ; la clé est retirée si le script venait de la poser |

Tests creux retirés : faux `os-release` que rien ne lisait, `grep -c` comparé à
« 1 ». Directive `shellcheck disable=SC2016` justifiée en tête du fichier de cas.

**Validations** : les cinq à **0**. Fichier de cas : **43 vérifications, 0 échec,
0 sautée** — contre 26 et une sautée avant. Script 199 lignes, cas 149.
