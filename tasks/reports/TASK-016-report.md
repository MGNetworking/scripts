# TASK-016 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Uniformiser les codes de retour et les messages d'erreur d'usage des scripts
`Linux/System`. Quatre écarts découverts en éprouvant ces scripts par
l'exécution lors de TASK-004, et laissés en l'état : les corriger aurait
débordé le périmètre de cette tâche-là.

Aucun n'était fonctionnel. Ils portaient sur les codes, les messages et le bruit
de diagnostic — c'est-à-dire sur ce qu'un appelant automatique lit pour savoir
ce qui s'est passé.

## Travail réalisé

**1. `configure-swap.sh --file` sans valeur.** La forme
`FICHIER_SWAP="${1:?--file attend un chemin}"` produisait un message sans préfixe
et sortait en 1. Remplacée par un contrôle explicite,
`[ -n "${1:-}" ] || die "--file attend un chemin." 2`, sur le modèle de
`--horaire` dans `configure-cron.sh`. Message préfixé, journalisé, code 2.

**2. Valeur d'argument invalide → 2 partout.** Les quatre `die` de
`valider_fuseau` et les cinq de `valider_nom` passent en code 2. Aucun message ni
comportement changé, seul le code. `configure-swap.sh` appelait déjà `die … 2`.

**3. Le `trap ERR` ne double plus le diagnostic métier.** `en_megaoctets` rendait
sa valeur sur `stdout`, donc s'exécutait dans le sous-shell de
`TAILLE_MO="$(en_megaoctets …)"`. Son `die` ne quittait que ce sous-shell ; le
code remonté au shell principal déclenchait le `trap ERR` du socle, d'où une
seconde ligne parasite.

La fonction renseigne désormais la variable `TAILLE_MO` et s'appelle hors
substitution. Son `die` s'applique au script entier, sans commande en échec à
signaler. `lib/common.sh` n'a pas été touché — le `trap` est en zone protégée,
la correction devait venir de l'appelant. C'est la forme que `configure-cron.sh`
avait déjà retenue pour `valider_horaire` : les deux scripts sont maintenant
alignés sur le même motif.

**4. `configure-hostname.sh` sans nom.** `show_help >&2` déversait 28 lignes où
le diagnostic se perdait. Remplacé par trois lignes et un renvoi vers `--help`,
sur la forme exacte de son homologue dans `configure-timezone.sh`.

**5. La convention est écrite.** `docs/architecture-technique.md` §6 — inscrit
par TASK-015 — est complété : la valeur d'argument invalide rattachée au 2, une
sous-section sur les deux façons de perdre le code ou le message (`${1:?…}` et
`die` en substitution de commande), une autre sur le fait qu'un diagnostic n'est
pas un manuel. `Linux/System/README.md` reçoit une section « Codes de retour ».

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `Linux/System/configure-swap.sh` | défauts 1 et 3 |
| `Linux/System/configure-timezone.sh` | défaut 2 — quatre `die` |
| `Linux/System/configure-hostname.sh` | défauts 2 et 4 — cinq `die`, plus l'aide |
| `Linux/System/README.md` | section « Codes de retour » |
| `docs/architecture-technique.md` | §6 complété |
| `tests/integration/linux-system.test.sh` | 104 → 162 assertions |
| `tests/README.md` | hors `scope` — voir « Écarts de périmètre » |

## Commandes exécutées

| Commande | Code |
|---|---|
| `tests/run.sh lint` (hôte) | 0 |
| `tests/env/run-in-container.sh -- tests/run.sh lint` (shellcheck présent) | 0 — 0 erreur, 2 avertissements sur les Synology hérités, préexistants |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | **0** — 162 vérifications, 0 échec, 5 NON EXÉCUTÉ |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | 0 — 161 vérifications, 0 échec |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | PASS — réserve : `shellcheck` absent de l'hôte. Relancé **en conteneur**, où il est présent : code 0 |
| `tests/env/run-in-container.sh -- tests/run.sh integration` | PASS |
| `tests/env/run-in-container.sh -- tests/run.sh unit` | PASS — non-régression du socle |

