# tasks/ — backlog exécutable

Ce répertoire est la **source de vérité du travail de l'agent**. Une tâche = un
fichier. La commande `/tache` ne lit rien d'autre pour savoir quoi faire.

Il ne remplace pas [docs/refactorisation-plan.md](../docs/refactorisation-plan.md),
qui reste le document de conception du chantier : le plan explique *ce que doit
faire* chaque script et *pourquoi* ; les tâches d'ici définissent *ce qui est à
faire maintenant*, *comment le prouver* et *où on en est*.

---

## 1. Organisation

```text
tasks/
├── README.md      ce document
├── backlog.md     index de toutes les tâches, y compris non atomisées
├── pending/       tâches écrites, pas encore prêtes ou en attente de dépendance
├── active/        tâche en cours — au plus une à la fois
├── completed/     tâches terminées et validées
├── blocked/       tâches interrompues, en attente d'une décision humaine
├── cancelled/     tâches abandonnées, conservées pour mémoire
└── reports/       un rapport d'exécution par tâche terminée ou bloquée
```

Le fichier se **déplace** d'un répertoire à l'autre au fil du cycle de vie ; son
nom ne change jamais.

Il y a sept statuts pour cinq répertoires : le répertoire dit **l'étape**, le
champ `status` dit **la précision**.

| Répertoire | Statuts qu'il accueille |
|---|---|
| `pending/` | `pending`, `ready` |
| `active/` | `in_progress`, `validating` |
| `completed/` | `completed` |
| `blocked/` | `blocked` |
| `cancelled/` | `cancelled` |

Un fichier dont le `status` ne figure pas dans la colonne de droite de son
répertoire est une incohérence à signaler. **Ne créez pas de répertoire
supplémentaire pour rétablir une correspondance exacte** : `ready` et
`in_progress` sont des états trop brefs pour justifier un déplacement de plus.

### Atomisation progressive

Le plan de refactorisation décrit une cinquantaine de scripts. Écrire
cinquante fichiers de tâche d'avance produirait un backlog obsolète avant
d'être utile.

Règle : **une entrée du plan devient un fichier de tâche lorsqu'elle entre dans
l'horizon de travail.** Tant qu'elle n'y est pas, elle figure dans
[backlog.md](backlog.md) comme ligne d'index avec un renvoi vers sa section du
plan. Une ligne d'index n'est jamais sélectionnable par `/tache`.

---

## 2. Format d'un fichier de tâche

`pending/TASK-001.md` — un frontmatter YAML délimité par `---`, suivi d'un corps
Markdown libre.

Le frontmatter porte tout ce qui doit être lu sans ambiguïté. Le corps porte ce
qu'un humain ou un modèle doit comprendre : contexte, pièges, références.

```markdown
---
id: TASK-001
title: "Titre court à l'infinitif"
status: pending
priority: high
depends_on: []
environment: host
human_approval_required: false
objective: |
  Description précise du résultat attendu, en une phrase ou deux.
  Ce qui doit être vrai une fois la tâche terminée.
scope:
  - fichier ou comportement inclus
  - fichier ou comportement inclus
out_of_scope:
  - ce qui est explicitement exclu
acceptance_criteria:
  - critère fonctionnel, observable
  - critère fonctionnel, observable
validation:
  - "commande exacte à exécuter"
  - "commande exacte à exécuter"
implementation_notes:
  - contrainte connue à respecter
---

# TASK-001 — Titre

Corps libre : contexte, décisions déjà prises, pièges identifiés, liens.
```

### Sous-ensemble YAML autorisé

Le frontmatter est volontairement pauvre : il doit se lire d'un coup d'œil et
ne prêter à aucune interprétation. Un champ ambigu produit un travail à côté de
la demande.

- `clé: valeur` scalaire, avec ou sans guillemets ;
- listes de scalaires, un `  - élément` par ligne ;
- blocs littéraux `clé: |` suivis de lignes indentées ;
- pas d'imbrication, pas de listes d'objets, pas d'ancres, pas de listes
  en ligne `[a, b]` — sauf `depends_on: []` vide.

### Champs

| Champ | Obligatoire | Valeurs |
|---|---|---|
| `id` | oui | `TASK-` suivi de trois chiffres, stable et jamais réutilisé |
| `title` | oui | court, à l'infinitif, en français |
| `status` | oui | voir §3 |
| `priority` | oui | `high` `medium` `low` |
| `depends_on` | oui | liste d'`id`, `[]` si aucune |
| `environment` | oui | `host` `container-debian` `container-systemd` |
| `human_approval_required` | oui | `true` `false` |
| `objective` | oui | bloc littéral |
| `scope` | oui | liste |
| `out_of_scope` | oui | liste — vide interdit : dire ce qu'on ne fait pas est le meilleur garde-fou contre l'élargissement |
| `acceptance_criteria` | oui | liste |
| `validation` | oui | liste de commandes exécutables telles quelles |
| `implementation_notes` | non | liste |
| `blocked_reason` | si `blocked` | bloc littéral |
| `attempts` | non | entier, tenu pendant l'exécution |

---

## 3. Statuts

