---
description: Transforme une section du plan de refactorisation en tâches exécutables, prêtes à être lancées
argument-hint: <domaine|section> — ex. « Linux/Security » ou « plan §2 »
---

Atomise **$1** : transforme les entrées d'index de cette section du plan en
fichiers de tâche exécutables.

---

## 1. Cadrer le lot

- lis `docs/refactorisation-plan.md` pour la section visée ;
- lis `tasks/backlog.md` §2 pour les entrées d'index correspondantes ;
- lis `docs/agent/decisions/ADR-0003-cadrage-execution-autonome.md` : il a
  tranché les cibles, la politique de sécurité, les codes de retour et la
  notification des échecs. Rien de tout cela ne se redemande ;
- constate ce qui existe déjà dans le domaine : un script présent ne se réécrit
  pas, il se complète ou se laisse tranquille.

**Un lot = un domaine.** Pas deux, pas le plan entier. Si le domaine compte plus
de sept scripts, découpe-le et annonce le découpage.

## 2. Ordonner

Au sein du domaine — ADR-0003, décision 16 :

```text
lecture seule  →  modifie le système  →  destructif
```

Les scripts en lecture seule d'abord : ils prouvent le domaine sans rien casser,
et ce qu'ils apprennent sert aux suivants.

## 3. Déléguer

Délègue au sous-agent **`redacteur-tache`**. Il démarre à froid : donne-lui le
domaine, la section du plan, les identifiants disponibles et l'ordre retenu.

Un fichier de tâche par script, dans `tasks/pending/`.

## 4. Vérifier avant d'ouvrir

Pour chaque tâche produite, contrôle toi-même :

- le frontmatter respecte le sous-ensemble YAML de `tasks/README.md` §2 ;
- `out_of_scope` n'est pas vide ;
- `validation` ne contient que des commandes exécutables telles quelles, et
  porte `tests/run.sh lint` si la tâche touche un `.sh` ;
- `acceptance_criteria` énonce des faits observables, pas des intentions ;
- `depends_on` ne cite que des identifiants réels ;
- `environment` est `container-systemd` dès qu'il est question de `systemctl`,
  `timedatectl` ou `hostnamectl`.

Une tâche qui ne passe pas ce contrôle est corrigée avant d'être ouverte, pas
après.

## 5. Ouvrir

ADR-0003, décision 3 : l'ouverture t'est déléguée.

- passe en `ready` les tâches dont le périmètre et les validations tiennent
  debout et dont les dépendances sont satisfaites ;
- laisse en `pending` celles qui attendent une autre tâche du lot ;
- mets à jour le tableau de `tasks/backlog.md`, retire les entrées d'index
  devenues des tâches, et avance « Prochain identifiant libre ».

## 6. Commiter

Branche `agent/atomisation-<domaine>`, message `chore(tasks):`, puis fusion dans
`master` comme pour une tâche ordinaire. Pas de push : il vient en fin de
domaine, une fois les scripts écrits.

## 7. Rendre compte

Un tableau : identifiant, titre, statut, dépendances, environnement. Puis la
première tâche à lancer.

Et enchaîne : lance `/tache` sur cette première tâche sans demander
confirmation.