## Vérification par mutation

Menée deux fois : par le testeur, puis **indépendamment par le relecteur**, sur
une copie hors dépôt.

| Mutation | Assertions rouges |
|---|---|
| `${1:?…}` rétabli sur `--file` | 3 |
| `en_megaoctets` remise en substitution de commande | 4 à 5 |
| `die` sans code dans `valider_fuseau` | 3 à 4 |
| `die` sans code dans `valider_nom` + `show_help >&2` | 6 à 12 |
| conversion `G` amputée du `× 1024` | 3 |
| aide déversée sur `stdout` | 2 |

Les six assertions d'absence ont été éprouvées une à une : aucune n'est creuse.

**Un point mérite d'être retenu.** Le décompte de lignes ne voit *pas* revenir
`${1:?…}` — le message brut de bash tient lui aussi sur une seule ligne. C'est
`assert_absent "configure-swap.sh: line"` qui ferme réellement le défaut 1. Le
testeur l'a constaté en rejouant sa mutation et a ajouté l'assertion manquante ;
le relecteur l'a confirmé indépendamment.

## Erreurs rencontrées

**Une affirmation fausse dans `Linux/System/README.md`**, trouvée par le
relecteur : « lancer l'un de ces scripts sans `sudo` rend 1 ». Faux pour
`system-info.sh`, qui rend 0 — il ne fait que lire. Le fichier de tests portait
d'ailleurs déjà une assertion contraire. Corrigé par une incise.

## Corrections automatiques

Une, celle ci-dessus. Faite directement plutôt que redéléguée : le relecteur
avait nommé la phrase et la correction exacte, et un démarrage à froid pour une
incise factuelle ne se justifiait pas (ADR-0003, décision 5, esprit).

## Tentatives

1 / 5

## Critères d'acceptation

- [x] une erreur d'usage rend le code 2 sur les six scripts — vérifié par
      exécution sur les sept, `configure-cron.sh` compris
- [x] une valeur d'argument invalide rend le même code sur tous les scripts
- [x] tout message d'erreur porte le préfixe `[ERROR]`, y compris ceux produits
      par une expansion Bash
- [x] un diagnostic métier n'est plus doublé par le message du `trap ERR`
- [x] un script appelé sans son argument obligatoire affiche un diagnostic
      lisible — 3 lignes contre 28
- [x] les comportements corrigés sont verrouillés par des assertions
- [x] aucun comportement fonctionnel n'est modifié — conversions vérifiées une à
      une : `2G`, `2GB`, `2GO`, `2g`, `2Go` → 2048 Mo ; `512M`, `512MB`, `512MO`
      → 512 Mo ; `2048` → 2048 ; `1G` → 1024

## Validation finale

PASS

## Écarts de périmètre

`docs/architecture-technique.md` n'est pas dans le champ `scope`, alors que les
`implementation_notes` de la tâche l'exigeaient explicitement. **Contradiction
interne de l'énoncé**, pas faute d'exécution — à éviter dans la rédaction des
tâches suivantes.

`tests/README.md` n'est ni dans le `scope` ni exigé nulle part. Écart formel,
contenu juste et utile : il documente les deux nouveaux groupes d'assertions.

## Ce que la tâche a révélé, sans le corriger

**`configure-swap.sh --file` accepte une option comme chemin.**
`configure-swap.sh 512M --file --dry-run` donne `FICHIER_SWAP="--dry-run"`, et
`DRY_RUN` reste `false` : l'option est **consommée**.

Le testeur a annoncé qu'un essai à blanc s'exécuterait donc réellement. **Le
relecteur l'a infirmé par l'exécution** : `dirname "--dry-run"` refuse l'option,
et `set -Eeuo pipefail` tue le script bien avant toute écriture. `/tmp` est resté
vide après l'essai. Le garde-fou est accidentel — il tient au seul fait que la
valeur avalée commence par `--` — mais il est mécanique.

