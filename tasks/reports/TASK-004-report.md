# TASK-004 — Rapport d'exécution

## Statut

COMPLETED

## Objectif

Vérifier **par l'exécution** que les six scripts `Linux/System` se comportent
comme annoncé : préflight, `--dry-run` sans effet, et surtout idempotence — une
propriété que les conventions du dépôt affirment depuis toujours et que
personne n'avait jamais éprouvée.

## Travail réalisé

- `tests/integration/run-integration.sh` — dispatcher du niveau, calqué sur
  `run-unit.sh`, avec le garde `reussites -eq 0 → 3` avant
  `non_executes > 0 → 4` ;
- `tests/integration/linux-system.test.sh` — **104 vérifications**, 5 non
  exécutées, 0 échec ;
- `tests/README.md` — niveau `integration` « implémenté », protocole
  d'idempotence et recouvrement avec TASK-011 documentés.

Aucun script d'administration modifié. `lib/common.sh` intact — vérifié par le
relecteur.

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `tests/run.sh lint` | **0** | 22 fichiers, `shellcheck` NON EXÉCUTÉ sur l'hôte |
| `run-in-container.sh -- tests/run.sh integration` | **0** | **104 réussites, 0 échec, 5 non exécutées** — 35 s |
| `tests/run.sh integration` (hôte) | 3 | aucun cas exécutable — cet hôte n'est pas un Linux |

## Validations

| Validation | Résultat |
|---|---|
| `tests/run.sh lint` | **PASS** |
| `run-in-container.sh -- tests/run.sh integration` | **PASS** |

Les deux relancées par le relecteur, chiffres confirmés à l'unité près.

## La garde `P0 != A` — au-delà de l'énoncé

Le rédacteur a ajouté une vérification que la tâche ne demandait pas.

Le protocole d'idempotence classique compare deux empreintes :

```text
exécution 1 → empreinte A → exécution 2 → empreinte B    A == B
```

**Ce protocole passe au vert sur un système déjà conforme, sans rien prouver.**
Si la première exécution n'avait rien à faire, `A == B` est trivialement vrai.

D'où la garde : `P0 != A` — vérifier que la première exécution **a réellement
modifié le système** avant de conclure quoi que ce soit de la seconde.

### Les deux directions de l'interlock, éprouvées

**Sens 1 — la garde attrape une preuve vide.** Contrôle négatif du rédacteur,
**reproduit par le relecteur** : système mis d'avance en état conforme, suite
relancée.

```text
[ERROR] ÉCHEC : configure-timezone.sh Europe/Paris : la première exécution modifie réellement le système
[ERROR] ÉCHEC : configure-logging.sh : la première exécution modifie réellement le système
[ERROR] ÉCHEC : configure-hostname.sh : la première exécution modifie réellement le système
        aucune modification relevée : la preuve d'idempotence serait vide
```

Observation décisive du relecteur : **dans ce scénario, les cinq assertions
`A == B` restent vertes**. Sans la garde, la suite aurait tamponné un vert sur
un système où rien n'avait été prouvé.

**Sens 2 — l'empreinte attrape une vraie non-idempotence.** Éprouvé par le
relecteur sur une copie jetable dans le conteneur, en trois tentatives dont deux
instructives par leur échec :

1. `echo >> /etc/hosts` injecté en fin de script → **non détecté**. Sa faute : la
   ligne était derrière un `exit 0` et ne s'exécutait jamais ;
2. règle logrotate rendue instable → détectée, mais par le message. Diagnostic :
   le script voyait la différence, appelait `confirm`, recevait une réponse vide
   et sortait sans écrire. `A == B` était **correct** ;
3. confirmation neutralisée en plus de l'horodatage, pour forcer une réécriture
   effective :

```text
[ERROR] ÉCHEC : configure-logging.sh : la seconde exécution laisse le système identique
[ERROR] Niveau « integration » : ÉCHEC (code 1)
```

Jugement du relecteur : *« la garde `P0 != A` est plus forte que la contrainte
d'origine — un conteneur neuf garantit un état de départ propre, la garde
vérifie que le premier passage a réellement agi, ce qu'un conteneur neuf ne
garantit pas si le système est conforme par construction. »*

## Le recouvrement avec TASK-011, assumé

