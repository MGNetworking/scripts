# TASK-003 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Couvrir de tests le socle chargé par tous les scripts du dépôt. `lib/common.sh`,
217 lignes, point de défaillance unique des huit scripts — **jamais testé depuis
la création du dépôt**.

## Travail réalisé

- `tests/lib/assert.sh` — assertions minimales, Bash pur, aucun framework tiers ;
- `tests/unit/common.test.sh` — **100 assertions** couvrant les onze critères ;
- `tests/unit/run-unit.sh` — dispatcher du niveau, au chemin qu'annonçait déjà
  `tests/run.sh --liste` depuis TASK-001 ;
- `tests/README.md` — le niveau `unit` passe « implémenté ».

**`lib/common.sh` n'a pas été modifié.** Vérifié indépendamment par le
relecteur : `git diff master --quiet -- lib/common.sh` → 0.

## Conception — l'isolation des cas

Le problème annoncé par la tâche : `common.sh` pose un `trap ERR`, les scripts
utilisent `set -Eeuo pipefail`, et tester une fonction qui appelle `exit`
demande de l'isoler.

L'énoncé suggérait un sous-shell. **Le rédacteur a démontré que c'était faux** :
un sous-shell hérite de `_COMMON_SH_CHARGE`, la garde anti-double-chargement.
Son `source` serait une opération nulle et le cas ne testerait rien.

La conception retenue est donc **un processus `bash` neuf par cas**, avec un bac
à sable dans `mktemp -d` — copie de `common.sh` vérifiée par `cmp`, `config/`
jetable, `LOG_DIR` passé en paramètre positionnel pour survivre à une
dégradation de privilèges.

Le testeur a mesuré ce raisonnement plutôt que de le croire : `SCRIPTS_ROOT`
falsifiée survit à un `source` en sous-shell, pas à un processus neuf. **Sans
cette propriété, les 100 assertions seraient vides.**

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `bash -n` sur les 3 nouveaux `.sh` | 0 | — |
| `tests/run.sh lint` (hôte) | **0** | 20 fichiers, `shellcheck` NON EXÉCUTÉ |
| `run-in-container.sh -- tests/run.sh lint` | **0** | 20 fichiers, 0 erreur, 2 avertis |
| `run-in-container.sh -- tests/run.sh unit` | **0** | **100 réussites, 0 échec, 0 non exécuté** |
| `tests/run.sh unit` (hôte) | 0 | niveau à 4 : 85 réussites, 7 non applicables |
| `tests/acceptance/TASK-012-semantique-codes.sh` | **1** | 57 réussites, **1 échec** — voir plus bas |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | **PASS** |
| `run-in-container.sh -- tests/run.sh unit` | **PASS** |

Les deux commandes du champ `validation` passent.

## Le pouvoir discriminant, éprouvé deux fois

La question qui compte pour une suite de tests n'est pas « passe-t-elle ? » mais
« **détecte-t-elle quelque chose ?** ». Elle a reçu deux réponses indépendantes.

**Le testeur** : 15 mutations de `lib/common.sh` sur une copie dans `/tmp` du
conteneur — **15 tuées**. Dont une, `run_logged` rendant le code du tube, qui ne
fait tomber qu'un seul cas : le discriminant est bien discriminant.

**Le relecteur** a refait l'exercice sans réutiliser celui du testeur — copie
montée à la place du dépôt : **8 mutations, 8 tuées**, chacune sur les
assertions attendues et sur elles seules.

| Mutation | Échecs provoqués |
|---|---|
| `die` : code fourni ignoré | 2 |
| `require_cmd` : liste toutes les commandes | 1 |
| `run_logged` : rend 0 au lieu de `PIPESTATUS[0]` | 2 |
| `load_config` : ajout de `set -a` | 1 |
| `confirm` : ignore `ASSUME_YES` | 3 |
| `require_os` : accepte tout | 3 |
| garde `_COMMON_SH_CHARGE` exportée | 75 |
| `_log` : écrit sur stdout | 15 |

Le dépôt n'a jamais été muté — uniquement des copies.

## Corrections automatiques

