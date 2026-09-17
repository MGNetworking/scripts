# TASK-082 — Rapport d'exécution

## Compte rendu

`tests/acceptance/TASK-012-semantique-codes.sh` vérifie que les codes de retour du
harnais de tests disent la vérité. Sur l'hôte Windows, il rendait 1 (échec) : trois cas
attendaient 0 de `tests/run.sh` avec le niveau `lint`, et obtenaient 3.

**Cause, établie par exécution.** Le fichier a été lancé deux fois, sans modification.
Sur l'hôte : 56 réussites, 3 échecs, code 1. La sortie des trois cas dit « shellcheck
absent : analyse approfondie NON EXÉCUTÉE » puis « Niveau lint : RIEN N'A PU ÊTRE
VÉRIFIÉ ». En conteneur, où `shellcheck` existe : 57 réussites, 0 échec. Les trois
échecs venaient donc tous d'une seule chose : `shellcheck` n'est pas installé sur
l'hôte. Depuis A03, `tests/lint.sh` rend alors 3, et le niveau `lint` ne peut pas être
« satisfait ». Le dispatcher, lui, n'était pas en faute.

- « sans argument : lint satisfait + acceptance partielle → 0 » : le cas suppose que
  lint est satisfait, ce qui est faux sans `shellcheck`. Le 3 obtenu est juste.
- « deux niveaux demandés explicitement, tous deux satisfaits → 0 » : même
  supposition, même cause.
- « tests/run.sh lint sur l'hôte → 0 » : sans `shellcheck`, le 0 est impossible par
  contrat (A03).

**Ce qui a été fait.** Aucune attente n'est affaiblie. Les trois `assert_code 0`
restent tels quels et continuent de tourner là où `shellcheck` est présent. Sur une
machine qui ne l'a pas, ils sont comptés NON EXÉCUTÉS, pour « environnement
indisponible ». La raison affichée renvoie au conteneur, où la preuve se fait :
`bash tests/env/run-in-container.sh -- bash tests/acceptance/TASK-012-semantique-codes.sh`.
Sur l'hôte, le fichier rend maintenant 3 (0 échec, rien de fiable prouvé pour ces cas)
au lieu de 1. **Ce fichier se lance en conteneur pour que ses trois cas `lint` soient
prouvés.** Il n'est vert nulle part d'un seul tenant : dans le conteneur, les §8 et §9
sautent, faute de Docker.

**Relecture.** Opus a rendu « fusionnable ». Il relève deux défauts mineurs, qui ne
changent pas le verdict. D'abord, la commande est lancée même quand l'assertion est
sautée. Ensuite, la garde regarde si `command -v shellcheck` le trouve, et non le code
rendu par `lint.sh`. Il signale aussi que trois cas déjà existants, qui attendent 3,
passent sur l'hôte pour une mauvaise raison. Rien de cela n'a été corrigé : c'est
consigné en A150.

**Coût.** Tâche menée par l'orchestrateur ; une relecture Opus, 17 194 jetons.

### Réserves

- Trois cas du §4 qui attendent 3 sont creux sur l'hôte sans `shellcheck` ; deux mineurs de la garde (A150).

## Statut

`completed`.

## Fichiers

- `tests/acceptance/TASK-012-semantique-codes.sh` (673 → 694 lignes ; fichier déjà au-delà de 150 lignes avant la tâche)

## Validations

| Commande | Code |
|---|---|
| `bash tests/acceptance/TASK-012-semantique-codes.sh` (hôte, avant) | 1 — 56 réussites, 3 échecs, 2 NON EXÉCUTÉS |
| `bash tests/env/run-in-container.sh -- bash tests/acceptance/TASK-012-semantique-codes.sh` (avant) | 3 — 57 réussites, 0 échec, 4 NON EXÉCUTÉS (dont 2 faute de Docker dans le conteneur) |
| `bash -n tests/acceptance/TASK-012-semantique-codes.sh` | 0 |
| `bash tests/acceptance/TASK-012-semantique-codes.sh` (hôte, après) | 3 — 56 réussites, 0 échec, 5 NON EXÉCUTÉS (les 3 cas `lint`) |
| `bash tests/env/run-in-container.sh -- bash tests/acceptance/TASK-012-semantique-codes.sh` (après) | 3 — 57 réussites, 0 échec ; les trois cas « code 0 » |
| `shellcheck -x -f gcc` du fichier, en conteneur | 0 |
| `bash orchestration/outils/juger.sh tasks/active/TASK-082.md` | 1 : « aucun fichier de cas dans le périmètre » ; le juge ne vise que `tests/integration/*.test.sh` |
| `git diff --name-only master...agent/TASK-082` | le fichier du scope, seul |
| lignes `assert_`/`ok`/`ko`/`saute` (master → branche) | 86 → 89 |

## Git

- `56c2d11` chore: TASK-082 en cours
- `b2d2260` fix(tests): TASK-012 ne rend plus 1 sur l'hôte sans shellcheck
- fusion `--no-ff` de `agent/TASK-082`, copie et branche supprimées
