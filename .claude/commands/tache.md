---
description: Orchestre une tâche du backlog — lancer l'agent, vérifier, relire, fusionner (orchestration/README.md)
argument-hint: <TASK-XXX>
---

Ces étapes 1 à 8 sont conduites par un sous-agent **`conducteur-tache`** ; la
session qui l'invoque suit l'étape 0 et l'étape 9. Dans les étapes 1 à 8,
« tu » désigne le conducteur et `$1` la tâche qu'il conduit.

## 0. Répartition — une session qui dure, un conducteur par tâche

Décision 46 amendée : la session ne se vide plus. Le contexte lourd d'une tâche
vit dans un conducteur **neuf**, qui disparaît à la clôture ; la session ne garde
que ses réponses, 30 lignes au plus chacune. Seul geste resté à la session :
lancer l'agent, qui peut tourner une heure, en arrière-plan.

| La session envoie | Le conducteur fait | Il rend |
|---|---|---|
| Agent `conducteur-tache` : « préparer $1 » ou « préparer la suivante » (jamais TASK-039, le registre) | 1-3 ; fiche `agent: orchestrateur` : 1-8 d'un trait | `PRÊTE <tâche> <commande>`, `CLOSE`, `REFUS` |
| `lancer-agent.sh` en arrière-plan, puis SendMessage « agent terminé » + sa sortie | 5, 6 ; fusionnable : 7-8 | `RELANCER <fichier de retours>`, `CLOSE`, `BLOQUÉE` |
| relance en arrière-plan, puis SendMessage « relance terminée » + sa sortie | 5 ; puis 7-8, ou finir lui-même, ou bloquer (étape 6) | `CLOSE`, `BLOQUÉE` |

Toute réponse peut être `BESOIN_USER` : la session pose la question telle quelle
et s'arrête. Après `CLOSE` ou `BLOQUÉE`, la session ajoute à `agents.tsv` une ligne
`conducteur` (jetons de sa **dernière** réponse, cumulés) et la commite seule :
`chore: mesure conducteur $1`. Identifiant du conducteur perdu (compaction) :
la session lance un conducteur neuf avec « reprendre $1 »,
l'état étant dans la fiche, la branche et le rapport.

## 1. Charger le contexte

- lis `orchestration/regles.md` et la fiche `$1` dans `tasks/pending/` ou `tasks/blocked/` ;
- si elle n'existe pas : arrête-toi et dis-le.

## 2. Vérifier qu'elle est exécutable

Refuse et explique pourquoi si :

- son `status` n'est pas `ready`, ou une `depends_on` n'est pas dans `tasks/completed/` ;
- l'environnement réclamé est indisponible — pour `container-debian`, le démon
  Docker doit répondre. Ne remplace jamais une validation comportementale par
  une analyse statique ;
- l'arbre Git de `master` n'est pas propre. Ne remise rien : signale ;
- elle sort du contrat du `CADRAGE.md` de son grand dossier (décision 49) : un
  changement incompatible sur un script existant, ou une fiche née hors de la boucle
  de réflexion validée par `user`. Dossier encore sans cadrage : passent une correction
  déjà au backlog et la tâche qui écrit ce cadrage.

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

Tu ne lances pas cette commande : tu la rends à la session (`PRÊTE`), qui la lance
en **arrière-plan** et te renvoie sa sortie. L'agent travaille dans
`../script-agents/$1`, branche `agent/$1`, écrit, teste, corrige 3 fois au plus,
commite, et rend une ligne `VERDICT`.

**`agent: orchestrateur`** : pas de lancement. Crée la branche `agent/$1` et
écris toi-même, puis passe à l'étape 5.

## 5. Vérifier — ne jamais croire l'agent sur parole

Dans la copie `../script-agents/$1`, chaque commande au premier plan avec un délai de
600000 ms ; un délai dépassé vaut NON EXÉCUTÉ et se rend en `BESOIN_USER` :

1. `bash orchestration/outils/juger.sh tasks/active/$1.md` — tu relances toi-même ;
2. **périmètre** : `git diff --name-only master...agent/$1` ne contient que des
   fichiers du `scope` ;
3. **tests** : lis `git diff <premier jet>..agent/$1 -- tests/`. Le nombre de lignes
   `assert_`, `ok`, `ko`, `saute` ne baisse jamais (`grep -cE` sur les deux
   versions) ; toute modification est une correction de construction justifiée
   dans son commit. Après le dernier commit `fix: retours de relecture ($1)`,
   seules les modifications demandées par ces retours sont admises ;
4. **longueur** : `wc -l` du script et du fichier de cas. Au-delà de 150 lignes
   sans raison donnée sur la ligne `VERDICT`, c'est un défaut à signaler au
   relecteur ;
5. les commandes du champ `validation`, codes réels consignés. Sur l'hôte, `tests/run.sh lint`
   rend 3 faute de `shellcheck` : c'est NON EXÉCUTÉ, la preuve est le lint en conteneur.

