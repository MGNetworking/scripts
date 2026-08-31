# TASK-002 — Rapport d'exécution

## Statut

COMPLETED — après un passage en `blocked` le 2026-08-29, levé le jour même.

Premier passage complet de la commande `/tache`. Les sept critères
d'acceptation étaient satisfaits et prouvés dès la première exécution ; la tâche
a d'abord été bloquée par sa commande de validation, qui porte sur des fichiers
hors de son périmètre. La dette levée par TASK-011, elle a été rejouée telle
quelle et passe.

Le déroulé du blocage est conservé plus bas, sans réécriture : il documente le
premier refus du système, et c'est ce qu'il a de plus instructif.

## Objectif

Permettre d'exécuter réellement les scripts du dépôt sur une Debian propre,
détruite après chaque essai. La machine hôte n'a ni `apt`, ni `systemctl`, ni
`/etc/os-release`.

## Travail réalisé

- `tests/env/Dockerfile.debian` — image `debian:12` avec quatre paquets :
  `ca-certificates`, `iproute2`, `procps`, `shellcheck`. `LANG=C.UTF-8` sans
  paquet `locales`, listes `apt` supprimées pour qu'un script installant des
  paquets fasse son propre `apt-get update`, comme sur un serveur neuf ;
- `tests/env/run-in-container.sh` — lanceur. Construit l'image si elle manque,
  monte le dépôt en lecture-écriture, exécute, détruit le conteneur. Codes de
  retour : 2 usage, 3 environnement indisponible, 4 échec de construction,
  sinon le code de la commande transmis tel quel ;
- `tests/acceptance/run-acceptance.sh` — dispatcher du niveau `acceptance`, à
  l'emplacement que `tests/run.sh --liste` annonçait déjà ;
- `tests/acceptance/TASK-002-environnement-conteneurise.sh` — 64 vérifications ;
- `tests/README.md` — section « Environnement de test conteneurisé ».

## Fichiers modifiés

| Fichier | Nature |
|---|---|
| `tests/env/Dockerfile.debian` | créé |
| `tests/env/run-in-container.sh` | créé |
| `tests/acceptance/run-acceptance.sh` | créé |
| `tests/acceptance/TASK-002-environnement-conteneurise.sh` | créé |
| `tests/README.md` | modifié |
| `tasks/active/TASK-002.md` → `tasks/blocked/` | déplacé, statut, `blocked_reason`, `scope` élargi |
| `tasks/pending/TASK-011.md` | créé — la dette révélée |
| `tasks/backlog.md` | modifié |

Aucun script d'administration touché. `lib/common.sh` intact.

## Commandes exécutées

| Commande | Code | Résultat |
|---|---|---|
| `docker version` | 0 | 28.5.2, `linux/amd64`, démon actif |
| `tests/run.sh lint` (hôte) | 0 | 14 fichiers, `shellcheck` **NON EXÉCUTÉ** |
| `tests/env/run-in-container.sh -- bash -c 'cat /etc/os-release'` | 0 | `ID=debian`, `VERSION_ID="12"` |
| `tests/env/run-in-container.sh -- Linux/System/system-info.sh` | 0 | rapport complet |
| `tests/acceptance/run-acceptance.sh` | 0 | 64 vérifications, 0 échec, 0 NON EXÉCUTÉ |
| `run-in-container.sh -- shellcheck … <les 3 livrables>` | 0 | après correction SC2317 |
| `run-in-container.sh -- tests/run.sh lint` | **1** | 6 fichiers en erreur, tous hors périmètre |

## Validations

| Validation | Environnement | Résultat |
|---|---|---|
| `tests/run.sh lint` | hôte | **PARTIEL** — `bash -n` seul, `shellcheck` NON EXÉCUTÉ |
| `tests/run.sh lint` | conteneur, qui fait foi | **ÉCHEC** — code 1 |
| `run-in-container.sh -- bash -c 'cat /etc/os-release'` | conteneur | PASS |
| `run-in-container.sh -- Linux/System/system-info.sh` | conteneur | PASS |

