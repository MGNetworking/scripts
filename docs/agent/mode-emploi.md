# Mode d'emploi — travailler avec les agents

Ce document s'adresse **à Maxime**, pas à l'agent.

Tous les autres documents de la couche agentique sont des consignes destinées
aux agents : [AGENTS.md](../../AGENTS.md) est leur contrat,
[tasks/README.md](../../tasks/README.md) le format de leur travail,
`.claude/commands/tache.md` leur déroulé. Celui-ci dit comment vous, vous vous
en servez.

---

## 1. Les trois commandes

```text
/backlog              où en est le projet, quelle tâche prendre
/tache TASK-002       exécuter une tâche de bout en bout
```

C'est tout. Il n'y a pas de troisième commande à retenir.

Pour relire un compte rendu, ouvrez simplement le fichier :
`.agent/reports/TASK-002-report.md`.

## 2. Une séance type

```text
1.  /backlog
        → « TASK-002 est prête, TASK-003 attend TASK-002 »

2.  /tache TASK-002
        → l'agent travaille seul pendant plusieurs minutes :
          plan, script, tests, relecture, corrections, rapport, commit

3.  vous lisez le rapport et le diff
        → git diff master..agent/TASK-002

4.  si le travail vous convient :
        git switch master
        git merge agent/TASK-002

5.  retour au point 1
```

**Vous n'êtes pas dans la boucle pendant une tâche. Vous l'êtes entre deux.**

C'est le rythme de travail à accepter : vous lancez, vous vaquez, vous revenez
juger sur pièces.

## 3. Ce que fait l'agent, ce que vous faites

| | Agent | Vous |
|---|---|---|
| choisir la tâche à lancer | — | **vous** |
| écrire le script et sa doc | agent | — |
| écrire les tests | agent | — |
| valider, corriger, revalider | agent | — |
| commiter sur `agent/TASK-xxx` | agent | — |
| **fusionner dans `master`** | — | **vous** |
| **pousser sur GitHub** | — | **vous** |
| décider qu'une tâche est prête | **vous** | — |
| trancher une tâche bloquée | — | **vous** |

L'agent ne fusionne jamais et ne pousse jamais. Ces deux gestes vous
appartiennent, définitivement.

## 4. Ajouter du travail au backlog

Le backlog n'est pas figé. Deux façons d'y ajouter une tâche.

**En la demandant en conversation** — « ajoute une tâche pour écrire
`check-disk.sh` ». L'agent l'écrit au format attendu et l'ajoute à l'index.

**En l'écrivant vous-même** — copiez un fichier de `tasks/pending/` et adaptez.
Le format est décrit dans [tasks/README.md](../../tasks/README.md) §2.

Dans les deux cas, **c'est vous qui la passez en `ready`**. Une tâche `pending`
n'est jamais prise. C'est votre point de contrôle sur ce que l'agent s'autorise
à faire.

Le champ qui compte le plus est `out_of_scope` : c'est lui qui empêche le
travail de déborder.

## 5. Quand une tâche se bloque

L'agent s'arrête après cinq tentatives de correction, ou dès qu'il rencontre une
décision qui ne lui appartient pas.

Le rapport contient alors :

```text
Pourquoi l'intervention est nécessaire
Ce qui a déjà été tenté
Ce qui bloque exactement
Quelle décision est attendue
Les conséquences de chaque option
```

**Vous répondez en une phrase**, en conversation. Vous n'avez pas à reprendre
les commandes ni à relire tout le travail.

Le fichier de tâche est dans `tasks/blocked/`. Une tâche bloquée n'est jamais
reprise automatiquement : c'est vous qui la relancez, une fois la décision
prise.

## 6. Ce qu'il faut regarder avant de fusionner

Le rapport est écrit par l'agent : lisez-le, mais ne vous y fiez pas seul.

Trois vérifications valent le coup d'œil :

1. **le diff** — `git diff master..agent/TASK-xxx`. Des fichiers touchés hors du
   périmètre annoncé ? C'est le signal le plus parlant ;
