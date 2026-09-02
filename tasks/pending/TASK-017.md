---
id: TASK-017
title: "Durcir la validation de --file dans configure-swap.sh"
status: ready
priority: high
depends_on:
  - TASK-016
environment: container-debian
human_approval_required: false
objective: |
  --file accepte aujourd'hui n'importe quelle chaîne non vide comme chemin, y
  compris une option du script lui-même, qu'il consomme alors sans avertir. Il
  accepte aussi un chemin relatif, ce qui peut faire naître un fichier d'échange
  dans le répertoire courant.
scope:
  - Linux/System/configure-swap.sh — validation de la valeur de --file
  - tests/integration/linux-system.test.sh — assertions verrouillant les refus
  - Linux/System/README.md — si la contrainte de chemin absolu est documentée
out_of_scope:
  - lib/common.sh — zone protégée
  - le doublement du trap ERR sur les autres substitutions de commande, traité par TASK-018
  - toute évolution fonctionnelle de la gestion du fichier d'échange
  - les cinq autres scripts de Linux/System, non concernés
acceptance_criteria:
  - "--file suivi d'une valeur commençant par un tiret est refusé avec le code 2 et un message nommant la valeur"
  - "--dry-run et -y ne sont plus consommés par --file : ils restent actifs quand ils suivent une valeur valide"
  - "--file suivi d'un chemin relatif est refusé avec le code 2"
  - un chemin absolu reste accepté, et le comportement nominal du script est inchangé
  - aucun message du trap ERR ne s'ajoute aux diagnostics de ces refus
  - les trois refus sont verrouillés par des assertions qui rougissent sous mutation
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- tests/run.sh unit"
implementation_notes:
  - découvert par le testeur de TASK-016, gravité mesurée et corrigée par le relecteur — voir tasks/reports/TASK-016-report.md
  - le garde-fou actuel est accidentel - dirname refuse l'option et set -Eeuo pipefail tue le script avant toute écriture. Ne pas s'y fier
  - le cas le plus sérieux est l'ordre inversé - configure-swap.sh --file 2G donne un chemin relatif, et avec SRV_SWAP_SIZE défini dans server.env un fichier d'échange naîtrait dans le répertoire courant
  - refuser une valeur commençant par un tiret ne suffit pas - c'est l'exigence de chemin absolu qui ferme le cas grave
  - configure-cron.sh a déjà le motif de contrôle explicite d'une valeur d'option, à imiter
---

# TASK-017 — La valeur de `--file` n'est pas contrôlée

## Origine

Découvert pendant [TASK-016](../completed/TASK-016.md) par le rédacteur des
tests, puis **mesuré et requalifié par le relecteur**. Aucun des deux n'a pu le
corriger : `Linux/System` sortait de leur périmètre, et une assertion rouge
aurait bloqué la validation de TASK-016 sans qu'aucune correction soit permise.

## Les deux cas

**1. Une option est avalée comme chemin**

```text
$ configure-swap.sh 512M --file --dry-run
[INFO] Fichier d'échange : --dry-run
dirname: unrecognized option '--dry-run'
[ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.
[ERROR] Échec (code 1) à la ligne 195 de configure-swap.sh.   code=1
```

`FICHIER_SWAP` vaut `--dry-run`, et `DRY_RUN` reste `false` : **l'option est
consommée**. L'utilisateur croit demander un essai à blanc et ne l'obtient pas.

Le contrôle posé par TASK-016 — `[ -n "${1:-}" ]` — ne rejette que la valeur
vide. Il ne pouvait pas faire plus : son objet était le code de retour, pas la
nature de la valeur.

**Ce qui sauve aujourd'hui est un accident.** Le relecteur a vérifié qu'aucune
écriture n'a lieu : `dirname` refuse une chaîne commençant par `--`, et
`set -Eeuo pipefail` tue le script bien avant la ligne 291. `/tmp` est resté
vide après l'essai. Le garde-fou tient au seul fait que la valeur avalée
commence par deux tirets — il disparaîtrait avec n'importe quelle autre valeur.

**2. Un chemin relatif est accepté — le cas grave**

```text
$ configure-swap.sh --file 2G
```

L'ordre est inversé, `FICHIER_SWAP` vaut `2G`, chemin **relatif**. Avec
`SRV_SWAP_SIZE` défini dans `config/server.env`, la taille ne manque pas : rien
n'arrête le script, et un fichier d'échange serait créé **dans le répertoire
courant** — quel qu'il soit.

C'est le cas que le relecteur a jugé plus sérieux que le premier, et c'est lui
qui commande la correction : refuser une valeur commençant par un tiret ne
suffirait pas à le fermer.

## Ce qu'il faut donc

Deux contrôles, pas un :

| Contrôle | Ferme |
|---|---|
| la valeur ne commence pas par `-` | le cas 1 — l'option avalée |
| la valeur est un chemin **absolu** | le cas 2 — le fichier d'échange égaré |

Le second est le seul qui protège vraiment. Un fichier d'échange n'a de sens
qu'à un emplacement choisi ; il n'y a aucun usage légitime d'un chemin relatif
ici.

## Pièges

Le message de refus ne doit pas être doublé par le `trap ERR` : valider **avant**
toute substitution de commande, jamais à l'intérieur. C'est la leçon du défaut 3
de TASK-016, et `configure-cron.sh` porte déjà le motif à imiter.

Vérifier que `--dry-run` et `-y` **restent actifs** quand ils suivent un `--file`
correctement renseigné : c'est l'assertion qui prouve qu'ils ne sont plus
consommés, et elle manque aujourd'hui.
