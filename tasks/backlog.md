# Backlog

Index de tout le travail connu. Deux natures d'entrées y coexistent.

**Tâches atomisées** — un fichier dans `pending/`, `active/`, `completed/` ou
`blocked/`, au format défini par [README.md](README.md). Seules celles-ci sont
sélectionnables par `/tache`.

**Entrées d'index** — travail identifié mais pas encore mis en forme, avec un
renvoi vers sa section du plan de refactorisation. Jamais sélectionnable. Une
entrée devient une tâche lorsqu'elle entre dans l'horizon de travail.

Prochain identifiant libre : **TASK-072**.

Depuis le 2026-09-02, le chantier se déroule en autonomie :
[décisions](../orchestration/decisions.md) fixe
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
| [TASK-024](completed/TASK-024.md) | Écrire `Linux/System/notify-failure.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-025](completed/TASK-025.md) | Écrire `Linux/System/manage-users.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-026](completed/TASK-026.md) | Écrire `Linux/System/reboot-system.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-028](completed/TASK-028.md) | Justifier la directive shellcheck nue de `linux-system.test.sh` | `completed` | haute | — | conteneur `debian` | non |
| [TASK-039](pending/TASK-039.md) | Tenir le registre unique des anomalies et les traiter | `ready` | haute | — | conteneur `debian` | non |
| [TASK-040](completed/TASK-040.md) | Ramener `manage-users.sh` et son fichier de cas à la sobriété visée | `completed` | basse | 025 | conteneur `debian` | non |
| [TASK-041](completed/TASK-041.md) | Écrire `Linux/Security/audit-users.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-042](completed/TASK-042.md) | Écrire `Linux/Security/audit-ports.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-043](completed/TASK-043.md) | Écrire `Linux/Security/security-check.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-044](completed/TASK-044.md) | Écrire `Linux/Security/configure-fail2ban.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-045](completed/TASK-045.md) | Écrire `Linux/Security/configure-firewall.sh` | `completed` | haute | — | conteneur `debian` | **oui** |
| [TASK-046](completed/TASK-046.md) | Écrire `Linux/Security/configure-ssh.sh` | `completed` | haute | 025 | conteneur `debian` | **oui** |
| [TASK-047](completed/TASK-047.md) | Écrire `Linux/Security/disable-root-login.sh` | `completed` | haute | 046 | conteneur `debian` | **oui** |
| [TASK-048](completed/TASK-048.md) | Consigner les jetons de relecture à l’étape 6 de `/tache` (A47) | `completed` | moyenne | — | hôte | non |
| [TASK-049](completed/TASK-049.md) | Enchaîner les tâches sans vidage ni « reprends », par un sous-agent jetable par tâche | `completed` | haute | — | hôte | **oui** |
| [TASK-029](completed/TASK-029.md) | Écrire `Docker/Installation/install-docker.sh` | `completed` | haute | — | conteneur `systemd` | **oui** |
| [TASK-031](completed/TASK-031.md) | Écrire `Docker/Diagnostics/check-docker.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-033](completed/TASK-033.md) | Écrire `Docker/Diagnostics/list-containers.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-034](completed/TASK-034.md) | Écrire `Docker/Diagnostics/docker-disk-usage.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-030](completed/TASK-030.md) | Écrire `Docker/Configuration/configure-docker.sh` | `completed` | moyenne | 029 | conteneur `systemd` | **oui** |
| [TASK-032](completed/TASK-032.md) | Écrire `Docker/Configuration/create-network.sh` | `completed` | moyenne | 029 | conteneur `systemd` | **oui** |
| [TASK-035](completed/TASK-035.md) | Écrire `Docker/Maintenance/update-images.sh` | `completed` | moyenne | 029 | conteneur `debian` | **oui** |
| [TASK-036](completed/TASK-036.md) | Écrire `Docker/Maintenance/update-docker.sh` | `completed` | moyenne | 029 | conteneur `systemd` | **oui** |
| [TASK-037](completed/TASK-037.md) | Écrire `Docker/Cleanup/docker-cleanup.sh` | `completed` | haute | 034 | conteneur `debian` | **oui** |
| [TASK-050](completed/TASK-050.md) | Écrire `Linux/K3s/verify-k3s.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-051](completed/TASK-051.md) | Écrire `Linux/K3s/install-k3s.sh` | `completed` | haute | 050 | conteneur `debian` | **oui** |
| [TASK-052](completed/TASK-052.md) | Écrire `Linux/K3s/configure-k3s.sh` | `completed` | moyenne | 051 | conteneur `debian` | **oui** |
| [TASK-053](completed/TASK-053.md) | Écrire `Linux/K3s/upgrade-k3s.sh` | `completed` | moyenne | 050, 051 | conteneur `debian` | **oui** |
| [TASK-054](completed/TASK-054.md) | Écrire `Linux/K3s/uninstall-k3s.sh` | `completed` | moyenne | 051 | conteneur `debian` | **oui** |
| [TASK-055](completed/TASK-055.md) | Écrire `Kubernetes/Maintenance/cluster-status.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-056](completed/TASK-056.md) | Écrire `Kubernetes/Maintenance/pods-status.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-057](completed/TASK-057.md) | Écrire `Kubernetes/Maintenance/events.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-058](completed/TASK-058.md) | Écrire `Kubernetes/Maintenance/diagnostics.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-059](completed/TASK-059.md) | Écrire `Kubernetes/Maintenance/resource-usage.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-060](completed/TASK-060.md) | Écrire `Kubernetes/Maintenance/backup-resources.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-061](completed/TASK-061.md) | Écrire `Kubernetes/Maintenance/cleanup-resources.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-062](completed/TASK-062.md) | Écrire `Kubernetes/Installation/install-kubectl.sh` | `completed` | moyenne | — | conteneur `debian` | non |
| [TASK-063](completed/TASK-063.md) | Écrire `Kubernetes/Installation/install-helm.sh` | `completed` | moyenne | — | conteneur `debian` | **oui** |
| [TASK-064](completed/TASK-064.md) | Écrire `Kubernetes/Installation/install-ingress.sh` | `completed` | moyenne | 062 | conteneur `debian` | non |
| [TASK-065](completed/TASK-065.md) | Écrire `Kubernetes/Installation/install-cert-manager.sh` | `completed` | haute | 062, 063 | conteneur `debian` | **oui** |
| [TASK-066](pending/TASK-066.md) | Écrire `Kubernetes/Installation/install-metrics.sh` | `ready` | basse | 062 | conteneur `debian` | non |
| [TASK-067](completed/TASK-067.md) | Écrire `Kubernetes/Configuration/configure-namespaces.sh` | `completed` | moyenne | 062 | conteneur `debian` | non |
| [TASK-068](completed/TASK-068.md) | Écrire `Kubernetes/Configuration/configure-storage.sh` | `completed` | moyenne | 062 | conteneur `debian` | **oui** |
| [TASK-069](completed/TASK-069.md) | Écrire `Kubernetes/Configuration/configure-ingress.sh` | `completed` | moyenne | 062, 064 | conteneur `debian` | **oui** |
| [TASK-070](completed/TASK-070.md) | Écrire `Kubernetes/Configuration/configure-tls.sh` | `completed` | moyenne | 062, 065 | conteneur `debian` | **oui** |
| [TASK-071](pending/TASK-071.md) | Écrire `Kubernetes/Configuration/configure-registry.sh` | `ready` | moyenne | 062, 067 | conteneur `debian` | **oui** |

