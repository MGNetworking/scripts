---
id: TASK-003
title: "Écrire les tests unitaires de lib/common.sh"
status: completed
priority: high
depends_on:
  - TASK-001
  - TASK-002
environment: container-debian
human_approval_required: false
objective: |
  Couvrir de tests le socle chargé par tous les scripts du dépôt. Une régression
  dans lib/common.sh casse aujourd'hui les huit scripts sans que rien ne le
  signale.
scope:
  - tests/unit/run-unit.sh — dispatcher du niveau, au chemin qu'annonce tests/run.sh --liste
  - tests/unit/common.test.sh
  - tests/lib/assert.sh — assertions minimales du harnais
  - tests/README.md
out_of_scope:
  - toute modification de lib/common.sh — si un test révèle un défaut, il est consigné et fait l'objet d'une tâche distincte
  - tests d'intégration des scripts d'administration (TASK-004)
acceptance_criteria:
  - load_config charge un fichier existant et exporte ses variables
  - load_config sur un fichier absent arrête le script avec un code non nul
  - require_cmd réussit sur une commande présente et échoue en listant les commandes manquantes
  - require_root échoue avec un code non nul lorsque l'utilisateur n'est pas root
  - require_os accepte une distribution attendue et refuse les autres
  - detect_os renseigne OS_ID, OS_VERSION et OS_ARCH
  - info, warn, error et success écrivent sur stderr et dans le fichier de log
  - die sort avec le code fourni, et 1 par défaut
  - confirm retourne 0 sans interaction lorsque ASSUME_YES vaut true
  - un double chargement de common.sh ne provoque ni erreur ni effet de bord
  - run_logged retourne le code de la commande enveloppée, pas celui de tee
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh unit"
implementation_notes:
  - les assertions restent en Bash pur, sans bats — absent de la machine et dépendance non justifiée pour ce volume
  - les tests qui vérifient require_root doivent tourner sous un utilisateur non privilégié dans le conteneur
  - le trap ERR de common.sh interfère avec les tests attendant un échec — isoler chaque cas dans un sous-shell
  - LOG_DIR doit être redirigé vers un répertoire temporaire pendant les tests
---

# TASK-003 — Tests unitaires du socle

## Enjeu

`lib/common.sh` est le point de défaillance unique du dépôt : 217 lignes
chargées par chaque script. C'est aussi la zone protégée par
[AGENTS.md](../../AGENTS.md) §5 — le fichier ne se modifie pas en effet de bord.

Le tester, c'est rendre cette protection vérifiable plutôt que déclarative.

## Difficulté principale

Tester du code qui appelle `exit` demande d'isoler chaque cas :

```bash
( source lib/common.sh; require_cmd commande_absente ) 2>/dev/null
assert_exit_code 1 $?
```

Le `trap ERR` posé par `common.sh` et le `set -Eeuo pipefail` du harnais se
gênent mutuellement. C'est le piège attendu de cette tâche : ne pas le résoudre
en désactivant `set -e`, ce que l'article §12 d'AGENTS.md interdit
explicitement.

## Si un test révèle un défaut

Le consigner dans le rapport, créer une tâche, **ne pas corriger
`lib/common.sh` au passage**.

## Corrections apportées à l'énoncé avant lancement, le 2026-08-29

Le `scope` listait `tests/unit/common.test.sh` mais pas
`tests/unit/run-unit.sh`, qui est le chemin où `tests/run.sh` cherche le niveau
`unit` — voir `tests/run.sh --liste`. Sans ce fichier, `tests/run.sh unit`
sortirait en 3, « niveau non implémenté », et la seconde validation aurait
échoué quel que soit le travail fourni.

`tests/run.sh` a été retiré du `scope` : le branchement du niveau ne demande
aucune modification de ce fichier, le chemin y étant déjà déclaré depuis
TASK-001. Y toucher serait modifier le validateur sans nécessité.

Contrôle effectué au titre de la règle inscrite dans
[tasks/README.md](../README.md) §5 après les blocages de TASK-002 et TASK-011 :
*si le travail était parfait, cette commande sortirait-elle en 0 ?*
