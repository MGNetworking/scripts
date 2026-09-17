# TASK-079 — Rapport d'exécution

## Compte rendu

Le 2026-09-17, tu as validé la proposition `docs/proposition-ansible-et-tests.md`. Cette tâche en fait une
règle du dépôt : la **décision 50**. Ansible installe et configure les machines. Bash
garde les diagnostics, l'exploitation ponctuelle et `Synology/`. Toute preuve dit son niveau :
simulé, conteneur ou machine. Une CI devient obligatoire.

**Autorisation.** `regles.md` §5 range `CLAUDE.md` en zone interdite. Le conducteur s'est
donc arrêté pour te demander ton accord. Tu l'as donné par l'intermédiaire de la session
orchestratrice, pour cette seule tâche et pour trois ajouts seulement : `Ansible/` dans
l'arborescence cible, la frontière entre Ansible et Bash, et les conventions minimales
d'un rôle. `CLAUDE.md` ne contient rien d'autre de nouveau.

**Ce qui a été écrit.**

- `orchestration/decisions.md` : nouvelle section G, avec la décision 50. Elle contient tes quatre
  réponses, le fonctionnement (poste WSL, `pipx`, `--check --diff` puis `--limit`,
  inventaire hors Git), le lien avec la décision 49 (contrat dans
  `meta/argument_specs.yml`, script remplacé mis en dépréciation) et le cadre de test. Elle
  précise aussi que le pilote se termine par un bilan comparatif et que toi seul décides de
  poursuivre. La **décision 43** (« pas de CI pendant le chantier ») contredisait la
  nouvelle règle : elle est retirée et ajoutée à la liste des numéros remplacés.
- `CLAUDE.md` : les trois ajouts autorisés.
- `orchestration/regles.md` §10 : comment valider un rôle, et les niveaux de preuve.
- `orchestration/architecture.md` §8 : quatre nouveaux contrôles, et un paragraphe sur les niveaux de preuve.
- `.claude/agents/relecteur.md` : le relecteur vérifie que le niveau de preuve est nommé,
  et contrôle la ligne `Prouvé par :` dans les cadrages qui l'ont.
- La proposition est supprimée. Aucun lien n'y renvoyait ; seuls le rapport et la fiche de
  TASK-078 la citent encore, en texte simple, comme trace du passé.

**Relecture.** Opus a rendu « fusionnable après corrections », avec deux défauts majeurs :

- `regles.md` exigeait une CI « verte avant tout push ». C'est impossible puisque la CI tourne au
  moment du push, et cela bloquait tout push avant TASK-080. La règle suit maintenant la
  décision : aucun push sur une CI rouge, une fois la CI posée.
- `CLAUDE.md` donnait l'impression que la répartition s'appliquait déjà. Il précise
  maintenant que les scripts Bash restent la référence jusqu'au bilan du pilote et à ta décision.

Trois défauts mineurs ont aussi été corrigés : les secrets pouvaient seulement passer par Vault,
`README.md` manquait dans la liste d'`Ansible/`, et une gravité avait été ajoutée au
relecteur sans que la décision la prévoie. Un quatrième, l'emploi mêlé de « Maxime » et de
« user », existait avant la tâche et n'a pas été touché.

**Coût.** Tâche menée par le conducteur, avec une relecture Opus de 32 777 jetons.

### Réserves

- La ligne A18 du registre cite toujours la décision 43, qui est retirée (A151).
- `regles.md` §8 n'autorise encore ni `pipx`, ni `ansible-lint`, ni `yamllint`, ni `molecule`,
  ni les conteneurs de Molecule. Il faut trancher ce point pour TASK-080 (A152).

## Statut

`completed`. TASK-080 passe en `ready`.

## Fichiers

- `orchestration/decisions.md` (décision 50 ajoutée, décision 43 retirée)
- `CLAUDE.md`, `orchestration/regles.md`, `orchestration/architecture.md`, `.claude/agents/relecteur.md`
- `docs/proposition-ansible-et-tests.md` (supprimé)

## Validations

| Commande | Code |
|---|---|
| `bash orchestration/outils/verifier-liens.sh` (branche, avant et après corrections) | 0 |
| `git diff --name-only master...agent/TASK-079` | 6 fichiers, tous dans le scope |
| `bash orchestration/outils/juger.sh tasks/active/TASK-079.md` | 1 : « aucun fichier de cas dans le périmètre » ; sans objet pour une tâche documentaire |
| `grep -rn proposition-ansible --include=*.md` | aucun lien ; texte simple seulement dans la fiche et le rapport de TASK-078 |

## Git

- `79e2d84` chore: TASK-079 en cours
- `4c224a6` docs(orchestration): décision 50, Ansible pour installer et configurer, cadre de test
- `d5fe75e` fix: retours de relecture (TASK-079)
- fusion `--no-ff` de `agent/TASK-079`, branche supprimée (aucune copie `script-agents` : travail dans le dépôt principal)