TASK-020 à TASK-026 atomisent le domaine `Linux/System` — plan §1 — dans l'ordre
fixé par [décisions](../orchestration/decisions.md)
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
relecteur obligatoire (decisions.md, décision 5).

---

**TASK-029 à TASK-037 atomisent le domaine `Docker`** — plan §8 à §10, atomisé
le 2026-09-13 en deux lots, le domaine dépassant les sept scripts qu'un lot
unique admet.

Le domaine **passe devant `Linux/Security`**, que decisions.md décision 16 plaçait
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

**La sobriété s'applique depuis le 2026-09-13**
([décisions](../orchestration/decisions.md) 25, 26, 28) : un script vise 150
lignes, un fichier de cas aussi, un fichier de tâche 30. Les huit fichiers de
tâche Docker restants comptent de 190 à 295 lignes — ils restent justes et
exécutables, mais ils ne servent pas de modèle de longueur.

**Les tâches sont confiées à des agents depuis le 2026-09-14**
([orchestration/](../orchestration/README.md)). Chaque fiche porte un champ
`agent` : un modèle externe de `orchestration/modeles/`, un modèle Claude, ou
`orchestrateur`. L'agent — Claude Code piloté par ce modèle — écrit, teste et
corrige dans sa propre copie du dépôt ; l'orchestrateur vérifie, fait relire par
Opus, écrit seul les README et ce backlog, et fusionne. Coûts et défauts au
[journal](../orchestration/mesures/journal.md).