```text
pending      écrite, pas encore prête (dépendance, décision, périmètre à figer)
ready        prête à être sélectionnée
in_progress  planifiée et en cours d'exécution
validating   implémentation faite, validations en cours
completed    validations réussies, review passée, rapport produit
blocked      interrompue, décision humaine attendue
cancelled    abandonnée, conservée pour l'historique
```

Transitions normales :

```text
pending → ready → in_progress → validating → completed
                       ↑             ↓
                       └─── (correction, MAX_RETRIES = 5)
                                     ↓
                                  blocked
```

`pending → ready` est un acte **humain ou explicitement délégué** : c'est le
moment où l'on constate que le périmètre et les validations tiennent debout.
L'agent ne se donne pas du travail à lui-même.

`blocked` n'est jamais repris automatiquement.

---

## 4. Règles de sélection

Une tâche n'est prise par `/tache` que si :

1. son `status` est `ready` ;
2. toutes ses `depends_on` sont `completed` ;
3. son `human_approval_required` est `false`, ou l'accord a été donné ;
4. l'environnement qu'elle réclame est disponible.

Départage, dans l'ordre : `priority`, puis ordre d'apparition dans
[backlog.md](backlog.md).

Une seule tâche dans `active/` à la fois.

---

## 5. Distinction critères d'acceptation / validation

Les deux notions ne se confondent pas.

**`acceptance_criteria`** décrit ce qui doit être vrai — le contrat fonctionnel,
lisible par un humain :

```text
- le script installe le fichier /etc/cron.d/mgnetworking
- une seconde exécution ne modifie rien
- le script refuse de s'exécuter sans privilège root
```

**`validation`** décrit comment le démontrer — des commandes, avec un code de
retour :

```text
- "shellcheck Linux/System/configure-cron.sh"
- "bash -n Linux/System/configure-cron.sh"
- "tests/run.sh integration configure-cron"
```

Une validation qui n'a pas été exécutée vaut `NON EXÉCUTÉ`, jamais `PASS`.
Une tâche dont une validation échoue n'est pas terminée, quelle que soit
l'apparente qualité du code produit.

### Une validation doit être satisfaisable

Cette règle a manqué deux fois, et a bloqué deux tâches dont le travail était
bon. Elle tient en deux points.

**Une validation ne porte que sur le périmètre de la tâche.** Écrire
`tests/run.sh lint` — qui analyse tout le dépôt — pour une tâche dont le `scope`
compte trois fichiers, c'est la faire dépendre de l'état de fichiers qu'elle ne
touche pas. La moindre dette antérieure la bloque. C'est arrivé à TASK-002.

**Une validation doit pouvoir réussir dans l'`environment` déclaré.** Exiger le
vert d'une suite qui comporte des cas inaccessibles à cet environnement, c'est
écrire une exigence qu'aucun travail ne peut satisfaire. C'est arrivé à
TASK-011, dont la suite sautait sept cas faute de `systemd`.

Avant de passer une tâche en `ready`, poser la question : **si le travail était
parfait, cette commande sortirait-elle en 0 ?** Si la réponse n'est pas un oui
franc, la validation est mal écrite.

Corriger une validation défectueuse relève de celui qui écrit le backlog, jamais
de l'agent qui exécute la tâche. Un agent qui modifie sa propre validation pour
la faire passer neutralise le contrôle ; celui qui donne le travail corrige une
exigence fautive. La distinction n'est pas de forme.

---

## 6. Format du rapport

Un rapport par tâche terminée ou bloquée, dans `tasks/reports/TASK-042-report.md`.

```markdown
# TASK-042 — Rapport d'exécution

## Statut
COMPLETED

## Objectif
...

## Travail réalisé
- ...

## Fichiers modifiés
- ...

## Commandes exécutées
| Commande | Code | Durée |
|---|---|---|

## Validations
| Validation | Résultat |
|---|---|
| shellcheck … | PASS |

## Erreurs rencontrées
...

## Corrections automatiques
...

## Tentatives
1 / 5

## Critères d'acceptation
- [x] ...

## Validation finale
PASS

## Git
Branche : agent/TASK-042
Commit : <hash>

## Résumé
...
```

Pour une tâche bloquée, remplacer les trois dernières sections par :

```markdown
## Erreur finale
## Corrections tentées
## Cause probable
## Intervention humaine requise
## Prochaine action recommandée
```

Le rapport consigne les **faits observés**. Une commande non lancée ne figure
pas dans les commandes exécutées ; une validation en échec n'est pas présentée
comme réussie.

---

## 7. Créer une tâche

1. prendre le prochain `id` libre dans [backlog.md](backlog.md) ;
2. écrire le fichier dans `pending/` ;
3. remplir `out_of_scope` — c'est le champ le plus utile et le plus oublié ;
4. écrire les `validation` **avant** d'écrire le code : une tâche dont on ne
   sait pas formuler la preuve n'est pas prête ;
5. ajouter la ligne correspondante dans `backlog.md` ;
6. passer en `ready` seulement quand les points 3 et 4 tiennent.

Voir [AGENTS.md](../AGENTS.md) pour le contrat de travail complet.
