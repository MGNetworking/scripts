# Architecture de l'orchestration agentique

**Vue d'ensemble de référence** de la façon dont les agents IA produisent les scripts de
ce dépôt : qui intervient, où, avec quels artefacts, dans quel ordre, avec quels
contrôles. **Ses schémas sont la représentation graphique de référence** : ils sont
écrits ici en Mermaid et se modifient avec le texte, dans le même commit. Une évolution
de l'orchestration qui ne met pas ce fichier à jour est incomplète. L'affiche
[orchestration.png](orchestration.png), générée depuis [orchestration.html](orchestration.html), en est une présentation dessinée, datée : en cas
d'écart, ce fichier fait foi.

Pour les règles détaillées, ce fichier renvoie ; il ne les répète pas et ne les
remplace pas :

| Sujet | Fait foi |
|---|---|
| droits, commandes, Git, arrêt | [regles.md](regles.md) |
| décisions numérotées | [decisions.md](decisions.md) |
| cycle d'une tâche, pas à pas | [.claude/commands/tache.md](../.claude/commands/tache.md) |
| consignes de chaque rôle | [.claude/agents/](../.claude/agents/), [.claude/commands/](../.claude/commands/) |
| format des fiches, statuts, sélection | [tasks/README.md](../tasks/README.md) |
| écarts et dettes | [tasks/pending/TASK-039.md](../tasks/pending/TASK-039.md) (registre) |

En cas de désaccord entre ce fichier et une de ces sources, la source a raison et ce
fichier est à corriger.

---

## 1. Acteurs

