# TASK-072 — Rapport d'exécution

## Compte rendu

TASK-072 est terminée et fusionnée. Elle est née d'un incident de TASK-071. Le premier jet du fichier de cas de `configure-registry.sh` créait des liens symboliques vers les vrais outils du conteneur, dont `timeout`, dans `$BAC/bin`. Il écrivait ensuite son faux `timeout` au même endroit par `cat >`. L'écriture a suivi le lien et remplacé `/usr/bin/timeout` du conteneur. Ce faux se rappelait lui-même sans fin, et deux conteneurs sont restés bloqués plus de 30 minutes. Pour ce lancement, `agents.tsv` a de plus relevé 1 tour et 243 jetons, pour 2 269 s de travail.

**D'abord, la cause du mauvais relevé.** Claude Code garde le transcript de chaque session d'agent. Celui du premier lancement de TASK-071 montre 81 appels au modèle. L'agent a rendu son verdict à 08:30. Quatre minutes plus tard, un Monitor qu'il avait armé a expiré, et sa notification a relancé une boucle d'un seul appel : 243 jetons d'entrée, 442 de sortie. Ce sont exactement les chiffres du relevé. `claude -p` ne rend dans sa sortie JSON que la dernière boucle. La durée maximale n'était pas en cause (2 269 s sur 3 600), et la sortie ne contenait qu'un seul objet JSON.

**Ce qui a changé.**
- `lancer-agent.sh` lit maintenant les jetons dans le transcript de la session, sans se fier à la sortie JSON. Sur la relance de TASK-071, dont la sortie était juste, la somme retrouve exactement la ligne de `agents.tsv` : 163 399, 9 729 280 et 75 789 jetons, 0,198 $. Sur le premier lancement, elle donne 81 appels et 0,217 $. Si le transcript est introuvable, par exemple pour un agent tué par la durée maximale, la ligne porte `incomplet` et des `?`, jamais des chiffres faux.
- `juger.sh` refuse, avant de lancer le conteneur, un fichier de cas qui crée un lien puis écrit vers le même chemin. La détection est dans `orchestration/outils/lien-ecrit.awk`.
- `tests/README.md` fixe la règle : un faux binaire est un fichier ordinaire du bac, jamais écrit à travers un lien, et il n'appelle jamais le vrai par son nom.

**Relecture.** Opus a jugé le travail fusionnable, avec un défaut majeur. Ma première version marquait « incomplet » un seul tour pour plus de 600 s. Ce seuil reposait sur un seul cas et ne voyait pas une boucle relancée de deux tours. Je l'ai remplacé par la somme du transcript. J'ai aussi corrigé deux mineurs : une écriture après un `rm` du lien était signalée à tort, et le code manquait de lisibilité. Enfin, la preuve est conservée dans `tests/acceptance/TASK-072-faux-binaires.sh`, et `/tache` dit à l'étape 8.5 quoi faire d'une ligne `incomplet`.

**Coût.** Travail de l'orchestrateur, sans agent externe. Relecture : 29 540 jetons.

**Réserves.**
- La détection des faux binaires est textuelle : affectations, `ln -t` et quelques formes restent invisibles (A123).
- Le nouveau relevé n'a pas encore servi dans un vrai lancement d'agent, et `tours` compte désormais les appels au modèle (A124).

## Statut

`completed`. Critères 1, 2 et 3 tenus (relecture Opus, puis revalidation après corrections).

## Travail réalisé

- `tests/README.md` : sous-section « Écrire un faux binaire sans toucher au vrai ».
- `orchestration/outils/juger.sh` : appelle `lien-ecrit.awk` sur le fichier de cas et sort en 1 avant le conteneur s'il signale.
- `orchestration/outils/lien-ecrit.awk` (83 lignes) : liens `ln -s` (options séparées, redirections écartées, `-t` ignoré), `rm` du chemin, variables de boucle `for`, fonction d'une ligne écrivant `…/$1`.
- `orchestration/outils/lancer-agent.sh` (125 lignes) : somme de l'usage des appels distincts (`message.id`) du transcript `<CLAUDE_CONFIG_DIR ou ~/.claude>/projects/*/<session_id>.jsonl`.
- `tests/acceptance/TASK-072-faux-binaires.sh` : 4 signalés, 4 non signalés.
- `.claude/commands/tache.md` 8.5 ; `orchestration/README.md` : tableau des outils.

## Déroulé

| Étape | Qui | Résultat |
|---|---|---|
| activation | conducteur | 9c1a30d |
| écriture | conducteur | de2da19, 1e1d489 (lint : SC1112 et SC2016 corrigés) |
| relecture | Opus, 8 appels, 29 540 jetons, 98 s | FUSIONNABLE ; 1 majeur, 2 mineurs, 2 demandes |
| corrections | conducteur | 85daf2a `fix: retours de relecture (TASK-072)`, scope de la fiche étendu à 3 fichiers |

## Validations (après corrections)

- `tests/env/run-in-container.sh -- tests/run.sh lint` : 0 (119 fichiers, 0 erreur, 2 avertis : scripts hérités Synology).
- `bash orchestration/outils/juger.sh tasks/completed/TASK-071.md` : 0, PASSE, aucun signalement (contre-épreuve sur le fichier de cas final).
- `juger.sh` sur TASK-070 et TASK-064 : 0, aucun signalement ; avant corrections, 065, 061 et 053 : 0.
- Démonstration : `git show 6ad93f8:tests/integration/configure-registry.test.sh`, copie jetable avec une fiche jetable, retirées ensuite : `juger.sh` 1, « …:297, $BAC/bin/timeout (lien ligne 42) », conteneur non lancé.
- `bash tests/acceptance/TASK-072-faux-binaires.sh` en conteneur (mawk 1.3.4) : 0, 8 réussies. Mutants : détection vide → 1 (4 échecs) ; `rm` ignoré → 1 (1 échec).
- Détection passée sur tous les `tests/integration`, `tests/unit` et `tests/acceptance` (gawk hôte, mawk conteneur) : aucun signalement, hormis les fixtures volontaires de `TASK-072-faux-binaires.sh`, que `juger.sh` ne lit pas.
- Relevé, bloc node extrait : transcripts réels de TASK-071 → 81 / 140 965 / 6 868 480 / 111 201 (0,217 $) et 90 / 163 399 / 9 729 280 / 75 789 (0,198 $, identique à `agents.tsv`) ; session inconnue, sortie vide, `CLAUDE_CONFIG_DIR` sans transcript → `incomplet`.
- NON EXÉCUTÉ : un lancement réel de `lancer-agent.sh` (A124). Portée de `duration_ms` non vérifiée : sorties JSON non conservées.

## Réserves

- détection textuelle : affectations, `ln -t`, `ln --symbolic`, `#` dans une chaîne (A123) ;
- relevé par transcript non exercé en lancement réel ; `tours` = appels distincts ; sous-agents non comptés (A124).

## Git

Branche `agent/TASK-072` : de2da19, 1e1d489, 85daf2a ; fusion `--no-ff` ee31e19 ; copie et branche supprimées. Pas de push.
