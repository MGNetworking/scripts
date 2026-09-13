# ADR-0004 — Sobriété des scripts et du processus

**Date** : 2026-09-13
**Statut** : accepté
**Décideur** : Maxime Ghalem
**Amende** : [ADR-0003](ADR-0003-cadrage-execution-autonome.md) décisions 5 et 6

---

## Contexte

Constaté le 2026-09-13, en produisant `Docker/Diagnostics/check-docker.sh`.

Le dépôt produisait des scripts de 700 à 800 lignes pour des diagnostics en
lecture seule, et l'agent mobilisait six sous-agents pour livrer un script.
Mesures relevées ce jour-là :

| Fichier | Lignes | dont code |
|---|---|---|
| `Linux/System/check-memory.sh` | 815 | 503 |
| `Linux/System/check-services.sh` | 635 | — |
| `tests/integration/check-memory.test.sh` | 1 062 | — |
| `check-docker.sh`, première version | 706 | 427 |
| `check-docker.sh`, après cet ADR | **150** | — |

La première version de `check-docker.sh` n'était pas une dérive : elle copiait
fidèlement la norme du dépôt, et était même plus courte que `check-memory.sh`.
**C'est la norme qui était en cause**, et la corriger sur un seul script
n'aurait servi à rien — les huit tâches Docker suivantes seraient reparties à
700 lignes.

La version courte fait la même chose, avec les mêmes rubriques, les mêmes trois
codes de retour et les mêmes bornes de temps. Elle est couverte par 26
vérifications réussies, et le raccourcissement a lui-même révélé un défaut que
la version longue portait : `${REP%% *}` affichait `github.com/docker/buildx` au
lieu de la version de Buildx.

## Décision 25 — Un script d'administration vise 150 lignes

Un script fait une chose : préflight court, corps, sortie. Les commentaires
n'expliquent que ce que le code ne dit pas seul — une contrainte système, un
piège mesuré, une raison de faire autrement que l'évidence.

Ce qui relève de la pédagogie va au `README.md` du domaine. Les rubriques
décorées, les blocs d'explication en tête de fonction et les messages d'erreur
en trois paragraphes n'ont pas leur place dans un `.sh`.

150 lignes est une cible, pas un couperet : un script d'installation qui doit
détecter l'OS, gérer les conflits de paquets et vérifier son travail dépassera
légitimement. Un diagnostic en lecture seule qui les dépasse est en revanche un
signal à instruire.

**Les scripts existants ne sont pas repris.** Une mise au standard est une tâche
en soi, jamais un effet de bord — `AGENTS.md` §6. `Linux/System` reste tel quel.

## Décision 26 — Les fichiers de cas suivent la même règle

Un fichier de cas vise 150 lignes lui aussi. Il affirme des faits ; il ne
raconte pas pourquoi il les affirme. `tests/integration/check-docker.test.sh`
couvre les treize critères d'acceptation de TASK-031 en 110 lignes, là où
`check-memory.test.sh` en compte 1 062 pour un script comparable.

La règle ne s'applique pas à `tests/integration/linux-system.test.sh`, qui porte
six scripts et dont l'ordre des groupes est contraint.

## Décision 27 — L'agent écrit les scripts lui-même

Plus de délégation à `redacteur-script` ni à `redacteur-tests` par défaut.
L'agent code, lance les validations et commite dans le même fil.

Motifs mesurés :

- **le coût**. Six sous-agents pour un script, et chacun démarre à froid : il
  relit `CLAUDE.md`, `AGENTS.md`, le fichier de tâche et les scripts modèles.
  Les deux rédacteurs de l'atomisation Docker ont consommé 280 000 jetons à eux
  seuls ;
- **l'outillage**. `redacteur-script` n'a ni `Bash` ni terminal : il ne peut
  lancer aucune validation. Le 2026-09-13, il a rendu un script de 706 lignes en
  signalant honnêtement n'avoir exécuté ni `bash -n` ni `tests/run.sh lint` —
  l'agent principal a dû tout valider après coup. La délégation n'avait donc
  économisé aucun travail, elle l'avait déplacé ;
