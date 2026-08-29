# ADR-0002 — Claude Code comme moteur d'exécution

**Date** : 2026-08-28
**Statut** : accepté
**Décideur** : Maxime Ghalem
**Remplace** : [ADR-0001](ADR-0001-socle-agentique.md), décisions 1 et 3
**Conserve** : ADR-0001, décision 2 (conteneur Docker jetable)

---

## Contexte

Le plan de transformation initial décrivait la construction d'un système
agentique complet : orchestrateur, planner, executor, validator, machine à
états, couche d'outils, interface LLM et adaptateurs interchangeables.

Cette construction supposait d'écrire un programme — en Node — et de le
maintenir. Elle représentait un projet en soi, plus lourd que la bibliothèque de
scripts qu'elle devait servir.

Elle reposait aussi sur un besoin qui n'existe pas ici : l'abonnement disponible
est **Claude Code Pro**. Aucun autre fournisseur n'est accessible sur ce projet.
Construire une abstraction pour trois moteurs quand un seul est utilisable
revenait à payer un coût d'architecture pour une option inutilisable.

---

## Décision 1 — Le moteur est Claude Code

**Aucun code d'orchestration n'est écrit. Claude Code fournit la boucle, les
outils, l'exécution et les limites.**

Ce qui reste à produire n'est pas du code mais des **définitions en Markdown** :

| Élément | Emplacement | Nature |
|---|---|---|
| contrat de travail | `AGENTS.md` | déjà écrit, lu automatiquement |
| backlog | `tasks/` | déjà écrit |
| preuve | `tests/run.sh` | déjà écrit |
| sous-agents | `.claude/agents/*.md` | rôle, outils, règles |
| déclenchement | `.claude/commands/*.md` | enchaînement d'une tâche |

**Conséquence** : les tâches TASK-005 à TASK-008 perdent leur objet. Elles sont
annulées, non supprimées — leur contenu documente ce qui a été délibérément
écarté.

---

## Décision 2 — Trois sous-agents

| Sous-agent | Rôle | Écriture |
|---|---|---|
| `redacteur-script` | écrit le script et sa documentation | oui |
| `redacteur-tests` | écrit les tests du script | oui |
| `relecteur` | vérifie et lance les validations | **non** |

Le relecteur n'a pas le droit d'écrire. Il ne peut donc pas neutraliser une
assertion ni « réparer » un test pour le faire passer : il constate et rapporte.
C'est le garde-fou contre l'agent qui se donne une bonne note.

Trois rôles et pas davantage. Un découpage plus fin multiplierait les
transmissions de contexte sans rien apporter à un dépôt de scripts Bash.

---

## Décision 3 — Abandon du découplage multi-fournisseur

**Le projet ne construit aucune abstraction destinée à d'autres moteurs.**

Ce qui disparaît : `.agent/config/providers/`, `.agent/runtime/llm/`, les
adaptateurs, le format d'échange normalisé, le test de portabilité entre
fournisseurs.

Ce qui subsiste, sans effort particulier : `AGENTS.md` est un format ouvert,
lu par plusieurs outils du marché. Le backlog, les critères et les validations
restent de simples fichiers Markdown et Bash, indépendants de tout moteur. Un
autre agent pourrait reprendre ce dépôt — mais rien ne sera construit pour lui.

**Réversibilité** : moyenne. Revenir au multi-fournisseur demanderait d'écrire
l'orchestrateur écarté ici. Le backlog, les tâches, les tests et le contrat
resteraient en revanche utilisables tels quels : c'est la partie qui a de la
valeur, et elle est déjà indépendante.

---

## Ce qui reste de l'ADR-0001

**Décision 2 — conteneur Docker jetable** : inchangée. Les scripts se valident
dans un conteneur neuf, la machine hôte ne pouvant pas les exécuter.

**Décision 3 — Git** : l'intention est conservée — travail sur branche dédiée,
jamais de commit sur `master`, jamais de `git push`. L'exécutant change : c'est
Claude Code, sous le regard de Maxime, et non un programme autonome.

---

## Limite assumée

L'autonomie s'arrête au bord de la tâche. Les sous-agents travaillent sans
intervention **pendant** une tâche ; la main revient à Maxime **entre** deux
tâches.

Un enchaînement complet sans humain resterait possible par d'autres moyens.
Il n'est pas retenu aujourd'hui : sur un abonnement Pro, une boucle non
surveillée épuise les limites d'usage rapidement, et les premières exécutions
révèlent toujours des règles mal formulées.
