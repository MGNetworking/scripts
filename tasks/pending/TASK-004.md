---
id: TASK-004
title: "Éprouver l'idempotence des scripts Linux/System existants"
status: pending
priority: medium
depends_on:
  - TASK-002
  - TASK-003
environment: container-debian
human_approval_required: false
objective: |
  Vérifier par l'exécution que les six scripts Linux/System se comportent comme
  annoncé : préflight correct, --dry-run sans effet, seconde exécution sans
  modification.
scope:
  - tests/integration/linux-system.test.sh
  - tests/run.sh — brancher le niveau integration
  - tests/README.md
out_of_scope:
  - correction des défauts découverts — chacun donne lieu à une tâche distincte
  - scripts Synology hérités
  - update-system.sh en exécution réelle — apt upgrade dans un conteneur de test n'apporte aucune information utile
acceptance_criteria:
  - chaque script affiche son aide avec --help et sort avec le code 0
  - chaque script modifiant le système refuse de s'exécuter sans privilège root
  - configure-hostname.sh, configure-timezone.sh, configure-swap.sh et configure-logging.sh en --dry-run ne modifient aucun fichier — vérifié par empreinte avant/après
  - chaque script exécuté deux fois de suite laisse le système identique après la seconde exécution
  - system-info.sh s'exécute sans privilège et sort avec le code 0
  - une option inconnue est refusée avec le code 2
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
implementation_notes:
  - la comparaison avant/après se fait par empreinte des fichiers touchés (/etc/hosts, /etc/hostname, /etc/fstab, /etc/logrotate.d/mgnetworking)
  - configure-timezone.sh et configure-hostname.sh appellent timedatectl et hostnamectl, absents sans systemd — prévoir un saut explicite marqué NON EXÉCUTÉ, jamais un PASS
  - configure-swap.sh manipule le swap : impossible dans un conteneur non privilégié, se limiter au --dry-run et au préflight
  - un conteneur neuf par cas, sans quoi le test d'idempotence ne prouve rien
---

# TASK-004 — Idempotence des scripts existants

## Ce que la tâche vérifie vraiment

Le dépôt affirme l'idempotence dans ses conventions. Personne ne l'a jamais
vérifiée par l'exécution : les huit scripts n'ont, à ce jour, jamais tourné
ailleurs que sur un serveur réel, à la main.

Le test décisif tient en trois temps :

```text
état initial → exécution 1 → empreinte A → exécution 2 → empreinte B
```

`A == B` prouve l'idempotence. `A != B` révèle un ajout aveugle ou une écriture
non conditionnelle.

## Limites assumées de l'environnement

Un conteneur non privilégié ne donne accès ni au swap, ni à systemd. Trois
scripts ne seront donc que partiellement couverts à ce niveau. Ces cas sont
marqués `NON EXÉCUTÉ` et non `PASS` — la couverture complète attend le profil
`container-systemd`, qui fera l'objet de sa propre tâche.

Il vaut mieux une couverture partielle et honnête qu'une couverture affichée
comme totale et fausse.
