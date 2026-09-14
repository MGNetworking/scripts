# Mesure — `deepseek-flash` sur TASK-031

**Date** : 2026-09-14 — **Question** : un modèle bien moins cher peut-il écrire un
script de ce dépôt au niveau de la référence ?

## Protocole

- **Conditions identiques** : worktree au commit `c179617`, où la fiche TASK-031
  existe et `check-docker.sh` n'existe pas encore.
- **Entrées envoyées** : la fiche, `CLAUDE.md`, `lib/common.sh`. Rien d'autre,
  aucun `config/*.env`. Consigne : ~150 lignes, `shellcheck` sans avertissement.
- **Évaluation** : [`TASK-031-grille.sh`](TASK-031-grille.sh), 17 contrôles de
  comportement — codes de retour, valeurs extraites, absence de messages bruts,
  borne de temps. Aucun libellé imposé.
- **Grille étalonnée** : la référence (commit `22ff26f`) obtient 17/17 ; la même
  référence avec le défaut de Buildx réintroduit tombe à 16/17.
- **Cascade** : un échec est renvoyé avec la ligne `FAIL` exacte, sans diagnostic.
  Deux tentatives au plus.
- Lecture seule contrôlée à part, par recherche de commandes modifiantes dans le
  source.

## Résultats

| Génération | Score | Lignes | Entrée | Sortie | Durée | Coût, pointe |
|---|---|---|---|---|---|---|
| Référence (Claude) | 17/17 | 150 | — | — | — | non mesuré |
| A — 1re tentative | **17/17** | 167 | 8 119 | 50 521 | 182 s | 0,063 $ |
| B — 1re tentative | 16/17 | 180 | 8 119 | 23 813 | 93 s | 0,029 $ |
| B — correction | **17/17** | 213 | 9 943 | 9 183 | 37 s | 0,012 $ |

Tarifs `deepseek-flash` relevés le jour même, par million de jetons : entrée
0,30 $ (0,006 $ en cache), sortie 1,20 $ — moitié prix en heures creuses.

**Coût par tâche réussie : 0,04 à 0,06 $ en pointe.** Les trois appels réunis :
0,10 $. Données brutes : [`2026-09-14-deepseek-flash.tsv`](2026-09-14-deepseek-flash.tsv).

L'échec de B portait sur la borne de temps : face à un démon figé, 30 s pour
rendre la main — plusieurs appels bornés à 5 s enchaînés. Corrigé en une passe
sur la seule ligne `FAIL`. Les trois versions sont en lecture seule, et toutes
affichent la version de Buildx — le défaut qu'avait la référence avant son test.

## Ce que la mesure établit

Sur ce type de tâche — un diagnostic en lecture seule, porté par une fiche
détaillée —, `deepseek-flash` atteint le niveau de la référence, en une ou deux
tentatives, pour quelques centimes. La cascade à deux tentatives suffit.

## Ce qu'elle n'établit pas

- **Deux générations, une tâche.** La catégorie la plus simple du dépôt, celle
  que l'ADR-0004 décision 29 confie déjà à Haiku. Rien n'est prouvé pour un
  script qui modifie le système, comme `install-docker.sh`.
- **Le fichier de cas n'était pas demandé.** On ne sait pas si DeepSeek aurait
  trouvé seul le défaut de Buildx par ses propres tests.
- **La grille ne juge ni le `--help`, ni les messages, ni le README.**
- **La consommation est instable** : 50 521 puis 23 813 jetons de sortie pour la
  même demande — du raisonnement interne facturé. Le coût varie du simple au double.
- **La correction grossit le script** : 180 → 213 lignes, loin de la cible de 150.
- **Le coût côté Claude n'a pas été mesuré**, ni pour la référence, ni pour
  l'orchestration de cette mesure.

## Rejouer

```bash
node docs/agent/mesures/deleguer.mjs <worktree> --liste
node docs/agent/mesures/deleguer.mjs <worktree> deepseek-flash <worktree>/Docker/Diagnostics/check-docker.sh
```

La clé est lue dans `DEEPSEEK_API_KEY`, jamais affichée ni écrite. La grille
s'exécute dans le conteneur, depuis le worktree :
`tests/env/run-in-container.sh -- bash TASK-031-grille.sh` après l'avoir copiée
à sa racine.
