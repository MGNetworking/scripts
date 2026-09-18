# TASK-085 — Rapport d'exécution

## Compte rendu

L'outillage Ansible (ansible, ansible-lint, yamllint, molecule) tournait jusqu'ici
installé dans la WSL de `user` par `pipx` — seul écart du dépôt à la règle « rien sur
la machine, tout en conteneur jetable » (constaté à TASK-080). Cette tâche referme
l'écart : un profil `ansible` de `tests/env/run-in-container.sh`, une image dédiée
(`tests/env/Dockerfile.ansible`, outils épinglés) et une commande unique,
`tests/env/valider-ansible.sh`, qui enchaîne yamllint, ansible-lint puis
`molecule test` sur `securite_base` — désormais la commande de référence, dans
`Ansible/README.md` comme dans la CI.

L'agent `deepseek` a livré le profil, l'image et le fichier de cas en deux passages ;
`Ansible/README.md` lui était fermé (`deny Edit(**/README.md)` de `limites.json`,
zone protégée), le conducteur l'a donc complété lui-même — c'était dans le `scope` de
la fiche. Le juge (`juger.sh`) a rendu `FAIL` : son motif de reconnaissance des
fichiers de cas ne couvre pas `tests/integration/` quand le `scope` déclaré ne cite
que `tests/env/`, comme la fiche de TASK-085. Le fichier de cas existe bien (30
vérifications) et la commande réelle, rejouée par le conducteur dans un vrai
conteneur avec le vrai démon Docker, a rendu 0 : yamllint, ansible-lint et
`molecule test` complet (create, prepare, converge, idempotence, verify, destroy),
aucune instance `mgnet-test-securite-*` avant ni après. La relecture Opus a jugé le
travail fusionnable, avec six défauts mineurs (absence de `set -Eeuo pipefail` dans
le fichier de cas, pas de `--help` sur `valider-ansible.sh`, relevé « avant »
purement informatif, messages figés « debian:12 » dans `run-in-container.sh`, deux
trous de documentation) — versés au registre (A163 à A167), non corrigés ici.