| Tâche | Agent |
|---|---|
| TASK-024, TASK-033, TASK-034, TASK-035 | `deepseek` |
| TASK-041 à TASK-047 | `deepseek` (agents `sonnet` indisponibles, A41) |
| TASK-039 | `orchestrateur` |

**Le domaine ne connaît aucune application.** Ni son nom, ni son fichier Compose,
ni sa configuration n'apparaissent dans un script. `create-network.sh` prend le
nom du réseau en argument ; il ignore que ce réseau servira un reverse proxy.

Deux conséquences documentaires de cette atomisation : `Linux/Docker` — plan §3 —
est **abandonnée**, son préflight étant absorbé par `install-docker.sh` ; et
`docker-status.sh` / `docker-info.sh` **disparaissent** au profit de
`check-docker.sh` et `list-containers.sh`, qui couvrent leur contenu sans
enfreindre la frontière de lecture seule de `Docker/Diagnostics/`.

**[TASK-039](pending/TASK-039.md) passe devant elles.** C'est le registre unique des
anomalies — orchestration, harnais, socle, scripts —, et sa ligne A01 rend
aujourd'hui l'acceptance rouge sur `master`. Tout défaut ou point ouvert s'y inscrit,
et nulle part ailleurs.

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
[décisions](../orchestration/decisions.md). Les
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
| `manage-users.sh` | atomisée : [TASK-025](completed/TASK-025.md) — **la suppression d'un utilisateur en est exclue**, `userdel -r` détruit un répertoire personnel : tâche distincte à écrire |
| `check-disk.sh` | atomisée : [TASK-021](completed/TASK-021.md) |
| `check-memory.sh` | atomisée : [TASK-022](completed/TASK-022.md) |
| `check-services.sh` | atomisée : [TASK-023](completed/TASK-023.md) |
| `reboot-system.sh` | atomisée : [TASK-026](completed/TASK-026.md) |
| brancher la notification sur la ligne de cron | laissé de côté par [TASK-024](completed/TASK-024.md) : changer la ligne déposée impose de reprendre `configure-cron.sh`, son fichier de cas et son README |
| `df` sur un montage réseau injoignable | traité : `check-disk.sh` borne `df` (registre TASK-039, A25) |

### Linux / Security — plan §2

| Entrée | Note |
|---|---|
| `audit-users.sh` | atomisée : [TASK-041](completed/TASK-041.md) |
| `audit-ports.sh` | atomisée : [TASK-042](completed/TASK-042.md) |
| `security-check.sh` | atomisée : [TASK-043](completed/TASK-043.md) |
| `configure-fail2ban.sh` | atomisée : [TASK-044](completed/TASK-044.md) |
| `configure-firewall.sh` | atomisée : [TASK-045](completed/TASK-045.md) — **peut couper l'accès à la machine** |
| `configure-ssh.sh` | atomisée : [TASK-046](completed/TASK-046.md) — **peut couper l'accès à la machine** |
| `disable-root-login.sh` | atomisée : [TASK-047](completed/TASK-047.md) — **peut couper l'accès à la machine** |

### Linux / Docker — plan §3 — abandonnée

`prepare-docker-host.sh`, `configure-docker-host.sh`, `verify-docker-host.sh`.

**Abandonnée le 2026-09-13** : le préflight d'`install-docker.sh` couvre le même
besoin, et l'ordre d'installation de `CLAUDE.md` le lui impose déjà. Deux scripts
à tenir d'accord pour une vérification unique — voir plan §3.

### Linux / K3s — plan §4

| Entrée | Note |
|---|---|
| `verify-k3s.sh` | atomisée : [TASK-050](completed/TASK-050.md) |
| `install-k3s.sh` | atomisée : [TASK-051](completed/TASK-051.md) |
| `configure-k3s.sh` | atomisée : [TASK-052](completed/TASK-052.md) — décisions prises (décision 47) |
| `upgrade-k3s.sh` | atomisée : [TASK-053](completed/TASK-053.md) — décisions prises (décision 47) |
| `uninstall-k3s.sh` | atomisée : [TASK-054](completed/TASK-054.md) — décisions prises (décision 47) |

