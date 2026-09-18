# TASK-086 — Outillage de vérification et de clôture

## Compte rendu

Depuis quelques tâches, le conducteur — l'agent qui prépare, surveille et clôt une
tâche — consomme entre 36 000 et 199 000 jetons, dont environ 70 % pour des gestes
toujours identiques : comparer la liste des fichiers modifiés au périmètre annoncé,
relancer les commandes de validation, déplacer une fiche, mettre le backlog et le
journal à jour. Ce sont des gestes mécaniques : un script les fait mieux, plus vite
et sans se tromper. C'est l'objet de cette première tâche du plan de l'outil de
préparation des serveurs, écrit et validé le 2026-09-18.

Trois livraisons.

**`orchestration/outils/verifier-travail.sh`** (144 lignes) fait l'étape « vérifier »
d'une tâche : il compare le diff de la branche au champ `scope` de la fiche, mesure
la longueur des scripts livrés, lance le juge automatique, puis exécute une à une les
commandes du champ `validation` en affichant leur code réel. Il termine par une ligne
`VERDICT` et rend 0 ou 1. Un choix a demandé réflexion : un agent livre presque
toujours un fichier de cas que la fiche n'a pas nommé dans son périmètre — le premier
jet de TASK-085 en est l'exemple. Le script admet donc un fichier **ajouté** sous
`tests/`, en le comptant à part sous l'étiquette `PREUVE`, mais refuse un test
**modifié** hors périmètre, qui reste un débordement.

**`orchestration/outils/clore-tache.sh`** (126 lignes) fait l'étape « clore » : il
vérifie d'abord que le rapport existe et que chaque anomalie `Axx` citée en réserve
figure bien au registre — le contrôle que `/tache` demandait à l'agent de faire de
tête —, puis déplace la fiche vers `tasks/completed/`, met à jour la ligne du backlog
et sa section « Terminé », ajoute la ligne de journal et les lignes de mesure qu'on
lui fournit, et lance la vérification des liens. Il n'écrit aucun texte et ne commite
rien : la rédaction et le commit restent au conducteur. Si un contrôle échoue, il
n'écrit rien du tout.

**La branche documentaire de `juger.sh`** (anomalie A172) : une fiche dont le
périmètre ne contient ni script ni rôle Ansible — deux fichiers de cadrage, par
exemple — recevait le même échec qu'une fiche mal formée, ce qui avait fait conclure
à tort à un échec sur TASK-083. Elle rend désormais « SANS OBJET » et 0 ; un périmètre
réellement vide reste un défaut.

La preuve la plus parlante est celle de la clôture : sur une copie jetable du dépôt
placée juste avant la clôture réelle de TASK-083, le script rejoue cette clôture et
le résultat est **identique au commit réel, fichier pour fichier**. Le fichier de cas
compte 24 vérifications, toutes au vert.

La relecture Opus a rendu « fusionnable après corrections » avec un défaut majeur, vu
par personne d'autre : les cas qui fabriquent un dépôt d'essai ont besoin de `git`,
absent de l'image du conteneur de test — ils y seraient tombés en échec au lieu de se
déclarer non exécutables. Corrigé : dans le conteneur, le fichier rend maintenant 3,
« environnement indisponible », ce qui est la vérité. Trois autres corrections ont
suivi (points d'insertion contrôlés avant d'écrire, message de contrôle exact, cas
supplémentaire pour un garde non couvert). Cinq remarques mineures restent ouvertes,
versées au registre en A173 à A176.

Coût : aucun agent externe, la tâche relevant de `orchestration/`, interdit en
écriture aux agents lancés. Relecture Opus : 74 686 jetons.

## Statut

COMPLETED

## Objectif

Confier à deux scripts déterministes les gestes mécaniques de la vérification et de
la clôture d'une tâche, et donner à `juger.sh` un verdict « sans objet » pour un
périmètre purement documentaire (A172).

## Travail réalisé

- `orchestration/outils/verifier-travail.sh` (nouveau, 144 lignes) : périmètre contre
  le `scope`, longueur des `.sh`, `juger.sh`, commandes de `validation`, ligne
  `VERDICT` ; options `--ref`, `--base`, `--copie`, `--sans-validation`, `--perimetre`.
