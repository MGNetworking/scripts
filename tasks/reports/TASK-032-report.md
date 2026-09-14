# TASK-032 — Rapport

**Statut** : `completed` — 2026-09-14
**Script** : `Docker/Configuration/create-network.sh`, 148 lignes
**Cas** : `tests/integration/create-network.test.sh`, 147 lignes — 36 vérifications
**Exécutant** : Sonnet en sous-agent, relu par Opus, corrigé une fois par Sonnet.
Mesure des jetons et comparaison avec DeepSeek dans
[le journal](../../docs/agent/mesures/journal.md).

## Validations

| Commande | Code attendu | Code réel |
|---|---|---|
| `tests/run.sh lint` | 0 | **0** |
| `run-in-container.sh -- tests/run.sh lint` | 0 | **0** |
| `run-in-container.sh -- tests/run.sh integration` | 0 | **0** |
| `run-in-container.sh -- bash …/create-network.sh --help` | 0 | **0** |
| `run-in-container.sh --profil systemd -- bash …/create-network.sh mgnet-test-reseau --dry-run` | 0 | **0** |

## Ce qui a été produit

Crée un réseau Docker nommé, indépendant de tout fichier Compose. Nom en argument,
sinon `SRV_DOCKER_NETWORK`. Réseau absent : créé ; conforme : rien ; divergent :
l'écart est affiché, rien n'est touché, le script rend 1 et renvoie à
`cleanup-networks.sh`. Ne supprime jamais.

## Réserve

La règle de nom (au moins deux caractères) est celle des conteneurs ; rien dans
le conteneur de test ne permet de vérifier qu'elle vaut pour les réseaux.