- **la fidélité**. Un rédacteur à froid copie ce qu'il trouve. C'est ainsi que la
  verbosité s'est propagée de `check-memory.sh` à `check-docker.sh`.

Les sous-agents restent disponibles sur demande explicite de Maxime, et
`relecteur` garde son rôle sur les scripts destructifs.

## Décision 28 — Un fichier de tâche vise 30 lignes

Objectif, périmètre, hors-périmètre, critères d'acceptation, validations. Les
pièges connus tiennent en quelques lignes.

Les neuf tâches Docker écrites le 2026-09-13 comptent de 190 à 295 lignes
chacune. Elles ne sont **pas réécrites** — le travail est fait et il est juste —
mais elles ne servent pas de modèle. TASK-031 a été menée sans que sa longueur
ajoute quoi que ce soit à ce que 30 lignes auraient dit.

## Conséquences

`AGENTS.md` et `CLAUDE.md` ne sont pas amendés par cet ADR : ils sont
respectivement à demande explicite et en zone interdite (`AGENTS.md` §5). Maxime
décidera s'il veut y reporter ces quatre décisions.

**Correction à signaler** : `CLAUDE.md` a été modifié le 2026-09-13 par l'agent
— arborescence `Docker/` à cinq dossiers, et frontière de lecture seule de
`Docker/Diagnostics/`. C'était une infraction à `AGENTS.md` §5. Les
modifications sont justes et ont été conservées, mais elles auraient dû être
demandées.

## Décision 29 — Un modèle par famille de travail

Ajoutée le 2026-09-14. Tarifs Anthropic relevés ce jour, par million de jetons :
Opus 5 à 5 $ en entrée et 25 $ en sortie, Sonnet 5 à 2 $ / 10 $, Haiku 4.5 à
1 $ / 5 $ — soit 2,5 fois et 5 fois moins cher qu'Opus.

| Travail | Modèle | Où c'est réglé |
|---|---|---|
| Écrire un script depuis une fiche détaillée | Sonnet | `model: sonnet` dans `.claude/agents/redacteur-script.md` |
| Écrire un fichier de cas | Sonnet | `.claude/agents/redacteur-tests.md` |
| Relire un travail terminé | Sonnet | `.claude/agents/relecteur.md` |
| **Script en lecture seule** — `check-*`, `list-*`, `audit-*`, `*-status` | **Haiku** | surcharge du modèle **à l'appel** de l'agent |
| Atomiser un domaine en tâches | Opus | `model: inherit` dans `.claude/agents/redacteur-tache.md` |
| Arbitrer une frontière, écrire un ADR, diagnostiquer un échec non trivial | Opus | l'agent principal |

Le clivage n'est pas la difficulté apparente mais **l'endroit où se prend la
décision**. Quand la fiche de tâche porte déjà les décisions et que le harnais
de tests attrape les erreurs, écrire le script est une exécution de
spécification — Sonnet suffit, Haiku suffit même pour un diagnostic qui n'écrit
rien. Quand la décision reste à prendre — une frontière d'arborescence, un
abandon de section, un diagnostic dont deux tentatives ont échoué —, c'est Opus.

Trois faits de TASK-029 et TASK-031 étayent ce partage :

- `[ -t 0 ]` avant `confirm` n'a pas été trouvé, il a été **lu** dans les
  `implementation_notes` de TASK-029 ;
- le défaut de Buildx — `${REP%% *}` affichant `github.com/docker/buildx` au lieu
  de la version — a été trouvé par **le fichier de cas**, pas par le modèle ;
- les trois SC2015 ont été trouvés par **`shellcheck` dans le conteneur**, et
  restaient invisibles sur l'hôte où il n'est pas installé.

**L'ordre des économies reste celui-ci : d'abord moins d'appels, ensuite des
modèles moins chers.** Les deux agents d'atomisation du 2026-09-13 ont consommé
280 000 jetons ; les passer en Sonnet aurait divisé leur coût par 2,5, ne pas les
lancer l'a divisé bien davantage — décision 27.