**Tentative 1 — compléments du testeur**, aucune correction de défaut mais trois
trous de couverture comblés :

- un **second cas discriminant** sur `run_logged` : commande à 42 *et* `tee` en
  échec. Le seul code qui distingue `PIPESTATUS[0]` à la fois du code du tube et
  de celui de `tee`, tous deux à 1 ;
- une section **« journalisation impossible »** : `LOG_DIR` détourné vers un
  chemin non créable. Comble un trou réel — **la branche de `run_logged` sans
  `tee`, moitié de la fonction visée par le onzième critère, n'était jamais
  exécutée** ;
- la **portée de la garde** prouvée en code, pas seulement raisonnée.

87 assertions au départ, **100** à l'arrivée.

## Tentatives

1 / 5

## Critères d'acceptation

- [x] `load_config` charge un fichier existant
- [ ] **… et exporte ses variables — NON SATISFAIT par le socle** (voir ci-dessous)
- [x] `load_config` sur un fichier absent arrête le script, code non nul
- [x] `require_cmd` réussit sur une commande présente, échoue en listant les manquantes
- [x] `require_root` échoue sans privilège — dégradation **réelle** par `setpriv` vers `nobody`, éprouvée par un `id -u` et non supposée
- [x] `require_os` accepte une distribution attendue et refuse les autres
- [x] `detect_os` renseigne `OS_ID`, `OS_VERSION`, `OS_ARCH`
- [x] `info`, `warn`, `error`, `success` écrivent sur stderr et dans le journal — et rien sur stdout
- [x] `die` sort avec le code fourni, et 1 par défaut
- [x] `confirm` retourne 0 sans interaction quand `ASSUME_YES` vaut true — stdin sur `/dev/null` prouve l'absence de `read`
- [x] double chargement sans erreur ni effet de bord
- [x] `run_logged` retourne le code de la commande, pas celui de `tee`

**Dix critères sur onze satisfaits. Le onzième est contredit par la mesure.**

## Le critère contredit

Le critère dit « `load_config` charge un fichier existant **et exporte ses
variables** ». Mesuré dans le conteneur :

```text
shell appelant : VAR_NUE=valeur-nue   VAR_EXP=valeur-exp
processus fils : VAR_NUE=ABSENTE      VAR_EXP=valeur-exp
```

`load_config` fait `. "$fichier"` sans `export`. Pour la forme d'écriture que
`config/README.md` prescrit — affectations nues — **les variables n'atteignent
pas les processus fils**. Le socle ne fait pas ce que le critère affirme.

Le testeur n'a ni corrigé le socle, ni maquillé le critère : il a mesuré les deux
frontières, les a nommées, et affiche deux `[WARN]` à chaque exécution.

**Un piège à connaître** : la suite épingle le comportement *observé*
(`FILS_NUE=absente`), donc un défaut du socle comme s'il était le contrat. Le
jour où quelqu'un corrigera `load_config`, cette assertion devra être retournée
dans le même commit — les deux sous-agents ont vérifié qu'une mutation `set -a`
fait passer la suite au rouge.

C'est acceptable — un test caractérisant un défaut connu est légitime — **à
condition que le défaut soit tracé ailleurs que dans un commentaire**. Il l'est
désormais : [TASK-015](../pending/TASK-015.md).

## Validation finale

PASS, avec la réserve ci-dessus explicitement portée : **le vert de
`tests/run.sh unit` ne vaut pas « les onze critères sont prouvés »**. Dix le
sont, le onzième est mesuré et contredit.

## La régression laissée au dépôt

`tests/acceptance/TASK-012-semantique-codes.sh` ligne 425 affirme
`tests/run.sh unit → 3 (niveau non implémenté)`. TASK-003 fournit ce niveau : le
cas obtient 0, le fichier sort en 1, et **le niveau `acceptance` passe au
rouge**.

TASK-003 n'a rien cassé — elle a rendu l'assertion obsolète. Celle-ci vérifiait
un comportement en s'appuyant sur un état du dépôt.

