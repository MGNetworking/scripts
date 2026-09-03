---
id: TASK-024
title: "Écrire Linux/System/notify-failure.sh"
status: ready
priority: medium
depends_on: []
environment: container-debian
human_approval_required: true
objective: |
  Livrer le script de notification appelé lorsqu'un script planifié échoue. Il
  émet une alerte vers ntfy ou vers un webhook dont l'URL vit dans un .env non
  versionné, borne son temps d'émission, et ne laisse jamais fuir l'URL ni un
  jeton dans une sortie, un journal ou un rapport.
scope:
  - Linux/System/notify-failure.sh
  - config/notify.env.example
  - tests/integration/notify-failure.test.sh
  - config/README.md — la ligne du nouveau contexte, si le tableau le demande
  - docs/points-en-suspens.md — clore le point 2
  - Linux/System/README.md — ligne du tableau, utilisation, risques, secrets
  - README.md — ligne du tableau des scripts
out_of_scope:
  - toute modification de configure-cron.sh et de la ligne déposée dans /etc/cron.d/mgnetworking — voir « Articulation », tâche distincte
  - toute modification d'update-system.sh, de security-check.sh, de backup-resources.sh ou de docker-cleanup.sh
  - l'envoi d'un extrait de journal dans la notification
  - le courriel, le MTA local et toute forme de notification par messagerie — écartés par ADR-0003 décision 15
  - la notification d'un succès, d'un avertissement ou d'un seuil dépassé — ce script notifie un échec
  - un mécanisme de réessai, de file d'attente ou de dédoublonnage des alertes
  - l'ajout de curl à l'image de test — le fichier de cas emploie un faux curl en tête de PATH
acceptance_criteria:
  - le script prend en arguments le nom du script en échec et son code de retour, et refuse en 2 lorsque l'un des deux manque ou est mal formé
  - l'URL de destination est lue par load_config dans config/notify.env, jamais écrite dans le dépôt, et --config <nom> permet d'en changer le fichier
  - config/notify.env.example est versionné, ne contient aucune URL réelle, et documente chaque variable et sa valeur par défaut
  - sans configuration exploitable, le script avertit en nommant le fichier attendu et rend 1, sans rien émettre
  - le message émis porte le nom du script, son code de retour, le nom de la machine, la date et le chemin du journal — et rien d'autre
  - deux formats sont pris en charge, ntfy et webhook JSON, choisis par une variable de configuration ; une valeur inconnue rend 2
  - l'émission est bornée dans le temps, la borne étant configurable, de sorte qu'un service injoignable ne suspende jamais une tâche planifiée
  - une réponse hors de la plage 2xx, une résolution de nom en échec ou un dépassement du délai rendent 1 avec un message qui nomme la cause
  - --dry-run affiche la méthode, le format et le message qui seraient émis, sans rien émettre
  - ni l'URL complète, ni le jeton d'authentification n'apparaissent dans un message, dans le journal ou en --dry-run — l'hôte de destination peut être affiché, le reste est masqué
  - l'absence de curl rend 1 en nommant la dépendance
  - --help documente les options, le fichier de configuration attendu, le format du message et les codes de retour
  - aucune émission réelle n'a lieu pendant les validations — le fichier de cas éprouve le chemin d'émission par un faux curl qui enregistre ses arguments
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- bash Linux/System/notify-failure.sh --help"
  - "tests/env/run-in-container.sh -- bash Linux/System/notify-failure.sh --script update-system.sh --code 1 --dry-run"
implementation_notes:
  - ADR-0003 décision 15 a tranché le principe et la cible — ntfy ou webhook, URL dans un .env non versionné
  - AGENTS.md §8 interdit à l'agent toute publication, webhook compris — l'interdiction porte sur ce que l'agent lance, pas sur ce que le script fera chez son utilisateur
  - AGENTS.md §16 interdit de journaliser une variable dont le nom porte TOKEN, PASSWORD, SECRET, KEY ou CREDENTIAL — ici c'est l'URL elle-même qui est le secret, un sujet ntfy valant mot de passe
  - load_config exporte depuis ADR-0003 décision 7 — les variables du contexte atteignent curl et tout autre processus fils
  - un en-tête passé en argument de curl est visible dans la table des processus — le dire dans le README plutôt que de le taire
  - --dry-run doit rester utilisable sans configuration, pour qu'on puisse lire ce qui serait émis avant d'écrire le .env
