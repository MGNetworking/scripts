---
id: TASK-016
title: "Uniformiser les codes de retour et les messages d'erreur d'usage"
status: ready
priority: medium
depends_on:
  - TASK-004
environment: container-debian
human_approval_required: false
objective: |
  Quatre écarts aux conventions du dépôt, découverts en éprouvant les scripts
  Linux/System par l'exécution. Aucun n'est fonctionnel : ils portent sur les
  codes de retour, les messages et le bruit de diagnostic.
scope:
  - Linux/System/configure-swap.sh — code 2 et préfixe sur --file sans valeur, code du trap
  - Linux/System/configure-hostname.sh — code sur valeur invalide, aide sur stdout
  - Linux/System/configure-timezone.sh — code sur valeur invalide
  - tests/integration/linux-system.test.sh — assertions verrouillant les comportements corrigés
  - Linux/System/README.md — si une convention est explicitée
out_of_scope:
  - lib/common.sh — zone protégée ; le trap ERR ne s'y corrige pas ici
  - toute évolution fonctionnelle des scripts
  - les scripts Synology hérités
  - update-system.sh et configure-logging.sh, non concernés
acceptance_criteria:
  - une erreur d'usage rend le code 2 sur les six scripts, quelle qu'en soit la nature — à l'exception du privilège insuffisant, qui reste en 1 par ADR-0003 décision 10
  - une valeur d'argument invalide rend le même code sur tous les scripts
  - tout message d'erreur porte le préfixe [ERROR], y compris ceux produits par une expansion Bash
  - un diagnostic métier n'est plus doublé par le message du trap ERR
  - un script appelé sans son argument obligatoire affiche un diagnostic lisible, sans déverser son aide entière
  - les comportements corrigés sont verrouillés par des assertions dans tests/integration/
  - aucun comportement fonctionnel n'est modifié
validation:
  - "tests/run.sh lint"
  - "tests/env/run-in-container.sh -- tests/run.sh integration"
  - "tests/env/run-in-container.sh -- tests/run.sh unit"
implementation_notes:
  - les quatre défauts sont reproduits et confirmés par deux sous-agents lors de TASK-004
  - « ${1:?message} » produit un message sans préfixe et sort en 1 — c'est la cause du défaut 1
  - le doublon de trap vient d'un « die » appelé dans une substitution de commande
  - la convention « erreur d'usage → 2 » n'est écrite nulle part : l'inscrire dans docs/architecture-technique.md fait partie du travail
  - ADR-0003 décision 10 borne la convention : require_root garde le code 1, un privilège insuffisant étant un échec d'exécution et non une erreur d'usage. Ne pas l'aligner sur 2
  - si TASK-015 est passée avant, docs/architecture-technique.md porte déjà la distinction : la compléter, ne pas la réécrire
---

# TASK-016 — Cohérence des erreurs d'usage

## Origine

Découverts pendant [TASK-004](../completed/TASK-004.md), qui a éprouvé les six scripts
`Linux/System` par l'exécution. **Reproduits et confirmés indépendamment par le
rédacteur des tests puis par le relecteur.**

Aucun n'a été corrigé : l'`out_of_scope` de TASK-004 l'interdisait, et ajouter
des assertions rouges aurait fait échouer une validation sans qu'aucune
correction soit permise — l'agent se serait auto-bloqué.

## Les quatre défauts

**1. `configure-swap.sh --file` sans valeur : code 1, message hors convention**

```text
configure-swap.sh: line 57: 1: --file attend un chemin      code=1
```

`FICHIERS_SWAP="${1:?--file attend un chemin}"` produit un message sans préfixe
`[ERROR]` et sort en 1. C'est une erreur d'usage : le dépôt lui réserve le
code 2.

**2. Codes incohérents pour une valeur d'argument invalide**

| Appel | Code |
|---|---|
| `configure-swap.sh 12X` | **2** |
| `configure-timezone.sh Zone/Inexistante` | **1** |

`configure-swap.sh` appelle `die … 2`, les autres `die` sans code — donc 1.

Nuance relevée par le relecteur : `configure-hostname.sh -mauvais-` rend 2, mais
parce que le tiret initial le fait basculer sur « Option inconnue ». L'exemple
d'origine était mal choisi ; l'incohérence, elle, existe bien.

**3. Le `trap ERR` double le diagnostic**

```text
[ERROR] Taille invalide : abc
[ERROR] Échec (code 2) à la ligne 143 de configure-swap.sh.
```

`die` est appelé depuis `en_megaoctets`, à l'intérieur d'une substitution de
commande : le `trap ERR` de `lib/common.sh` se déclenche et redouble le message.

Le `trap` lui-même est dans le socle, **zone protégée**. La correction doit venir
du script appelant, pas de `common.sh`.

**4. `configure-hostname.sh` sans nom déverse son aide sur `stderr`**

28 lignes, dans lesquelles le diagnostic réel se perd. `show_help >&2` suivi
d'une sortie en 2.

## Ce qui manque avant de corriger

**La convention « erreur d'usage → 2 » n'est écrite nulle part.** Elle
s'observe dans le code, elle se déduit des messages, mais aucun document ne
l'énonce.

Un autre écart connexe a été relevé lors de TASK-011 : `require_root` sort en 1,
pas en 2 — ce qui est cohérent sur les cinq scripts et conforme à
`lib/common.sh`, mais contredit la convention supposée. Le refus de privilège
est-il une erreur d'usage ? La question mérite d'être tranchée avant
d'uniformiser quoi que ce soit.

Inscrire la règle retenue quelque part fait donc partie du travail — sans quoi
la prochaine tâche la redécouvrira.

## Verrouiller les corrections

Les comportements corrigés doivent être **épinglés par des assertions** dans
`tests/integration/linux-system.test.sh`. Sans cela, rien n'empêche la dérive de
revenir : c'est exactement ce qui s'est passé pour la dette `shellcheck`, restée
invisible depuis les premiers commits faute d'un contrôle qui la voie.
