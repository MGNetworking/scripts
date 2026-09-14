# TASK-028 — Rapport d'exécution

## Statut
COMPLETED — critère d'acceptance ajusté par l'orchestrateur

## Travail réalisé
`tests/integration/linux-system.test.sh` : une ligne de commentaire au-dessus de la
directive `# shellcheck disable=SC2016` (ligne 2016) — `$1` est un champ awk,
entre guillemets simples pour atteindre awk tel quel. Écrit par l'orchestrateur.

## Validations
| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh acceptance` | **1** |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 |

## L'acceptance reste rouge, pour d'autres causes
La directive de `linux-system.test.sh` n'est plus signalée. TASK-011 échoue sur
deux écarts apparus après la rédaction de cette fiche :

- 4 directives sans justification au-dessus : `configure-docker.sh` l.91 et 141,
  `install-docker.sh` l.145 (commentaire placé sous la directive),
  `configure-docker.test.sh` l.107 (aucun) ;
- `ASSUME_YES` lue par `install-docker.sh` et `configure-docker.sh`, hors de
  `lib/common.sh`.

Correction hors périmètre, touchant peut-être la zone protégée : confiée à
**TASK-038**. Le critère de cette fiche a été récrit en conséquence (tasks/README.md
§5 : corriger une validation relève de celui qui écrit le backlog).

## Constat sur le circuit
`juger.sh` ne lance que shellcheck et le fichier de cas de la tâche : les règles
transverses de l'acceptance (TASK-011) échappent aux agents comme au relecteur.
Consigné dans les points ouverts d'`orchestration/README.md`.

## Git
Branche agent/TASK-028, commit 4eff3d0, fusionnée puis supprimée.