### Kubernetes — plan §5 à §7

Découpé en trois lots (plus de sept scripts), tous atomisés le 2026-09-16.

| Lot | Fiches | Note |
|---|---|---|
| Maintenance — plan §7 | [TASK-055](completed/TASK-055.md) à [TASK-061](completed/TASK-061.md) | lecture seule d'abord ; `cleanup-resources.sh` **destructif** ; décision 48 |
| Installation — plan §5 | [TASK-062](completed/TASK-062.md) à [TASK-066](pending/TASK-066.md) | vérification seule de kubectl, Traefik et metrics-server ; décision 48 |
| Configuration — plan §6 | [TASK-067](completed/TASK-067.md) à [TASK-071](pending/TASK-071.md) | secrets du registry hors dépôt ; décision 48 |

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

Aucune liste ici. Les sujets transverses ouverts — dettes du harnais, du socle,
de l'orchestration — sont les lignes du registre
[TASK-039](pending/TASK-039.md). Les entrées tranchées qui figuraient dans ce
tableau restent dans l'historique Git et dans [décisions](../orchestration/decisions.md).

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
| [TASK-033](completed/TASK-033.md) | Écrire `Docker/Diagnostics/list-containers.sh` | [rapport](reports/TASK-033-report.md) |
| [TASK-028](completed/TASK-028.md) | Justifier la directive shellcheck nue de `linux-system.test.sh` | [rapport](reports/TASK-028-report.md) |
| [TASK-034](completed/TASK-034.md) | Écrire `Docker/Diagnostics/docker-disk-usage.sh` | [rapport](reports/TASK-034-report.md) |
| [TASK-037](completed/TASK-037.md) | Écrire `Docker/Cleanup/docker-cleanup.sh` | [rapport](reports/TASK-037-report.md) |
| [TASK-035](completed/TASK-035.md) | Écrire `Docker/Maintenance/update-images.sh` | [rapport](reports/TASK-035-report.md) |
| [TASK-036](completed/TASK-036.md) | Écrire `Docker/Maintenance/update-docker.sh` | [rapport](reports/TASK-036-report.md) |
| [TASK-024](completed/TASK-024.md) | Écrire `Linux/System/notify-failure.sh` | [rapport](reports/TASK-024-report.md) |
| [TASK-025](completed/TASK-025.md) | Écrire `Linux/System/manage-users.sh` | [rapport](reports/TASK-025-report.md) |
| [TASK-026](completed/TASK-026.md) | Écrire `Linux/System/reboot-system.sh` | [rapport](reports/TASK-026-report.md) |
| [TASK-040](completed/TASK-040.md) | Ramener `manage-users.sh` et son fichier de cas à la sobriété visée | [rapport](reports/TASK-040-report.md) |
| [TASK-020](completed/TASK-020.md) | Construire le profil de conteneur `systemd` et ouvrir le niveau `environment` | [rapport](reports/TASK-020-report.md) |
| [TASK-022](completed/TASK-022.md) | Écrire `Linux/System/check-memory.sh` | [rapport](reports/TASK-022-report.md) |
| [TASK-023](completed/TASK-023.md) | Écrire `Linux/System/check-services.sh` | [rapport](reports/TASK-023-report.md) |
| [TASK-041](completed/TASK-041.md) | Écrire `Linux/Security/audit-users.sh` | [rapport](reports/TASK-041-report.md) |
| [TASK-042](completed/TASK-042.md) | Écrire `Linux/Security/audit-ports.sh` | [rapport](reports/TASK-042-report.md) |
| [TASK-043](completed/TASK-043.md) | Écrire `Linux/Security/security-check.sh` | [rapport](reports/TASK-043-report.md) |
| [TASK-045](completed/TASK-045.md) | Écrire `Linux/Security/configure-firewall.sh` | [rapport](reports/TASK-045-report.md) |
| [TASK-048](completed/TASK-048.md) | Consigner les jetons de relecture à l’étape 6 de `/tache` | [rapport](reports/TASK-048-report.md) |
| [TASK-046](completed/TASK-046.md) | Écrire `Linux/Security/configure-ssh.sh` | [rapport](reports/TASK-046-report.md) |
| [TASK-047](completed/TASK-047.md) | Écrire `Linux/Security/disable-root-login.sh` | [rapport](reports/TASK-047-report.md) |
| [TASK-044](completed/TASK-044.md) | Écrire `Linux/Security/configure-fail2ban.sh` | [rapport](reports/TASK-044-report.md) |
| [TASK-049](completed/TASK-049.md) | Enchaîner les tâches sans vidage ni « reprends », par un sous-agent jetable par tâche | [rapport](reports/TASK-049-report.md) |
| [TASK-050](completed/TASK-050.md) | Écrire `Linux/K3s/verify-k3s.sh` | [rapport](reports/TASK-050-report.md) |
| [TASK-051](completed/TASK-051.md) | Écrire `Linux/K3s/install-k3s.sh` | [rapport](reports/TASK-051-report.md) |
| [TASK-052](completed/TASK-052.md) | Écrire `Linux/K3s/configure-k3s.sh` | [rapport](reports/TASK-052-report.md) |
| [TASK-053](completed/TASK-053.md) | Écrire `Linux/K3s/upgrade-k3s.sh` | [rapport](reports/TASK-053-report.md) |
| [TASK-054](completed/TASK-054.md) | Écrire `Linux/K3s/uninstall-k3s.sh` | [rapport](reports/TASK-054-report.md) |
| [TASK-055](completed/TASK-055.md) | Écrire `Kubernetes/Maintenance/cluster-status.sh` | [rapport](reports/TASK-055-report.md) |
| [TASK-056](completed/TASK-056.md) | Écrire `Kubernetes/Maintenance/pods-status.sh` | [rapport](reports/TASK-056-report.md) |
| [TASK-057](completed/TASK-057.md) | Écrire `Kubernetes/Maintenance/events.sh` | [rapport](reports/TASK-057-report.md) |
| [TASK-058](completed/TASK-058.md) | Écrire `Kubernetes/Maintenance/diagnostics.sh` | [rapport](reports/TASK-058-report.md) |
| [TASK-059](completed/TASK-059.md) | Écrire `Kubernetes/Maintenance/resource-usage.sh` | [rapport](reports/TASK-059-report.md) |
| [TASK-060](completed/TASK-060.md) | Écrire `Kubernetes/Maintenance/backup-resources.sh` | [rapport](reports/TASK-060-report.md) |
| [TASK-061](completed/TASK-061.md) | Écrire `Kubernetes/Maintenance/cleanup-resources.sh` | [rapport](reports/TASK-061-report.md) |
| [TASK-062](completed/TASK-062.md) | Écrire `Kubernetes/Installation/install-kubectl.sh` | [rapport](reports/TASK-062-report.md) |
| [TASK-063](completed/TASK-063.md) | Écrire `Kubernetes/Installation/install-helm.sh` | [rapport](reports/TASK-063-report.md) |
| [TASK-065](completed/TASK-065.md) | Écrire `Kubernetes/Installation/install-cert-manager.sh` | [rapport](reports/TASK-065-report.md) |
| [TASK-064](completed/TASK-064.md) | Écrire `Kubernetes/Installation/install-ingress.sh` | [rapport](reports/TASK-064-report.md) |
| [TASK-069](completed/TASK-069.md) | Écrire `Kubernetes/Configuration/configure-ingress.sh` | [rapport](reports/TASK-069-report.md) |
| [TASK-070](completed/TASK-070.md) | Écrire `Kubernetes/Configuration/configure-tls.sh` | [rapport](reports/TASK-070-report.md) |
| [TASK-067](completed/TASK-067.md) | Écrire `Kubernetes/Configuration/configure-namespaces.sh` | [rapport](reports/TASK-067-report.md) |
| [TASK-068](completed/TASK-068.md) | Écrire `Kubernetes/Configuration/configure-storage.sh` | [rapport](reports/TASK-068-report.md) |

Les travaux antérieurs à la mise en place de ce backlog — socle `lib/common.sh`,
six scripts `Linux/System`, documentation — sont tracés dans l'historique Git et
dans [docs/refactorisation-plan.md](../docs/refactorisation-plan.md).
