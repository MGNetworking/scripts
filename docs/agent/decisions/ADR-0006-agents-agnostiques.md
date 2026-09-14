# ADR-0006 — Des agents agnostiques, orchestrés par Claude Code

**Date** : 2026-09-14
**Statut** : accepté le 2026-09-14
**Décideur** : Maxime Ghalem
**Remplace** : [ADR-0005](ADR-0005-orchestration-multi-llm.md), décisions 30 à 35

---

## Contexte

ADR-0005 appelait DeepSeek comme un simple générateur de texte : un script lui
envoyait des fichiers et écrivait sa réponse. DeepSeek ne lisait rien, ne lançait
rien, ne corrigeait qu'une fois. Maxime veut autre chose : **des agents qui
travaillent eux-mêmes dans le projet**, sous les ordres d'un orchestrateur, et un
projet ouvert à d'autres modèles que ceux d'aujourd'hui.

Fait vérifié le 2026-09-14 dans la documentation de DeepSeek : son API accepte le
format d'Anthropic à l'adresse `https://api.deepseek.com/anthropic`. Claude Code
peut donc tourner avec DeepSeek comme modèle, avec tous ses outils.

## Décision 36 — Claude Code est l'orchestrateur et le harness

- **L'orchestrateur** est la session Claude Code de Maxime (Opus). Il suit
  `.claude/commands/tache.md` : il active la fiche, lance l'agent, vérifie,
  fait relire, fusionne, écrit README, backlog, rapport et journal.
- **Un agent** est une autre instance de Claude Code, sans interface
  (`claude -p`), lancée par `docs/agent/outils/lancer-agent.sh`. Il suit
  `.claude/commands/executer-tache.md` : écrire, tester, corriger, commiter.

Le harness est le même pour tous : outils, règles du dépôt, `CLAUDE.md`. Seul le
modèle change.

## Décision 37 — Un modèle = un profil

Chaque modèle est décrit par `docs/agent/profils/<nom>.env` : l'adresse de l'API,
le nom du modèle, et le **nom** de la variable qui porte la clé. Aucun secret n'y
figure.

Greffer un modèle, c'est écrire un profil. Condition : que son API accepte le
format d'Anthropic. Un modèle qui ne l'accepte pas demandera un relais de
traduction ; ce cas sera tranché le jour où il se présentera.

Profils au 2026-09-14 : `deepseek` (clé `DEEPSEEK_API_KEY`), `sonnet` (abonnement
Claude, sans clé).

## Décision 38 — La fiche désigne son agent

Le champ `agent` remplace `niveau`, `executor` et `effort` : un nom de profil, ou
`orchestrateur` pour une tâche de décision. Répartition initiale, reprise du
classement d'ADR-0005 : `deepseek` pour TASK-024, 033, 034, 035 ; `sonnet` pour
TASK-025, 026, 036, 037 ; `orchestrateur` pour TASK-028.

## Décision 39 — L'agent est isolé

- il travaille dans une copie séparée (`git worktree`, `../script-agents/<TASK>`),
  jamais dans le dépôt principal ;
- `docs/agent/profils/agent-settings.json` borne ses droits : écrire hors de
  `tasks/`, `docs/`, `lib/`, `.claude/`, des README et de `CLAUDE.md` ; lancer le
  juge et le conteneur de test ; `git add` et `commit`. Interdits : `push`,
  `merge`, `reset`, lecture des `config/*.env`, web, sous-agents ;
- aucun serveur MCP (`--strict-mcp-config`) : ni Jira, ni messagerie ;
- la clé est lue dans l'environnement et transmise au seul processus de l'agent.

## Décision 40 — La boucle et ses plafonds

```text
agent : premier jet ─► juger.sh ─► jusqu'à 3 corrections du script
        (fichier de cas figé après le premier jet, arrêt si les FAIL ne baissent plus)
orchestrateur : juger.sh relancé ─► périmètre ─► tests figés ─► relecture Opus
        défauts ─► agent relancé 1 fois avec les retours ─► sinon l'orchestrateur finit ou bloque
```

Le figement du fichier de cas empêche l'agent d'affaiblir un test pour passer ;
l'orchestrateur le contrôle par `git diff` depuis le commit du premier jet.

## Mesure

`lancer-agent.sh` ajoute une ligne par lancement à `docs/agent/mesures/agents.tsv` :
tours, jetons d'entrée, de cache et de sortie, durée, code. Le coût se calcule au
tarif du profil. Chaque tâche ajoute sa ligne au
[journal](../mesures/journal.md).

## Ce qui a été retiré

`executer.sh`, `deleguer.mjs` et les mesures qui ne servaient qu'à eux ; les
niveaux N1 à N4 ; les agents `redacteur-script` et `redacteur-tests`, que plus
aucun circuit n'appelle.

## Ce qui reste incertain

- Claude Code piloté par DeepSeek n'a pas encore tourné sur ce dépôt : premier
  essai prévu sur TASK-033.
- Les règles de `agent-settings.json` sont écrites d'après la syntaxe documentée
  de Claude Code ; leur effet réel se constate au premier lancement.
- Le parallélisme (plusieurs agents à la fois) est permis par les copies
  séparées, mais n'est pas ouvert avant trois tâches passées sans incident.
