# Backlog

Index de tout le travail connu. Deux natures d'entrées y coexistent.

**Tâches atomisées** — un fichier dans `pending/`, `active/`, `completed/` ou
`blocked/`, au format défini par [README.md](README.md). Seules celles-ci sont
sélectionnables par `/tache`.

**Entrées d'index** — travail identifié mais pas encore mis en forme, avec un
renvoi vers sa section du plan de refactorisation. Jamais sélectionnable. Une
entrée devient une tâche lorsqu'elle entre dans l'horizon de travail.

Prochain identifiant libre : **TASK-038**.

Depuis le 2026-09-02, le chantier se déroule en autonomie :
[ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) fixe
les vingt-quatre décisions qui l'encadrent — conduite du travail, contrat du
socle, cibles, politique de sécurité. L'agent écrit ses tâches, les ouvre, les
exécute, fusionne et pousse en fin de domaine. Il ne demande plus confirmation
de ce que cet ADR a tranché.

---

## 1. Tâches atomisées

| ID | Titre | Statut | Prio | Dépend de | Env. | Humain |
|---|---|---|---|---|---|---|
| [TASK-001](completed/TASK-001.md) | Mettre en place le harnais de validation du dépôt | `completed` | haute | — | hôte | non |
| [TASK-002](completed/TASK-002.md) | Fournir un environnement de test conteneurisé jetable | `completed` | haute | 001 | hôte | non |
| [TASK-011](completed/TASK-011.md) | Remettre le dépôt au niveau de l'analyse statique `shellcheck` | `completed` | haute | — | conteneur | non |
| [TASK-012](completed/TASK-012.md) | Distinguer « rien de prouvé » de « cas non applicable » dans le harnais | `completed` | haute | — | hôte | non |
| [TASK-013](completed/TASK-013.md) | Distinguer un cas non applicable d'un environnement indisponible | `completed` | moyenne | 012 | hôte | non |
| [TASK-003](completed/TASK-003.md) | Écrire les tests unitaires de `lib/common.sh` | `completed` | haute | 001, 002 | conteneur | non |
| [TASK-014](completed/TASK-014.md) | Affranchir la suite d'acceptation de l'état d'implémentation du dépôt | `completed` | haute | 003 | hôte | non |
| [TASK-015](completed/TASK-015.md) | Trancher deux défauts de `lib/common.sh` révélés par les tests unitaires | `completed` | moyenne | 003 | conteneur | **oui** |
| [TASK-004](completed/TASK-004.md) | Éprouver l'idempotence des scripts `Linux/System` | `completed` | moyenne | 002, 003 | conteneur | non |
| [TASK-016](completed/TASK-016.md) | Uniformiser les codes de retour et les messages d'erreur d'usage | `completed` | moyenne | 004 | conteneur | non |
| [TASK-017](completed/TASK-017.md) | Durcir la validation de `--file` dans `configure-swap.sh` | `completed` | haute | 016 | conteneur | non |
| [TASK-019](completed/TASK-019.md) | Contrôler la nature de la cible de `--file`, pas seulement la forme du chemin | `completed` | haute | 017 | conteneur | non |
| [TASK-018](completed/TASK-018.md) | Supprimer le doublement du `trap ERR` sur les substitutions de commande | `completed` | moyenne | 017 | conteneur | non |
| [TASK-009](completed/TASK-009.md) | Écrire `Linux/System/configure-cron.sh` | `completed` | moyenne | 004 | conteneur | non |
| [TASK-010](completed/TASK-010.md) | Mettre en place les sous-agents et la commande `/tache` | `completed` | haute | — | hôte | non |
| [TASK-020](completed/TASK-020.md) | Construire le profil de conteneur `systemd` et ouvrir le niveau `environment` | `completed` | haute | — | hôte | non |
| [TASK-021](completed/TASK-021.md) | Écrire `Linux/System/check-disk.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-027](completed/TASK-027.md) | Rendre le démon Docker disponible sans intervention humaine | `completed` | haute | — | hôte | **oui** |
| [TASK-022](completed/TASK-022.md) | Écrire `Linux/System/check-memory.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-023](completed/TASK-023.md) | Écrire `Linux/System/check-services.sh` | `completed` | moyenne | 020 | conteneur `systemd` | non |
| [TASK-024](pending/TASK-024.md) | Écrire `Linux/System/notify-failure.sh` | `ready` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-025](pending/TASK-025.md) | Écrire `Linux/System/manage-users.sh` | `ready` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-026](pending/TASK-026.md) | Écrire `Linux/System/reboot-system.sh` | `ready` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-028](pending/TASK-028.md) | Justifier la directive shellcheck nue de `linux-system.test.sh` | `ready` | haute | — | conteneur `debian` | non |
| [TASK-029](completed/TASK-029.md) | Écrire `Docker/Installation/install-docker.sh` | `completed` | haute | — | conteneur `systemd` | **oui** |
| [TASK-031](completed/TASK-031.md) | Écrire `Docker/Diagnostics/check-docker.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-033](pending/TASK-033.md) | Écrire `Docker/Diagnostics/list-containers.sh` | `ready` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-034](pending/TASK-034.md) | Écrire `Docker/Diagnostics/docker-disk-usage.sh` | `ready` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-030](completed/TASK-030.md) | Écrire `Docker/Configuration/configure-docker.sh` | `completed` | moyenne | 029 | conteneur `systemd` | **oui** |
| [TASK-032](completed/TASK-032.md) | Écrire `Docker/Configuration/create-network.sh` | `completed` | moyenne | 029 | conteneur `systemd` | **oui** |
| [TASK-035](pending/TASK-035.md) | Écrire `Docker/Maintenance/update-images.sh` | `ready` | moyenne | 029 | conteneur `debian` | **oui** |
| [TASK-036](pending/TASK-036.md) | Écrire `Docker/Maintenance/update-docker.sh` | `ready` | moyenne | 029 | conteneur `systemd` | **oui** |
| [TASK-037](pending/TASK-037.md) | Écrire `Docker/Cleanup/docker-cleanup.sh` | `pending` | haute | 034 | conteneur `debian` | **oui** |

TASK-020 à TASK-026 atomisent le domaine `Linux/System` — plan §1 — dans l'ordre
fixé par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md)
décision 16 : l'outillage d'abord, puis la lecture seule, puis ce qui modifie,
puis le destructif. `human_approval_required: true` ne suspend plus l'exécution
(décision 2) : il signale ce qui mérite une lecture attentive.

**TASK-023 attendait le profil `systemd`**, sans lequel aucune de ses preuves
n'existait — le profil `debian` n'a pas d'init, et `systemctl` y est absent. Elle
a été menée le 2026-09-08, et elle est la **première tâche du dépôt dont la
preuve vit au niveau `environment`** : c'est ce que TASK-020 avait été construite
pour rendre possible.

Restent **trois tâches** au domaine — TASK-024, TASK-025 et TASK-026 —, toutes
`ready`, indépendantes entre elles, et toutes sur le profil `debian`. Ce sont
celles qui écrivent sur le système : elles relèvent du **cycle complet**,
relecteur obligatoire (ADR-0003, décision 5).

---

**TASK-029 à TASK-037 atomisent le domaine `Docker`** — plan §8 à §10, atomisé
le 2026-09-13 en deux lots, le domaine dépassant les sept scripts qu'un lot
unique admet.

Le domaine **passe devant `Linux/Security`**, que l'ADR-0003 décision 16 plaçait
avant lui. Décision de Maxime, prise le 2026-09-13 : le premier serveur à servir
doit héberger une application conteneurisée derrière un reverse proxy, sans
Kubernetes. L'ordre des domaines n'est pas abrogé, il est devancé une fois.

Ordre retenu au sein du domaine :

```text
TASK-031 ── TASK-033 ── TASK-034      lecture seule, aucune dépendance
     check      list       disk        s'éprouvent avec un faux « docker »
                                   │
