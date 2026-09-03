# TASK-020 — Rapport d'exécution

## Statut

COMPLETED — après trois tours de correction.

## Objectif

Construire le profil de conteneur `systemd`, prévu par
[ADR-0001](../../docs/agent/decisions/ADR-0001-socle-agentique.md) et jamais
écrit, puis ouvrir le niveau `environment` — le niveau 4 du tableau
d'`AGENTS.md` §10, qui n'existait pas.

Sans lui, rien de ce qui touche `systemctl`, `timedatectl` ou `hostnamectl`
n'était validable par l'exécution. Des cas de `configure-timezone.sh` et
`configure-hostname.sh` étaient déclarés `NON EXÉCUTÉ` depuis des mois.

## Ce qui a été produit

**L'image** `tests/env/Dockerfile.systemd` — Debian 12, `systemd` en PID 1.
Quatre paquets, chacun avec sa raison : `systemd`, `systemd-sysv` (c'est lui qui
pose `/sbin/init`), `dbus` (`timedatectl` et `hostnamectl` passent par le bus, et
`dbus` n'est qu'une `Recommends`), `tzdata`. Des unités sans objet en conteneur
sont masquées pour que `degraded` reste un signal et non le bruit de fond.

**Le lancement**, dans `tests/env/run-in-container.sh`. Le profil ne se reconnaît
pas à son nom mais au label `mgnet.test.init` lu **dans le Dockerfile** — pour
que `--dry-run` réponde juste avant toute construction. Attente bornée du
démarrage, puis `docker exec`, puis destruction.

**Le niveau `environment`** — `tests/environment/run-environment.sh`, calqué sur
`run-integration.sh`, et un premier fichier de cas.

## Les mesures — c'est l'essentiel de cette tâche

**Aucun sous-agent n'a pu exécuter quoi que ce soit** : Bash leur était refusé
durant toute la tâche. Ils l'ont dit franchement plutôt que de présenter du
raisonnement comme de la mesure. Toutes les mesures ci-dessous ont été faites par
l'orchestrateur.

| Fait mesuré | Résultat |
|---|---|
| démarrage de systemd | **1 à 2 s**, état `running` ou `degraded` selon le moment |
| unités en échec | aucune |
| `--privileged` + `--tmpfs /run` | **suffisent** — `--cgroupns=host` s'est révélé inutile |
| `systemctl list-units`, `is-active`, `--failed` | fonctionnent |
| **`timedatectl set-timezone Europe/Paris`** | **aboutit** |
| **`hostnamectl set-hostname`** | **échoue** — `Device or resource busy` |
| cause de cet échec | `/etc/hostname` est un **bind-mount Docker**, relevé dans `/proc/mounts`. Structurel, aucune option n'y change rien |
| `hostname(1)` | fonctionne |
| code de retour transmis | `exit 7` → **7** |

**Deux cas jusque-là `NON EXÉCUTÉ` sont passés au vert** : `configure-timezone.sh`
posant le fuseau par `timedatectl`, et `configure-hostname.sh` changeant
réellement le nom. Leurs `saute` ont été retirés de
`tests/integration/linux-system.test.sh`.

## Le vrai travail : un blocage qui se déplaçait

Le lanceur a plus que doublé de taille, presque entièrement pour borner les
appels Docker. Trois fois de suite, la borne posée à un endroit a révélé qu'un
autre appel restait libre.

| Tour | Ce qui était borné | Ce qui restait libre | Durée mesurée avec un démon figé |
|---|---|---|---|
| 1 | rien | tout | attente indéfinie |
| 2 | la boucle d'attente | le `trap EXIT` de nettoyage | **315 s** |
| 3 | + le chemin de sortie | le `docker run -d` | **200 s+** (plafonné par un `timeout` externe) |
| final | + le lancement détaché et le préflight | `build` et la commande, à dessein | **21 à 34 s** |