---

# TASK-024 — Notifier l'échec d'une tâche planifiée

## Origine

Point n° 2 de [docs/points-en-suspens.md](../../docs/points-en-suspens.md),
soulevé le 2026-08-26 comme conséquence directe du point 1, et **tranché le
2026-09-02 par
[ADR-0003](../../docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md),
décision 15** : un script de notification appelé en cas d'échec, émettant vers
`ntfy` ou un webhook dont l'URL vit dans un `.env` non versionné.

Deux pistes ont été explicitement **écartées**, et ne sont pas à rouvrir : le
courriel par `cron`, qui suppose un MTA et une boîte réellement lue — hypothèse
rarement vraie sur un VPS —, et le contrôle de fraîcheur des journaux, passif,
qui exige que quelque chose le lise.

Le problème que cela ferme : *avec la sortie jetée vers `/dev/null`, une mise à
jour qui échoue ne prévient personne. Le code de retour est correct et le journal
contient l'erreur, mais rien ne remonte. Un serveur peut rester sans mise à jour
pendant des mois sans que cela se voie.*

## Articulation avec `configure-cron.sh` — lire avant d'écrire

La ligne déposée aujourd'hui par `configure-cron.sh` dans
`/etc/cron.d/mgnetworking` est :

```text
0 4 * * 1 root /bin/bash <racine>/Linux/System/update-system.sh --yes >/dev/null
```

La redirection est `>/dev/null` **sans** `2>&1`, et c'est délibéré : la sortie
d'erreur reste transmise à cron, qui l'expédie par courriel. C'est la première
piste du point n° 2, *en place à titre conservatoire, sans avoir été choisie*.
Elle est le filet actuel, et elle ne vaut que sur une machine dotée d'un MTA.

**La forme cible** de la ligne est un enchaînement conditionnel :

```text
… update-system.sh --yes >/dev/null || /bin/bash <racine>/Linux/System/notify-failure.sh --script update-system.sh --code $?
```

Deux points à connaître avant de s'y risquer, et c'est pourquoi cette
modification est **hors périmètre de cette tâche** :

- le contenu du fichier `/etc/cron.d/mgnetworking` est vérifié **au caractère
  près** par `configure-cron.sh` lui-même — `fichier_attendu | diff -q` — et par
  `tests/integration/configure-cron.test.sh`, qui compte jusqu'aux lignes de
  `stderr`. Changer la ligne, c'est reprendre le script, son fichier de cas et son
  README ;
- **le `%` est proscrit** dans une ligne de crontab, `cron` le remplaçant par un
  retour à la ligne, et `configure-cron.sh` refuse déjà un chemin qui en
  contient. Toute forme retenue devra passer cette garde.

Écrire d'abord le notifieur et le prouver ; brancher la planification ensuite,
dans une tâche qui aura le droit de toucher `configure-cron.sh`.

## Le secret, ici, c'est l'URL

Un sujet `ntfy` est une URL publique : qui la connaît peut lire et écrire les
alertes du serveur. Elle vaut donc mot de passe, alors qu'aucun nom de variable
ne contiendra `TOKEN` ni `SECRET` — la règle littérale d'`AGENTS.md` §16 ne la
couvre pas, son intention si.

Trois conséquences, toutes portées par les critères d'acceptation :

- l'URL vit dans `config/notify.env`, **non versionné**, dont seul le `.example`
  entre dans le dépôt ;
- elle n'apparaît ni dans un message, ni dans le journal, ni en `--dry-run`.
  Afficher l'hôte de destination suffit à vérifier qu'on parle au bon service ;