| Acteur | Nature | Modèle | Consigne | Peut | Ne peut pas |
|---|---|---|---|---|---|
| **user** | humain | — | — | exprimer un besoin (jamais une commande), valider seul le cadrage, décider, reconnecter Claude Code, basculer `mode.json` | — |
| **Session orchestratrice** | session Claude Code interactive, qui dure | Opus | boucle de réflexion ([décision 49](decisions.md)) ; `/tache` étapes 0 et 9 ; `/atomiser`, appliqué après validation du cadrage, qui délègue au rédacteur | proposer un cadrage ; lancer conducteurs, rédacteurs et `lancer-agent.sh` en arrière-plan ; écrire décisions, `mode.json`, ce fichier ; commiter la mesure du conducteur ; pousser en fin de domaine | écrire un script ; vider son contexte (décision 46 amendée) |
| **Conducteur** | sous-agent Claude Code, neuf par tâche | Opus | [conducteur-tache.md](../.claude/agents/conducteur-tache.md), `/tache` étapes 1 à 8 | activer, vérifier, faire relire, écrire le fichier de retours, fusionner, clore ; terminer lui-même ou bloquer ; écrire lui-même une tâche `agent: orchestrateur` | lancer `lancer-agent.sh` ; pousser, rebaser, `reset --hard` ; appeler Python (absent de l'hôte, A87) |
| **Agent exécutant** | Claude Code sans interface (`claude -p`) | celui de la fiche : `deepseek` (modèle externe, [modeles/](modeles/)) ou `sonnet`/`opus`/`haiku` | [executer-tache.md](../.claude/commands/executer-tache.md) | écrire le script, son fichier de cas et un éventuel `config/*.env.example` ; lancer `juger.sh` ; `git add`/`commit` dans sa copie | tout ce que refuse [limites.json](limites.json) : `CLAUDE.md`, README, `tasks/`, `docs/`, `lib/`, `orchestration/`, `.claude/` ; `push`, `merge`, `rebase`, `reset`, `checkout`, `switch`, `worktree` ; web, sous-agents, MCP (décision 39) ; lecture des `config/*.env` |
| **Relecteur** | sous-agent, lecture seule | Opus | [relecteur.md](../.claude/agents/relecteur.md) | lire, rendre un verdict de 40 lignes au plus | écrire, lancer une commande |
| **Rédacteur** | sous-agent | hérité de la session | [redacteur-tache.md](../.claude/agents/redacteur-tache.md) | écrire des fiches dans `tasks/pending/`, mettre `tasks/backlog.md` à jour | écrire un script ; inventer une décision |
| **Juge** | script, sans modèle | — | [outils/juger.sh](outils/juger.sh), [outils/lien-ecrit.awk](outils/lien-ecrit.awk) | shellcheck, fichier de cas en conteneur, règles transverses, signal de longueur, refus d'un faux binaire écrit à travers un lien | — |

Un sous-agent Claude Code peut lancer un autre sous-agent (essai du 2026-09-16) : la
consigne confie donc la relecture au conducteur. Que le conducteur le fasse en pratique
reste à constater dans une session neuve (A59). Un Bash au premier plan est plafonné à
10 minutes : l'agent, qui peut tourner une heure (`DUREE_MAX`), reste lancé par la session.

## 2. Lieux

| Lieu | Contenu | Qui écrit |
|---|---|---|
| dépôt, branche `master` | tout ; y vont les activations, les clôtures, les mesures, les fusions `--no-ff` (tâches et atomisations), et les commits de la session (décisions, registre, `mode.json`, ce fichier) | session, conducteur |
| copie `../script-agents/<TASK>`, branche `agent/<TASK>` | `git worktree` créé par `lancer-agent.sh` ; supprimé à la clôture d'une tâche `completed`, gardé pour une tâche `blocked` | agent ; conducteur s'il termine lui-même |
| conteneur `mgnet-test-debian-*` / `mgnet-test-systemd-*` | exécution des tests, détruit après chaque appel | `tests/env/run-in-container.sh` |
| scratchpad de la session | textes pour le relecteur, fichiers de retours | conducteur |
| GitHub `origin` | `master`, poussé en fin de domaine | session |

Aucun script d'administration ne s'exécute sur l'hôte Windows, sur un serveur ni sur le
NAS ([regles.md](regles.md) §7).

## 3. Artefacts

| Artefact | Rôle | Écrit par | Lu par |
|---|---|---|---|
| `<dossier>/CADRAGE.md` | besoin, ensembles et contrat de chaque script d'un grand dossier ; il engage (décision 49) | session, validé par user seul | session, rédacteur, conducteur, relecteur |
| `docs/refactorisation-plan.md` | scripts du chantier initial, par domaine | user, session | rédacteur |
| `tasks/pending/`, `active/`, `completed/`, `blocked/`, `cancelled/` | une fiche par tâche ; le répertoire suit le statut | rédacteur, conducteur | tous |
| `tasks/backlog.md` | tableau des tâches, index du plan, identifiant libre | rédacteur, session, conducteur | session, conducteur |
| `tasks/pending/TASK-039.md` | **registre unique** des anomalies `Axx` | conducteur, session | tous |
| `tasks/reports/TASK-XXX-report.md` | compte rendu puis détail technique | conducteur | user |
| `orchestration/decisions.md` | décisions de user, numérotées | session | tous |
| `orchestration/mode.json` | `automatique` ou `manuel` | session, à la demande de user | session |
| `orchestration/mesures/agents.tsv` | une ligne par lancement d'agent, par relecture, par conducteur | `lancer-agent.sh`, conducteur, session | clôture, journal |
| `orchestration/mesures/journal.md` | une ligne par tâche livrée : coût, défauts, rattrapage | conducteur | user |
| fichier de retours (scratchpad) | défauts à corriger, remis à l'agent | conducteur | agent |
| README des domaines | rôle, scripts, risques, usage | conducteur | user |

## 4. Vue d'ensemble

```mermaid
flowchart TB
    U(["user"])
    subgraph Session["Session orchestratrice — Opus, dure"]
        S["/tache étapes 0 et 9<br/>/atomiser"]
    end
    subgraph Sous["Sous-agents — neufs, jetables"]
        R["Rédacteur"]
        C["Conducteur<br/>1 par tâche"]
        L["Relecteur Opus<br/>lecture seule"]
    end
    subgraph Hors["Hors session"]
        A["Agent exécutant<br/>claude -p, modèle de la fiche"]
        J["juger.sh"]
        K[("Conteneur jetable<br/>mgnet-test-*")]
    end
    subgraph Depot["Dépôt"]
        M[("master")]
        W[("copie ../script-agents<br/>branche agent/TASK")]
        F["tasks/ fiches, backlog,<br/>registre, rapports"]
        O["orchestration/ décisions,<br/>mode.json, mesures"]
    end
    G[("GitHub origin")]

    U -- "besoin, validation du cadrage,<br/>décisions" --> S
    S -- "cadrage proposé, questions<br/>en une série, question fermée" --> U
    S -- "cadrage validé" --> CA["CADRAGE.md<br/>par grand dossier"]
    S -- "/atomiser après<br/>validation" --> R
    R -- "fiches, backlog" --> F
    S -- "préparer, reprendre<br/>SendMessage" --> C
    C -- "PRÊTE, REFUS, RELANCER,<br/>CLOSE, BLOQUÉE, BESOIN_USER" --> S
    S -- "lancer-agent.sh<br/>arrière-plan" --> A
    A -- "écrit, commite" --> W
    A --> J
    C --> J
    J --> K
    C -- "relire" --> L
    L -- "verdict" --> C
    C -- "fusion --no-ff, clôture" --> M
    C -- "rapport, registre" --> F
    C -- "mesures" --> O
    S -- "décisions, mode" --> O
    S -- "push fin de domaine" --> G
```

## 5. Cycle d'une tâche

Une seule tâche dans `active/` à la fois ([tasks/README.md](../tasks/README.md) §4). Pas
de parallélisme tant que la décision 40 ne l'ouvre pas (trois tâches sans incident et
exécutions concurrentes du harnais maîtrisées, A06). Une seule relecture, une seule
relance de l'agent (décision 40).