À chaque tour, le diagnostic arrivait vite et juste — puis le script restait
suspendu de longues minutes. **C'est le pire cas d'un point de vue humain** :
l'utilisateur a lu le message d'erreur et croit le script terminé.

Rien de cela ne se voyait sans un `docker` factice pour le mesurer :

```bash
case "$1" in
    info)  echo "28.5.2" ;;
    build) echo "faux build" ;;
    run)   sleep 300 ;;     # ou ps|exec|logs|rm, selon le tour
esac
```

**La distinction qui a permis de fermer.** `docker run` n'est pas une seule
chose. En mode direct, il **porte la commande** — sa durée est celle de
`tests/run.sh` entier, plusieurs minutes ; le borner serait un contresens. En
mode `systemd`, il est **détaché** : il démarre le conteneur et rend la main.
Seul le second est borné.

Preuve que la distinction tient, mesurée avec un `docker` figé sur `info` :

```text
mode systemd : abandonne en 22 s, code 3
mode debian  : pend toujours — 45 s à mon timeout externe, jamais interrompu
```

Le relecteur a fait l'inventaire final : **douze appels Docker exécutés, neuf
bornés, trois libres** — `build`, et les deux lancements de la commande demandée.

Un piège transitif a été fermé au passage : une expiration de
`docker image inspect` ne doit surtout pas se lire « image absente », sinon on
enchaîne sur un `docker build` que rien ne borne, et le blocage revient par la
bande.

## Décision de conception : `--rm` retiré du mode systemd

`--rm` effaçait le conteneur avant qu'on puisse lire son journal : le seul
diagnostic prévu pour un démarrage raté était **systématiquement vide**. Le
`trap … EXIT` devient le destructeur unique.

Le relecteur a vérifié le troc plutôt que de le croire :

| Cas | Résultat |
|---|---|
| `SIGINT` pendant `docker exec` | conteneur détruit, aucun résidu |
| `SIGINT` pendant l'attente | conteneur détruit, aucun résidu |
| `SIGKILL` du lanceur | **conteneur survivant** — mais `--rm` n'aurait rien effacé non plus, le PID 1 étant `/sbin/init` |
| deux exécutions simultanées | noms distincts, les deux détruits |

Zéro garantie perdue, le journal gagné. Le cas du `SIGKILL` est documenté dans
`tests/README.md`, pas dissimulé.

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `tests/env/Dockerfile.systemd` | **créé** — l'image |
| `tests/env/run-in-container.sh` | lancement du profil, bornes de temps, diagnostics |
| `tests/env/Dockerfile.debian` | commentaire annonçant le profil comme « non écrite » |
| `tests/environment/run-environment.sh` | **créé** — le dispatcher |
| `tests/environment/systemd.test.sh` | **créé** — le premier fichier de cas |
| `tests/integration/linux-system.test.sh` | deux `saute` retirés, la preuve existant ailleurs |
| `tests/integration/configure-cron.test.sh` | un `saute` conservé, sa raison corrigée |
| `tests/README.md` | niveaux, profils, bornes de temps |
| `docs/points-en-suspens.md` | point n° 9 — hors `scope`, voir plus bas |
| `tasks/backlog.md` | lien réparé — hors `scope` |

## Commandes exécutées

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 — 27 fichiers, **shellcheck absent de l'hôte** |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 — shellcheck présent, 0 erreur |
| `… --profil systemd -- systemctl list-units --type=service --no-pager` | 0 — 13 unités |
| `… --profil systemd -- tests/run.sh environment` | **0** — 48 réussites, 0 échec, 2 sauts |
| `… -- tests/run.sh lint unit integration environment` | **0** — 4 niveaux verts |
| `… --profil systemd --dry-run -- true` | 0 — annonce 165 s, aucun appel réel |
| `docker ps -a --filter name=mgnet-test-` | 0, **sortie vide** |