**Pourquoi le conteneur fait foi**, et non l'hôte — raisonnement du relecteur,
retenu : sur l'hôte, `shellcheck` est absent et le harnais l'annonce lui-même
`NON EXÉCUTÉ`. Le code 0 rendu n'est donc pas un `PASS` de `tests/run.sh lint`,
mais un `PASS` de `bash -n` seul. Valider un environnement de test en refusant
de s'en servir n'aurait aucun sens.

## Erreur finale

`tests/env/run-in-container.sh -- tests/run.sh lint` sort en **1** : six
fichiers échouent à l'analyse statique.

```text
[SUCCESS] tests/env/run-in-container.sh          livrable, corrigé
[SUCCESS] tests/acceptance/run-acceptance.sh     livrable
[SUCCESS] tests/acceptance/TASK-002-…sh          livrable
[ERROR]   Linux/System/configure-hostname.sh     SC2034, SC1087 x2
[ERROR]   Linux/System/configure-swap.sh         SC2034, SC1087 x2
[ERROR]   Linux/System/configure-logging.sh      SC2034
[ERROR]   Linux/System/configure-timezone.sh     SC2034
[ERROR]   Linux/System/update-system.sh          SC2034
[ERROR]   tests/lint.sh                          SC1073, SC1072
```

Les trois livrables de la tâche passent. Les six fichiers en défaut sont
**préexistants** et hors de son `scope`.

## Corrections tentées

**Tentative 1 — SC2317 sur `tests/env/run-in-container.sh`**

*Diagnostic* : défaut du script, pas du test. `shellcheck` classait
`nettoyer_conteneur` comme inatteignable, n'ayant pas suivi le `trap … EXIT`
qui l'appelle. La fonction n'est pas morte.

*Correction* : directive `# shellcheck disable=SC2317` avec justification
écrite au-dessus, déléguée à `redacteur-script`.

*Résultat* : `shellcheck` sur les trois livrables sort en **0**. Correction
vérifiée dans le conteneur.

Aucune autre tentative : les six fichiers restants sont hors périmètre, et
`AGENTS.md` §12 impose de bloquer plutôt que d'élargir.

## Tentatives

1 / 5

## Cause probable

**Une erreur dans la rédaction de la tâche, pas dans son exécution.**

Le champ `validation` porte `tests/run.sh lint`, qui analyse le **dépôt
entier**, alors que le `scope` de la tâche ne compte que trois fichiers. La
tâche dépendait donc de l'état de fichiers qu'elle ne touche pas.

Cause aggravante : `shellcheck` étant absent de la machine, cette dette était
invisible. TASK-002 livre précisément l'outil qui la révèle. Elle est punie par
ce qu'elle a mis au jour.

## Critères d'acceptation

- [x] un conteneur Debian 12 se construit — `VERSION_ID="12"` confirmé
- [x] le dépôt est monté en lecture-écriture — écriture depuis le conteneur, relecture depuis l'hôte
- [x] code de retour transmis fidèlement — `exit 0/1/7/42`, `false`, et `exit 3` malgré la collision avec le code d'environnement
- [x] le conteneur est détruit après exécution — `--rm` + `trap`, éprouvé aussi sur `SIGTERM` en cours d'exécution
- [x] deux exécutions partent d'un état identique — marqueur absent au second passage, empreintes identiques
- [x] démon arrêté : message clair, code non nul, jamais de faux succès — code 3, absence de tout `[SUCCESS]` vérifiée
- [x] conteneurs et images préfixés `mgnet-test-` — constaté

Les sept critères fonctionnels sont satisfaits.

## Validation finale

**ÉCHEC** — `tests/run.sh lint` sort en 1 dans l'environnement de référence.

La tâche n'est pas déclarée terminée. Une validation en échec n'est pas
présentée comme réussie, quelle que soit la qualité du travail par ailleurs.

## Écarts de périmètre constatés

Relevés par le relecteur, tous deux soumis à Maxime :