```mermaid
sequenceDiagram
    autonumber
    participant S as Session
    participant C as Conducteur
    participant A as Agent
    participant J as juger.sh et conteneur
    participant L as Relecteur
    participant D as master

    S->>C: préparer TASK ou la suivante
    C->>D: étapes 1-2 : ready, dépendances, Docker, arbre propre
    alt non exécutable
        C-->>S: REFUS
    else exécutable
        C->>D: étape 3 : fiche vers active, backlog, 1 commit
        C-->>S: PRÊTE + commande lancer-agent.sh
    end
    S->>A: étape 4 : lancer-agent.sh, arrière-plan
    A->>J: premier jet, puis 3 passages au plus
    A-->>S: ligne VERDICT, ligne agents.tsv
    S->>C: agent terminé + sortie
    C->>J: étape 5 : juger, périmètre, assertions, longueur, validations
    alt périmètre débordé ou tests affaiblis
        C->>D: tâche bloquée
        C-->>S: BLOQUÉE
    end
    C->>L: étape 6 : relire
    L-->>C: verdict, défauts, tests creux
    C->>D: ligne relecteur dans agents.tsv
    alt fusionnable
        C->>D: étapes 7-8 : rapport, registre, README, fusion, clôture
        C-->>S: CLOSE + suivante
    else défauts
        C-->>S: RELANCER + fichier de retours
        S->>A: relance unique avec retours
        A-->>S: VERDICT
        S->>C: relance terminée
        C->>J: étape 5 refaite, pas de seconde relecture
        alt tient
            C->>D: clôture
            C-->>S: CLOSE
        else ne tient pas
            C->>D: termine lui-même ou bloque
            C-->>S: CLOSE ou BLOQUÉE
        end
    end
    S->>D: mesure du conducteur, commit séparé
    S->>C: étape 9 : conducteur neuf, suivante si mode automatique
```

À tout moment, le conducteur peut rendre `BESOIN_USER` (décision non tranchée, délai
de 600 000 ms dépassé) : la session pose la question et la boucle s'arrête.

Fiche `agent: orchestrateur` : pas de `lancer-agent.sh` ; le conducteur écrit lui-même
sur `agent/<TASK>` et conduit les étapes 1 à 8 d'un trait.

