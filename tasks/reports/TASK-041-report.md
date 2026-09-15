# TASK-041 — Rapport d'exécution

## Compte rendu
TASK-041 (`audit-users.sh`) est terminée et fusionnée : premier script du domaine `Linux/Security`, en lecture seule, écrit par l’agent DeepSeek pour 0,23 $.

L’agent a livré un premier jet qui passait tous les tests (48 vérifications). La relecture Opus a relevé trois défauts mineurs : `sync` était signalé à tort comme compte à shell de connexion, les comptes dont `sudo` est le groupe principal passaient inaperçus, et une panne de la source de comptes se lisait comme « groupe absent ». Elle a aussi vu que le cas « `/etc/shadow` illisible » n’était pas réellement testé. Une relance a tout corrigé : 63 vérifications, 143 + 150 lignes. J’ai créé le README du domaine.

## Statut
COMPLETED

## Travail réalisé
- `Linux/Security/audit-users.sh` — 143 lignes, lecture seule
- `tests/integration/audit-users.test.sh` — 150 lignes, 63 vérifications, faux `getent`
- par l'orchestrateur : `Linux/Security/README.md` créé, `Linux/README.md`, README racine, backlog, journal

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| lancement 1 | agent `deepseek` | 31 tours, 255 s, 0,090 $ ; juge PASSE, 48 vérif. |
| vérification | orchestrateur | lint 0, intégration 0, `--help` 0, exécution 0 |
| relecture | Opus, 21 409 jetons | APRÈS CORRECTIONS — 3 mineurs, 2 tests creux |
| lancement 2, retours | agent `deepseek` | 49 tours, 416 s, 0,143 $ ; juge PASSE, 63 vérif. |
| vérification | orchestrateur | les quatre validations à 0 |

## Défauts corrigés
Shells de connexion fondés sur `/etc/shells` (plus de `sync` signalé) ; groupe principal pris en compte ; panne de la source de comptes distinguée d'un groupe absent ; `/etc/shadow` existant mais illisible réellement testé.

## Git
Commits 9cd9d17, 29ec795 — branche agent/TASK-041 fusionnée puis supprimée.