TASK-029 ─────────────────────────┘    installe le moteur, ouvre le domaine
     │
     ├── TASK-030  configure le démon
     ├── TASK-032  crée le réseau partagé
     ├── TASK-035  met à jour les images d'un projet
     └── TASK-036  met à jour le moteur
                   │
                   TASK-037  nettoie — destructif, dépend de TASK-034
```

Les trois diagnostics passent en premier : ils ne dépendent de rien, ne modifient
rien, et **installent le montage sur lequel tout le domaine repose** — un faux
`docker` en tête de `PATH`. Le conteneur de test n'a pas de démon Docker et n'en
aura pas : on n'installe pas Docker dans Docker, et aucun paquet n'est ajouté à
l'image. C'est la transposition du faux `curl` retenu par TASK-024.

`TASK-029` ouvre réellement le domaine : elle crée l'arborescence, le
`Docker/README.md` unique — plan §13 — et le bloc « Architecture » du README
racine.

**[ADR-0004](../docs/agent/decisions/ADR-0004-sobriete.md) a changé la façon
d'écrire, le 2026-09-13, pendant TASK-031** : un script vise 150 lignes, un
fichier de cas aussi, un fichier de tâche 30, et l'agent écrit lui-même au lieu
de déléguer à `redacteur-script` et `redacteur-tests`. Les huit fichiers de
tâche Docker restants comptent de 190 à 295 lignes — ils restent justes et
exécutables, mais ils ne servent pas de modèle de longueur.

**Le domaine ne connaît aucune application.** Ni son nom, ni son fichier Compose,
ni sa configuration n'apparaissent dans un script. `create-network.sh` prend le
nom du réseau en argument ; il ignore que ce réseau servira un reverse proxy.

Deux conséquences documentaires de cette atomisation : `Linux/Docker` — plan §3 —
est **abandonnée**, son préflight étant absorbé par `install-docker.sh` ; et
`docker-status.sh` / `docker-info.sh` **disparaissent** au profit de
`check-docker.sh` et `list-containers.sh`, qui couvrent leur contenu sans
enfreindre la frontière de lecture seule de `Docker/Diagnostics/`.

**[TASK-028](pending/TASK-028.md) passe devant elles.** Elle n'appartient pas au
chantier des scripts : c'est une dette d'une ligne, ouverte par TASK-021, qui
rend **rouge la commande de référence du dépôt** — une directive `shellcheck`
déposée sans la justification qu'exige le critère d'acceptation de TASK-011. Tant
qu'elle n'est pas fermée, `tests/run.sh` sans argument sort en 1, et le prochain
rapport de tâche qui citera cette commande devra répéter que le rouge n'est pas
le sien.

### Chemin critique

```text
TASK-001 ── TASK-002 ── TASK-011 ── TASK-003 ── TASK-004 ── TASK-009
 harnais    conteneur   dette de     tests de    idempotence  1re tâche
 (fait)     (fait)      shellcheck   common.sh   des scripts  métier
                        (fait)       (fait)      (fait)       (FAIT)