TASK-011 couvrait déjà, pour cinq scripts : `--help`, option inconnue, refus
sans privilège, `--dry-run`, idempotence de `/etc/hosts`, `/etc/localtime`,
`/etc/logrotate.d`, `/etc/fstab`.

Le rédacteur a choisi de **reprendre cette couverture** plutôt que de s'y
adosser. Trois raisons, dont la troisième est décisive : les assertions de
TASK-011 sont formulées autour des corrections `SC1087` et **disparaîtront avec
elle** ; une validation qui en dépendrait ne prouverait plus rien le jour de leur
retrait.

Verdict du relecteur : *« ce n'est pas de la duplication, c'est un transfert de
propriété. Le niveau `integration` est le domicile durable de ces preuves ;
TASK-011 est un échafaudage. »* Coût : un conteneur (35 s) contre onze.

**Apport propre**, au-delà du recouvrement :

| Apport | Pourquoi TASK-011 ne l'avait pas |
|---|---|
| `system-info.sh` entier | elle ne le couvre que par `--help` |
| la garde `P0 != A` | absente |
| empreinte de **tout** `/etc` — 119 fichiers, contenu et liens | son empreinte relève une liste arrêtée d'avance |
| cas « le nom demandé est déjà un alias de la ligne 127.0.1.1 » | chemin qu'aucun cas existant n'empruntait |

## « Un conteneur neuf par cas » — contrainte intenable, substituts validés

`tests/run.sh integration` est invoqué **dans** le conteneur, où `docker`
n'existe pas. Trois dispositions la remplacent : groupes non modifiants d'abord,
empreinte de contrôle avant le groupe d'idempotence, cas portant sur des
fichiers disjoints.

Le relecteur les valide, avec une réserve qu'il a fait corriger : l'empreinte de
contrôle référence le début du **groupe 2**, pas le début du fichier — le
commentaire l'affirmait à tort. Écart de commentaire, pas de dispositif : la
seule mutation du préflight, le remplacement de `/etc/os-release`, porte sa
propre assertion de restauration. Corrigé, en trois endroits du fichier.

## Tentatives

1 / 5

## Critères d'acceptation

L'énoncé en contient **six** — l'en-tête du fichier de test en annonçait sept,
le septième étant une assertion ajoutée. Écart relevé par le relecteur, corrigé.

- [x] aide avec `--help`, code 0 — 6/6 scripts, plus `-h`
- [x] refus sans privilège — 5/5 scripts modifiants, UID réellement abaissé par
      `setpriv`, le lanceur étant **éprouvé** et non supposé
- [x] `--dry-run` sans effet, vérifié par empreinte — double filet : empreinte de
      tout `/etc` **et** `find -newer` sur sept arborescences
- [~] **deux exécutions laissent le système identique — partiel.** Preuve réelle
      pour `system-info.sh`, `configure-timezone.sh`, `configure-logging.sh`,
      `configure-hostname.sh`. Pour `configure-swap.sh` et `update-system.sh`,
      seul le chemin `--dry-run` est joué deux fois : leur `A == B` est
      trivialement vrai et **ne prouve pas l'idempotence**. Les chemins réels
      sont déclarés NON EXÉCUTÉ, et le niveau sort en 4
- [x] `system-info.sh` sans privilège, code 0 — lecture seule prouvée
- [x] option inconnue refusée avec le code 2 — 6/6 scripts

## Validation finale

PASS, avec la réserve du quatrième critère explicitement portée : **l'idempotence
de deux scripts sur six n'est pas prouvée**, par construction de l'environnement.

## Les cinq cas non exécutés

Déclarés à l'écran, jamais tamponnés :

1. `configure-timezone.sh` par `timedatectl` — pas de systemd ;
2. `configure-hostname.sh` changeant réellement le nom — `hostnamectl` absent,
   `hostname <nom>` exige `CAP_SYS_ADMIN` ;
3. `configure-swap.sh` créant un fichier d'échange — `swapon` exige
   `CAP_SYS_ADMIN` ;
4. `update-system.sh` appliquant `apt-get upgrade` — exclu par l'`out_of_scope` ;
5. `configure-logging.sh` sans le groupe `adm` — Debian le fournit toujours.

Les trois premiers attendent le profil `container-systemd`.

## Neutralisation

