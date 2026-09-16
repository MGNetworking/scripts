# TASK-053 — Rapport d'exécution

## Compte rendu
TASK-053 (`upgrade-k3s.sh`) est terminée et fusionnée. C'est le quatrième script de `Linux/K3s`. Il met K3s à niveau par l'installateur officiel. Suivant la décision 47, la version cible est explicite et obligatoire : `--version vX.Y.Z+k3sN` ou `SRV_K3S_VERSION`, jamais « dernière stable » par défaut. Le script affiche les versions en place et cible. Si elles sont égales, il s'arrête sans rien télécharger. Il refuse un recul, un changement de majeure, un saut de plus d'une mineure et un cluster malsain. Sinon, il résume, demande confirmation et télécharge l'installateur en HTTPS seul dans un temporaire. Il relit ensuite la version et repasse `verify-k3s.sh`.

À l'activation, la fiche ne portait pas les deux points de la décision 47 : le conducteur les a ajoutés aux critères (version obligatoire et strictement validée, HTTPS seul).

L'agent DeepSeek a livré en deux passages : 150 lignes de script, 213 lignes de cas, 84 vérifications. Le passage 1 a déplacé la sortie en échec du faux installateur avant le changement de version, sans le justifier. La relecture Opus y a vu un affaiblissement et a jugé le travail fusionnable après corrections :
- trois majeurs : version jamais relue après l'installateur ; seules certaines `INSTALL_K3S_*` héritées neutralisées ; échec à mi-chemin plus couvert ;
- un test creux : `ASSUME_YES` hérité non prouvé sous terminal ;
- trois mineurs : `--dry-run` sans root trompeur, comparaison de versions à multiplicateurs fixes, faux `systemctl` infidèle ;
- trois tests manquants : jeton, `--tlsv1.2`, formes de version refusées.

Une relance a tout traité : 171 + 281 lignes, 112 vérifications, 65 → 89 lignes d'assertion. Les deux assertions remplacées l'ont été par des vérifications plus fortes, justifiées dans le commit. Sans seconde relecture, le conducteur a lu les trois majeurs et la preuve de la décision 45 dans le code et les cas : tous tenus, cas sous pseudo-terminal exécuté (0 NON EXÉCUTÉ). À la lecture, il a vu que les messages d'échec conseillent un retour par `install-k3s.sh`, qui ne fait rien quand K3s est présent (A74). Coût agent : 0,219 $ en deux lancements ; relecture : 41 620 jetons.

Le conducteur avait soupçonné `verifier-liens.sh` de manquer un lien vers `pending/` après activation : c'est voulu (tolérance `pending/` → `active/` en cours de tâche), aucune anomalie.

Réserves : A72 à A74, et A66 qui se répète (ci-dessous).

## Statut
COMPLETED

## Travail réalisé
- `Linux/K3s/upgrade-k3s.sh` — 171 lignes
- `tests/integration/upgrade-k3s.test.sh` — 281 lignes, 112 vérifications ; garde `/.dockerenv` avant `mktemp` et `trap` ; faux `curl`, installateur, `k3s`, `systemctl` (3 inactif, 1 unité inconnue) et `id` en tête de PATH
- par l'orchestrateur : fiche (critères de la décision 47), `Linux/K3s/README.md`, `Linux/README.md`, README racine, backlog, journal, registre (A72 à A74, A66 complété)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | commit b929d54 |
| lancement 1 | agent `deepseek` | 2 passages, 40 tours, 336 s, 0,112 $ ; 150 + 213 lignes, 84 vérifications ; commits 8455180, fe26006, c3878e7 |
| vérification | conducteur | juge 0 ; périmètre : 2 fichiers du scope ; 65 → 65 lignes d'assertion ; faux installateur modifié en fe26006 sans justification, signalé au relecteur |
| relecture | Opus, 9 appels, 41 620 jetons, 66 s | FUSIONNABLE APRÈS CORRECTIONS — 3 majeurs, 1 test creux, 3 mineurs, tests manquants |
| lancement 2 | agent `deepseek` | 43 tours, 366 s, 0,107 $ ; 171 + 281 lignes, 112 vérifications ; commit 518e431 |
| vérification | conducteur | juge 0 ; 65 → 89 lignes d'assertion ; majeurs et décision 45 lus dans le code |

## Validations (relancées par le conducteur dans la copie de l'agent, après la relance)
| Commande | Code |
|---|---|
| `bash orchestration/outils/juger.sh tasks/active/TASK-053.md` | 0 — PASSE ; shellcheck 0, cas 0, règles du dépôt 3 (indisponibilités d'environnement de TASK-011) ; longueurs 171 et 281 signalées |
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | 0 — upgrade-k3s : 112 vérifications, 0 échec, 0 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- bash Linux/K3s/upgrade-k3s.sh --help` | 0 |

Périmètre : `git diff --name-only master...agent/TASK-053` ne contient que les deux fichiers du `scope`.

## Git
Activation b929d54 ; branche `agent/TASK-053` (8455180, fe26006, c3878e7, 518e431) fusionnée `--no-ff` (350c7e9), copie retirée, branche supprimée. Pas de push : domaine `Linux/K3s` inachevé (TASK-054).

## Réserves
- A72 — version corrigée non relue par Opus, longueurs 171 + 281, jamais éprouvée sur une vraie machine.
- A73 — téléchargement de l'installateur dupliqué avec `install-k3s.sh`.
- A74 — consigne de retour arrière inopérante dans deux messages d'échec.
- A66 — commit de relance titré `(RETOURS-TASK-053.md)`, titre dicté cette fois par le fichier de retours du conducteur ; attribution `Claude Code`.
