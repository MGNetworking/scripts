# Backlog

Index de tout le travail connu. Deux natures d'entrées y coexistent.

**Tâches atomisées** — un fichier dans `pending/`, `active/`, `completed/` ou
`blocked/`, au format défini par [README.md](README.md). Seules celles-ci sont
sélectionnables par `/tache`.

**Entrées d'index** — travail identifié mais pas encore mis en forme, avec un
renvoi vers sa section du plan de refactorisation. Jamais sélectionnable. Une
entrée devient une tâche lorsqu'elle entre dans l'horizon de travail.

Prochain identifiant libre : **TASK-012**.

---

## 1. Tâches atomisées

| ID | Titre | Statut | Prio | Dépend de | Env. | Humain |
|---|---|---|---|---|---|---|
| [TASK-001](completed/TASK-001.md) | Mettre en place le harnais de validation du dépôt | `completed` | haute | — | hôte | non |
| [TASK-002](blocked/TASK-002.md) | Fournir un environnement de test conteneurisé jetable | `blocked` | haute | 001 | hôte | non |
| [TASK-011](pending/TASK-011.md) | Remettre le dépôt au niveau de l'analyse statique `shellcheck` | `ready` | haute | — | conteneur | non |
| [TASK-003](pending/TASK-003.md) | Écrire les tests unitaires de `lib/common.sh` | `pending` | haute | 001, 002 | conteneur | non |
| [TASK-004](pending/TASK-004.md) | Éprouver l'idempotence des scripts `Linux/System` | `pending` | moyenne | 002, 003 | conteneur | non |
| [TASK-009](pending/TASK-009.md) | Écrire `Linux/System/configure-cron.sh` | `pending` | moyenne | 004 | conteneur | non |
| [TASK-010](completed/TASK-010.md) | Mettre en place les sous-agents et la commande `/tache` | `completed` | haute | — | hôte | non |

### Chemin critique

```text
TASK-001 ── TASK-002 ── TASK-011 ── TASK-002 ── TASK-003 ── TASK-004 ── TASK-009
 harnais    conteneur   dette de     revalidée    tests de   idempotence  1re tâche
 (fait)     (bloquée)   shellcheck                common.sh  des scripts  métier

TASK-010 ── moteur d'exécution (fait) : 3 sous-agents + /tache
```

TASK-002 apparaît deux fois : son travail est fait et prouvé, mais sa validation
échoue sur une dette antérieure qu'elle a elle-même rendue visible. TASK-011
lève cette dette, puis TASK-002 est rejouée sans que son énoncé change.

Une seule ligne désormais, celle de **la preuve** : rendre vérifiable ce que le
dépôt produit. Le moteur qui exécute n'est plus à construire — c'est Claude
Code, cadré par TASK-010.

TASK-009 reste le point d'arrivée : la première tâche métier menée de bout en
bout par les sous-agents. Tant qu'elle n'est pas passée, la chaîne n'est pas
démontrée.

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

| Entrée | Note |
|---|---|
| `manage-users.sh` | création, suppression, clés SSH — destructif, approbation humaine probable |
| `check-disk.sh` | lecture seule, bonne candidate après TASK-004 |
| `check-memory.sh` | lecture seule |
| `check-services.sh` | lecture seule |
| `reboot-system.sh` | **destructif** — approbation humaine requise |

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

### Linux / Docker — plan §3

`prepare-docker-host.sh`, `configure-docker-host.sh`, `verify-docker-host.sh`.

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

Installation : `install-docker.sh`, `verify-docker.sh`.

Maintenance : `docker-status.sh`, `docker-info.sh`, `update-images.sh`,
`restart-container.sh`, `container-logs.sh`, `inspect-container.sh`.

Cleanup : `cleanup-images.sh`, `cleanup-containers.sh`, `cleanup-networks.sh`,
`cleanup-volumes.sh`, `docker-cleanup.sh` — **tout ce domaine est destructif**,
`--dry-run` obligatoire, approbation humaine requise.

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
| Remontée des échecs des tâches planifiées | [points-en-suspens.md](../docs/points-en-suspens.md) §2 | trois pistes concurrentes (courriel, webhook, contrôle de fraîcheur) — **décision d'architecture, approbation humaine requise** |
| Profil de conteneur `systemd` | [ADR-0001](../docs/agent/decisions/ADR-0001-socle-agentique.md) | débloque la validation de `configure-timezone.sh` et `configure-hostname.sh` |
| Enchaînement de plusieurs tâches sans humain | [ADR-0002](../docs/agent/decisions/ADR-0002-claude-code-comme-moteur.md) | écarté pour l'instant : coûteux en limites d'usage, et prématuré tant que les règles n'ont pas été éprouvées |
| Ajustement des sous-agents | [TASK-010](completed/TASK-010.md) | après le premier passage réel de `/tache` — il révélera les règles mal formulées |
| Intégration continue | audit §5 | aucune CI aujourd'hui ; `tests/run.sh` en est le prérequis |
| `tests/run.sh` confond « niveau en échec » et « niveau non prouvé » | [TASK-002](reports/TASK-002-report.md) | un script de niveau sortant en 3 est compté ÉCHEC ; le code 3 ne couvre que « script absent » |
| Angle mort de l'hôte : `tests/lint.sh` sort en 0 en annonçant NON EXÉCUTÉ | [TASK-002](reports/TASK-002-report.md) | un validateur lira 0 et conclura PASS — c'est ce qui a laissé passer la dette de TASK-011 |
| `run-in-container.sh` : message de démon injoignable tronqué, et `--profil --dry-run` mal analysé | [TASK-002](reports/TASK-002-report.md) | deux défauts mineurs, relevés et non corrigés |

---

## 4. Terminé

| ID | Titre | Rapport |
|---|---|---|
| [TASK-001](completed/TASK-001.md) | Mettre en place le harnais de validation du dépôt | [rapport](reports/TASK-001-report.md) |
| [TASK-010](completed/TASK-010.md) | Mettre en place les sous-agents et la commande `/tache` | [rapport](reports/TASK-010-report.md) |

Les travaux antérieurs à la mise en place de ce backlog — socle `lib/common.sh`,
six scripts `Linux/System`, documentation — sont tracés dans l'historique Git et
dans [docs/refactorisation-plan.md](../docs/refactorisation-plan.md).