**Pratique non prescrite** (observée sur les domaines K3s et Kubernetes, absente de
l'étape 5 de `/tache`) : avant la relecture, le conducteur **sonde** le script en
conteneur avec des faux binaires qui journalisent, **mute** une copie jetable pour
vérifier que la suite échoue, et relance la suite plusieurs fois pour vérifier sa
**stabilité**. Après la relance, il rejoue ces sondes à la place d'une seconde
relecture. À décider : l'inscrire dans `/tache` ou non (A128).

## 6. États d'une tâche

```mermaid
stateDiagram-v2
    [*] --> pending: rédacteur écrit la fiche
    pending --> ready: périmètre et validations tiennent, dépendances closes
    ready --> in_progress: conducteur active, 1 commit
    in_progress --> completed: vérifié, relu, fusionné
    in_progress --> blocked: périmètre débordé, tests affaiblis, second échec, lib/common.sh touché
    pending --> cancelled: abandon décidé
    ready --> cancelled: abandon décidé
    blocked --> ready: décision de user, jamais automatique
    completed --> [*]
    cancelled --> [*]
```

L'ouverture `pending → ready` est déléguée (décision 3). Une fiche qui attend un choix
de user reste `pending` jusqu'à la décision numérotée. À chaque clôture, le conducteur
passe en `ready` les tâches qu'elle débloque. Le statut `validating`
([tasks/README.md](../tasks/README.md) §3) n'a servi qu'à une tâche d'orchestration qui se
prouvait à l'usage (TASK-049).

## 7. Du besoin au push

Aucune fiche ne naît hors de la boucle de réflexion de la [décision 49](decisions.md) :
user exprime un besoin en langage normal, la session lit le `CADRAGE.md` du dossier et
propose, user seul valide. Le plan initial n'alimente plus que le chantier en cours. Les
fiches d'orchestration nées d'un écart (pointillés) restent régies par la décision 46.

```mermaid
flowchart TD
    B(["user exprime un besoin"]) --> Lec["Lecture : CADRAGE.md, README,<br/>décisions, scripts voisins"]
    Lec --> Conf["Confrontation au contrat"]
    Conf --> Prop{"Proposition"}
    Prop -- "déjà couvert" --> Rien(["Rien à faire, montré à user"])
    Prop -- "correction, ajout compatible,<br/>nouveau script, incompatible<br/>= nouveau + ancien déprécié" --> Qs["Questions en une seule série"]
    Qs --> Val{"user valide ?"}
    Val -- "non" --> Prop
    Val -- "oui" --> Cad["CADRAGE.md mis à jour et daté"]
    Cad --> P
    P["Domaine à atomiser<br/>(ou plan initial)"] --> Q{"plus de 7 scripts ?"}
    Q -- "oui" --> Lots["Découper en lots"]
    Q -- "non" --> At
    Lots --> At["/atomiser appliqué par la session :<br/>rédacteurs, une fiche par script"]
    At --> Dec{"choix non tranchés<br/>par decisions.md ?"}
    Dec -- "oui" --> Qu["Choix techniques restants<br/>à user, en une série"]
    Qu --> DN["Décision numérotée<br/>+ fiches alignées"]
    Dec -- "non" --> Ready
    DN --> Ready["Fiches ready,<br/>lecture seule d'abord"]
    Ready --> Loop["Boucle : un conducteur par tâche"]
    Loop --> Clo["Clôture : rapport, README,<br/>registre, journal, agents.tsv"]
    Clo --> Fin{"dernière tâche du domaine ?"}
    Fin -- "oui" --> Push["git push origin master<br/>point d'étape à user"]
    Fin -- "non" --> Next
    Push --> Next{"tâche ready suivante<br/>et mode automatique ?"}
    Next -- "oui" --> Loop
    Next -- "non" --> Stop(["Arrêt : attente de user"])
    Clo -. "écart d'agent ou d'architecture" .-> Fi["Fiche TASK d'orchestration<br/>+ ligne Axx"]
    Fi -.-> Ready
```

**Mesures produites** : chaque lancement d'agent (jetons lus dans le transcript de la
session, coût), chaque relecture et chaque conducteur ajoutent une ligne à
`agents.tsv` ; chaque tâche livrée ajoute une ligne au journal.

## 8. Contrôles et ce qu'ils prouvent

