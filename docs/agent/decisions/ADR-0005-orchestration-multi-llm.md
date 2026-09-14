# ADR-0005 — Orchestration des tâches entre plusieurs LLM

**Date** : 2026-09-14
**Statut** : proposé — en attente des choix de Maxime
**Décideur** : Maxime Ghalem
**S'appuie sur** : [ADR-0004](ADR-0004-sobriete.md) décision 29, et les mesures du
[journal de comparaison](../mesures/journal.md)

---

## Contexte

Le postulat : confier chaque tâche du backlog au modèle le moins cher capable de la
réussir, sous le contrôle d'un arbitre. Quatre tâches ont servi à le mettre à
l'épreuve le 2026-09-14.

| Mesure | Résultat |
|---|---|
| `deepseek-flash`, diagnostic en lecture seule (TASK-031 rejouée) | niveau de la référence, 0,04 à 0,06 $ |
| `deepseek-flash`, script qui modifie le système (TASK-030) | 2 défauts majeurs réels ; la correction introduit 3 échecs ; 0,22 $ |
| Sonnet en sous-agent, même nature (TASK-032) | 1 défaut majeur (lint) ; correction propre ; 270 602 jetons |
| Claude, session principale (TASK-029) | 2 défauts majeurs, même verdict que DeepSeek |
| Relecture Opus, quel que soit l'auteur | 30 000 à 36 000 jetons ; a trouvé tous les défauts |
| Validations du dépôt (`tests/run.sh`, `shellcheck` en conteneur) | le seul juge qui ne coûte aucun jeton |

Trois faits commandent la suite : **aucun modèle ne livre du fusionnable en
l'état** ; **la relecture est nécessaire quel que soit l'auteur** ; **DeepSeek
produit à bas coût mais corrige mal, Sonnet corrige bien**.

## Décision 30 — Trois rôles

```text
ARBITRE — Opus, session Claude Code
   atomise, classe chaque fiche, choisit l'exécutant, lance,
   écrit les fichiers partagés (README, backlog), fusionne
        │
        ▼
EXÉCUTANT — le modèle désigné par la fiche
   écrit le script, son fichier de cas, le *.env.example
   ne touche à rien d'autre (liste blanche de chemins)
        │
        ▼
JUGE AUTOMATIQUE — les validations de la fiche, en conteneur
   0 jeton ; tranche avant toute relecture humaine ou LLM
        │
        ▼
RELECTEUR — Opus en sous-agent, grille fixe, une lecture
   seulement aux niveaux qui l'exigent (décision 31)
```

L'arbitre ne code pas par défaut. Il spécifie, route, vérifie et fusionne.

## Décision 31 — Quatre niveaux, un exécutant chacun

Le niveau est **écrit dans la fiche au moment de l'atomisation**, jamais jugé à
l'exécution : c'est Opus qui atomise, il a déjà tout le contexte.

| Niveau | Tâches | Exécutant | Relecture Opus | Correction |
|---|---|---|---|---|
| **N1** | lecture seule : `check-*`, `list-*`, `audit-*`, `*-status` | `deepseek-flash`, effort `low` | **aucune** — le juge automatique suffit | DeepSeek, sur les lignes `FAIL` |
| **N2** | modifie le système, un seul effet réversible : créer, écrire un fichier idempotent | `deepseek-flash`, effort `low` | oui | **Sonnet** |
| **N3** | plusieurs effets enchaînés, restauration, redémarrage, ou destructif | **Sonnet** | oui | Sonnet |
| **N4** | atomiser, arbitrer une frontière, écrire un ADR, diagnostiquer un échec répété | **Opus** | — | — |

**Le point clé du N2** : DeepSeek écrit le premier jet, parce qu'il le fait bien et
pour quelques centimes ; **Sonnet corrige**, parce que DeepSeek régresse en
corrigeant (TASK-030) et que Sonnet non (TASK-032).

Classement des tâches Docker restantes :

| Tâche | Niveau |
|---|---|
| TASK-033 `list-containers.sh`, TASK-034 `docker-disk-usage.sh` | N1 |
| TASK-035 `update-images.sh` | N2 |
| TASK-036 `update-docker.sh`, TASK-037 `docker-cleanup.sh` | N3 |

