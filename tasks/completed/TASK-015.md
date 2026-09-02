---
id: TASK-015
title: "Trancher deux défauts de lib/common.sh révélés par les tests unitaires"
status: completed
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
  - load_config rend ses variables visibles d'un processus fils, pour un .env écrit en affectations nues
  - set +a est rétabli même lorsque le source du fichier de configuration échoue
  - un journal devenu inécrivable n'interrompt plus le script — un avertissement sur stderr, une seule fois, puis l'exécution se poursuit
  - le message du trap ERR nomme le fichier réellement fautif, y compris quand l'échec vient de lib/common.sh
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
  - les trois arbitrages sont tranchés par ADR-0003 décisions 7, 8 et 9 — voir la section « Les décisions sont prises » en fin de fichier. Rien à décider, tout à mettre en œuvre
  - set +a doit être rétabli même si le source échoue, sinon tout ce que le script déclare ensuite serait exporté à son insu
  - l'avertissement de journal inaccessible doit être émis UNE SEULE FOIS, pas à chaque appel de info
  - docs/architecture-technique.md est à mettre à jour : contrat du socle et distinction entre code 1 et code 2
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

---

## Les décisions sont prises — 2026-09-02

Par [ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md).
**Il n'y a plus rien à arbitrer ici : il y a à mettre en œuvre.**

### Défaut 1 → `set -a` dans `load_config` (décision 7)

`load_config` encadre son `source` par `set -a` / `set +a`. Toute la
configuration atteint les processus fils.

Rien ne change dans les fichiers `.env` ni dans la façon de les écrire :
`config/README.md` continue de prescrire des affectations nues. Les deux autres
options — statu quo documenté, `export` explicite dans chaque `.env` — sont
écartées.

`set +a` doit être rétabli **même si le `source` échoue**, sans quoi tout ce que
le script déclare ensuite se retrouverait exporté à son insu.

### Défaut 2 → avertir une fois, puis continuer (décision 8)

Si le fichier de journal devient inécrivable en cours d'exécution, le socle
écrit **un seul** avertissement sur la sortie d'erreur, puis poursuit sans
journal. Il ne meurt pas, il ne se tait pas non plus.

« Une seule fois » est un critère à tenir : un script qui appelle `info`
cinquante fois ne doit pas produire cinquante avertissements.

### Défaut connexe → `BASH_SOURCE` dans le `trap ERR` (décision 9)

Le message désigne le fichier réellement fautif. La correction est explicitement
autorisée dans le périmètre de cette tâche.

### Ce qui n'est pas dans cette tâche

`require_root` **conserve le code 1** (décision 10) : un privilège insuffisant
est un échec d'exécution, pas une erreur d'usage. Aucun script n'est modifié pour
cela, et la distinction est à inscrire dans `docs/architecture-technique.md` :

```text
2  erreur d'usage      option inconnue, argument manquant, valeur invalide
1  échec d'exécution   privilège insuffisant, dépendance absente, opération échouée
```
