---
id: TASK-014
title: "Affranchir la suite d'acceptation de l'état d'implémentation du dépôt"
status: completed
priority: high
depends_on:
  - TASK-003
environment: host
human_approval_required: false
objective: |
  Une assertion de TASK-012 encode l'absence du niveau unit comme un invariant.
  TASK-003 l'implémente, l'assertion devient fausse, et tout le niveau acceptance
  passe au rouge. Rendre la vérification indépendante de ce que le dépôt
  contient à un instant donné.
scope:
  - tests/acceptance/TASK-012-semantique-codes.sh — l'assertion de la ligne 425 environ
out_of_scope:
  - toute autre assertion du fichier
  - tests/run.sh, run-acceptance.sh, le niveau unit
  - la sémantique des codes elle-même, fixée par TASK-012
acceptance_criteria:
  - tests/run.sh acceptance sort en 0 sur le dépôt courant
  - la vérification du comportement « niveau non implémenté rend 3 » subsiste — elle n'est pas supprimée mais reformulée
  - la vérification ne dépend plus de l'état d'implémentation d'un niveau particulier du dépôt
  - implémenter un niveau supplémentaire ne fait plus échouer la suite
  - le cas ne déclenche plus l'exécution d'une suite complète, ce que son propre commentaire disait vouloir éviter
validation:
  - "tests/run.sh lint"
  - "tests/run.sh acceptance"
implementation_notes:
  - partir d'une branche contenant le travail de TASK-003, sans quoi le niveau unit n'existe pas et la correction ne peut pas être vérifiée
  - le bac à sable du fichier permet déjà de fabriquer un niveau absent sans dépendre du dépôt réel
  - les niveaux integration et environment sont encore non implémentés, mais s'y adosser ne ferait que déplacer le piège
---

# TASK-014 — Une assertion qui teste un état, pas un comportement

## Origine

Relevée par le relecteur de [TASK-003](../completed/TASK-003.md), qui l'a mesurée :

```text
tests/acceptance/TASK-012-semantique-codes.sh:425
  assert_code 3 "tests/run.sh unit sur le dépôt réel → 3 (niveau non implémenté)"
  → obtenu 0
tests/run.sh acceptance → 1
```

## Le défaut de conception

L'assertion voulait vérifier un **comportement** : un niveau non implémenté rend
3. Elle l'a fait en s'appuyant sur un **état** : à cette date, `unit` n'existait
pas.

TASK-003 n'a rien cassé — elle a rendu l'assertion obsolète. C'est la différence
entre un test qui vérifie ce que fait le harnais et un test qui photographie ce
que le dépôt contenait ce jour-là.

Le même piège attend `integration` et `environment` : s'adosser à eux ne ferait
que le déplacer de quelques semaines.

## Pourquoi c'est urgent

**Le dépôt est rouge tant que ce point n'est pas traité.** `tests/run.sh
acceptance` sort en 1 sur la branche de TASK-003, et sortira en 1 sur `master`
dès que ce travail y sera fusionné.

## Une contrainte d'ordre

Cette tâche ne peut pas être vérifiée sur `master` en l'état : le niveau `unit`
n'y existe pas encore, et l'assertion corrigée y échouerait en sens inverse.

Elle doit donc partir d'une branche contenant TASK-003 — ou être menée après sa
fusion, en acceptant que `master` reste rouge entre les deux.