## Décision 32 — Le juge passe avant le relecteur

Ne jamais payer Opus pour trouver une erreur que `shellcheck` trouve gratuitement.

```text
exécutant ─► validations ─┬─ lint en échec ─► renvoi des lignes exactes à l'exécutant (1 fois)
                          ├─ tests en échec ─► renvoi des lignes FAIL à l'exécutant (1 fois)
                          └─ tout passe ─────► relecture Opus (N2, N3)
```

Plafond ferme : **une génération, une correction automatique, une correction sur
relecture.** Au-delà, l'arbitre reprend la main ou bloque la tâche.

## Décision 33 — Appeler les exécutants par l'API, pas en sous-agent

Mesure de TASK-032 : un sous-agent Sonnet a consommé 270 602 jetons en 31 appels
d'outils, parce qu'il relit tout son contexte à chaque action. DeepSeek, appelé
une fois avec les fichiers joints, n'a pas ce coût.

`docs/agent/mesures/deleguer.mjs` devient le **lanceur unique**, pour tous les
fournisseurs : les fichiers nécessaires sont joints à un appel, la réponse est
écrite derrière la liste blanche, les jetons d'entrée et de sortie sont consignés
**séparément** dans `appels.tsv`. Le coût de chaque tâche devient exact, Claude
compris.

Conséquence : appeler Sonnet par l'API demande une clé `ANTHROPIC_API_KEY` et se
facture sur le compte API, distinct de l'abonnement Claude Code.

## Décision 34 — Ce que porte une fiche

Trois champs s'ajoutent au frontmatter de `tasks/README.md` §2 :

```yaml
niveau: N2
executor: deepseek-flash
effort: low
```

Et le périmètre d'une tâche ne contient plus les fichiers partagés : les README et
le backlog sont écrits par l'arbitre à la fusion. Plus aucun chevauchement entre
deux tâches, ce qui ouvre la voie au parallélisme.

## Décision 35 — Le parallélisme, plus tard et sous condition

Deux exécutants simultanés, chacun dans son `git worktree`, **seulement** quand
les décisions 33 et 34 sont en place et qu'au moins trois tâches ont suivi ce
circuit sans incident. Les conteneurs de test portent déjà un nom unique.

## Garde-fous permanents

- Aucune clé d'API dans le dépôt ; lecture dans l'environnement, jamais affichée.
- Seuls des fichiers versionnés sont envoyés à un fournisseur externe — jamais un
  `config/*.env`.
- Un exécutant n'écrit que dans la liste blanche ; tout autre chemin est refusé et
  signalé.
- Un script destructif ne s'exécute qu'en conteneur jetable, quel que soit son
  auteur.
- Chaque tâche ajoute sa ligne au journal de comparaison : niveau, exécutant,
  coût, défauts, rattrapage. Le routage se révise sur ces chiffres, pas sur une
  impression.

## Mise en place

| Étape | Contenu | Coût estimé |
|---|---|---|
| 1 | Champs `niveau`, `executor`, `effort` ; retrait des fichiers partagés du périmètre des fiches restantes ; `/tache` lit le niveau et suit les décisions 31 et 32 | une session courte, sans appel externe |
| 2 | `deleguer.mjs` multi-fournisseur (DeepSeek, Anthropic) ; boucle automatique « lint → renvoi » | une session, un appel de contrôle |
| 3 | Premier passage réel : TASK-033 (N1) puis TASK-035 (N2) dans le circuit complet | le coût des deux tâches |
| 4 | Révision du routage sur les chiffres du journal | lecture du journal |
| 5 | Parallélisme par worktrees, si la décision 35 est remplie | — |

## Ce qui reste incertain

- **Sonnet appelé par l'API** n'a pas encore été mesuré : l'économie annoncée par
  la décision 33 est déduite, pas prouvée. L'étape 3 la mesure.
- **Sonnet corrigeant un premier jet de DeepSeek** (N2) n'a jamais été éprouvé.
- **Deux tâches par niveau au plus** ont été mesurées. Le classement N1 à N4 est
  une hypothèse de travail, à réviser à l'étape 4.