Périmètre débordé ou tests modifiés : travail rejeté, tâche bloquée.

## 6. Relire, corriger une fois

Sous-agent `relecteur`, modèle `opus`, une lecture : critères de la fiche un par
un, défauts BLOQUANT / MAJEUR / MINEUR, tests creux, verdict.

**Dès son retour**, avant toute autre action, ajoute une ligne à
`orchestration/mesures/agents.tsv` dans le dépôt principal — jamais dans
`../script-agents/$1` —, onze colonnes séparées par des tabulations
(`printf '%s\t…\n' >>`) : `date '+%F %T'`, `$1`, `relecteur`, `opus`, appels d'outils,
`-`, `-`, jetons **totaux** du sous-agent (seul chiffre fourni : pour ce profil, la
colonne `sortie` ne se somme pas avec les autres), durée en secondes, `0`, vide.
Une session interrompue ne perd ainsi pas la mesure (A47).

- **Fusionnable** : étape 7.
- **Défauts** : écris-les dans un fichier du scratchpad et rends `RELANCER <ce
  fichier>` : la session relance **une fois** `lancer-agent.sh <agent> $1 <ce fichier>`,
  puis te renvoie sa sortie ; refais l'étape 5. `agent: orchestrateur` : corrige
  toi-même, une fois, puis refais l'étape 5.
- **Encore en échec** : termine toi-même dans la copie, ou bloque la tâche.
  Aucun troisième lancement ni seconde relecture.

Si un défaut touche `lib/common.sh` : ne le corrige pas, consigne-le et bloque.

## 7. Rendre compte

`tasks/reports/$1-report.md`. Il **commence par « ## Compte rendu »** : ce qui a été
réalisé, raconté à `user` exactement comme dans la conversation — contexte d'abord,
déroulé, défauts trouvés et corrigés, coût, réserves, en français simple. Suivent
les sections techniques de `tasks/README.md` §6 : fichiers, commandes et codes réels,
validations, Git. **Faits observés seulement.**

### Verser ce qui survit à la tâche

Le contexte de cette conversation disparaîtra. Trois cas, selon ce que vise la
correction découverte :

- **liée à la tâche** (script, fichier de cas, fiche) : elle se fait dans la tâche ;
- **liée aux agents ou à l'architecture du projet** (consignes, outils, socle,
  harnais, règles) : crée une **fiche TASK** dans `tasks/pending/`, référencée par une
  ligne du registre ;
- **urgente** (elle fausse une validation, expose un secret, peut casser une
  machine) : sa fiche porte `priority: high` et passe **avant** toute autre tâche prête.

**Tout défaut non corrigé** — réserve
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
   jetons et jetons de relecture, lus tous deux dans `orchestration/mesures/agents.tsv`
   (lignes `relecteur`), défauts ; une ligne d'agent `incomplet` (transcript de session
   introuvable) s'écrit « non relevé », sauf si l'usage se lit dans le `.jsonl` de la session ;
6. `bash orchestration/outils/verifier-liens.sh` : 0, sinon corrige les liens cassés
   par le déplacement de la fiche ;
7. `git commit`, `agents.tsv` compris, avec la ligne `Tâche : $1`.

**Tâche `blocked`** : fiche vers `tasks/blocked/` avec `blocked_reason`, rapport,
commit sur `master`. Branche et copie gardées, rien fusionné.

Jamais de `push` ici (groupé en fin de domaine), de `rebase`, de `reset --hard`
ni de `push --force`. `git status` final.

## 9. Résumer et enchaîner

Quelques lignes, reprises du résumé du conducteur : fait, prouvé, en suspens,
prochaine tâche prête. Aucun vidage (décision 46 amendée) : la session ne garde de la tâche
que ce résumé, jamais les diffs ni les sorties. Puis lis `orchestration/mode.json` :

- **`automatique`** : la session lance aussitôt un conducteur **neuf**, « préparer la suivante » —
  tâche `ready` suivante, tous domaines confondus, urgentes d'abord —, sans rien
  demander et sans attendre de message de `user` ;
- **`manuel`** : la session attend une consigne explicite de `user`.

La boucle s'arrête d'elle-même sur : aucune tâche `ready`, tâche `blocked`,
plafond de la décision 40 atteint, `BESOIN_USER`, erreur système, conducteur
mort sans réponse, ou `mode` passé à `manuel`.

Quand `user` demande l'arrêt du mode automatique, écris `"mode": "manuel"` dans le
fichier, termine la tâche en cours, puis arrête-toi.

Domaine achevé : `git push origin master` et point d'étape court.

---

**En cas de blocage**, présente : pourquoi, ce qui a été tenté, ce qui bloque,
la décision attendue et les conséquences de chaque option — une question à
laquelle Maxime répond en une phrase. Vérifie d'abord que decisions.md ne l'a pas
déjà tranchée.