- un jeton d'authentification, s'il en existe un, subit le même sort. À noter
  dans le README : un en-tête passé en argument de `curl` reste **visible dans la
  table des processus** — c'est une limite à écrire, pas à cacher.

## Décisions que cette tâche tranche

**Un seul essai, avec un délai borné.** Pas de réessai, pas de file d'attente.
Une tâche planifiée qui traîne parce que son notifieur retente trois fois est un
défaut plus coûteux que l'alerte manquée ; le journal reste, lui, sur la machine.
Délai par défaut 10 secondes, surchargeable par configuration.

**Le message est court et sans contenu de journal.** Nom du script, code,
machine, date, chemin du journal. Un extrait de journal expédié vers un service
tiers fait sortir des données du serveur — c'est un choix qui se prend
séparément, pas un confort qu'on ajoute au passage.

**Le script rend 1 quand il n'a pas pu alerter**, configuration absente comprise.
Appelé par `cron` derrière un `||`, ce 1 laisse la sortie d'erreur remonter par
le filet actuel : les deux mécanismes se complètent au lieu de se remplacer.

Ces trois choix sont réversibles et locaux au sens d'`AGENTS.md` §14 ; ils sont
fixés ici pour ne pas être rediscutés pendant l'exécution, et à consigner dans le
rapport.

## Pièges connus

**`curl` est absent de l'image de test.** L'image ne porte que
`ca-certificates`, `iproute2`, `procps` et `shellcheck`. Ce n'est pas un obstacle
et il ne faut pas y ajouter de paquet : le fichier de cas place un **faux `curl`
en tête de `PATH`**, qui enregistre ses arguments et rend le code qu'on lui
demande. C'est la mutation la moins coûteuse du dépôt et elle est déjà employée
partout — voir `tests/README.md`, « Les échecs qui ne sont pas fatals ». Elle
permet en outre d'éprouver les trois issues d'émission — 2xx, réponse d'erreur,
délai dépassé — sans le moindre paquet réseau.

**Aucune émission réelle pendant les validations.** `AGENTS.md` §8 interdit à
l'agent toute publication, webhook compris. Un `curl` vers une adresse réelle,
même de test, sort du cadre. Le `--dry-run` et le faux `curl` couvrent tout.

**Le fichier de cas ne doit pas écrire dans `config/`.** `config/*.env` hors
`.example` est en zone interdite (`AGENTS.md` §5). Le contexte de test se crée
ailleurs et se charge par `--config`, ou par un bac à sable comme le fait
`tests/unit/common.test.sh` avec une copie de `lib/common.sh`.

**`load_config` exporte** depuis ADR-0003 décision 7 : tout ce que
`config/notify.env` déclare est visible de `curl` et de tout processus fils. Une
raison de plus pour n'y mettre que ce qui est nécessaire.

## Codes de retour attendus des validations

| Commande | Code |
|---|---|
| `tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh lint` | 0 |
| `run-in-container.sh -- tests/run.sh integration` | 0 |
| `run-in-container.sh -- bash …/notify-failure.sh --help` | 0 |
| `run-in-container.sh -- bash …/notify-failure.sh --script update-system.sh --code 1 --dry-run` | 0, aucune émission |

La dernière exige que `--dry-run` fonctionne **sans configuration** : c'est ce
qui permet de lire ce qui serait émis avant d'écrire le `.env`.

## Ce que la tâche clôt

Le point n° 2 de `docs/points-en-suspens.md`, à marquer traité dans le même
commit — sur le modèle des points 1 et 3, dont le texte d'origine est conservé
tel quel, suivi d'une section disant ce qui a été fait.

Restent hors de cette tâche, et à indexer au backlog : le branchement de la
planification, puis les trois autres appelants que la décision 15 nomme —
`security-check.sh`, `backup-resources.sh`, `docker-cleanup.sh` — qui n'existent
pas encore.
