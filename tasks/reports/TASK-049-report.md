# TASK-049 — Rapport d'exécution

## Compte rendu
TASK-049 est terminée. Jusqu'ici, la décision 46 imposait de vider le contexte après chaque tâche : la session s'arrêtait, et `user` devait écrire « reprends » pour lancer la suivante. `user` a demandé une boucle qui enchaîne seule, sans perdre l'essentiel entre deux tâches, et a validé le principe le 2026-09-16.

La solution : la session orchestratrice dure, et chaque tâche est conduite par un sous-agent `conducteur-tache` neuf. Il porte tout le contexte lourd (fiche, règles, diffs, sorties de tests) et ne rend que des réponses de 30 lignes au plus ; son contexte disparaît avec lui. La session ne garde qu'un geste : lancer l'agent DeepSeek en arrière-plan, qui peut tourner une heure, puis reprendre le même conducteur par SendMessage. La décision 46 porte un avenant daté.

Avant d'écrire, deux mécanismes ont été éprouvés plutôt que supposés. Un sous-agent repris par SendMessage retrouve son contexte. Et un sous-agent **peut** lancer un autre sous-agent : la fiche affirmait le contraire, et la première version laissait la relecture à la session pour cette raison.

La relecture Opus de la première version a trouvé un défaut bloquant : la mesure du conducteur, écrite par la session après la clôture, laissait `master` modifié, et la tâche suivante aurait refusé de partir. Elle a aussi relevé trois majeurs (commandes au premier plan plafonnées à 10 minutes, phase manquante pour « terminer ou bloquer », ma mémoire qui imposait encore le vidage) et six mineurs. Tout a été corrigé en une révision : le conducteur fait aussi relire, la mesure du conducteur a son propre commit, délais et conditions d'arrêt sont explicites, la mémoire est à jour.

La preuve demandée par la fiche est faite : TASK-047 (`disable-root-login.sh`) puis TASK-044 (`configure-fail2ban.sh`) ont été conduites par deux conducteurs, jusqu'à la clôture, sans vidage. Le passage de l'une à l'autre s'est fait sans message de `user`. La session n'a reçu que les réponses des conducteurs et les verdicts des relecteurs.

Réserves : pendant ces deux tâches, les conducteurs suivaient encore la première version de leur définition — Claude Code la garde en cache dans la session —, si bien que c'est la session qui a lancé les relecteurs (A59). La boucle suppose un mode de permissions qui laisse passer les commits et les tests (A60). Trois petits écarts des conducteurs sont notés (A61).

## Statut
COMPLETED

## Travail réalisé
- `.claude/agents/conducteur-tache.md` — nouveau sous-agent, 40 lignes
- `.claude/commands/tache.md` — section 0 (répartition session / conducteur), étapes 4, 5, 6 et 9 adaptées ; « préparer la suivante » exclut TASK-039
- `orchestration/decisions.md` — avenant du 2026-09-16 à la décision 46
- `orchestration/regles.md` §17, `orchestration/README.md`, `orchestration/mode.json`
- hors dépôt : mémoire `autonomie-totale-registre.md` et son index
- clôture : backlog, journal, registre (A59-A61, et « prochain identifiant libre » rattrapé à A62)

## Déroulé
| Étape | Qui | Résultat |
|---|---|---|
| fiche | orchestrateur | écrite pendant TASK-046, principe validé par `user` |
| première version | orchestrateur | 811eb3e |
| essais | orchestrateur | reprise par SendMessage : contexte conservé ; sous-agent lançant un sous-agent : réponse « OK » |
| relecture | Opus, 15 appels, 33 559 jetons, 83 s | FUSIONNABLE APRÈS CORRECTIONS — 1 bloquant, 3 majeurs, 6 mineurs |
| révision | orchestrateur | 00d6410, fusion 22dfa33, passage en `validating` 55f8b71 |
| preuve 1 | conducteur, 31 appels, 64 075 jetons, 865 s | TASK-047 close (6bdd5d9) |
| preuve 2 | conducteur, 50 appels, 67 741 jetons, 1 444 s | TASK-044 close (c2ef425), après une relance de l'agent |

## Validations
| Commande | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` | 0 |
| enchaîner deux tâches `ready` réelles, deux clôtures sans message de `user` entre elles | fait — TASK-047 close à 6bdd5d9, conducteur de TASK-044 lancé aussitôt par la session, TASK-044 close à c2ef425 ; lignes `conducteur` dans `agents.tsv` |

`user` a écrit « ok, continue la boucle » pendant que l'agent de TASK-047 tournait ; ce message n'a déclenché aucune étape, et la transition de TASK-047 à TASK-044 s'est faite sans lui.

## Réserves
- A59 — définition du conducteur en cache : la révision n'a pas servi pendant la preuve ; à constater dans une session neuve.
- A60 — permissions : la boucle s'arrête sans signal dans un mode plus strict.
- A61 — écarts des conducteurs sur leurs deux premières tâches.

## Git
811eb3e, 00d6410 sur `agent/TASK-049`, fusionnée en 22dfa33 puis supprimée ; 55f8b71 (validation réelle) ; clôture ci-dessous.