Gravité retenue : **moyenne**. Pas de risque de données. Ce qui reste : une
option acceptée sans broncher, un `--dry-run` ou un `-y` perdu sans
avertissement, et un message `dirname` incompréhensible doublé d'un trap.

Le relecteur a trouvé un cas voisin plus sérieux : `configure-swap.sh --file 2G`
— ordre inversé — donne un chemin **relatif**, et avec `SRV_SWAP_SIZE` défini
dans `server.env`, un fichier d'échange serait créé dans le répertoire courant.
La correction utile n'est donc pas seulement « refuser une valeur commençant par
`-` », mais « exiger un chemin absolu ». Porté en **TASK-017**.

Ni l'un ni l'autre n'a été transformé en assertion rouge : corriger
`Linux/System` sortait du périmètre du testeur, et une assertion rouge aurait
bloqué la validation sans qu'aucune correction soit permise — exactement la
situation que TASK-016 décrit à propos de TASK-004.

**Le doublement du `trap ERR` subsiste ailleurs dans `configure-swap.sh`.**
Ligne 195, `repertoire_swap="$(dirname "$FICHIER_SWAP")"` : quand `dirname`
échoue, la sortie porte deux fois le message du trap. Le critère d'acceptation
visait le diagnostic *métier*, qui n'est plus doublé ; mais le motif de fond —
`die` ou échec dans une substitution de commande — n'a été traité que sur
`en_megaoctets`. Préexistant, non introduit ici. Porté en **TASK-018**.

**Inconsistance mineure, signalée seulement.** `configure-swap.sh abc` déverse
ses seize lignes d'état *avant* le diagnostic, là où les autres scripts refusent
avant d'écrire quoi que ce soit. C'est pourquoi aucune borne de lignes n'a été
posée sur ces cas — seulement le décompte des lignes `[ERROR]`.

## Réserves

**Les cinq `assert_code 1` de `require_root` ne sont pas éprouvées par
mutation** : la seule mutation possible vivrait dans `lib/common.sh`, exclu par
l'`out_of_scope`. Le relecteur juge la limite acceptable — les assertions lisent
bien `$CODE`, et `assert_code` est prouvé fonctionnel par les cas voisins qui
rougissent. À noter tout de même : `tests/unit/common.test.sh` n'utilise
qu'`assert_code_non_nul`, si bien que la valeur exacte 1 n'est épinglée que par
ces cinq assertions d'intégration.

**La borne sur l'aide est de 5 lignes, pas une égalité à 3.** Choix assumé : une
égalité rougirait sur une reformulation légitime. Un diagnostic qui passerait à
5 lignes ne serait donc pas vu — mais l'aide, à 28, l'est.

**Les cas « argument manquant » sont conditionnels.** Ils sont déclarés
`NON EXÉCUTÉ` si `SRV_HOSTNAME` ou `SRV_TIMEZONE` est fourni par l'environnement
ou par `config/server.env` — sinon le script prendrait la valeur et ne
diagnostiquerait rien. Dans le conteneur, `server.env` est absent : ils tournent.

## Git

Branche : `agent/TASK-016`
Fusionnée dans `master` en `--no-ff` après validation.

## Résumé

Les sept scripts de `Linux/System` disent maintenant la même chose de la même
façon : 2 quand l'appelant s'est trompé, 1 quand le travail n'a pas pu être
fait, un préfixe `[ERROR]` sur chaque message, et un diagnostic qui n'est plus
noyé sous une aide de 28 lignes ni doublé par le trap.

La convention n'est plus déductible du code : elle est écrite, dans
`docs/architecture-technique.md` §6 et dans le README du domaine.

Deux découvertes valent mieux que la tâche elle-même. Le testeur a trouvé que
`--file` avale l'option qui le suit ; le relecteur a vérifié sa conséquence
annoncée et l'a **infirmée**, puis a trouvé un cas voisin plus grave que le
premier. C'est exactement ce qu'on attend d'une relecture indépendante : ni
confirmer, ni contredire par principe — vérifier.