| Contrôle | Prescrit par | Prouve | Ne prouve pas |
|---|---|---|---|
| `juger.sh` | `/tache` 5.1, `executer-tache` §3 | shellcheck ; fichier de cas sans échec en conteneur (cas sautés admis) ; règles transverses ; signal de longueur ; aucun faux binaire écrit à travers un lien | que les tests testent quelque chose |
| périmètre `git diff --name-only` | `/tache` 5.2 | aucun fichier hors `scope` | — |
| comptage des assertions, lecture des diffs de tests | `/tache` 5.3 | aucun test retiré ni affaibli sans justification | la pertinence des tests |
| longueur `wc -l` | `/tache` 5.4 | dépassement signalé au relecteur | — |
| commandes du champ `validation` | `/tache` 5.5 | codes réels, lint en conteneur | — |
| relecture Opus | `/tache` 6 | critères, défauts, tests creux, lus dans le code | l'exécution réelle |
| chaque réserve porte un `Axx` existant | `/tache` 7 | rien de perdu à la clôture | — |
| `verifier-liens.sh` | `/tache` 8.6 | aucun lien Markdown mort après déplacement de fiche | — |
| sondes, mutations, stabilité | pratique non prescrite (A128) | comportement sur les chemins à risque ; suite qui échoue quand le script est faux ; test déterministe | comportement contre un vrai système |
| `ansible-lint`, `yamllint` | décision 50, regles.md §10 | rôle et YAML conformes | le comportement |
| Molecule `converge`, `idempotence`, `verify` | décision 50, regles.md §10 | rôle appliqué en conteneur ; second passage sans changement ; état vérifié | le comportement sur un vrai VPS |
| `ansible-playbook --check --diff --limit` | décision 50, lancé par user | changements prévus sur la machine réelle | l'application elle-même |
| CI GitHub Actions | décision 50 | lint et tests verts sur chaque push | ce que les tests ne couvrent pas |

**Limite commune** : les tests tournent contre des faux (`kubectl`, `helm`, `systemctl`,
`ufw`…) dont les messages sont parfois imités de mémoire. Aucun script n'est éprouvé sur
un vrai serveur tant qu'un essai sur machine virtuelle n'a pas eu lieu.

