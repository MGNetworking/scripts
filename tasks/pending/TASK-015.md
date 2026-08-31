---
id: TASK-015
title: "Trancher deux défauts de lib/common.sh révélés par les tests unitaires"
status: pending
priority: medium
depends_on:
  - TASK-003
environment: container-debian
human_approval_required: true
objective: |
  Les premiers tests unitaires du socle ont révélé deux écarts entre ce que
  lib/common.sh promet et ce qu'il fait. Les deux demandent un arbitrage, et
  toucher au socle impose de revalider tout le dépôt.
scope:
  - lib/common.sh — zone protégée, modification autorisée par cette tâche uniquement
  - tests/unit/common.test.sh — retourner les assertions qui épinglent le comportement corrigé
  - config/README.md — si la convention d'écriture des .env change
  - docs/architecture-technique.md — si le contrat du socle change
  - tasks/completed/TASK-003.md — corriger le critère si c'est lui qu'on retient comme fautif
out_of_scope:
  - toute autre fonction de lib/common.sh que celles visées
  - enable_full_logging, non couvert par les tests unitaires
  - la refonte de la journalisation
acceptance_criteria:
  - la décision retenue pour chaque défaut est écrite et justifiée
  - tests/env/run-in-container.sh -- tests/run.sh unit sort en 0 après correction
  - les assertions qui épinglaient l'ancien comportement sont retournées dans le même commit
  - les huit scripts du dépôt sont revalidés — une régression du socle les casse tous
  - la documentation reflète le contrat effectif du socle
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh unit"
  - "tests/env/run-in-container.sh -- bash -c 'for s in Linux/System/*.sh; do \"$s\" --help >/dev/null || exit 1; done'"
  - "tests/run.sh acceptance"
implementation_notes:
  - lib/common.sh est chargé par les huit scripts : toute régression est globale
  - les assertions concernées sont repérées dans tests/unit/common.test.sh, autour de FILS_NUE
  - la mutation « set -a dans load_config » fait tomber la suite aujourd'hui — c'est le signe que le test épingle bien le comportement actuel
---

# TASK-015 — Deux écarts du socle

Révélés par [TASK-003](../completed/TASK-003.md), qui les a mesurés sans les corriger :
`lib/common.sh` est une zone protégée, et une tâche ne modifie pas le socle en
effet de bord.

## Défaut 1 — `load_config` n'exporte pas

```text
shell appelant : VAR_NUE=valeur-nue   VAR_EXP=valeur-exp
processus fils : VAR_NUE=ABSENTE      VAR_EXP=valeur-exp
```

`load_config` fait `. "$fichier"` sans `export` ni `set -a`. Les variables sont
disponibles dans le shell appelant, mais **n'atteignent pas les processus fils**
— pour la forme d'écriture que `config/README.md` prescrit, c'est-à-dire des
affectations nues.

L'arbitrage porte sur trois options :

| Option | Conséquence |
|---|---|
| `set -a` dans `load_config` | toute la configuration passe aux fils ; change le contrat du socle, et expose des variables à des commandes qui ne les demandent pas |
| ne rien changer, reformuler le critère de TASK-003 | le socle garde son comportement ; `config/README.md` devrait alors dire quand écrire `export` |
| exporter explicitement dans les `.env` | déplace la charge sur chaque fichier de configuration, et sur celui qui les écrit |

## Défaut 2 — la journalisation peut tuer le script

Sous `set -e`, si `LOG_FILE` est renseignée mais que le fichier devient non
inscriptible, un simple `info` interrompt le script :

```text
[INFO] Exécution : true
lib/common.sh: line 78: /chemin/inexistant/journal.log: No such file or directory
[ERROR] Échec (code 1) à la ligne 78 de rl.sh.      → code 1
```

Le cas ne survient que si le répertoire de journaux disparaît en cours
d'exécution. C'est une fragilité de robustesse, pas une contradiction du
contrat — mais un script d'administration qui meurt parce qu'il n'a pas pu
écrire dans son journal est un mauvais comportement.

Défaut connexe relevé au passage : **le message du `trap ERR` désigne le mauvais
fichier**. `à la ligne 78 de rl.sh` alors que la ligne 78 est celle de
`lib/common.sh` — `$LINENO` vient du contexte fautif, `basename "$0"` du script
appelant. Diagnostic trompeur dès que l'échec vient du socle.

## Pourquoi une approbation humaine

Trois raisons.

`lib/common.sh` est chargé par les huit scripts du dépôt, dont ceux qui tournent
sur un serveur réel : toute régression est globale et silencieuse.

Le défaut 1 est un **arbitrage de contrat**, pas une correction évidente. Les
trois options ont des conséquences différentes sur la façon d'écrire les scripts
à venir.

Et les tests unitaires épinglent aujourd'hui le comportement actuel : les
retourner fait partie du même commit, sans quoi la suite passe au rouge. Ce n'est
pas un travail à mener sans décision préalable.
