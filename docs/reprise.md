# Reprise — état du projet

Fichier de passation. Il dit **où en est le projet, ce qui vient ensuite, et comment
relancer la chaîne**, sans dépendre de la session qui l'a écrit. Mis à jour à la clôture
de chaque tâche qui change l'état d'ensemble. À supprimer quand la recette
`serveur-neuf.yml` sera livrée.

Dernière mise à jour : **2026-09-19**.

---

## 1. Où lire la suite

| Question | Fichier |
|---|---|
| Que construit-on, dans quel ordre | [docs/plan-outil-preparation-serveurs.md](plan-outil-preparation-serveurs.md) |
| Comment l'outil fonctionne, à hauteur d'utilisateur | [Ansible/GUIDE.md](../Ansible/GUIDE.md) |
| Qui exécute quoi, avec quels droits et à quel coût | [orchestration/architecture.md](../orchestration/architecture.md) |
| Ce que garantit chaque script et chaque rôle | `*/CADRAGE.md` (décision 49) |
| Ce que chaque tâche a réellement produit | `tasks/reports/TASK-XXX-report.md` |
| Les défauts connus, non corrigés | [tasks/pending/TASK-039.md](../tasks/pending/TASK-039.md) — registre, A01 à A184 |
| Les règles de conduite d'une tâche | [orchestration/regles.md](../orchestration/regles.md), [.claude/commands/tache.md](../.claude/commands/tache.md) |
| Les décisions en vigueur | [orchestration/decisions.md](../orchestration/decisions.md) — 50 décisions |

**Rien d'important ne vit dans une session** : tout ce qui a été décidé est dans ces
fichiers, et `master` est poussé sur GitHub.

## 2. État au 2026-09-19

**Livré et prouvé** — 51 scripts Bash testés en conteneur ; un cadrage par dossier, validé
par user ; le rôle Ansible `securite_base` avec son scénario Molecule ; l'outillage Ansible
exécutable en conteneur jetable, sans rien installer sur le poste ; une CI GitHub Actions
verte (lint, tests Bash, Ansible) ; l'outillage d'orchestration (`verifier-travail.sh`,
`clore-tache.sh`, `juger.sh` capable de juger une tâche documentaire).

**Les quatre dernières tâches**, qui ne figuraient pas dans la version précédente de ce
fichier :

| Tâche | Ce qu'elle a changé |
|---|---|
| TASK-093 | l'outillage sait conduire une tâche documentaire ; permissions des agents corrigées (A177, A178) |
| TASK-097 | `lancer-agent.sh` lit la clé d'API dans les variables utilisateur de Windows quand le harnais ne la transmet pas (`resoudre-cle.sh`) |
| TASK-098 | `orchestration/modeles/anthropic.env` porte **plusieurs modèles** — `haiku` (défaut), `sonnet`, `opus` — choisis par `--modele`, avec leurs tarifs ; `--dry-run` dit ce qui serait lancé sans rien dépenser |
| TASK-094 | `orchestration/architecture.md` porte enfin les vues d'exécution, de couches, le registre des agents et l'inventaire des capacités (ce qui est générique, ce qui est propre au dépôt). **Première tâche du dépôt conduite par l'API Anthropic**, et non par l'abonnement |

**Changement de régime, 2026-09-19** — l'abonnement est presque épuisé. Il fait tourner le
harnais lui-même ; **ce qui écrit et ce qui relit passe par l'API**, facturée à la clé :
`deepseek` pour écrire, `anthropic --modele haiku|sonnet|opus` pour conduire et relire. La
règle d'arbitrage, avec les tarifs relevés ce jour-là, est la §19 de
[regles.md](../orchestration/regles.md). Chaque lancement écrit son coût dans
`orchestration/mesures/agents.tsv` : l'arbitrage se tranche sur ces chiffres.

**Reste à faire, dans cet ordre**