`tests/acceptance/` étant hors `scope`, ni le testeur ni le relecteur n'y ont
touché : `AGENTS.md` §12 impose de bloquer plutôt que d'élargir. Le point est
traité par [TASK-014](../pending/TASK-014.md), **à faire avant toute fusion**
sous peine de transmettre un dépôt rouge à `master`.

## Neutralisation

Contrôlé par le relecteur, pas cru : aucun `|| true`, `set +e`, `set +u` ni
`set +o pipefail` dans `tests/unit/` et `tests/lib/` ; aucune assertion
commentée ; champ `validation` inchangé ; `set -Eeuo pipefail` en place.

`assert.sh` ne le pose pas — et c'est correct : c'est une bibliothèque
`source`-ée, comme `lib/common.sh` qui ne le pose pas davantage.

## Réserves

- **`tests/run.sh acceptance` non exécuté en tant que niveau** par le relecteur,
  durée oblige. Son code 1 est **déduit** de deux faits vérifiés, pas mesuré
  directement ;
- **`shellcheck` absent de l'hôte** : la validation `tests/run.sh lint` ne
  couvre que la syntaxe. Le passage conteneur a été fait séparément et sort
  en 0 ;
- **non couvert, et pourquoi** : `enable_full_logging` (hors des onze critères,
  et `exec > >(tee …)` remplace les descripteurs du processus — la capture du
  harnais devient l'objet du test) ; le chargement automatique de
  `config/server.env`, délibérément neutralisé par le bac à sable ; le repli par
  défaut de `LOG_DIR` ; la branche « stderr est un terminal », inatteignable
  sans pty ; `confirm` avec `oui`/`yes` ; le contenu du message de `_on_error` ;
- **les gardes de `run-unit.sh` ne sont pas couvertes en permanence** — éprouvées
  par sonde jetable (aucun cas → 3, un échec → 1, que des sauts → 3, un ok + un
  saut → 4, que des ok → 0), mais aucune suite ne les vérifie en continu.
  `TASK-012-semantique-codes.sh` couvre le dispatcher `acceptance`, pas
  celui-ci.

## Défauts révélés, non corrigés

1. **`load_config` n'exporte pas** — critère contredit → [TASK-015](../pending/TASK-015.md) ;
2. **`_log` tue le script sous `set -e`** si `LOG_FILE` est renseignée mais non
   inscriptible : un simple `info` interrompt l'exécution, le `trap ERR` étant
   armé par le `printf >> "$LOG_FILE"`. Fragilité de robustesse, pas
   contradiction du contrat → TASK-015 ;
3. **le message du `trap ERR` désigne le mauvais fichier** : « à la ligne 78 de
   `rl.sh` » alors que la ligne 78 est celle de `lib/common.sh`. `$LINENO` vient
   du contexte fautif, `basename "$0"` du script appelant. Diagnostic trompeur
   dès que l'échec vient du socle → TASK-015 ;
4. **`tests/lib/` est un nom piégeux** : la résolution en trois lignes cherche
   `<candidat>/lib/common.sh` ; depuis `tests/`, le premier candidat testé est
   `tests/lib/common.sh`. Tant qu'il n'existe pas, tout va bien. Le jour où
   quelqu'un l'y déposerait, tous les scripts du dépôt chargeraient ce
   fichier-là. Averti en tête de `assert.sh` et dans le README ; le chemin étant
   imposé par le `scope`, il n'a pas été changé.

## Git

Branche : `agent/TASK-003`.

## Résumé

Le socle du dépôt a des tests. C'est la première fois depuis sa création : 217
lignes chargées par huit scripts d'administration, dont certains tournent sur un
serveur réel, reposaient jusqu'ici sur la seule relecture.

Cent assertions, éprouvées par 23 mutations au total — 15 par le testeur, 8 par
le relecteur travaillant séparément — **toutes tuées**. La suite ne se contente
pas de passer : elle détecte.

Et elle a trouvé. Trois défauts du socle, dont un qui **contredit un critère de
la tâche elle-même** : `load_config` n'exporte pas ce que le critère affirme
qu'il exporte. Aucun n'a été corrigé — `lib/common.sh` est zone protégée, et
c'était précisément l'objet de cette tâche : savoir ce que le socle fait
vraiment, pas obtenir qu'il passe.