Sous le profil `debian`, le niveau `environment` rend 13 réussites et 13 sauts —
il ne sort **jamais** en 3, ce qui était le risque de régression le plus concret :
`tests/run.sh` passe désormais par un étage de plus.

## Corrections automatiques

Trois tours, tous sur les bornes de temps, plus une affirmation fausse relevée
par le testeur : le commentaire de `tzdata` prétendait que le profil `debian` n'a
pas les données de fuseau. Mesuré : `/usr/share/zoneinfo/Europe/Paris` **existe**
dans cette image. Ce qui manque là-bas est `timedatectl`.

## Tentatives

3 / 5

## Critères d'acceptation

- [x] `systemctl` répond réellement dans le conteneur
- [x] au moins un cas jusque-là `NON EXÉCUTÉ` passe au vert — **deux** le font
- [x] la garde du fichier de cas est **mesurée**, jamais fondée sur le nom du
      profil : `/proc/1/comm` **et** `is-system-running`, deux sources
      indépendantes
- [x] sous `debian`, le niveau sort en 4 et jamais en 3
- [x] `run-environment.sh` découvre et agrège comme `run-integration.sh`
- [x] jamais d'attente indéfinie — **c'est le critère qui a demandé trois tours**
- [x] aucun conteneur survivant, hors `SIGKILL` du lanceur, documenté
- [x] le profil `debian` est indemne — mesuré : il pend encore là où `systemd`
      abandonne

## Validation finale

PASS

## Écarts de périmètre

Deux fichiers hors `scope` : `docs/points-en-suspens.md`, que `CLAUDE.md` désigne
comme l'endroit où verser ce genre de point, et `tasks/backlog.md`, dont le lien
avait été cassé par le déplacement du fichier de tâche par cette tâche même. Le
relecteur les signale sans leur donner de gravité.

## Réserves

**`--privileged` est conservé sans preuve qu'il soit indispensable.** Justifié
par un besoin réel — systemd crée un cgroup par unité, `/sys/fs/cgroup` est monté
en lecture seule sans lui — mais l'alternative étroite (`--cap-add SYS_ADMIN` et
les `--security-opt` adéquats) n'a pas été essayée. Porté au **point n° 9** des
points en suspens.

**Le plafond de 30 s du lancement détaché est un jugement, pas une mesure.** Le
nominal a été mesuré à moins d'une seconde ; le cas défavorable *légitime* — hôte
chargé, premier montage après redémarrage de Docker Desktop — ne l'a pas été.
Consigné au même point n° 9, pour qu'un faux positif soit reconnu comme une borne
à réviser et non comme une panne.

**`hostnamectl set-hostname` reste non applicable par nature**, avec sa cause
lue à l'exécution. Après relecture, cette qualification ne subsiste que sur les
deux branches où la cause est **établie** ; la troisième — « aucun montage relevé,
la cause reste à établir » — a été requalifiée en saut neutre. Affirmer une
limite structurelle au moment où l'on reconnaît ne pas la connaître serait un
abus.

**`shellcheck` est absent de l'hôte.** La couverture réelle vient du même niveau
relancé en conteneur.

## Git

Branche : `agent/TASK-020`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

Le niveau 4 existe, et le profil qu'il exigeait fonctionne. Deux preuves qui
manquaient depuis ADR-0001 sont produites.

Mais l'enseignement de cette tâche n'est pas là. Il est qu'**un diagnostic juste
et rapide ne suffit pas** : trois fois de suite, le script a dit la bonne chose en
dix secondes, puis est resté muet cinq minutes. Le blocage ne disparaissait pas,
il se déplaçait — de la boucle au nettoyage, du nettoyage au lancement. Chaque
correction le rendait plus difficile à voir, parce que le message d'erreur, lui,
arrivait toujours plus vite.

Rien de cela n'était visible sans un `docker` factice de six lignes. C'est le
même enseignement que TASK-018, sous une autre forme : **un site est présumé
atteignable tant qu'on n'a pas cherché la mutation qui l'atteint.**
