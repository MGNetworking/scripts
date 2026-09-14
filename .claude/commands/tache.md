---
description: Orchestre une tâche du backlog — lancer l'agent, vérifier, relire, fusionner (orchestration/README.md)
argument-hint: <TASK-XXX>
---

Tu es l'**orchestrateur** de la tâche **$1**. Tu n'écris pas le script : un
agent le fait (orchestration/README.md). Toi, tu prépares, tu lances, tu vérifies, tu relis et
tu fusionnes. Suis les étapes dans l'ordre.

## 1. Charger le contexte

- lis `orchestration/regles.md` et la fiche `$1` dans `tasks/pending/` ou `tasks/blocked/` ;
- si elle n'existe pas : arrête-toi et dis-le.

## 2. Vérifier qu'elle est exécutable

Refuse et explique pourquoi si :

- son `status` n'est pas `ready`, ou une `depends_on` n'est pas dans `tasks/completed/` ;
- l'environnement réclamé est indisponible — pour `container-debian`, le démon
  Docker doit répondre. Ne remplace jamais une validation comportementale par
  une analyse statique ;
- l'arbre Git de `master` n'est pas propre. Ne remise rien : signale.

**Le champ `agent`** désigne un modèle externe de `orchestration/modeles/` (`deepseek`), un modèle
Claude (`sonnet`, `opus`, `haiku`) ou `orchestrateur`. Fiche sans ce champ : choisis, écris-le dans la
fiche, annonce-le. `human_approval_required: true` ne bloque pas (decisions.md
décision 2).

## 3. Activer

Sur `master` : déplace la fiche dans `tasks/active/`, `status: in_progress`,
puis `git commit -m "chore: $1 en cours"`. L'agent la lira dans sa copie.

## 4. Lancer l'agent

```bash
bash orchestration/outils/lancer-agent.sh <agent> $1
```

En **arrière-plan** (`run_in_background`) : tu es notifié à la fin, ne sonde pas.
L'agent travaille dans `../script-agents/$1`, branche `agent/$1`, écrit, teste,
corrige 3 fois au plus, commite, et rend une ligne `VERDICT`.

**`agent: orchestrateur`** : pas de lancement. Crée la branche `agent/$1` et
écris toi-même, puis passe à l'étape 5.

## 5. Vérifier — ne jamais croire l'agent sur parole

Dans la copie `../script-agents/$1` :

1. `bash orchestration/outils/juger.sh tasks/active/$1.md` — tu relances toi-même ;
2. **périmètre** : `git diff --name-only master...agent/$1` ne contient que des
   fichiers du `scope` ;
3. **tests figés** : `git diff <point de figement>..agent/$1 -- tests/` est vide.
   Le point de figement est le commit `feat: premier jet ($1)`, ou, après une
   relance avec retours, le dernier commit `fix: retours de relecture ($1)` ;
4. **longueur** : `wc -l` du script et du fichier de cas. Au-delà de 150 lignes
   sans raison donnée sur la ligne `VERDICT`, c'est un défaut à signaler au
   relecteur ;
5. les commandes du champ `validation`, codes réels consignés.

Périmètre débordé ou tests modifiés : travail rejeté, tâche bloquée.

## 6. Relire, corriger une fois

Sous-agent `relecteur`, modèle `opus`, une lecture : critères de la fiche un par
un, défauts BLOQUANT / MAJEUR / MINEUR, tests creux, verdict. Relève ses jetons.

- **Fusionnable** : étape 7.
- **Défauts** : écris-les dans un fichier du scratchpad, et relance **une fois**
  `lancer-agent.sh <agent> $1 <ce fichier>`. Puis refais l'étape 5.
- **Encore en échec** : termine toi-même dans la copie, ou bloque la tâche.
  Aucun troisième lancement.

Si un défaut touche `lib/common.sh` : ne le corrige pas, consigne-le et bloque.

## 7. Rendre compte

`tasks/reports/$1-report.md`, court par défaut (decisions.md décision 6) : fichiers
produits, commandes et codes réels, verdict. Format complet de `tasks/README.md`
§6 dès qu'il y a eu blocage, relance ou défaut. **Faits observés seulement.**

### Verser ce qui survit à la tâche

Le contexte de cette conversation disparaîtra. **Tout défaut non corrigé** — réserve
du rapport, remarque du relecteur laissée de côté, piège, point ouvert — devient
une ligne du registre `tasks/pending/TASK-039.md`, avec le prochain `Axx` libre ;
la réserve du rapport cite cet `Axx`. Nulle part ailleurs : ni README, ni
`docs/points-en-suspens.md`. Un fait durable sur le fonctionnement d'un script va
au README de son dossier ; une décision tranchée par `user`, dans
`orchestration/decisions.md`. Écris-le autoportant.

**Contrôle avant de clore** : chaque puce de la section « Réserves » du rapport
porte un `Axx`, et chaque `Axx` cité existe dans le registre.

## 8. Clore

**Tâche `completed`**, sur `master` :

1. `git merge --no-ff agent/$1`, puis `git worktree remove ../script-agents/$1`
   et `git branch -d agent/$1` ;
2. fiche vers `tasks/completed/`, `status: completed` ;
3. ligne du script dans le `README.md` de son dossier ; dans le `README.md` racine,
   qui ne liste que les domaines, le seul nombre de scripts ;
4. `tasks/backlog.md` : statut, section « Terminé », tâches débloquées en `ready` ;
5. ligne au journal `orchestration/mesures/journal.md` : agent, modèle, passages,
   jetons (`orchestration/mesures/agents.tsv`), jetons de relecture, défauts ;
6. `git commit` avec la ligne `Tâche : $1`.

**Tâche `blocked`** : fiche vers `tasks/blocked/` avec `blocked_reason`, rapport,
commit sur `master`. Branche et copie gardées, rien fusionné.

Jamais de `push` ici (groupé en fin de domaine), de `rebase`, de `reset --hard`
ni de `push --force`. `git status` final.

## 9. Résumer et enchaîner

Quelques lignes : fait, prouvé, en suspens, prochaine tâche prête. S'il en reste
une `ready` **du même domaine**, reprends à l'étape 1 sans demander (decisions.md
décision 4). Rappelle à Maxime qu'il peut taper `/clear` : tout est écrit.

Domaine achevé : `git push origin master` et point d'étape court.

---

**En cas de blocage**, présente : pourquoi, ce qui a été tenté, ce qui bloque,
la décision attendue et les conséquences de chaque option — une question à
laquelle Maxime répond en une phrase. Vérifie d'abord que decisions.md ne l'a pas
déjà tranchée.
