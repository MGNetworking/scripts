---
description: Consigne d'un agent exécutant — écrire, tester, corriger, s'arrêter (orchestration/README.md)
argument-hint: <TASK-XXX> [RETOURS-TASK-XXX.md]
---

Tu es un **agent exécutant**. Un orchestrateur t'a confié la tâche **$1** et
reprendra ton travail derrière toi. Tu travailles seul, sans interlocuteur :
personne ne répondra à une question.

## 1. Lire, une fois chacun

- `tasks/active/$1.md` — la fiche : objectif, `scope`, `out_of_scope`, critères ;
- `lib/common.sh` et `tests/lib/assert.sh` ;
- un script existant de même nature que celui à écrire, et son fichier de cas
  dans `tests/integration/` — c'est ton modèle de forme et de longueur ;
- si un second argument est donné (`$2`) : ce fichier porte les défauts relevés
  par la relecture. **Corrige-les, ne touche à rien d'autre.** Ces retours
  lèvent le figement du fichier de cas (§3) pour les seuls points qui le visent ;
  commite-les en `fix: retours de relecture ($1)`, qui devient le nouveau point
  de figement.

`CLAUDE.md` est déjà chargé. Ne parcours pas le reste du dépôt.

## 2. Écrire

- uniquement les fichiers du `scope` de la fiche : le script, son fichier de
  cas, un éventuel `config/*.env.example` ;
- jamais les README, `tasks/`, `docs/`, `lib/`, `CLAUDE.md` — ils sont à
  l'orchestrateur ;
- **150 lignes au plus par script et par fichier de cas.** Pas de bandeaux de
  section, pas de commentaire qui répète le code : un commentaire ne dit que ce
  que le code ne dit pas seul. L'aide `--help` tient en une vingtaine de lignes.

**Avant de commiter, compte** : `wc -l <script> <fichier de cas>`. Au-delà de
150, raccourcis d'abord — commentaires, aide, code en double. Si un fichier
dépasse encore, garde-le, et donne la raison en une phrase sur la ligne de
verdict.

Puis `git add` de ces fichiers seulement, et `git commit -m "feat: premier jet ($1)"`.

## 3. Tester et corriger — 3 passages au plus

```bash
bash orchestration/outils/juger.sh tasks/active/$1.md
```

Code 0 : terminé. Sinon, lis les lignes `FAIL` et corrige **le script**.

- **Le fichier de cas ne perd jamais une vérification.** Tant que le juge n'a
  jamais rendu PASSE, tu peux corriger une erreur de CONSTRUCTION du test —
  directive shellcheck mal placée, outil manquant dans un PATH restreint, faux
  binaire qui répond mal — en écrivant la raison dans le message de commit
  (`test: …`). Tu ne retires, n'affaiblis ni ne commentes aucune assertion.
  Après le premier PASSE, ou après le commit des retours de relecture (§1), le
  fichier est figé. L'orchestrateur compte les assertions et lit chaque diff.
- Après chaque correction, relance le juge et commite (`fix: passage N ($1)`).
- **Arrête-toi** si le nombre de lignes `FAIL` ne baisse pas d'un passage au
  suivant, ou après le troisième passage.
- Ne neutralise jamais une vérification : ni `|| true`, ni `set +e`, ni
  désactivation `shellcheck` sans justification écrite sur la ligne.

## 4. Rendre la main

Termine par une seule ligne, sans autre commentaire :

```text
VERDICT PASSE|ECHEC — passages N — FAIL restants K — lignes S + C [— raison du dépassement]
```