1. **`tests/acceptance/` créé hors `scope`.** Le testeur a produit deux fichiers
   que la tâche ne prévoyait pas. Décision de Maxime : **acter l'ajout au
   `scope`** — une tâche sans preuve de son propre fonctionnement ne pourrait de
   toute façon pas être déclarée terminée, le `scope` était incomplet ;
2. **le corps du fichier de tâche a été réécrit à l'étape 3** par l'agent
   principal : doublon dans `scope`, et section « Prérequis bloquant »
   annonçant un démon Docker arrêté qui ne l'était plus. Vérifié au diff :
   `validation`, `acceptance_criteria` et `out_of_scope` **intacts**. Aucune
   exigence retirée. Reste qu'un agent ne réécrit pas l'énoncé de sa tâche.

## Neutralisation

Contrôle du relecteur : **rien n'a été neutralisé**. `tests/lint.sh` et
`tests/run.sh` non modifiés, aucun `set +e`, aucune assertion commentée, champ
`validation` intact. Les 12 `|| true` du fichier d'acceptation sont tous en
contexte de sonde ou de nettoyage. L'unique directive `disable` porte sa
justification.

Le fichier d'acceptation applique lui-même la règle « NON EXÉCUTÉ ≠ PASS » : il
sort en 3 dès qu'un cas est sauté, et le dispatcher propage ce 3 sans le
convertir en succès.

## Intervention humaine requise

**Fait le 2026-08-29.** Deux décisions prises par Maxime :

1. **bloquer TASK-002 et traiter la dette d'abord**, plutôt que restreindre la
   validation à ses seuls livrables. L'énoncé de la tâche n'est donc pas
   modifié : sa validation redeviendra verte d'elle-même ;
2. **acter `tests/acceptance/` au `scope`**.

## Prochaine action recommandée

[TASK-011](../completed/TASK-011.md) — remise à niveau de l'analyse statique, six
fichiers, trois causes identifiées et documentées.

Puis reprendre TASK-002 : rejouer ses trois validations, sans rien changer à son
énoncé. Le travail est fait et prouvé ; seule la validation reste à obtenir.

**Point à trancher avant TASK-011** : elle a besoin du conteneur, livré par
cette tâche mais resté sur la branche `agent/TASK-002`. Il faut soit fusionner
cette branche malgré le statut `blocked` — le travail est prouvé par 64
vérifications —, soit exécuter TASK-011 depuis cette branche.

## Git

Branche : `agent/TASK-002`.

## Réserves

- **`--reconstruire` non couvert par la suite** : vérifié une fois à la main par
  le testeur (27 s, `--pull --no-cache`, `shellcheck 0.9.0`), volontairement
  laissé hors suite pour ne pas ajouter 27 secondes à chaque exécution. Prouvé
  une fois, pas en continu ;
- **arrêt réel du démon Docker non testé** : simulé par `PATH` amputé et
  `DOCKER_HOST` sur port fermé, qui couvrent les deux branches du préflight.
  Un démon qui tombe *pendant* un `docker run` n'est pas couvert ;
- **interruption clavier (`SIGINT`)** non couverte — seul `SIGTERM` l'est ;
- **portabilité hôte Linux ou macOS** non vérifiée : tout a été éprouvé sous
  Git Bash. La branche sans `cygpath` n'est jamais empruntée ici ;
- **exécutions concurrentes** non testées, et les assertions « aucun conteneur
  résiduel » seraient fausses en parallèle. La suite est mono-exécution ;
- le fichier d'acceptation écrit un témoin temporaire dans `logs/`, listé en
  zone interdite par `AGENTS.md` §5. Il est supprimé à la sortie et `logs/` est
  ignoré par Git — effet nul, mais la lettre de la règle est franchie.

## Défauts révélés hors périmètre

Trouvés par le testeur et le relecteur, non corrigés ici :

1. **`tests/run.sh` ne distingue pas « niveau en échec » de « niveau non
   prouvé ».** Un script de niveau sortant en 3 est compté `ÉCHEC`. Le code 3
   documenté ne couvre que « script absent », pas « script présent, rien de
   prouvé » ;