TASK-010 ── moteur d'exécution (fait) : 3 sous-agents + /tache
TASK-012 ── sémantique des codes de retour du harnais (fait)
```

**Le chemin critique est achevé.** La chaîne complète — backlog, planification,
rédaction, tests, relecture, correction, rapport, commit — a produit un script
d'administration réel et l'a prouvé.

Ce qui reste au backlog n'est plus de l'outillage : ce sont les dettes que le
dispositif a mises au jour en fonctionnant, et le chantier des scripts
lui-même.

TASK-002 avait été bloquée par une dette antérieure qu'elle a elle-même rendue
visible, en livrant un conteneur embarquant `shellcheck`. TASK-011 a levé la
dette ; TASK-002 a été rejouée sans qu'une virgule de son énoncé change, et
passe.

Une seule ligne désormais, celle de **la preuve** : rendre vérifiable ce que le
dépôt produit. Le moteur qui exécute n'est plus à construire — c'est Claude
Code, cadré par TASK-010.

TASK-009 était le point d'arrivée : la première tâche métier menée de bout en
bout par les sous-agents. Elle est passée le 2026-08-31, et le dispositif a servi
dès son premier usage réel — deux défauts sérieux du script ont été trouvés avant
qu'il n'atteigne un serveur, dont un que l'environnement de test masquait.

La suite du travail est le chantier des scripts lui-même, décrit dans
[docs/refactorisation-plan.md](../docs/refactorisation-plan.md) : une
cinquantaine de scripts, dont huit écrits.

### Tâches annulées

| ID | Titre | Raison |
|---|---|---|
| [TASK-005](cancelled/TASK-005.md) | Couche d'outils de l'agent | fournie par Claude Code |
| [TASK-006](cancelled/TASK-006.md) | État, logs, rapports | état et logs tenus par Claude Code ; les rapports restent, produits par `/tache` |
| [TASK-007](cancelled/TASK-007.md) | Orchestrateur et machine à états | remplacé par `.claude/commands/tache.md` |
| [TASK-008](cancelled/TASK-008.md) | Interface LLM | découplage multi-fournisseur abandonné |

Annulées le 2026-08-28 par
[ADR-0002](../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md). Les
fichiers sont conservés : ils documentent ce qui a été délibérément écarté, et
pourquoi.

---

## 2. Entrées d'index — chantier des scripts

Renvois vers [docs/refactorisation-plan.md](../docs/refactorisation-plan.md).
Aucune n'est sélectionnable en l'état.

### Linux / System — plan §1

**Domaine atomisé le 2026-09-03** — TASK-020 à TASK-026, §1 ci-dessus. Les
entrées ci-dessous sont conservées pour dire ce que ces tâches ont laissé de
côté ; elles restent non sélectionnables.

| Entrée | Note |
|---|---|
| `manage-users.sh` | atomisée : [TASK-025](pending/TASK-025.md) — **la suppression d'un utilisateur en est exclue**, `userdel -r` détruit un répertoire personnel : tâche distincte à écrire |
| `check-disk.sh` | atomisée : [TASK-021](completed/TASK-021.md) |
| `check-memory.sh` | atomisée : [TASK-022](completed/TASK-022.md) |
| `check-services.sh` | atomisée : [TASK-023](completed/TASK-023.md) |
| `reboot-system.sh` | atomisée : [TASK-026](pending/TASK-026.md) |
| brancher la notification sur la ligne de cron | laissé de côté par [TASK-024](pending/TASK-024.md) : changer la ligne déposée impose de reprendre `configure-cron.sh`, son fichier de cas et son README |
| `df` sur un montage réseau injoignable | laissé de côté par [TASK-021](completed/TASK-021.md) : un `df` peut y suspendre l'exécution indéfiniment |

### Linux / Security — plan §2

| Entrée | Note |
|---|---|
| `configure-ssh.sh` | **peut couper l'accès à la machine** — approbation humaine requise |
| `disable-root-login.sh` | idem |
| `configure-firewall.sh` | **peut couper l'accès à la machine** — approbation humaine requise |
| `configure-fail2ban.sh` | approbation humaine |
| `audit-users.sh` | lecture seule |
| `audit-ports.sh` | lecture seule |
| `security-check.sh` | lecture seule, destiné à cron |

### Linux / Docker — plan §3 — abandonnée

`prepare-docker-host.sh`, `configure-docker-host.sh`, `verify-docker-host.sh`.

**Abandonnée le 2026-09-13** : le préflight d'`install-docker.sh` couvre le même
besoin, et l'ordre d'installation de `CLAUDE.md` le lui impose déjà. Deux scripts
à tenir d'accord pour une vérification unique — voir plan §3.

### Linux / K3s — plan §4

`install-k3s.sh`, `configure-k3s.sh`, `verify-k3s.sh`, `upgrade-k3s.sh`,
`uninstall-k3s.sh` — ce dernier **destructif**, approbation humaine requise.

### Kubernetes — plan §5 à §7

Installation : `install-kubectl.sh`, `install-helm.sh`, `install-ingress.sh`,
`install-cert-manager.sh`, `install-metrics.sh`.

Configuration : `configure-namespaces.sh`, `configure-storage.sh`,
`configure-ingress.sh`, `configure-tls.sh`, `configure-registry.sh`.

Maintenance : `cluster-status.sh`, `diagnostics.sh`, `pods-status.sh`,
`events.sh`, `resource-usage.sh`, `backup-resources.sh`,
`cleanup-resources.sh` — ce dernier **destructif**.

### Docker — plan §8 à §10

**Domaine atomisé le 2026-09-13** — TASK-029 à TASK-037, §1 ci-dessus. Neuf
tâches couvrent le chantier prioritaire : installer le moteur, le configurer, le
diagnostiquer, créer un réseau d'infrastructure partagé entre projets Compose
indépendants, inventorier les conteneurs, mesurer le stockage, mettre à jour les
images d'un projet puis le moteur lui-même, et nettoyer ce qui ne sert plus.

Le domaine **ne connaît aucune application** : ni son nom, ni son fichier
Compose, ni sa configuration. Il fournit les primitives ; les projets applicatifs
portent leur propre cycle de vie.

Restent en index, non atomisés :

| Script | Dossier | Note |
|---|---|---|
| `verify-docker.sh` | `Installation/` | valide une installation qu'on vient de faire, quand `check-docker.sh` diagnostique une machine qu'on découvre |
| `restart-container.sh` | `Maintenance/` | jamais sur un workload géré par Kubernetes |
| `container-logs.sh` | `Maintenance/` | lecture seule malgré son dossier |
| `inspect-container.sh` | `Maintenance/` | sans afficher automatiquement les secrets |
| `list-images.sh` | `Diagnostics/` | dépôt, étiquette, identifiant, date, taille, usage |
| `cleanup-images.sh` | `Cleanup/` | **destructif** — distinguer `dangling` d'`unused` |
| `cleanup-containers.sh` | `Cleanup/` | **destructif** |
| `cleanup-networks.sh` | `Cleanup/` | **destructif** — épargner les réseaux d'infrastructure déclarés |
| `cleanup-volumes.sh` | `Cleanup/` | **hautement destructif** — les volumes portent les données |

`docker-cleanup.sh` (TASK-037) orchestre les nettoyages sans les remplacer : il
exclut les volumes par défaut, et aucune suppression automatique de volume ne
sera introduite sans justification explicite.

`docker-status.sh` et `docker-info.sh`, que le plan prévoyait en `Maintenance/`,
**disparaissent** : `check-docker.sh` et `list-containers.sh`, en `Diagnostics/`,
couvrent leur contenu et respectent la frontière de lecture seule.

### Synology — plan §11 et §12

Mise au standard de `organize-series.sh` et `update-plex.sh` — deux scripts
hérités qui ne chargent pas `lib/common.sh`. Puis les scripts d'administration :
sauvegarde, stockage, réseau, services, utilisateurs, maintenance.

Aucune exécution possible en conteneur : ces scripts visent DSM. Leur validation
se limitera au niveau 1 tant qu'un environnement Synology de test n'existe pas.

### Documentation — plan §13

`Linux/README.md`, `Docker/README.md`, `Kubernetes/README.md`,
`Synology/README.md` — un README par domaine.

---

## 3. Entrées d'index — sujets transverses

| Entrée | Source | Note |
|---|---|---|
| Remontée des échecs des tâches planifiées | [points-en-suspens.md](../docs/points-en-suspens.md) §2 | **tranché** par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) décision 15 : script de notification vers `ntfy` ou webhook. **Atomisée** : [TASK-024](pending/TASK-024.md) |
| Profil de conteneur `systemd` | [ADR-0001](../docs/agent/decisions/ADR-0001-socle-agentique.md) | **tranché** par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) décision 12 : construit **avant** les domaines. Débloque `configure-timezone.sh`, `configure-hostname.sh` et le niveau 4. **Faite** le 2026-09-03 : [TASK-020](completed/TASK-020.md), [rapport](reports/TASK-020-report.md) |
| Enchaînement de plusieurs tâches sans humain | [ADR-0002](../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md) | **ouvert** par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) décisions 1 à 4 : fusion et push par l'agent, ouverture des tâches déléguée, point d'étape par domaine |
| Ajustement des sous-agents | [TASK-010](completed/TASK-010.md) | **autorisé en permanence** par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) décision 5 : mode léger pour les scripts en lecture seule, relecteur obligatoire dès qu'un script écrit |
| Intégration continue | audit §5 | aucune CI aujourd'hui ; `tests/run.sh` en est le prérequis |
| Angle mort de l'hôte : `tests/lint.sh` sort en 0 en annonçant NON EXÉCUTÉ | [TASK-002](reports/TASK-002-report.md) | un validateur lira 0 et conclura PASS — c'est ce qui a laissé passer la dette de TASK-011. Non traité par [TASK-012](completed/TASK-012.md), qui l'a laissé hors périmètre — le harnais a désormais le code 4 pour l'exprimer |
| Les niveaux `unit` et `integration` gardent ~70 sauts non qualifiés | [TASK-013](reports/TASK-013-report.md) | ils n'affirment plus rien depuis TASK-013, mais leur nature n'est pas établie : le faux vert reste ouvert un étage plus bas |
| `docker info` sans borne de temps dans trois fichiers de cas | [TASK-013](reports/TASK-013-report.md) | un Docker Desktop en cours de démarrage suspend l'appel — constaté, plus de dix minutes. Un fichier de cas peut suspendre le niveau indéfiniment |
| Les scripts sont versionnés en `100644` | [TASK-009](reports/TASK-009-report.md) | **tranché** par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) décision 11 : bit `+x` posé dans Git sur tous les `.sh` |
| Le piège du commentaire commençant par `shellcheck` | [TASK-011](reports/TASK-011-report.md) | `tests/lint.sh` est protégé, rien ne protège les autres fichiers ; le testeur y est tombé deux fois |
| `require_root` sort en 1, pas en 2 | [TASK-011](reports/TASK-011-report.md) | **tranché** par [ADR-0003](../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md) décision 10 : le 1 est conservé — un privilège insuffisant est un échec d'exécution, pas une erreur d'usage. Aucun script modifié |
| Branche morte dans `configure-logging.sh` | [TASK-011](reports/TASK-011-report.md) | le `[dry-run] Créerait $REPERTOIRE_LOGS` est inatteignable, `common.sh` ayant déjà créé le répertoire |
| Asymétrie `server.env` / `load_config` : deux chemins de chargement, deux contrats | [TASK-015](reports/TASK-015-report.md) | `lib/common.sh` charge `config/server.env` par un `source` nu, quand `load_config` exporte depuis ADR-0003 décision 7. Une variable de `server.env` n'atteint pas les processus fils, une de `docker.env` si — alors que `config/README.md` prescrit la même forme d'écriture aux deux. Sans conséquence aujourd'hui (tous les `SRV_*` sont lus par le script lui-même), mais c'est un piège pour la suite |
| `set +a` n'est pas rétabli quand le `source` avorte le shell | [TASK-015](reports/TASK-015-report.md) | un `.env` référençant une variable non définie sous `set -u` tue le shell avant `set +a` : le piège `EXIT` s'exécute alors avec `allexport` armé. Le critère « rétabli même si le `source` échoue » tient pour les échecs qui rendent un code, pas pour ceux qui tuent le shell. Exposition limitée aux variables déclarées dans un handler de nettoyage |
| Les liens entre tâches cassent à chaque changement de statut | reprise de TASK-002 | le répertoire fait partie du chemin : six liens rompus au seul passage de `blocked/` à `completed/`. À traiter par une convention de lien, ou par un contrôle automatique dans `tests/` |
| `run-in-container.sh` : message de démon injoignable tronqué, et `--profil --dry-run` mal analysé | [TASK-002](reports/TASK-002-report.md) | deux défauts mineurs, relevés et non corrigés |

---

## 4. Terminé

| ID | Titre | Rapport |
|---|---|---|
| [TASK-001](completed/TASK-001.md) | Mettre en place le harnais de validation du dépôt | [rapport](reports/TASK-001-report.md) |
| [TASK-010](completed/TASK-010.md) | Mettre en place les sous-agents et la commande `/tache` | [rapport](reports/TASK-010-report.md) |
| [TASK-011](completed/TASK-011.md) | Remettre le dépôt au niveau de l'analyse statique `shellcheck` | [rapport](reports/TASK-011-report.md) |
| [TASK-002](completed/TASK-002.md) | Fournir un environnement de test conteneurisé jetable | [rapport](reports/TASK-002-report.md) |
| [TASK-012](completed/TASK-012.md) | Distinguer « rien de prouvé » de « cas non applicable » dans le harnais | [rapport](reports/TASK-012-report.md) |
| [TASK-003](completed/TASK-003.md) | Écrire les tests unitaires de `lib/common.sh` | [rapport](reports/TASK-003-report.md) |
| [TASK-014](completed/TASK-014.md) | Affranchir la suite d'acceptation de l'état d'implémentation du dépôt | [rapport](reports/TASK-014-report.md) |
| [TASK-004](completed/TASK-004.md) | Éprouver l'idempotence des scripts `Linux/System` | [rapport](reports/TASK-004-report.md) |
| [TASK-009](completed/TASK-009.md) | Écrire `Linux/System/configure-cron.sh` | [rapport](reports/TASK-009-report.md) |
| [TASK-013](completed/TASK-013.md) | Distinguer un cas non applicable d'un environnement indisponible | [rapport](reports/TASK-013-report.md) |
| [TASK-015](completed/TASK-015.md) | Trancher deux défauts de `lib/common.sh` révélés par les tests unitaires | [rapport](reports/TASK-015-report.md) |
| [TASK-016](completed/TASK-016.md) | Uniformiser les codes de retour et les messages d'erreur d'usage | [rapport](reports/TASK-016-report.md) |
| [TASK-017](completed/TASK-017.md) | Durcir la validation de `--file` dans `configure-swap.sh` | [rapport](reports/TASK-017-report.md) |
| [TASK-019](completed/TASK-019.md) | Contrôler la nature de la cible de `--file`, pas seulement la forme du chemin | [rapport](reports/TASK-019-report.md) |
| [TASK-018](completed/TASK-018.md) | Supprimer le doublement du `trap ERR` sur les substitutions de commande | [rapport](reports/TASK-018-report.md) |
| [TASK-021](completed/TASK-021.md) | Écrire `Linux/System/check-disk.sh` | [rapport](reports/TASK-021-report.md) |
| [TASK-027](completed/TASK-027.md) | Rendre le démon Docker disponible sans intervention humaine | [rapport](reports/TASK-027-report.md) |
| [TASK-031](completed/TASK-031.md) | Écrire `Docker/Diagnostics/check-docker.sh` | [rapport](reports/TASK-031-report.md) |
| [TASK-029](completed/TASK-029.md) | Écrire `Docker/Installation/install-docker.sh` | [rapport](reports/TASK-029-report.md) |
| [TASK-030](completed/TASK-030.md) | Écrire `Docker/Configuration/configure-docker.sh` | [rapport](reports/TASK-030-report.md) |
| [TASK-032](completed/TASK-032.md) | Écrire `Docker/Configuration/create-network.sh` | [rapport](reports/TASK-032-report.md) |
| [TASK-020](completed/TASK-020.md) | Construire le profil de conteneur `systemd` et ouvrir le niveau `environment` | [rapport](reports/TASK-020-report.md) |
| [TASK-022](completed/TASK-022.md) | Écrire `Linux/System/check-memory.sh` | [rapport](reports/TASK-022-report.md) |
| [TASK-023](completed/TASK-023.md) | Écrire `Linux/System/check-services.sh` | [rapport](reports/TASK-023-report.md) |

Les travaux antérieurs à la mise en place de ce backlog — socle `lib/common.sh`,
six scripts `Linux/System`, documentation — sont tracés dans l'historique Git et
dans [docs/refactorisation-plan.md](../docs/refactorisation-plan.md).