**Le premier push sur `master` a fait tomber la CI**, en 52 secondes : `permission
denied` sur `tests/env/valider-ansible.sh`. Le fichier avait été entré au dépôt en
mode Git `100644` au lieu de `100755`, sans effet visible sur le poste de travail —
le partage de fichiers de Docker Desktop sous Windows rend tout fichier monté
exécutable, quel que soit son mode Git — mais bloquant sur le checkout Linux natif
du runner GitHub, qui respecte le mode exact. Corrigé par le conducteur
(`git update-index --chmod=+x`), versé au registre en `A168` (seule anomalie posée
`[x]`, corrigée dans la foulée) : le niveau **conteneur** obtenu sur le poste ne
suffisait pas à garantir un run Linux natif, une limite à garder en tête pour les
prochaines tâches Ansible. Le second push a rendu la CI **verte** :
[run 35339673025](https://github.com/MGNetworking/scripts/actions/runs/35339673025),
les trois travaux réussis, dont Ansible en 3 min 17 s.

## Statut

COMPLETED

## Objectif

`ansible`, `ansible-lint`, `yamllint` et `molecule` s'exécutent depuis un conteneur
jetable lancé par `tests/env/`, comme `tests/run.sh` pour Bash — aucune installation
sur la machine de `user` n'est plus nécessaire pour valider un rôle.

## Travail réalisé

- `tests/env/Dockerfile.ansible` : image `mgnet-test-ansible`, `python:3.12-slim-bookworm`
  (Ansible 14.4.0 exige Python ≥ 3.12, que Debian 12 ne fournit pas), outils pip
  épinglés, client Docker statique 28.5.2, `rsync` (phase `create` de Molecule),
  label `mgnet.test.docker="socket"`.
- Profil `ansible` ajouté à `tests/env/run-in-container.sh` : monte le socket Docker
  de l'hôte, sans Docker imbriqué.
- `tests/env/valider-ansible.sh` : yamllint sur tout le dépôt, ansible-lint sur
  `Ansible/`, installation des collections du scénario, puis `molecule test` sur
  `securite_base` ; relevé des instances `mgnet-test-securite-*` avant et après.
- `.github/workflows/ci.yml` : le travail Ansible appelle ce profil au lieu
  d'installer l'outillage par `pipx` sur le runner.
- `Ansible/README.md` (conducteur) : la commande conteneurisée devient la commande
  de référence, section dédiée en tête ; l'installation `pipx` reste documentée,
  reformulée pour l'application réelle contre l'inventaire (`ansible-playbook`), plus
  pour la seule validation.
- Correctif A168 : mode exécutable de `tests/env/valider-ansible.sh` rétabli.

## Fichiers modifiés

- `tests/env/Dockerfile.ansible` (créé, 76 lignes)
- `tests/env/valider-ansible.sh` (créé, 58 lignes)
- `tests/env/run-in-container.sh` (+45 lignes, profil `ansible`)
- `.github/workflows/ci.yml` (travail Ansible reformulé)
- `tests/integration/ansible-profil.test.sh` (créé, 109 lignes, 30 vérifications)
- `Ansible/README.md` (conducteur, hors capacité d'écriture de l'agent)
- `orchestration/mesures/agents.tsv`, `orchestration/mesures/journal.md`,
  `tasks/pending/TASK-039.md` (A163 à A168), `tasks/backlog.md` (clôture)

## Commandes exécutées

| Commande | Code | Contexte |
|---|---|---|
| `bash tests/integration/ansible-profil.test.sh` | 0 | hôte, faux `docker`, 30/30 vérifications |
| `bash tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh` | 0 | conteneur, vrai démon Docker, poste de travail |
| `bash orchestration/outils/verifier-liens.sh` | 0 | commande de la fiche |
| `bash orchestration/outils/juger.sh tasks/active/TASK-085.md` | 1 | « aucun fichier de cas dans le périmètre » — limite de `juger.sh`, A158/A167, pas un échec du travail |
| CI GitHub Actions, run 35339381587 (1er push) | échec, 126 | `valider-ansible.sh` non exécutable (A168) |
| CI GitHub Actions, run 35339673025 (2e push) | succès | https://github.com/MGNetworking/scripts/actions/runs/35339673025 |

## Validations

| Validation | Résultat |
|---|---|
| Fichier de cas (simulé, faux `docker`) | PASS — 30/30 |
| Commande de référence (conteneur, vrai démon) | PASS — yamllint, ansible-lint, molecule test (create/prepare/converge/idempotence/verify/destroy) |
| Instances `mgnet-test-securite-*` avant/après | PASS — aucune dans les deux relevés |
| `verifier-liens.sh` | PASS |
| `juger.sh` | NON APPLICABLE — limite connue (A158), étendue par A167 |
| CI sur `master` | PASS — run 35339673025, après correction A168 |

## Erreurs rencontrées

`tests/env/valider-ansible.sh` livré en mode Git `100644` : invisible sur le poste
(partage de fichiers Docker Desktop), bloquant sur le runner GitHub (`permission
denied`, code 126). Corrigé par le conducteur (A168).

## Corrections automatiques

Aucune : la correction du mode exécutable est un geste manuel du conducteur, pas une
relance de l'agent (2 passages déjà consommés, cf. Tentatives).

## Tentatives

2 / 3 (agent `deepseek`, `orchestration/outils/lancer-agent.sh`)

## Critères d'acceptation

- [x] une seule commande, documentée, lance ansible-lint, yamllint puis molecule test sur securite_base sans rien installer sur l'hôte ; codes réels au rapport
- [x] les instances Molecule créées portent le préfixe mgnet-test- et sont supprimées à la fin, prouvé par docker ps -a avant et après
- [x] l'image et les versions des outils sont épinglées, comme les linters de ci.yml
- [x] la CI utilise ce profil et reste verte ; lien du run au rapport — run 35339673025, après correction du mode exécutable (A168)

## Validation finale

PASS

## Réserves

- 6 mineurs de la relecture Opus non corrigés : A163 (`set -Eeuo pipefail` manquant
  dans le fichier de cas), A164 (`valider-ansible.sh` sans parsing d'arguments),
  A165 (relevé « avant » non contraignant), A166 (messages « debian:12 » figés dans
  `run-in-container.sh`), A167 (profil non documenté dans `tests/README.md`, `scope`
  de la fiche à revoir avec `juger.sh`, lié à A158).
- A168 : la preuve **conteneur** obtenue sur le poste de travail ne garantit pas un
  run Linux natif — le partage de fichiers de Docker Desktop masque les bits
  d'exécution Git faux. Limite à garder pour toute future tâche livrant un script
  invoqué directement (sans `bash`) par un profil de conteneur.

## Git

- `7be628a` feat: premier jet (TASK-085)
- `7137cf9` fix: passage 2 (TASK-085)
- `b85e2de` doc(ansible): faire de la commande conteneurisée la référence de validation (conducteur)
- fusion `--no-ff` sur `master` (`335b50f`), suppression de `agent/TASK-085`
- `5a9b351` chore: clôture TASK-085 — `9156bea` fix(tests): bit exécutable (A168)
- Branche `agent/TASK-085` et copie `../script-agents/TASK-085` supprimées

## Résumé

Livré et vérifié en conteneur puis sur la CI réelle (après un correctif de mode
exécutable, A168). Six mineurs versés au registre, aucun bloquant.
