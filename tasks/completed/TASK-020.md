---
id: TASK-020
title: "Construire le profil de conteneur systemd et ouvrir le niveau environment"
status: completed
priority: high
depends_on: []
environment: host
human_approval_required: false
objective: |
  Livrer le profil de conteneur « systemd » annoncé depuis ADR-0001 et jamais
  construit — une image dérivée où systemd tourne en PID 1 et où systemctl
  répond réellement — puis ouvrir le niveau de validation « environment » qui
  l'utilise. À la fin de la tâche, au moins un cas aujourd'hui NON EXÉCUTÉ
  faute de systemd est réellement exécuté et réussi.
scope:
  - tests/env/Dockerfile.systemd — nouvelle image, dérivée de debian 12
  - tests/env/run-in-container.sh — lancement, attente du démarrage, exécution et destruction pour ce profil
  - tests/env/Dockerfile.debian — le commentaire qui annonce le profil systemd comme « non encore écrite »
  - tests/environment/run-environment.sh — dispatcher du niveau, sur le modèle de tests/integration/run-integration.sh
  - tests/environment/ — un premier fichier de cas, qui reprend un cas jusque-là NON EXÉCUTÉ
  - tests/integration/linux-system.test.sh et tests/integration/configure-cron.test.sh — les lignes « saute » rendues caduques par la preuve nouvelle
  - tests/README.md — tableau des niveaux, tableau des profils, description du profil systemd
out_of_scope:
  - toute écriture ou modification d'un script de Linux/System
  - l'exécution du niveau integration sous le profil systemd — voir le corps, plusieurs assertions y deviendraient rouges sans qu'aucun défaut n'existe
  - la reprise des sauts qui ne tiennent pas à systemd — swapon et CAP_SYS_ADMIN, absence de paquet obsolète, montage Docker Desktop en 0777
  - les deux défauts mineurs de run-in-container.sh relevés par TASK-002 — message de démon injoignable tronqué, analyse de « --profil --dry-run »
  - l'ajout de paquets au profil debian existant
  - l'installation de Docker, de K3s ou d'un quelconque service applicatif dans la nouvelle image
  - la modification d'AGENTS.md, dont le tableau des niveaux décrit déjà le niveau 4
acceptance_criteria:
  - tests/env/Dockerfile.systemd existe, part de debian 12 comme le profil debian, et chaque paquet installé y porte sa raison écrite
  - run-in-container.sh --profil systemd démarre le conteneur avec systemd en PID 1, attend la fin du démarrage, exécute la commande demandée depuis /depot, puis détruit le conteneur
  - l'attente du démarrage est bornée dans le temps — un systemd qui ne démarre pas produit un message explicite et un code non nul, jamais une attente indéfinie
  - le code de retour de la commande exécutée est transmis fidèlement à l'appelant, comme pour le profil debian
  - dans le conteneur systemd, systemctl répond réellement — l'inventaire des unités aboutit, et « systemctl is-system-running » rend « running » ou « degraded », jamais « offline »
  - le profil debian est inchangé dans son comportement — mêmes commandes, mêmes codes, aucun conteneur détaché
  - aucun conteneur ne survit à une exécution, en sortie normale comme après interruption, et image comme conteneur portent le préfixe mgnet-test-
  - le niveau environment existe — tests/environment/run-environment.sh découvre les fichiers *.test.sh du répertoire en maxdepth 1 et agrège leurs verdicts comme run-integration.sh
  - au moins un cas aujourd'hui NON EXÉCUTÉ faute de systemd est réellement exécuté et réussi sous le profil systemd
  - la garde de ce cas éprouve la présence de systemd, jamais le nom du profil
  - sous le profil debian, le niveau environment sort en 4 et jamais en 3 — au moins un de ses cas s'exécute sans systemd, les autres sont sautés par nature
  - la ligne « saute » correspondante des fichiers de tests/integration/ nomme l'endroit où la preuve vit désormais, ou disparaît — aucun saut ne continue d'affirmer hors de portée un cas prouvé ailleurs
  - tests/README.md décrit le profil systemd, les options docker qu'il exige et ce qu'il permet ; le niveau environment n'y est plus annoncé « à écrire »
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh --profil systemd -- systemctl list-units --type=service --no-pager"
  - "tests/env/run-in-container.sh --profil systemd -- tests/run.sh environment"
  - "tests/env/run-in-container.sh -- tests/run.sh lint unit integration environment"
  - "tests/env/run-in-container.sh --profil systemd --dry-run -- true"
  - "docker ps -a --filter name=mgnet-test- --format '{{.Names}}'"