1. **TASK-099** — rendre la relecture lançable par l'API, avec un interrupteur
   `orchestration/relecture.json` qui dit « api » ou « abonnement ».
2. **TASK-095** — extraire dans `orchestration/outils/lib-agents.sh` ce que
   `lancer-agent.sh` a de générique (inventaire : `architecture.md` §14).
3. Les rôles Ansible `socle`, `docker`, `k3s`, `kubernetes`, puis la recette
   `serveur-neuf.yml` et les fichiers de réglages. **Aucune fiche n'est encore écrite**
   pour eux ; le plan en donne le contenu, les critères et l'ordre. Une fiche s'écrit au
   format de [tasks/README.md](../tasks/README.md).

Le registre [TASK-039](../tasks/pending/TASK-039.md) reste `ready` en permanence : il passe
devant le reste quand une anomalie devient urgente, jamais sélectionné automatiquement.

**En attente de user** — le `--check --diff` sur une machine réelle (aucun serveur n'existe
encore) ; la décision de poursuivre la migration au-delà du pilote ; la suppression
éventuelle d'un script déprécié.

## 3. Relancer la chaîne

```bash
# 1. écrire la fiche de la tâche suivante dans tasks/pending/, d'après le plan
# 2. l'activer : status ready → in_progress, fiche vers tasks/active/, commit
# 3. lancer l'agent qui écrit, dans une copie isolée du dépôt
bash orchestration/outils/lancer-agent.sh deepseek TASK-XXX
#    ou, pour un modèle Anthropic facturé à la clé :
bash orchestration/outils/lancer-agent.sh anthropic TASK-XXX --modele haiku
#    --dry-run dit ce qui serait lancé, sans rien dépenser
# 4. vérifier sans croire l'agent sur parole
bash orchestration/outils/verifier-travail.sh TASK-XXX
# 5. faire relire par un modèle fort, une seule fois (TASK-099 : par l'API)
# 6. fusionner et clore
bash orchestration/outils/clore-tache.sh TASK-XXX --journal <fichier>
```

Une fiche dont le champ `agent` vaut `orchestrateur` ne se lance pas : la session crée
elle-même la branche `agent/TASK-XXX` et écrit. C'est le cas de tout ce qui touche
`orchestration/outils/`, interdit en écriture aux agents lancés
([limites.json](../orchestration/limites.json)).

Validation d'un rôle Ansible, sans rien installer sur le poste :

```bash
tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh
```

Validation des scripts Bash :

```bash
tests/env/run-in-container.sh -- tests/run.sh
```

## 4. Reprise par un autre harnais

**Ce qui est indépendant de tout outil d'IA** — les scripts Bash, les rôles Ansible, les
scénarios Molecule, le harnais de test, la CI, les cadrages, le backlog, le registre, les
décisions, les rapports. C'est l'essentiel du dépôt, et rien n'y suppose un modèle
particulier.

**Ce qui est lié à Claude Code**, et devra être adapté :

| Fichier | Ce qu'il fait | À faire pour un autre harnais |
|---|---|---|
| `orchestration/outils/lancer-agent.sh` | lance l'agent qui écrit, dans une copie isolée, et relève jetons, durée et coût | remplacer l'appel `claude -p … --output-format json` par l'équivalent du harnais ; garder la copie isolée, le plafond de durée et le relevé |
| `orchestration/limites.json` | dit ce qu'un agent lancé peut lire, écrire et exécuter | traduire dans le mécanisme de permissions du harnais ; à défaut, appliquer les mêmes interdits à la main |
| `.claude/commands/tache.md`, `.claude/agents/*.md` | la procédure et les rôles (conducteur, relecteur, rédacteur) | ce sont des consignes en français, lisibles telles quelles par n'importe quel agent ; à recopier dans le format du harnais |
| `orchestration/modeles/deepseek.env` | adresse, modèle et tarif de l'agent externe | garder ; il ne dépend que d'une API compatible Anthropic |

