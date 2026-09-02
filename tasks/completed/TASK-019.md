---
id: TASK-019
title: "Contrôler la nature de la cible de --file, pas seulement la forme du chemin"
status: completed
priority: high
depends_on:
  - TASK-017
environment: container-debian
human_approval_required: false
objective: |
  TASK-017 contrôle la forme du chemin donné à --file : absolu, sans tiret
  initial. Elle ne contrôle pas ce que ce chemin désigne. Un fichier régulier
  existant qui n'est pas un fichier d'échange est supprimé après confirmation,
  et un répertoire fait mourir le script sur un message brut de rm.
scope:
  - Linux/System/configure-swap.sh — la fonction valider_fichier_swap et le contrôle de la cible
  - tests/integration/linux-system.test.sh — assertions verrouillant les refus
  - Linux/System/README.md — la contrainte documentée
out_of_scope:
  - lib/common.sh — zone protégée
  - le doublement du trap ERR sur les substitutions de commande, traité par TASK-018
  - la forme du chemin, déjà traitée par TASK-017
  - toute évolution fonctionnelle de la création ou du redimensionnement du fichier d'échange
acceptance_criteria:
  - un chemin absolu désignant un répertoire est refusé avec le code 2, avant toute confirmation et sans message brut de rm
  - un chemin absolu désignant un fichier régulier qui n'est pas un fichier d'échange n'est jamais supprimé sans que l'utilisateur en soit averti explicitement
  - un fichier d'échange existant reste traité comme aujourd'hui — c'est le cas nominal du redimensionnement
  - un chemin absolu inexistant reste accepté, c'est le cas de la création
  - le refus n'est pas doublé par le message du trap ERR
  - les refus sont verrouillés par des assertions qui rougissent sous mutation
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- tests/run.sh unit"
implementation_notes:
  - relevé par le testeur puis mesuré et requalifié par le relecteur de TASK-017 — voir tasks/reports/TASK-017-report.md
  - le point d'accroche est valider_fichier_swap, créée par TASK-017 - la fonction existe, il s'agit d'y ajouter le contrôle de nature
  - valider hors substitution de commande, comme TASK-017 - c'est ce qui évite le doublement du trap
  - le rm -f de la ligne 342 n'est pas récursif - un répertoire n'est donc jamais détruit, seul un fichier régulier l'est
  - distinguer trois natures - absent (création, nominal), fichier d'échange existant (redimensionnement, nominal), autre chose (à refuser ou à confirmer explicitement)
  - le fichier est reconnaissable - /proc/swaps liste les fichiers d'échange actifs, et la commande file ou l'en-tête du fichier permet d'identifier un swap inactif
---

# TASK-019 — Ce que `--file` désigne

## Origine

Découvert par le rédacteur des tests de [TASK-017](../completed/TASK-017.md),
puis **mesuré et requalifié par le relecteur**, qui a trouvé le cas le plus
sérieux.

TASK-017 a fermé la question de la **forme** du chemin. Celle de sa **nature**
restait entière — et c'est elle qui porte le vrai risque.

## Le cas sérieux : un fichier régulier existant est supprimé

```bash
rm -f "$FICHIER_SWAP"        # configure-swap.sh, ligne 342
```

`configure-swap.sh 64M --file /etc/passwd` passe la validation de TASK-017 : le
chemin est absolu et ne commence pas par un tiret. Le script affiche
`créer /etc/passwd (64 Mo)`, demande confirmation, et **supprime le fichier**.

L'utilisateur n'est pas aveugle — le résumé annonce la cible et la confirmation
est demandée. Mais c'est une destruction de données derrière un simple oui, là
où le script pourrait refuser d'emblée une cible qu'il ne reconnaît pas.

Un script d'administration qui s'apprête à supprimer un fichier qu'il n'a pas
créé doit le dire autrement qu'en l'appelant « créer ».

## Le cas mineur : un répertoire

```text
$ configure-swap.sh 64M --file /tmp/rep-essai -y
[INFO] Confirmation automatique : Appliquer ces opérations ?
rm: cannot remove '/tmp/rep-essai': Is a directory
[ERROR] Échec (code 1) à la ligne 342 de configure-swap.sh.
```

Rien n'est détruit : le `rm -f` n'est pas récursif. Le coût est un message brut
de `rm` et une ligne de trap, là où l'utilisateur aurait dû recevoir un refus
propre en code 2 à l'analyse des arguments.

`--file /` produit le même effet, et affiche `créer / (64 Mo)`.

## Pourquoi ce n'est pas TASK-018

TASK-018 porte sur le doublement du `trap ERR` dans les **substitutions de
commande**. Ici, la ligne 342 est un `rm` nu, et la cause première n'est pas le
trap : **c'est une validation absente**. Corriger le trap ne ferait que rendre
le message plus propre, sans empêcher la suppression.

## Les trois natures à distinguer

| La cible | Traitement |
|---|---|
| n'existe pas | création — cas nominal, à laisser passer |
| est un fichier d'échange existant | redimensionnement — cas nominal, à laisser passer |
| est autre chose | à refuser, ou à faire confirmer en disant ce qui va être détruit |

Un fichier d'échange se reconnaît : `/proc/swaps` liste ceux qui sont actifs, et
l'en-tête du fichier — ou `file` — permet d'identifier un swap inactif.

## Piège

Valider **hors** substitution de commande, comme l'a fait TASK-017. C'est ce qui
évite que le refus soit doublé par le message du `trap ERR`.