- `orchestration/outils/clore-tache.sh` (nouveau, 126 lignes) : contrôles (rapport,
  `Axx` des réserves au registre, points d'insertion), puis fiche vers `completed/`,
  backlog (statut et section « Terminé »), journal, `agents.tsv`, `verifier-liens.sh`,
  et rappel de ce qui reste au conducteur.
- `orchestration/outils/juger.sh` : branche documentaire (A172), 115 → 137 lignes.
- `.claude/commands/tache.md` : étapes 5 et 8 appellent ces scripts et renvoient à
  leur en-tête au lieu de redécrire leurs gestes.
- `tests/acceptance/TASK-086-outillage.sh` (nouveau, 185 lignes, 24 vérifications).

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `orchestration/outils/verifier-travail.sh` | nouveau |
| `orchestration/outils/clore-tache.sh` | nouveau |
| `orchestration/outils/juger.sh` | modifié (branche documentaire) |
| `.claude/commands/tache.md` | modifié (étapes 5 et 8) |
| `tests/acceptance/TASK-086-outillage.sh` | nouveau |

## Commandes et codes réels

| Commande | Code |
|---|---|
| `tests/env/run-in-container.sh -- tests/run.sh lint` | 0 (126 fichiers, 0 erreur) |
| `bash tests/acceptance/TASK-086-outillage.sh` (hôte) | 0 (24/24) |
| `bash tests/env/run-in-container.sh -- bash tests/acceptance/TASK-086-outillage.sh` | 3 (git absent : indisponibilité déclarée, 11 vérifications faites, 0 échec) |
| `bash orchestration/outils/verifier-liens.sh` | 0 |
| `juger.sh tasks/completed/TASK-083.md` (documentaire) | 0, « SANS OBJET » |
| `juger.sh tasks/completed/TASK-081.md` (Ansible) | 0, scénario Molecule nommé |
| `juger.sh tasks/completed/TASK-069.md` (Bash), master puis branche | 0 dans les deux cas, sorties identiques |
| `verifier-travail.sh TASK-085 --ref 7be628a --base 7f75838 --perimetre` | 0 |
| `verifier-travail.sh TASK-086 --copie .` | 1 — périmètre PASSE, validations 3/3, juge 1 (A169) |

Niveau de preuve : **conteneur** pour le lint et le passage du fichier de cas en
environnement dépourvu de `git` ; **simulé** (hôte, dépôts jetables et historique Git
réel) pour les 24 vérifications. Aucune machine réelle engagée.

## Validations de la fiche

Les trois commandes du champ `validation` ont été exécutées, dans cet ordre, par
`verifier-travail.sh` lui-même : 0, 0, 0.

Critères d'acceptation :

1. **tenu** — 0 sur le premier jet de TASK-085, 1 sur un dépôt jetable où un fichier
   hors scope est ajouté (cas `s6` à `s9`) ;
2. **tenu** — clôture de TASK-083 rejouée sur un worktree détaché :
   `git diff --name-only 2bb9dc0` vide. Le rapport et le registre, qui sont du texte,
   sont pré-chargés depuis le commit réel : ils sont une entrée du script, pas une
   sortie qu'il prouverait ;
3. **tenu** — 0 sur un périmètre documentaire, 1 sur un scope vide, verdicts Bash et
   Ansible inchangés (TASK-069 comparé octet pour octet, TASK-081 dans le fichier de cas) ;
4. **tenu** — 144 et 126 lignes, `shellcheck` à 0 en conteneur ;
5. **tenu** — `tache.md` appelle les deux scripts et renvoie à leur en-tête.

## Relecture

Sous-agent `relecteur`, modèle `opus`, une lecture, 74 686 jetons, 328 s. Verdict :
FUSIONNABLE APRÈS CORRECTIONS — 1 majeur, 6 mineurs, 3 tests creux signalés.

Corrigés (commit `fix: retours de relecture (TASK-086)`) :

- MAJEUR : les cas qui créent un dépôt d'essai exigent `git`, absent de l'image de
  test ; ils tombaient en échec au lieu de déclarer l'indisponibilité. Garde ajouté,
  vérifié en conteneur (code 3) ;
- points d'insertion du backlog et du journal contrôlés **avant** toute écriture, le
  contrat « rien n'est écrit » ne souffrant pas d'écriture partielle ;
- le message de contrôle compte les réserves hors registre au lieu d'affirmer
  « tous au registre » même en défaut ;
- test creux comblé : un `.sh` au `scope`, où qu'il soit, n'obtient jamais le
  laissez-passer documentaire (2 vérifications ajoutées) ;
- `tache.md` renvoie à l'en-tête des scripts au lieu de redire leurs gestes.

Non corrigés, versés au registre : A173 à A176.

## Git

- `agent/TASK-086` : `c2a5948` (premier jet), `9312ae5` (retours de relecture) ;
- fusionnée par `60b72e6` (`--no-ff`), branche supprimée ;
- assertions du fichier de cas : 24 au premier jet, 27 après corrections — aucune
  baisse.

## Réserves

- Les deux outils ne sont documentés que par leur en-tête : ni `orchestration/README.md`
  ni `architecture.md` ne les mentionnent (A173, rejoint A170).
- `verifier-travail.sh` passe au juge de la copie un chemin de fiche résolu dans le
  dépôt principal : un code 2 « Usage » s'y lirait comme un échec du juge (A174).
- Le laissez-passer documentaire de `juger.sh` se décide sur le texte du `scope`, pas
  sur des chemins extraits (A175).
- Le fichier de cas fait 185 lignes pour trois outils, et deux de ses cas lisent des
  fiches vivantes (A176).
- `juger.sh` rend toujours 1 sur une fiche au périmètre `orchestration/`, faute de
  reconnaître un fichier de cas sous `tests/acceptance/` : c'est le cas de TASK-086
  elle-même, dont les preuves sont le lint en conteneur, le fichier de cas et les
  liens (A169, déjà ouverte).
- `clore-tache.sh` ne traite que la clôture d'une tâche terminée ; une tâche bloquée
  se clôt à la main, comme le dit l'étape 8 de `/tache`. Choix assumé, non un défaut.