2. **les validations** — le rapport dit-il `PASS`, ou `NON EXÉCUTÉ` présenté
   comme un succès ? Un `NON EXÉCUTÉ` est légitime, un `NON EXÉCUTÉ` déguisé ne
   l'est pas ;
3. **les tests** — cherchez un `|| true`, un `set +e`, une assertion commentée.
   C'est la façon la plus commode de faire passer un travail défectueux, et
   c'est explicitement interdit par le contrat.

Si quelque chose vous gêne, dites-le en conversation plutôt que de corriger
vous-même : le défaut vient souvent d'une règle mal formulée dans
`.claude/agents/`, et la corriger là profite à toutes les tâches suivantes.

## 7. Ce que l'agent ne fera jamais

- fusionner ou pousser ;
- commiter sur `master` ;
- exécuter un script d'administration sur votre machine ou sur un serveur réel —
  tout passe par un conteneur jetable ;
- toucher à `CLAUDE.md`, `config/*.env`, `.git/`, `logs/` ;
- modifier `lib/common.sh` en effet de bord d'une autre tâche ;
- versionner un secret ;
- déclarer réussie une validation qu'il n'a pas lancée.

Ces interdits sont écrits dans [AGENTS.md](../../AGENTS.md) §5, §8 et §16.

## 8. Où est quoi

| Vous cherchez | Fichier |
|---|---|
| comment m'en servir | **ce document** |
| comment ça fonctionne | [comprendre-agent.md](comprendre-agent.md) |
| l'état du travail | `tasks/backlog.md`, ou `/backlog` |
| une tâche précise | `tasks/<état>/TASK-xxx.md` |
| ce qu'a fait l'agent | `.agent/reports/TASK-xxx-report.md` |
| les règles imposées à l'agent | `AGENTS.md` |
| les conventions d'écriture des scripts | `CLAUDE.md` |
| le déroulé d'une tâche | `.claude/commands/tache.md` |
| le rôle de chaque sous-agent | `.claude/agents/*.md` |
| pourquoi telle décision | `docs/agent/decisions/` |
| lancer les validations à la main | `tests/run.sh` |

## 9. Limites connues

**Une tâche à la fois.** Il n'y a pas d'enchaînement automatique. C'est un choix
— voir [ADR-0002](decisions/ADR-0002-claude-code-comme-moteur.md) : une boucle
non surveillée épuise vite les limites d'un abonnement Pro, et les premières
exécutions révèlent toujours des règles mal formulées.

**Docker doit tourner** pour toute tâche dont l'environnement est
`container-debian`. Si le démon est arrêté, l'agent s'arrête au lieu de
prétendre valider.

**`shellcheck` est absent de la machine.** Le lint ne vérifie donc que la
syntaxe et l'annonce à chaque exécution. L'installer améliorerait nettement la
qualité du contrôle :

```bash
winget install koalaman.shellcheck
```

**Les sous-agents ne se souviennent de rien.** Chacun démarre sans connaître la
conversation. Tout ce qu'il doit savoir est dans la tâche et dans `AGENTS.md` —
c'est pourquoi une tâche mal écrite produit un travail à côté.

## 10. Si le résultat ne vous convient pas

Le réflexe naturel est de corriger le travail produit. Le bon réflexe est de
corriger **la règle qui a permis ce travail**.

| Symptôme | Où agir |
|---|---|
| le script ne suit pas les conventions | `.claude/agents/redacteur-script.md` |
| les tests sont superficiels | `.claude/agents/redacteur-tests.md` |
| la relecture laisse passer des défauts | `.claude/agents/relecteur.md` |
| l'agent déborde du périmètre | le champ `out_of_scope` de la tâche |
| le déroulé lui-même est bancal | `.claude/commands/tache.md` |

Ces fichiers sont du Markdown ordinaire. Vous pouvez les modifier vous-même, ou
le demander en conversation.