**Niveaux de preuve** (décision 50), toujours nommés : **simulé** (faux binaires, la
logique seule), **conteneur** (l'outil réel dans un conteneur jetable), **machine**
(constaté sur un VPS par user). Une preuve ne se présente jamais comme plus forte
qu'elle n'est.

## 9. Arrêts et reprise

Conditions d'arrêt de la boucle : `/tache` étape 9 et [regles.md](regles.md) §15. La
dernière tâche d'un domaine n'arrête pas la boucle : la session pousse, fait un point
d'étape, puis enchaîne s'il reste une tâche `ready`.

| Incident | Reprise | Source |
|---|---|---|
| identifiant du conducteur perdu (compaction) | conducteur neuf avec « reprendre TASK-XXX » ; l'état est dans la fiche, la branche, le rapport | `/tache` étape 0 |
| limite d'usage Claude pendant un conducteur | constater Git et la copie, puis SendMessage au même conducteur : « reprise » | pratique (sessions du 2026-09-16 et 17) |
| transcript de l'agent introuvable | ligne `incomplet` dans `agents.tsv`, jetons « non relevé » au journal | `lancer-agent.sh`, `/tache` 8.5 |
| Docker Desktop indisponible | arrêt signalé | décision 42 |
| conteneur de test bloqué | `docker rm -f` des seuls `mgnet-test-*`, cause cherchée dans le fichier de cas | regles.md §8, A122 |

## 10. Écarts connus entre prévu et réel

Chaque écart vit dans le registre ; cette liste ne fait que les signaler.

| Prévu | Réel | Registre |
|---|---|---|
| tâches à effets enchaînés ou destructives confiées à `sonnet` | toutes confiées à `deepseek` : l'agent Sonnet sans interface échoue sur l'authentification | A41 |
| le conducteur lance lui-même le relecteur | non encore constaté : dans la session qui a introduit ce mode, la définition du conducteur était en cache et la session lançait le relecteur | A59 |
| une seule relecture par tâche | la version corrigée après relance n'est jamais relue par Opus ; le conducteur vérifie les majeurs dans le code et par sondes | A64, A67, A72, A75… |
| 150 lignes par script et par fichier de cas | dépassements fréquents, justifiés sur la ligne VERDICT | A92, A105, A121… |
| chaque commit porte `Tâche : TASK-XXX` | les commits de l'agent ne la portent pas : `executer-tache.md` ne la lui demande pas | A66 |
| contrôles de l'étape 5 | sondes, mutations et stabilité pratiquées sans être prescrites | A128 |

## 11. Vue d'exécution

Trois endroits où tourne du code IA : la session, ses sous-agents, l'agent externe.

```mermaid
flowchart TB
    subgraph Session["Processus de la session — Claude Code interactif, Opus"]
        S["Session orchestratrice<br/>dossier : racine du dépôt<br/>API : api.anthropic.com"]
        C["Sous-agent conducteur<br/>même processus, contexte neuf<br/>dossier : racine du dépôt"]
        L["Sous-agent relecteur<br/>lecture seule"]
        R["Sous-agent rédacteur"]
    end
    subgraph Externe["Processus distinct — claude -p"]
        A["Agent exécutant<br/>dossier : ../script-agents/TASK-XXX<br/>API : celle du profil"]
    end
    LA["lancer-agent.sh"]
    V["verifier-travail.sh<br/>juger.sh"]
    D[("api.deepseek.com/anthropic")]
    N[("api.anthropic.com")]

    S -- "Agent, SendMessage" --> C
    S -- "Agent" --> L
    S -- "Agent" --> R
    S -- "commande, arrière-plan" --> LA
    LA -- "worktree, claude -p" --> A
    C -- "vérifie" --> V
    A -- "juger.sh" --> V
    A -- "profil deepseek" --> D
    A -- "profil anthropic, abonnement" --> N
```

| Cas | Programme | Dossier de travail | API contactée |
|---|---|---|---|
| session | Claude Code interactif | racine du dépôt | api.anthropic.com |
| sous-agent | le même processus que la session : nouvelle fenêtre de contexte, même programme | racine du dépôt | celle de la session |
| agent externe | processus `claude -p` lancé par `lancer-agent.sh` | copie `../script-agents/<TASK>` | selon le profil |

Côté agent externe, `ADRESSE` du profil devient `ANTHROPIC_BASE_URL` :
`api.deepseek.com/anthropic` pour `deepseek`, `api.anthropic.com` pour `anthropic`
([modeles/](modeles/)). Sans profil (`sonnet`, `opus`, `haiku`), aucune adresse ni clé
n'est posée : l'agent utilise l'abonnement Claude.

« Claude Code sans interface » désigne le seul agent externe. Un sous-agent n'a pas de
processus à lui : il partage la session, ses droits et son dossier. Le relecteur, en
lecture seule, ne juge pas par exécution : c'est le conducteur qui lance
`verifier-travail.sh`, donc `juger.sh`, et lui transmet les codes.

## 12. Les quatre couches

| Couche | Ce qu'elle contient | Interchangeable |
|---|---|---|
| **Modèle** | Opus, Sonnet, Haiku, `deepseek-flash` | oui : un profil `modeles/<nom>.env`, ou `--modele` |
| **Harnais** | Claude Code : `claude -p`, sous-agents, droits de [limites.json](limites.json) | en principe ; seul Claude Code est éprouvé et `lancer-agent.sh` appelle `claude -p` en dur |
| **Scripts** | `outils/*.sh`, `tests/` | non : la logique d'orchestration y vit ; voir §14 pour ce qui s'en détache |
| **Consignes** | [regles.md](regles.md), [decisions.md](decisions.md), `.claude/agents/`, `.claude/commands/` | oui, à condition de garder le sens |

Ce qu'un modèle doit savoir faire : répondre au protocole que Claude Code parle à son
API, l'adresse étant passée par `ANTHROPIC_BASE_URL`. C'est ce qui permet à DeepSeek
de remplacer Claude.

Contrat minimal d'un harnais, la seule chose que les scripts et les consignes lui
demandent :

1. lire et écrire des fichiers ;
2. exécuter une commande shell ;
3. parler à un modèle.

Le reste (worktree, juge, mesures, fiches) est dans les scripts et les consignes.

## 13. Registre des agents

Coûts en dollars lus dans les colonnes `profil` et `cout_usd` de
`orchestration/mesures/agents.tsv` ; « non mesuré » quand le fichier n'en dit rien.

| Agent | Défini dans | Modèle | Permissions | Coût moyen | Ne peut pas |
|---|---|---|---|---|---|
| **Conducteur** | [conducteur-tache.md](../.claude/agents/conducteur-tache.md) | `opus` ; `sonnet` sur certaines lignes de `agents.tsv` | Read, Write, Edit, Grep, Glob, Bash, PowerShell, Agent | non mesuré en dollars (abonnement, `cout_usd` vide) | lancer `lancer-agent.sh` ; pousser, rebaser, `reset --hard` |
| **Relecteur** | [relecteur.md](../.claude/agents/relecteur.md) | `opus` ; `sonnet` pour TASK-097 et TASK-098 | Read, Grep, Glob | non mesuré en dollars | écrire, lancer une commande |
| **Rédacteur** | [redacteur-tache.md](../.claude/agents/redacteur-tache.md) | hérité de la session | Read, Write, Edit, Grep, Glob | non mesuré | écrire un script ou un test ; exécuter une commande |
| **Exécutant `deepseek`** | [deepseek.env](modeles/deepseek.env) | `deepseek-flash` | [limites.json](limites.json) | moyenne 0,120 $ sur 82 lignes ; minimum 0,000 $, maximum 0,305 $ | ce que refuse `limites.json` (§1) |
| **Exécutant `anthropic`** | [anthropic.env](modeles/anthropic.env) | `haiku` (défaut), `sonnet`, `opus` | [limites.json](limites.json) | non mesuré : aucune ligne `anthropic` | idem |
| **Exécutant `sonnet`, `opus`, `haiku`** | `lancer-agent.sh`, sans profil | l'alias demandé | [limites.json](limites.json) | non mesuré en dollars (abonnement) | idem |

Tarif de `anthropic` (`anthropic.env`, relevé le 2026-09-19 sur
`platform.claude.com/docs/en/about-claude/pricing`), en dollars par million de jetons,
entrée / lecture du cache / sortie : `haiku` (`claude-haiku-4-5`) 1,00 / 0,10 / 5,00 ;
`sonnet` (`claude-sonnet-5`) 2,00 / 0,20 / 10,00 ; `opus` (`claude-opus-5`)
5,00 / 0,50 / 25,00. L'écriture de cache est comptée au tarif de lecture : le coût
affiché est sous-estimé (A184). Tarif `deepseek` : 0,30 / 0,006 / 1,20, relevé au
2026-09-14, en heures de pointe.

## 14. Inventaire des capacités

« Générique » : rien dans le script ne dépend de ce dépôt. Cette colonne désigne ce que
TASK-095 peut extraire.

| Script | Ce qu'il sait faire | Générique ou propre au projet |
|---|---|---|
| `lancer-agent.sh` | faire exécuter une tâche par un agent dans une copie isolée, `--modele`, `--dry-run`, `--relecture`, mesure du coût | **mixte** (le générique vit désormais dans `lib-agents.sh`, TASK-095). Propre : `tasks/active/`, branche `agent/<TASK>`, consigne `/executer-tache`, `limites.json`, l'en-tête à 11 colonnes d'`agents.tsv` (passé en argument à `journal_agents`) |
| `lib-agents.sh` | copie isolée par `git worktree`, plafond `DUREE_MAX`, lecture d'un profil `.env`, relevé de jetons dans le transcript de session, écriture d'une ligne de journal tabulé | **générique** : ne connaît ni ce dépôt ni le schéma d'`agents.tsv`, reçu en argument par l'appelant (TASK-095) |
| `juger.sh` | shellcheck, fichier de cas en conteneur, règles transverses | **propre** : lit le `scope` d'une fiche, lance `tests/env/run-in-container.sh` et `TASK-011` |
| `clore-tache.sh` | écrire la clôture : fiche vers `completed/`, backlog, journal, mesures | **propre** : `tasks/completed/`, `backlog.md`, `journal.md`, `agents.tsv` |
| `verifier-travail.sh` | périmètre, longueur, juge, validations de la fiche | **propre** : branche `agent/<TASK>`, `master`, champ `validation` d'une fiche, `juger.sh` |
| `verifier-liens.sh` | lister les liens Markdown morts | **propre** : suit les fiches qui passent de `pending/` à `active/`, ignore `tasks/completed/` |
| `resoudre-cle.sh` | écrire sur stdout la valeur d'une variable : environnement, puis variables utilisateur de Windows | **générique** : n'a besoin que d'un nom de variable |
| `lien-ecrit.awk` | signaler une écriture à travers un lien symbolique dans un fichier de cas | **propre** : cible les fichiers de cas du dépôt (A122), appelé par `juger.sh` |
