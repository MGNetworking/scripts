# tests/ — validations du dépôt

Ce répertoire porte la **preuve**. Tant qu'une commande d'ici n'a pas réussi,
rien n'est démontré : ni par la lecture du code, ni par la conviction d'un
modèle, ni par le fait que « ça a marché sur le serveur ».

Point d'entrée unique :

```bash
tests/run.sh              # tous les niveaux implémentés
tests/run.sh lint         # un niveau précis
tests/run.sh --liste      # ce qui existe et ce qui manque
```

Un seul point d'entrée, pour que la commande de validation inscrite dans une
tâche soit exactement celle qu'un humain tape.

---

## 1. Niveaux

| Niveau | Contenu | Environnement | État |
|---|---|---|---|
| `lint` | `bash -n` sur tous les `.sh`, `shellcheck` si disponible | hôte | **implémenté** |
| `unit` | fonctions de `lib/common.sh` | conteneur `debian` | à écrire — [TASK-003](../tasks/pending/TASK-003.md) |
| `integration` | exécution réelle, `--dry-run`, idempotence | conteneur `debian` | à écrire — [TASK-004](../tasks/pending/TASK-004.md) |
| `environment` | services, `systemctl`, état système | conteneur `systemd` | à écrire |
| `acceptance` | critères d'acceptation d'une tâche | selon la tâche | à écrire |

Un niveau s'ajoute en déposant son script au chemin annoncé par
`tests/run.sh --liste`. Aucune autre modification n'est nécessaire.

## 2. Codes de retour

| Code | Sens |
|---|---|
| 0 | tous les niveaux exécutés ont réussi |
| 1 | au moins un niveau a échoué |
| 2 | erreur d'usage — option ou niveau inconnu |
| 3 | un niveau demandé explicitement n'est pas implémenté |

Le code **3** est délibérément distinct de 0 et de 1. Sans lui,
`tests/run.sh unit` sortirait en 0 aujourd'hui et un validator conclurait que
les tests unitaires passent, alors qu'aucun n'existe. « Rien à exécuter » n'est
pas « tout va bien ».

C'est la traduction en code de retour de la règle d'[AGENTS.md](../AGENTS.md)
§10 : une validation non exécutée vaut `NON EXÉCUTÉ`, jamais `PASS`.

## 3. Analyse statique

```bash
tests/lint.sh                       # tout le dépôt
tests/lint.sh Linux/System/*.sh     # une sélection
tests/lint.sh --strict              # les scripts hérités deviennent bloquants
```

Deux contrôles de portées très inégales :

- **`bash -n`** ne vérifie que la syntaxe. Toujours disponible, il ne voit ni
  une variable non quotée, ni un `cd` sans garde, ni un `[ $a = $b ]` fragile.
  Le présenter comme une analyse complète serait trompeur ;
- **`shellcheck`** fait le vrai travail. Il est **absent de la machine de
  développement** : dans ce cas le résultat est annoncé `NON EXÉCUTÉ` et
  l'analyse ne prétend pas à l'exhaustivité.

Pour l'installer :

```bash
winget install koalaman.shellcheck     # Windows
sudo apt install shellcheck            # Debian, Ubuntu
```

Il est de toute façon présent dans l'image de test conteneurisée
([TASK-002](../tasks/pending/TASK-002.md)), qui reste la référence.

### Exclusions

`SC1090` et `SC1091` sont désactivés : `shellcheck` ne peut pas suivre
`source "$_dir/lib/common.sh"`, dont le chemin n'est résolu qu'à l'exécution.
C'est le mécanisme de chargement du dépôt, décrit dans
[docs/architecture-technique.md](../docs/architecture-technique.md) — pas un
défaut à corriger.

### Scripts hérités

`Synology/Plex/organize-series.sh` et `Synology/Plex/update-plex.sh` ne chargent
pas `lib/common.sh` et ne respectent pas les conventions. Leur mise au standard
est une tâche identifiée, pas un effet de bord d'un contrôle de routine.

**La tolérance dont ils bénéficient porte sur le style, jamais sur la syntaxe :**

| Problème détecté | Script courant | Script hérité |
|---|---|---|
| erreur de syntaxe (`bash -n`) | `ERROR`, bloquant | **`ERROR`, bloquant** |
| avertissement `shellcheck` | `ERROR`, bloquant | `WARN`, non bloquant |

Un script qui ne s'analyse plus est cassé, hérité ou non. Sans cette
distinction, l'un de ces fichiers pourrait devenir syntaxiquement invalide sans
que « 0 erreur » cesse de s'afficher — le contrôle mentirait.

Tant qu'ils passent `bash -n` et que `shellcheck` est absent de la machine, ces
deux fichiers s'affichent donc en `[SUCCESS]` comme les autres. Le `WARN`
n'apparaît qu'en cas de problème de style réellement détecté.

`--strict` supprime la tolérance et les rend bloquants sur tout, ce qui
permettra de constater le jour où ils seront à niveau.

## 4. Écrire un test

Les tests suivent les mêmes conventions que le reste du dépôt : en-tête en trois
lignes, chargement de `lib/common.sh`, messages préfixés, français.

Trois règles propres aux tests :

1. **un test qui ne peut pas s'exécuter le dit.** Il ne se contente jamais de
   passer silencieusement ;
2. **un test d'idempotence part d'un environnement neuf.** Un conteneur
   réutilisé entre deux exécutions invalide le résultat ;
3. **on ne corrige jamais un test pour le faire passer.** Neutraliser une
   assertion, ajouter `|| true` ou retirer `set -e` vaut échec de la tâche —
   voir [AGENTS.md](../AGENTS.md) §12.
