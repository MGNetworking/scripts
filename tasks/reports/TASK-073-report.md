# TASK-073 — Rapport d'exécution

## Compte rendu

Tu avais validé le 17 septembre la proposition de `docs/reprise-cadrage.md`, avec une seule correction : les questions sont posées en une seule série, pas une par une. Il restait à l'écrire dans les règles.

**Ce qui a été écrit.** La décision 49 est consignée dans `orchestration/decisions.md`, dans une nouvelle section F. Elle reprend tes cinq choix, les pistes écartées, le modèle de `CADRAGE.md` et la boucle de réflexion en sept étapes. Elle ajoute la règle de transition : un dossier qui n'a pas encore de cadrage n'empêche ni une correction déjà au backlog, ni la tâche qui écrit ce cadrage. Les consignes y renvoient désormais :
- `regles.md` demande de lire le cadrage avant d'écrire une fiche ;
- à l'étape 2 de `/tache`, le conducteur refuse une fiche hors contrat ;
- `/atomiser` ne s'applique qu'une fois le cadrage validé ;
- le rédacteur refuse d'écrire une fiche hors contrat ;
- le relecteur classe BLOQUANT tout travail qui sort du contrat.

`architecture.md` montre maintenant que tu exprimes un besoin, pas une commande. Son schéma §7 s'appelle « Du besoin au push » et commence par la boucle. L'affiche a été refaite dans le même sens, colonne 1 réécrite, puis le PNG régénéré et vérifié à l'œil. `docs/reprise-cadrage.md` est supprimé, et aucun lien n'y renvoie.

**Relecture.** Opus a rendu « fusionnable après corrections ». Il a relevé un défaut majeur : telle que je l'avais écrite, la transition aurait fait refuser TASK-074 à 077, puisqu'écrire un cadrage n'est pas une correction. C'est corrigé. Il a aussi relevé trois mineurs :
- **le rédacteur ne savait pas quoi faire d'un dossier sans cadrage** : aligné sur la transition ;
- **une question « après /atomiser » était ambiguë** : libellé revu ;
- **le cas des fiches nées d'un défaut n'était pas réglé** : la décision précise que le cadrage ne vise que les scripts des quatre grands dossiers, et que les fiches d'orchestration restent sous la décision 46.

Un cas reste ouvert : une correction de script découverte pendant une tâche peut-elle s'écrire directement, ou attend-elle ta validation ? C'est A129. Pendant la correction, le bloc BESOIN_USER de l'affiche débordait légèrement : c'est corrigé.

**Coût.** Travail de l'orchestrateur, sans agent externe. Relecture : 57 355 jetons.

**Réserves.**
- Articulation entre les décisions 46 et 49 pour une correction de script née d'un défaut : à trancher (A129).

## Statut

`completed`. Critères 1 à 5 tenus (relecture Opus, puis corrections vérifiées par le conducteur, sans seconde relecture).

## Fichiers

`orchestration/decisions.md`, `orchestration/architecture.md`, `orchestration/orchestration.html`, `orchestration/orchestration.png`, `orchestration/regles.md`, `.claude/commands/tache.md`, `.claude/commands/atomiser.md`, `.claude/agents/relecteur.md`, `.claude/agents/redacteur-tache.md`, `docs/refactorisation-plan.md` ; `docs/reprise-cadrage.md` supprimé.

## Validations

- `bash orchestration/outils/verifier-liens.sh` : 0, aucun lien mort (avant et après corrections).
- Périmètre `git diff --name-only master...agent/TASK-073` : les 11 fichiers du `scope`.
- `bash orchestration/outils/juger.sh tasks/active/TASK-073.md` : 1, « aucun fichier de cas dans le périmètre ». Sans objet, la tâche ne touche aucun `.sh`.
- Export Edge headless : 0, image 2700x1860 relue. La commande d'export en tête du HTML utilise désormais `$(pwd -W)` : avec `$PWD` (`/d/...`), Edge rendait 0 sans écrire le fichier.
- `grep -rn reprise-cadrage` : seule la fiche TASK-073 le cite.

## Git

Branche `agent/TASK-073` : 49695ca (décision et consignes), 212b116 `fix: retours de relecture (TASK-073)`, 8af72dd (affiche) ; fusion a5446c9 ; activation 08a4034.
