# TASK-084 — Apprendre à juger.sh à juger une tâche Ansible (A158)

## Compte rendu

`orchestration/outils/juger.sh` est le juge automatique du dépôt : avant toute
relecture, il passe shellcheck sur les scripts du périmètre d'une fiche, lance son
fichier de cas dans le conteneur de test, et rend 0 ou 1. Depuis que le projet écrit
des rôles Ansible, ce juge tombait à côté : TASK-080 puis TASK-081 et TASK-085 se
sont vu répondre « aucun fichier de cas dans le périmètre », code 1, alors qu'un
rôle Ansible ne se prouve pas par un fichier de cas Bash mais par un scénario
Molecule. Le verdict devait se lire « sans objet » — c'est-à-dire ne rien valoir.
C'était l'anomalie A158 du registre.

Le travail consistait à apprendre au juge à reconnaître ce cas. Désormais, quand le
périmètre d'une fiche ne contient aucun script Bash mais cite `Ansible/`, le juge
cherche les rôles du périmètre (`Ansible/roles/<nom>/`) et, sous chacun, un scénario
Molecule complet : `molecule/<nom>/molecule.yml`, `converge.yml` et `verify.yml`. Il
le nomme s'il le trouve et rend 0 ; il dit ce qui manque et rend 1 sinon. Il ne lance
pas Molecule : le juge reste statique et rapide, comme le demandait la fiche.

Le champ `agent` de la fiche disait `deepseek`. Il a été changé en `orchestrateur`
avant l'activation : tout le périmètre vit dans `orchestration/`, que
`orchestration/limites.json` interdit en écriture aux agents lancés
(`Edit(orchestration/**)` en `deny`). Un agent délégué n'aurait rien pu écrire. Le
travail a donc été fait par le conducteur, dans la copie `../script-agents/TASK-084`.

Le risque principal était la régression : casser le jugement des tâches Bash, qui
sont l'immense majorité. Il a été écarté par une mesure avant/après. Les sorties de
`juger.sh` sur trois fiches Bash déjà closes (TASK-069, TASK-070, TASK-071) ont été
capturées sur `master` avant modification, puis rejouées après : identiques octet
pour octet, code 0 dans les deux cas. Le code du chemin Bash n'a pas été touché ;
l'ajout est enfermé dans une condition qui est fausse dès qu'un `.sh` figure au
périmètre.

La relecture (Opus) a rendu « fusionnable après corrections ». Le seul défaut majeur
était l'absence de ce rapport, écrit ici. Quatre remarques mineures restent ouvertes
et sont versées au registre (A169 à A171) : une fiche mixte, citant à la fois un
script Bash et `Ansible/`, n'est jamais jugée sur Molecule et un `.sh` rangé sous
`Ansible/` n'est jamais passé à shellcheck ; `orchestration/architecture.md` décrit
encore le juge sans cette branche ; le message d'échec ne nomme pas le scénario
incomplet et rien, dans le dépôt, ne rejouera ces cas automatiquement.

Coût : aucun agent délégué. Une relecture Opus, 36 752 jetons, 157 s.

## Fichiers

| Fichier | Nature |
|---|---|
| `orchestration/outils/juger.sh` | +51 lignes : extraction des chemins `Ansible/` et des rôles du `scope`, fonction `juger_ansible`, branche prise quand le périmètre ne porte aucun `.sh` ; 64 → 115 lignes |
| `orchestration/README.md` | ligne du tableau des outils : le juge reconnaît un périmètre Ansible seul |

## Commandes et codes réels

Niveau de preuve : **conteneur** pour shellcheck et pour les trois exécutions de
non-régression (elles lancent le vrai harnais dans `mgnet-test-debian`) ; **hôte**
pour les lectures de scénario, qui ne sont que des tests de présence de fichiers.

| Commande | Code | Sortie |
|---|---|---|
| `bash orchestration/outils/juger.sh tasks/completed/TASK-081.md` | 0 | `JUGE  scénario Molecule Ansible/roles/securite_base/molecule/default (molecule.yml, converge.yml, verify.yml) : PASSE` |
| `bash orchestration/outils/juger.sh tasks/completed/TASK-080.md` | 1 | `FAIL  périmètre Ansible sans rôle : aucun Ansible/roles/<nom>/ dans le scope` |
| `juger.sh` sur une fiche temporaire visant `Ansible/roles/faux_role/` (scénario réduit à `molecule.yml`) et `Ansible/roles/absent_role/` | 1 | `FAIL  … aucun scénario Molecule complet sous molecule/<nom>/` puis `FAIL  attendus : molecule.yml, converge.yml, verify.yml — manquants : converge.yml verify.yml` |
| `bash tests/env/run-in-container.sh -- shellcheck -x -f gcc orchestration/outils/juger.sh` | 0 | aucune remarque |
| `bash -n orchestration/outils/juger.sh` | 0 | — |
| `bash orchestration/outils/verifier-liens.sh` | 0 | `LIENS  aucun lien mort` |
| `bash orchestration/outils/juger.sh tasks/active/TASK-084.md` | 1 | `aucun fichier de cas` — sans objet : le périmètre de cette fiche est `orchestration/`, ni Bash livré ni Ansible (A169) |

### Non-régression des tâches Bash (critère 4)

Sorties complètes capturées avant modification sur `master`, puis après dans la copie,
et comparées par `diff` :

| Fiche | Avant | Après | `diff` |
|---|---|---|---|
| `tasks/completed/TASK-069.md` | 0 — `JUGE  shellcheck 0, fichier de cas 0, règles du dépôt 3 : PASSE` | 0 — idem | identique |
| `tasks/completed/TASK-070.md` | 0 — `JUGE  shellcheck 0, fichier de cas 0, règles du dépôt 3 : PASSE` | 0 — idem | identique |
| `tasks/completed/TASK-071.md` | 0 — `JUGE  shellcheck 0, fichier de cas 0, règles du dépôt 3 : PASSE` | 0 — idem | identique |

## Validations de la fiche

| Validation | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/completed/TASK-081.md` | 0 |
| `bash orchestration/outils/verifier-liens.sh` | 0 |

## Relecture

Relecteur `opus`, une lecture, 15 appels d'outils, 36 752 jetons, 157 s.
Verdict : FUSIONNABLE APRÈS CORRECTIONS. Un MAJEUR : rapport de tâche absent — écrit
ici. Cinq MINEURS, aucun corrigé dans le périmètre : versés au registre en A169,
A170 et A171 (le cinquième, la dérive de `orchestration/architecture.md`, est A170).

## Git

- branche `agent/TASK-084`, un commit `feat(orchestration): juger une tâche Ansible sur son scénario Molecule` ;
- fusion `--no-ff` dans `master`, copie et branche supprimées ;
- périmètre du diff `master...agent/TASK-084` : `orchestration/README.md`, `orchestration/outils/juger.sh` — conforme au `scope` ;
- aucun fichier de `tests/` touché : le nombre d'assertions du dépôt est inchangé.

## Réserves

- Une fiche dont le périmètre mêle un script Bash et `Ansible/` n'est pas jugée sur
  Molecule, et un `.sh` rangé sous `Ansible/` n'est jamais passé à shellcheck (A169).
- `orchestration/architecture.md` décrit encore le juge sans cette branche (A170).
- Le message d'échec ne nomme pas le scénario incomplet lorsqu'un rôle en porte
  plusieurs, et aucun fichier de cas versionné ne rejoue le comportement du juge (A171).
