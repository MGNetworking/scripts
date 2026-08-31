---
id: TASK-002
title: "Fournir un environnement de test conteneurisé jetable"
status: completed
attempts: 1
priority: high
depends_on:
  - TASK-001
environment: host
human_approval_required: false
objective: |
  Permettre d'exécuter réellement les scripts du dépôt sur une Debian propre,
  détruite après chaque essai. C'est la seule façon de valider le comportement :
  la machine hôte n'a ni apt, ni systemctl, ni /etc/os-release.
scope:
  - tests/env/Dockerfile.debian — image de test, profil debian
  - tests/env/run-in-container.sh — exécute une commande dans un conteneur neuf
  - tests/README.md — documenter l'usage de l'environnement et les profils disponibles
  - tests/acceptance/run-acceptance.sh — dispatcher du niveau acceptance
  - tests/acceptance/TASK-002-environnement-conteneurise.sh — preuve des critères
out_of_scope:
  - profil systemd (image privilégiée avec /sbin/init) — tâche distincte
  - toute exécution sur un serveur réel ou sur le NAS
  - installation ou configuration de Docker Desktop
acceptance_criteria:
  - un conteneur Debian 12 se construit à partir du dépôt
  - le dépôt est monté dans le conteneur en lecture-écriture
  - une commande arbitraire s'exécute dans le conteneur et son code de retour est transmis fidèlement
  - le conteneur est détruit après exécution — aucun état ne survit
  - deux exécutions consécutives partent d'un état identique
  - le démon Docker arrêté produit un message clair et un code de retour non nul, jamais un faux succès
  - les conteneurs et images créés sont préfixés mgnet-test-
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- bash -c 'cat /etc/os-release'"
  - "tests/env/run-in-container.sh -- Linux/System/system-info.sh"
implementation_notes:
  - le démon Docker Desktop est arrêté sur la machine — la tâche ne peut être validée qu'après son démarrage
  - image de base debian:12, aucune image tierce non officielle
  - installer dans l'image le strict nécessaire — le combler au fil des besoins vaut mieux que tout embarquer
  - le montage du dépôt doit préserver les fins de ligne LF
---

# TASK-002 — Environnement de test jetable

## Pourquoi un conteneur et non l'hôte ou WSL

Décision arbitrée dans
[ADR-0001](../../docs/agent/decisions/ADR-0001-socle-agentique.md), décision 2.

L'hôte est disqualifié : `detect_os` échoue dès la première ligne sous Git Bash.
WSL fonctionnerait, mais ne se réinitialise pas proprement — or l'idempotence ne
se démontre que sur un état de départ connu, et plusieurs scripts du dépôt
écrivent dans `/etc/fstab` ou remplacent le nom d'hôte.

## Blocage du 2026-08-29, levé le jour même

Le champ `blocked_reason` a été retiré du frontmatter avec la levée du blocage —
il n'a de sens que pour une tâche `blocked`. Son contenu est conservé ici : la
trace vaut mieux que la ligne effacée.

> La commande de validation « `tests/run.sh lint` » porte sur le dépôt entier.
> Exécutée dans le conteneur que cette tâche livre — et où `shellcheck` est
> enfin disponible — elle échouait sur six fichiers préexistants qu'elle ne
> touche pas : cinq scripts `Linux/System` et `tests/lint.sh`.
>
> Les trois livrables de la tâche passaient, eux, sans réserve. Le blocage
> venait d'une dette antérieure que cette tâche a rendue visible, pas d'un
> défaut de son travail.
>
> Décision de Maxime : traiter la dette d'abord (TASK-011), puis reprendre cette
> tâche sans modifier son énoncé.

[TASK-011](TASK-011.md) a levé la dette. Les trois validations ont été rejouées
telles quelles, sans qu'une virgule de l'énoncé soit changée : elles passent,
et `tests/run.sh lint` sort désormais en 0 **dans le conteneur aussi**, avec
`shellcheck` réellement exécuté.

## Prérequis

Le démon Docker doit tourner. Il l'était au lancement de cette tâche
(Docker 28.5.2, `linux/amd64`) ; il ne l'était pas à la rédaction, d'où la
mention dans `implementation_notes`.

Si le démon s'arrête en cours de route, il faut le détecter et s'arrêter avec un
message explicite — jamais convertir l'échec en analyse statique.

## Forme attendue

```bash
tests/env/run-in-container.sh -- Linux/System/configure-swap.sh 512M --dry-run
tests/env/run-in-container.sh --profil debian -- tests/run.sh unit
```

Tout ce qui suit `--` est exécuté tel quel dans le conteneur, depuis la racine
du dépôt montée.