implementation_notes:
  - ADR-0003 décision 12 impose ce profil avant les domaines — il n'est pas un préalable optionnel
  - systemd en PID 1 ne se lance pas par « docker run <image> <commande> » — le conteneur démarre sur /sbin/init, la commande passe ensuite par docker exec
  - docker run --rm, docker exec, docker ps et docker rm sur le préfixe mgnet-test- sont autorisés par AGENTS.md §8 ; --privileged n'est pas interdit
  - un « reboot » ou un « systemctl poweroff » lancé dans ce conteneur le tuerait en pleine suite — aucun script de redémarrage ne s'y exécute
---

# TASK-020 — Le profil de conteneur `systemd`

## Origine

[ADR-0001](../../docs/agent/decisions/ADR-0001-socle-agentique.md) annonçait deux
profils de conteneur ; un seul a été écrit. Le second est **tranché par
[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md),
décision 12** : il se construit *avant* les domaines, parce que le construire
plus tard obligerait à revenir sur des scripts déjà déclarés terminés.

Ce n'est pas un script d'administration. C'est de l'outillage de test, et son
unique justification est la preuve : sans `systemctl`, `timedatectl` ni
`hostnamectl` réels, tout un pan du dépôt est écrit sans jamais être exécuté.

Ce qui attend ce profil, nommément :

| Où | Ce qui est déclaré `NON EXÉCUTÉ` |
|---|---|
| `tests/integration/linux-system.test.sh` §5 | `configure-timezone.sh` appliquant le fuseau **par `timedatectl`** |
| `tests/integration/linux-system.test.sh` §5 | `configure-hostname.sh` changeant **réellement** le nom de la machine |
| `tests/integration/configure-cron.test.sh` §9 | le rechargement de la planification par un **démon cron en service** |
| `tests/run.sh` | le niveau `environment`, `NON IMPLÉMENTÉ` depuis l'origine |

## Ce que la tâche livre

Trois pièces, indissociables — un profil que rien n'exerce ne prouve rien.

1. **`tests/env/Dockerfile.systemd`.** Image dérivée de `debian:12`, `systemd`
   en PID 1. Volontairement minimale, comme `Dockerfile.debian` : chaque paquet
   installé porte sa raison écrite dans le fichier. Le dépôt n'est **pas copié**
   dans l'image, il reste monté à l'exécution sur `/depot`.
2. **La prise en charge du profil dans `run-in-container.sh`.** Le mécanisme de
   sélection existe déjà — un profil `<nom>` est le fichier
   `tests/env/Dockerfile.<nom>`, et le script ne tient aucune liste en dur. Ce
   qui manque est le **chemin d'exécution** : `docker run --rm <image>
   <commande>` ne convient pas quand le PID 1 doit être `/sbin/init`.
3. **Le niveau `environment`.** `tests/run.sh` connaît déjà le niveau et le
   chemin qu'il attend — `tests/environment/run-environment.sh`, ligne 86. Le
   dispatcher se calque sur `tests/integration/run-integration.sh` : découverte
   des `*.test.sh` en `maxdepth 1`, agrégation des verdicts.

## Le piège central — ne pas lancer le niveau `integration` sous `systemd`

C'est le point à lire avant d'écrire quoi que ce soit.

`tests/integration/linux-system.test.sh` contient des assertions qui tiennent
**précisément parce que systemd est absent**. Deux exemples mesurés dans le
fichier tel qu'il est aujourd'hui :

```text
ligne 2914  assert_contient  "[INFO] Fuseau défini via /etc/localtime."
            « le repli /etc/localtime est bien emprunté, faute de systemd »
ligne 2925  assert_egal "9" "$(nb_lignes_erreur)"
            un décompte exact de lignes sur stderr
ligne 3054  if command -v timedatectl … then saute
            « timedatectl est présent sur cet hôte et répondrait »
