# TASK-036 — Rapport d'exécution

## Statut
COMPLETED

## Travail réalisé
- `Docker/Maintenance/update-docker.sh` — 150 lignes : met à jour les seuls composants Docker installés, relevé avant/après, coupure annoncée
- `tests/integration/update-docker.test.sh` — 148 lignes, 76 assertions, faux `docker`, `dpkg-query`, `apt-get`, `systemctl`
- par l'orchestrateur : `Docker/README.md`, README racine, backlog, journal

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| lancement 1 | agent `deepseek` (prévu `sonnet`, A41) | 51 tours, 384 s, 0,148 $ ; VERDICT ECHEC, 11 FAIL, test déclaré fautif |
| diagnostic | orchestrateur | confirmé : directive SC2016 sans portée, `uname` absent des PATH restreints, liste blanche d'un seul paquet par ligne. Corrigé (9893d87), aucune assertion retirée ; juge PASSE |
| vérification | orchestrateur | lint 0, intégration 0, `--help` 0, `--dry-run` debian 0, `--dry-run` systemd 0 |
| relecture | Opus, 36 518 jetons | APRÈS CORRECTIONS — 1 majeur, 6 mineurs |
| lancement 2, retours | agent `deepseek` | 92 tours, 621 s, 0,261 $ ; juge PASSE ; assertions 60 → 76 |
| vérification | orchestrateur | juge 0, les cinq validations à 0 |

## Défauts corrigés
- MAJEUR : `--dry-run` annonçait tous les composants installés comme à mettre à jour, sans rafraîchir l'index.
- Coupure annoncée même avec live-restore ou sans conteneur ; démon injoignable présenté comme « live-restore inactif » ; versions hors décision 14 acceptées ; refus implicite sans terminal rendant 0 ; réserve containerd affirmée au lieu de « non mesurée » ; `--no-install-recommends`.

## Réserves
- A42 (traité) : le figement du test dès le premier jet a bloqué l'agent sur ses propres erreurs de construction ; consignes assouplies.

## Git
Commits 5b60c7f, a6b5da8, 9893d87, 4acf60a — branche agent/TASK-036 fusionnée puis supprimée.
