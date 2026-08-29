---
description: Exécute une tâche du backlog de bout en bout — plan, code, tests, relecture, rapport
argument-hint: <TASK-XXX>
---

Exécute la tâche **$1** du backlog, du début à la fin.

C'est l'enchaînement complet. Suis-le dans l'ordre, sans en sauter d'étape.

---

## 1. Charger le contexte

- lis `AGENTS.md` — le contrat de travail ;
- lis la tâche `$1` dans `tasks/pending/`, `tasks/active/` ou `tasks/blocked/` ;
- si le fichier n'existe pas : arrête-toi et dis-le.

## 2. Vérifier qu'elle est exécutable

Refuse et explique pourquoi si :

- son `status` n'est pas `ready` ;
- une de ses `depends_on` n'est pas dans `tasks/completed/` ;
- son `human_approval_required` est `true` et l'accord n'a pas été donné dans la
  conversation ;
- l'environnement qu'elle réclame est indisponible — pour `container-debian`,
  vérifie que le démon Docker répond, et **arrête-toi s'il ne répond pas**. Ne
  remplace jamais une validation comportementale par une analyse statique en la
  présentant comme équivalente ;
- l'arbre Git n'est pas propre. Ne remise rien, ne supprime rien : signale.

## 3. Préparer

- `git status` pour constater l'état de départ ;
- crée la branche `agent/$1` depuis `master`, sauf si elle existe déjà ;
- déplace le fichier de tâche dans `tasks/active/` et passe son `status` à
  `in_progress`.

## 4. Planifier

Établis un plan court : fichiers à créer ou modifier, ordre des opérations,
validations à lancer. Annonce-le avant d'agir.

Si le plan sort du `scope` de la tâche, **arrête-toi**. Le périmètre ne
s'élargit pas en cours de route.

## 5. Rédiger

Délègue au sous-agent **`redacteur-script`** : script et documentation.

Passe-lui la tâche entière, il ne connaît pas la conversation.

## 6. Tester

Délègue au sous-agent **`redacteur-tests`** : tests du travail produit.

Passe-lui la tâche et ce qu'a produit l'étape précédente.

## 7. Valider et relire

Délègue au sous-agent **`relecteur`**. Il est en lecture seule : il constate,
il ne répare pas.

**Selon son verdict :**

- **CONFORME** → étape 8 ;
- **NON CONFORME** → boucle de correction ci-dessous ;
- **cinq tentatives atteintes** → la tâche est bloquée, va directement à
  l'étape 8 avec le statut `blocked`.

### Boucle de correction

```text
verdict NON CONFORME
        ↓
diagnostic : QUI a tort, le script ou le test ?
        ↓
   ┌────┴────┐
script      test
   ↓          ↓
redacteur   redacteur       ← on redélègue, on ne bricole pas soi-même
-script     -tests
   └────┬────┘
        ↓
    relecteur     tentative += 1
        ↓
  CONFORME ? → étape 8    sinon, on reboucle
        ↓
  5 tentatives → BLOCKED
```

### Le diagnostic, avant toute correction

Un test qui échoue a deux causes possibles. **La présomption est que le script
est fautif** — c'est lui qu'on teste.

Tu ne modifies un test que si tu peux dire précisément en quoi il est faux :
il vérifie autre chose que le critère d'acceptation, il se trompe de commande,
il attend un comportement que la tâche ne demande pas, ou il dépend de
l'environnement au lieu du script.

**Écris ce diagnostic dans le rapport, à chaque tentative.** « J'ai modifié le
test » sans justification est un aveu, pas une correction.

### Qui corrige

Redélègue au sous-agent concerné plutôt que de corriger toi-même :

- défaut dans le script ou sa documentation → **`redacteur-script`** ;
- défaut dans un test → **`redacteur-tests`**, avec le diagnostic ci-dessus ;
- défaut dans le backlog, un lien, un statut → tu le corriges directement.

Passe-lui le verdict complet du relecteur : il n'a pas suivi la conversation.

### Règles de la boucle

- corrige la cause, jamais le symptôme ;
- **ne neutralise jamais un test ni une validation pour obtenir un verdict
  favorable** — ni `|| true`, ni `set +e`, ni assertion commentée, ni validation
  retirée de la tâche. Cela vaut échec, quel que soit le verdict obtenu ensuite ;
- deux tentatives donnant la même erreur signalent un diagnostic faux : change
  d'hypothèse plutôt que de répéter la correction ;
- si la correction nécessaire sort du périmètre, bloque la tâche au lieu de
  l'élargir ;
- si le relecteur révèle un défaut dans `lib/common.sh`, **ne le corrige pas** :
  c'est une zone protégée. Consigne-le et bloque, ou crée une tâche.

## 8. Rendre compte

Écris `tasks/reports/$1-report.md` au format de `tasks/README.md` §6.

Le rapport consigne **les faits observés** : les commandes réellement lancées,
leurs vrais codes de retour, les validations réellement exécutées. Une commande
non lancée n'y figure pas. Une validation en échec n'y est pas présentée comme
réussie. Une réserve se dit.

## 9. Clore

- déplace le fichier de tâche vers `tasks/completed/` ou `tasks/blocked/`, et
  mets son `status` en cohérence ;
- mets à jour le tableau de `tasks/backlog.md`, y compris la section « Terminé »
  et les tâches que celle-ci débloque en `ready` ;
- `git add` et `git commit` sur la branche `agent/$1`, message conventionnel en
  français, avec la ligne `Tâche : $1` ;
- **jamais de `git push`, jamais de fusion, jamais de commit sur `master`** ;
- `git status` final.

## 10. Résumer

En quelques lignes : ce qui a été fait, ce qui a été prouvé, ce qui reste en
suspens, et la prochaine tâche prête.

---

**En cas de blocage à n'importe quelle étape**, arrête-toi et présente :
pourquoi l'intervention est nécessaire, ce qui a été tenté, ce qui bloque
exactement, quelle décision est attendue, et les conséquences de chaque option.

Une question à laquelle Maxime peut répondre en une phrase — pas un appel à
reprendre les commandes.