Contrôlé par le relecteur : aucun `|| true`, aucun `set +e`, aucune assertion
commentée, aucune validation retirée. Les deux `|| valeur` présents sont des
replis qui **font échouer** l'assertion, pas qui la sauvent.

## Défauts révélés, non corrigés

Quatre écarts aux conventions, dans les scripts d'administration. Reproduits et
confirmés indépendamment par le rédacteur puis par le relecteur.

1. **`configure-swap.sh --file` sans valeur → code 1, message hors convention** —
   `${1:?…}` produit un message sans préfixe `[ERROR]` ;
2. **codes incohérents pour une valeur invalide** — 2 pour `configure-swap.sh`,
   1 pour `configure-timezone.sh`. *Correction du relecteur* :
   `configure-hostname.sh -mauvais-` rend 2, pas 1 — le tiret initial le fait
   basculer sur « Option inconnue ». L'exemple d'origine était mal choisi,
   l'incohérence existe bien ;
3. **le `trap ERR` double le diagnostic** de `configure-swap.sh` — `die` appelé
   dans une substitution de commande ;
4. **`configure-hostname.sh` sans nom déverse son aide sur `stderr`** —
   *correction du relecteur* : **28** lignes, non 40.

**Aucune assertion rouge n'a été ajoutée pour ces défauts.** Ils ne violent aucun
critère de TASK-004, et l'`out_of_scope` en interdisait la correction : une
assertion rouge aurait fait échouer une validation sans qu'aucune correction soit
permise — l'agent se serait auto-bloqué.

Jugement du relecteur : *« le choix est le bon »* — assorti d'une réserve qu'il
avait raison de poser : le conditionnel de l'`out_of_scope` — « chacun donne lieu
à une tâche distincte » — n'était pas rempli. Il l'est désormais :
[TASK-016](../pending/TASK-016.md).

## Réserves

- **`shellcheck` absent de l'hôte** : le niveau 1 n'a vérifié que la syntaxe sur
  ce travail. Le passage conteneur couvre l'analyse approfondie, mais il n'a pas
  été relancé après les corrections de commentaires — celles-ci ne touchent
  aucune ligne de code ;
- **idempotence réelle de `configure-swap.sh` et `update-system.sh`** : non
  prouvée, correctement déclarée ;
- **niveaux `unit` et `acceptance` non relancés** par le relecteur, pour éviter
  la contention Docker déjà observée deux fois. **NON EXÉCUTÉ, pas PASS** : il ne
  peut pas affirmer que TASK-004 ne régresse pas les suites existantes ;
- **`find -newer` ne descend ni dans `/depot` ni dans `/var/log`** : une écriture
  dans le dépôt monté ou dans les journaux n'est pas détectée comme violation de
  `--dry-run`. Délibéré — `lib/common.sh` écrit un journal dès son chargement,
  avant tout parsing d'arguments ;
- **sur l'hôte Windows, `tests/run.sh` sans argument rend désormais 3**, là où il
  rendait 0. Sémantiquement correct au regard de TASK-012 — rien n'est prouvé sur
  un hôte qui n'est pas Linux, et un 0 serait un mensonge. Documenté dans
  `tests/README.md`. Le relecteur le juge acceptable, avec une seule gêne : qu'un
  humain lise ce 3 comme un échec.

## Git

Branche : `agent/TASK-004`.

## Résumé

L'idempotence des scripts `Linux/System` est éprouvée par l'exécution pour la
première fois. Le dépôt l'affirmait dans ses conventions depuis le premier
commit ; elle n'était démontrée nulle part.

Quatre scripts sur six la prouvent réellement. Deux ne la prouvent pas — `swapon`
et `apt upgrade` sont hors d'atteinte d'un conteneur non privilégié — et le
rapport le dit plutôt que de compter leurs `--dry-run` répétés comme une preuve.

Le travail vaut surtout par ce que la tâche ne demandait pas : la garde
`P0 != A`. Un protocole d'idempotence naïf passe au vert sur un système déjà
conforme, sans rien prouver — c'est le piège classique de ce genre de test. La
garde le ferme, et les deux directions de l'interlock ont été éprouvées à
l'exécution, la seconde après deux tentatives ratées que le relecteur a
consignées plutôt que d'effacer.