**Un point à connaître** : l'agent qui écrit tourne **déjà sur DeepSeek**, par une API
compatible. Ce n'est donc pas le modèle qui lie le projet à Claude Code, mais le programme
qui le lance et le système de permissions. Compter une tâche de portage, pas une refonte.

**Deux pièges rencontrés le 2026-09-18**, à ne pas redécouvrir :
- l'API DeepSeek refuse le schéma des outils `Artifact` du CLI ; ils sont exclus par
  `--disallowed-tools` dans `lancer-agent.sh` ;
- les permissions trop larges bloquaient toute écriture documentaire par un agent
  (A177, A178, corrigés par TASK-093).

## 4 bis. Procédure de portage, geste par geste

1. **Cloner le dépôt.** Il n'y a rien d'autre à transférer : ni base, ni configuration
   externe, ni état caché dans une session.
2. **Donner au nouvel outil son point d'entrée.** [AGENTS.md](../AGENTS.md) à la racine
   dit quoi lire et dans quel ordre ; il est écrit pour n'importe quel harnais. Si l'outil
   attend un autre nom de fichier, le pointer vers celui-là.
3. **Recopier les consignes des agents.** `.claude/agents/*.md` (conducteur, relecteur,
   rédacteur) et `.claude/commands/tache.md` sont du français, pas du code : les coller
   dans le format du nouvel outil, sans les réécrire.
4. **Réécrire un seul bloc de `lancer-agent.sh`** — l'appel au CLI. Le contrat à tenir :
   arguments `<profil> <TASK-XXX> [fichier de retours]` ; travail dans une copie isolée
   `../script-agents/<TASK>` sur la branche `agent/<TASK>` ; plafond de durée ; une ligne
   `VERDICT` en sortie ; une ligne dans `orchestration/mesures/agents.tsv`. Tout le reste
   du script est indépendant de l'outil.
5. **Traduire `orchestration/limites.json`** dans le système de permissions du nouvel
   outil. À défaut de mécanisme équivalent, garder au minimum les interdits :
   `CLAUDE.md`, `orchestration/`, `config/*.env` (hors `.example`), `.git/`, et aucun
   `push`.
6. **Éprouver le portage sur une tâche déjà close** — par exemple TASK-083 — dans une
   copie jetable : le nouvel harnais doit produire le même livrable et le même verdict.
   Tant que cette épreuve n'est pas faite, le portage n'est pas prouvé.

Ce qui ne change pas : les commandes de validation, la CI, les cadrages, le registre, le
backlog, les rapports. Un harnais est un pilote interchangeable, pas le projet.

## 5. Répartition des modèles, telle qu'elle est mesurée

| Qui | Rôle | Coût constaté |
|---|---|---|
| Agent externe (DeepSeek) | écrit le code et la documentation | 0,03 à 0,19 $ par tâche ; moyenne 0,120 $ sur 82 lancements |
| Conducteur | active, lance, vérifie, fusionne, clôt | 36 000 à 199 000 jetons ; 36 000 depuis l'outillage de TASK-086 |
| Relecteur (modèle fort) | une lecture par tâche | 40 000 à 80 000 jetons ; 0,602 $ par l'API sur TASK-094 (Opus, 13 tours, fichier documentaire de 400 lignes) |

Tarifs de l'API, relevés le 2026-09-19, en dollars par million de jetons, entrée / sortie :
`deepseek` 0,30 / 1,20 — Haiku 4.5 1 / 5 — Sonnet 5 2 / 10 — Opus 5 5 / 25.

La relecture par un modèle fort est le filet de sécurité de la chaîne : c'est elle qui a
rattrapé les défauts majeurs de TASK-074, TASK-078, TASK-081 et TASK-087. Ne pas
l'économiser.

Mesures complètes : `orchestration/mesures/agents.tsv` et `orchestration/mesures/journal.md`.