```

Sous un profil où `timedatectl` répond, `configure-timezone.sh` n'emprunte plus
le repli : ces assertions deviennent **rouges sans qu'aucun défaut n'existe**, et
le décompte de lignes change. Faire de
`run-in-container.sh --profil systemd -- tests/run.sh integration` une validation
de cette tâche reviendrait à exiger la réécriture d'un fichier de cas de 3 600
lignes — hors périmètre, et cause probable d'un blocage.

**Conséquence de conception** : la preuve nouvelle vit dans
`tests/environment/`, pas dans `tests/integration/`. Le niveau `integration`
reste l'affaire du profil `debian`, et sa non-régression sous ce profil est une
validation de cette tâche.

## Le second piège — ne pas faire rougir la commande de référence

Aujourd'hui, `tests/run.sh` sans argument **ignore** un niveau non implémenté.
Le jour où `tests/environment/run-environment.sh` existe, il est exécuté partout,
y compris sous le profil `debian`, où systemd n'est pas.

Si le fichier de cas s'y contente de sauter, deux issues très différentes :

| Ce que le fichier déclare | Code du fichier | Code de `tests/run.sh` |
|---|---|---|
| que des sauts, aucune réussite | **3** | **3** — la commande de référence cesse d'être verte |
| au moins une réussite, le reste sauté par nature | **4** | **0** |

La règle est écrite dans `tests/README.md` §2 : *le 4 exige au moins une
réussite*. Le fichier de cas du niveau doit donc porter au moins un cas qui
s'exécute **sans** systemd — l'aide du script éprouvé, une option inconnue, un
préflight — et qualifier le reste par `saute_par_nature`. C'est exactement
l'exemple canonique de la qualification « par nature » que la bibliothèque
d'assertions documente : *le profil debian n'a pas systemd et ne l'aura jamais*.

## Ce qui est connu de systemd en conteneur, et ce qui reste à mesurer

Ces éléments sont donnés comme **pistes à vérifier**, pas comme une recette. Le
dépôt a une règle sur ce point, apprise en cinq tours par TASK-018 : une
propriété se mesure, elle ne se déduit pas.

- le conteneur démarre sur `/sbin/init` — donc `docker run --rm -d`, puis
  `docker exec -w /depot` pour la commande, puis destruction. Les trois verbes
  sont autorisés par `AGENTS.md` §8 sur le préfixe `mgnet-test-` ;
- `--privileged` est le levier le plus simple ; des montages `tmpfs` sur `/run`
  et `/run/lock`, et un accès aux cgroups, sont les besoins classiques. L'hôte
  est Docker Desktop sous WSL2, donc cgroup v2 unifié — `--cgroupns=host` est à
  éprouver, pas à supposer ;
- **la course au démarrage est le défaut le plus probable.** Un `docker exec`
  lancé aussitôt après le `run` trouve un systemd encore en `initializing`, et
  `systemctl` répond mal ou pas du tout. L'attente doit être active et **bornée**
  — `systemctl is-system-running` interrogé en boucle avec un plafond, jamais un
  `sleep` de confort, jamais une attente sans fin ;
- `systemctl is-system-running` rend **`degraded`** dès qu'une unité a échoué, ce
  qui est banal en conteneur. Le traiter comme un échec rendrait le profil
  inutilisable ; `offline` ou `unknown`, en revanche, disent que rien ne répond ;
- `hostnamectl set-hostname` et `timedatectl set-timezone` demandent `dbus` et
  les services `systemd-hostnamed` / `systemd-timedated`. Ils fonctionnent
  usuellement dans un conteneur privilégié ; **cela reste à mesurer**, et si l'un
  des deux refuse, c'est un autre cas de la liste plus haut qui doit passer au
  vert — pas une case cochée sur une lecture de code ;
- la destruction doit rester garantie sur interruption. Le filet actuel — un
  `trap … EXIT` qui vérifie puis `docker rm -f` — vaut aussi pour un conteneur
  détaché, et il vaut davantage encore : `--rm` seul ne suffit plus quand le
  conteneur ne s'arrête pas de lui-même.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh --profil systemd -- systemctl list-units --type=service --no-pager` | 0 |
| `run-in-container.sh --profil systemd -- tests/run.sh environment` | 0 |
| `run-in-container.sh -- tests/run.sh lint unit integration environment` | 0 |
| `run-in-container.sh --profil systemd --dry-run -- true` | 0, et aucune commande docker réellement lancée |
| `docker ps -a --filter name=mgnet-test- …` | 0, **sortie vide** |

La dernière n'est pas décorative : elle est la seule à constater qu'un conteneur
détaché ne survit pas à sa suite.

`tests/run.sh` seul, sans niveau, n'est **pas** une validation de cette tâche :
le niveau `acceptance` appelle `docker`, absent du conteneur, ce qui produit une
indisponibilité et un code 3 sans rapport avec le travail fourni.

## Ce que la tâche débloque

Le niveau 4 d'`AGENTS.md` §10, [TASK-023](TASK-023.md) — `check-services.sh`,
qui ne peut être prouvé nulle part ailleurs —, et les cas de
`configure-timezone.sh` et `configure-hostname.sh` en attente depuis ADR-0001.