2. **angle mort de l'hôte** : `tests/lint.sh` sort en 0 tout en annonçant
   `NON EXÉCUTÉ`. Un validateur automatique lira 0 et conclura `PASS`. C'est
   exactement le mécanisme qui a permis de livrer un script en défaut de
   `shellcheck` ;
3. **message de démon injoignable tronqué** : `docker info | head -n 5`
   n'affiche que le bloc `Client:`, le `Cannot connect…` est coupé ;
4. **ergonomie** : `--profil --dry-run` accepterait `--dry-run` comme nom de
   profil.

À verser au backlog. Les points 1 et 2 concernent `tests/run.sh` et
`tests/lint.sh`, produits par TASK-001.

## Revalidation du 2026-08-29

[TASK-011](TASK-011-report.md) a levé la dette d'analyse statique. TASK-002 a
été rejouée sur la branche `agent/TASK-002-revalidation`, **sans qu'une virgule
de son énoncé soit modifiée** — c'était la condition posée par Maxime au moment
du blocage.

Ni les livrables ni les tests n'ont été touchés : `git diff master -- tests/`
est vide. Seul le reste du dépôt a changé.

| Validation | Environnement | Code | Résultat |
|---|---|---|---|
| `tests/run.sh lint` | hôte | 0 | 16 fichiers, `shellcheck` NON EXÉCUTÉ |
| `tests/run.sh lint` | **conteneur, qui fait foi** | **0** | 16 fichiers, 0 erreur, 2 avertis, `shellcheck` réellement lancé |
| `run-in-container.sh -- bash -c 'cat /etc/os-release'` | conteneur | 0 | `ID=debian`, `VERSION_ID="12"` |
| `run-in-container.sh -- Linux/System/system-info.sh` | conteneur | 0 | PASS |

Les deux lectures — hôte et conteneur — concordent désormais. Au premier
passage, elles divergeaient : c'était tout le problème.

**Verdict du relecteur : CONFORME AVEC RÉSERVES.** Il a relancé la suite
d'acceptation de la tâche — **64 vérifications, 0 échec, 0 NON EXÉCUTÉ** — et
vérifié par `git show 961a711` que les six fichiers ne passent pas grâce à une
neutralisation : cinq `export` de fond, quatre désambiguïsations `${VAR}[`, et
deux tirets dans un commentaire. Aucune directive `disable`, aucun `|| true`,
aucune assertion retirée.

Ses quatre réserves portaient sur la tenue des registres, non sur le travail :
statut du backlog, statut de ce rapport, sort du champ `blocked_reason`, et
déplacement du fichier de tâche. Les quatre sont traitées — le `blocked_reason`
a quitté le frontmatter, où il n'a de sens que pour une tâche `blocked`, et son
contenu est conservé dans le corps de `tasks/completed/TASK-002.md`.

## Validation finale

**PASS.** Les trois validations passent, dans l'environnement de référence
comme sur l'hôte.

## Résumé

Le dépôt dispose d'un environnement Linux jetable qui fonctionne : image
construite, dépôt monté en écriture, codes de retour fidèles, conteneur détruit,
état identique entre deux exécutions, 64 vérifications au vert.

Aucun des doutes du rédacteur ne s'est confirmé — le montage Windows fonctionne,
le bit exécutable est préservé, les codes de retour sont fidèles, rien ne
survit.

La tâche est pourtant bloquée, et c'est le bon résultat : sa commande de
validation échoue dans l'environnement de référence. Elle échoue sur une dette
antérieure que ce travail vient précisément de rendre visible — six fichiers
n'avaient jamais été analysés par `shellcheck`, faute de l'avoir sur la machine.

Le premier passage complet de `/tache` aura donc produit un environnement de
test, révélé une dette invisible depuis le début du dépôt, et mis au jour une
erreur dans la rédaction du backlog : une tâche de trois fichiers ne peut pas
avoir pour validation l'analyse de tout le dépôt.
