# ADR-0001 — Socle de la plateforme agentique

**Date** : 2026-08-27
**Statut** : **partiellement remplacé** le 2026-08-28 par
[ADR-0002](ADR-0002-claude-code-comme-moteur.md)
**Décideur** : Maxime Ghalem
**Contexte** : [project-audit.md](../project-audit.md), §18

> **Décision 1 (runtime Bash + Node) : caduque.** Aucun orchestrateur n'est
> écrit ; le moteur est Claude Code.
> **Décision 2 (conteneur Docker jetable) : toujours en vigueur.**
> **Décision 3 (Git) : intention conservée**, l'exécutant change.
>
> Ce document est conservé tel qu'il a été écrit : il garde la trace du
> raisonnement, y compris de ce qui a été abandonné.

---

## Décision 1 — Runtime

**Les outils sont écrits en Bash, l'orchestrateur et les adaptateurs LLM en Node
avec la seule bibliothèque standard.**

Aucun `package.json`, aucune dépendance npm. Node v26 est présent sur le poste ;
il fournit nativement JSON, HTTP et système de fichiers, là où Bash sans `jq`
rendrait l'état persistant et les appels d'API fragiles.

Les outils restent en Bash parce qu'ils enveloppent des commandes shell et que
c'est le langage du dépôt. Un outil est un script autonome, appelable à la main :

```bash
.agent/tools/shell.sh execute --timeout 60 -- shellcheck lib/common.sh
```

**Conséquence** : l'orchestrateur peut être remplacé sans toucher aux outils, et
inversement. Le contrat entre les deux est le JSON écrit sur la sortie standard.

**Réversibilité** : élevée. Les outils sont utilisables sans l'orchestrateur.

---

## Décision 2 — Environnement de validation

**Les validations comportementales s'exécutent dans un conteneur Docker
jetable.**

La machine hôte est écartée : Git Bash n'a ni `apt`, ni `systemctl`, ni
`/etc/os-release`, et le premier `detect_os` y échoue. Valider sur l'hôte
reviendrait à ne rien valider.

Le conteneur offre ce que WSL ne donne pas : une réinitialisation parfaite entre
deux exécutions, indispensable pour les tests d'idempotence et pour les scripts
qui écrivent dans `/etc/fstab` ou remplacent le nom d'hôte.

### Deux profils de conteneur

| Profil | Image | Couvre |
|---|---|---|
| `debian` | `debian:12` standard | analyse statique, tests unitaires de `lib/common.sh`, `--dry-run`, idempotence, `apt` |
| `systemd` | image dérivée avec `/sbin/init`, lancée en `--privileged` | `systemctl`, `timedatectl`, `hostnamectl`, `logrotate` |

Une tâche déclare le profil dont elle a besoin. Le profil `systemd` n'est
construit que lorsqu'une tâche l'exige.

### Prérequis opérationnel

Le démon Docker Desktop est **arrêté** au moment de cette décision. Les
validations de niveau 2 et supérieur exigent qu'il soit démarré. L'agent doit le
détecter et s'arrêter proprement plutôt que déclarer une validation réussie
faute d'avoir pu la lancer.

**Réversibilité** : élevée. `.agent/config/environment.yaml` décrit
l'environnement ; passer au conteneur `systemd`, à WSL ou à une VM ne change pas
la logique de l'orchestrateur.

---

## Décision 3 — Git

**L'agent commite automatiquement, mais uniquement sur une branche dédiée
`agent/TASK-xxx`. Jamais sur `master`. Jamais de `git push`.**

Cette décision arbitre un conflit : le plan de transformation demandait
`automatic_commit: true`, tandis qu'une règle permanente de ce dépôt interdit
tout commit non demandé explicitement.

La branche dédiée lève les deux objections. L'agent garde son autonomie et sa
traçabilité ; `master` reste sous contrôle humain, ce qui compense l'absence de
protection de branche sur un dépôt public.

La fusion est un acte humain. `git push` également.

**Réversibilité** : élevée. Une branche agent non fusionnée s'abandonne sans
conséquence.

---

## Décisions différées

**Périmètre du travail autonome** (audit §18.d) : quels scripts du backlog sont
éligibles à l'exécution autonome et lesquels exigent
`human_approval_required: true`. Sera tranché tâche par tâche lors de la
structuration du backlog (Phase 3), plutôt qu'en bloc a priori.
