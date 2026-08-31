---
id: TASK-009
title: "Écrire Linux/System/configure-cron.sh"
status: completed
priority: medium
depends_on:
  - TASK-004
environment: container-debian
human_approval_required: false
objective: |
  Installer la planification des scripts destinés à tourner sans humain, par un
  fichier /etc/cron.d/mgnetworking. C'est la première tâche métier réelle
  traversant toute la chaîne agentique : plan, code, tests, validation, rapport.
scope:
  - Linux/System/configure-cron.sh
  - tests/integration/configure-cron.test.sh
  - config/server.env.example — variables d'horaire
  - Linux/System/README.md
  - README.md — ligne du tableau des scripts
  - docs/points-en-suspens.md — marquer le point 1 comme traité
out_of_scope:
  - remontée des échecs des tâches planifiées — point en suspens n° 2, tâche distincte
  - modification de update-system.sh
  - planification des scripts Kubernetes, Docker ou Synology, qui n'existent pas encore
acceptance_criteria:
  - le script écrit /etc/cron.d/mgnetworking avec SHELL, PATH et une entrée par tâche planifiée
  - l'entrée porte l'utilisateur root après l'horaire, et non un appel à sudo
  - les scripts planifiés sont invoqués avec --yes, cron n'ayant pas de terminal
  - la sortie standard est redirigée vers /dev/null, la sortie d'erreur est conservée
  - --dry-run affiche le fichier qui serait écrit sans rien modifier
  - une seconde exécution ne modifie pas le fichier — vérifié par empreinte
  - le script refuse de s'exécuter sans privilège root
  - l'horaire est configurable par config/server.env et par la ligne de commande, la ligne de commande primant
  - le chemin de déploiement du dépôt est détecté, non écrit en dur
  - --help documente le tout
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash -c 'Linux/System/configure-cron.sh --dry-run'"
implementation_notes:
  - contenu attendu documenté dans docs/points-en-suspens.md, point 1
  - cron n'utilise pas sudo — le champ utilisateur suit l'horaire dans /etc/cron.d/
  - un fichier de /etc/cron.d/ dont le nom contient un point est ignoré silencieusement par cron
  - le fichier doit appartenir à root et ne pas être exécutable, sinon cron le rejette
  - SCRIPTS_ROOT donne le chemin de déploiement réel
  - ne pas rediriger stderr : c'est la seule alerte disponible tant que le point en suspens n° 2 n'est pas traité
---

# TASK-009 — Planification par cron

## Origine

Point en suspens n° 1, soulevé le 2026-08-26 dans
[docs/points-en-suspens.md](../../docs/points-en-suspens.md). Le contenu attendu
du fichier y est déjà rédigé, ainsi que les trois contraintes de fonctionnement :
absence de `sudo`, `--yes` obligatoire, redirection de la sortie.

## Rôle dans la transformation agentique

C'est la **tâche de démonstration de bout en bout**. Elle est réelle, utile, et
son périmètre est petit — les trois qualités attendues d'un premier essai.

Elle vérifie toute la chaîne :

```text
backlog → sélection → plan → code → conteneur → tests → validation → rapport
```

Une chaîne qui produit ce script, ses tests et son rapport sans intervention est
une chaîne qui fonctionne. Une chaîne qui produit un script sans tests, ou un
rapport annonçant des validations non lancées, ne fonctionne pas — quelle que
soit la qualité apparente du script.

## Décisions laissées ouvertes

L'horaire et le chemin de déploiement ne sont pas figés dans le point en
suspens. Ils sont réversibles et locaux : retenir une valeur par défaut simple
— hebdomadaire, tôt le matin — la rendre configurable, et la documenter dans le
rapport, conformément à [AGENTS.md](../../AGENTS.md) §14.

## Correction apportée à l'énoncé avant lancement, le 2026-08-29

La deuxième validation portait
`tests/env/run-in-container.sh -- tests/run.sh integration configure-cron`.

`tests/run.sh` n'accepte que des **niveaux**, jamais de filtre par fichier.
Mesuré :

```text
tests/run.sh integration configure-cron
[ERROR] Niveau inconnu : configure-cron (attendu : lint unit integration environment acceptance)
→ code 2
```

La commande était donc insatisfaisable quel que soit le travail fourni. C'est le
troisième énoncé de suite à porter ce défaut, après TASK-003 et TASK-004 : ces
tâches ont été écrites avant que le harnais n'existe, et supposaient des
capacités qu'il n'a pas.

Corrigée en `tests/run.sh integration` — le niveau entier. Le dispatcher
`tests/integration/run-integration.sh`, livré par TASK-004, découvre
automatiquement tout fichier `*.test.sh` du répertoire : le nouveau fichier de
test sera pris sans qu'aucun branchement soit nécessaire.

Contrôle effectué au titre de la règle inscrite dans
[tasks/README.md](../README.md) §5 : *si le travail était parfait, cette
commande sortirait-elle en 0 ?*
