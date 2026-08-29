# Audit du dépôt — préalable à la transformation en plateforme agentique

**Date** : 2026-08-27
**Commit audité** : `0ca655e`
**Objet** : état des lieux factuel du dépôt `MGNetworking/script` avant l'ajout
d'une couche d'orchestration agentique. Ce document décrit **ce qui existe
réellement**. Ce qui manque est signalé comme manquant, jamais supposé.

> **Note du 2026-08-28.** Le constat de cet audit reste valable ; la solution
> retenue a changé. Les sections 16, 17 et 18 décrivent une construction sur
> mesure — orchestrateur, couche d'outils, adaptateurs multi-fournisseur — qui a
> été **abandonnée** au profit de Claude Code comme moteur d'exécution. Voir
> [ADR-0002](decisions/ADR-0002-claude-code-comme-moteur.md).
>
> Ce document n'est pas réécrit : un audit est daté, et sa valeur tient à ce
> qu'il a constaté ce jour-là.

---

## 1. Nature du projet

Bibliothèque personnelle de scripts d'administration Linux / K3s / Kubernetes /
Docker / Synology. Aucun code applicatif, aucun service, aucun binaire produit :
le livrable est un ensemble de scripts Bash déployés par `git clone` sur un
serveur cible.

Conséquence directe pour l'agentique : **il n'existe ni build, ni artefact, ni
suite de tests**. La « preuve » que le plan de transformation attend des tests
devra être entièrement construite.

---

## 2. Structure réelle

```text
.
├── CLAUDE.md                     règles du dépôt (chargées à chaque session)
├── README.md                     présentation, index des scripts
├── .gitattributes                eol=lf
├── .gitignore                    logs/, config/*.env, .idea, .vscode…
├── .claude/settings.json         9 permissions Bash en lecture seule
├── lib/
│   └── common.sh                 217 l. — socle partagé
├── config/
│   ├── README.md
│   └── server.env.example        modèle ; server.env non versionné
├── docs/
│   ├── architecture-technique.md 316 l. — référence durable du socle
│   ├── refactorisation-plan.md   956 l. — backlog du chantier
│   ├── guide-dispatcher.md       521 l. — patterns de parsing CLI
│   └── points-en-suspens.md       72 l. — registre des sujets écartés
├── Linux/System/                 6 scripts + README
├── Synology/Plex/                2 scripts hérités + README
├── Synology/Administration/      README seul, aucun script
└── logs/                         sorties d'exécution locales (non versionné)
```

31 fichiers versionnés. Les répertoires `Linux/Security`, `Linux/Docker`,
`Linux/K3s`, `Kubernetes/`, `Docker/` de l'architecture cible **n'existent pas
encore** : ils sont décrits dans le plan, pas créés.

---

## 3. Technologies et dépendances

| Élément | État |
|---|---|
| Langage | Bash 4+, `set -Eeuo pipefail` partout |
| Dépendances de build | aucune |
| Gestionnaire de paquets | aucun |
| Bibliothèques tierces | aucune |
| Dépendances d'exécution | utilitaires système : `apt`, `systemctl`, `hostnamectl`, `timedatectl`, `swapon`, `logrotate` |
| Cibles supportées | Debian, Ubuntu (`require_os debian ubuntu`), Synology DSM pour les scripts Plex |

Le dépôt est volontairement sans dépendance. Toute brique agentique introduisant
un runtime tiers rompt cette propriété — voir §12.

---

## 4. Socle commun — `lib/common.sh`

Chargé par trois lignes de résolution de racine placées en tête de chaque script.
Fournit :

- journalisation : `info` `warn` `error` `success` `die`, avec écriture
  simultanée écran + fichier `<LOG_DIR>/<script>.log` ;
- capture de sortie : `run_logged`, `enable_full_logging` ;
- préflight : `require_root`, `require_cmd`, `require_os`, `detect_os` ;
- interaction : `confirm`, contournable par `ASSUME_YES=true` ;
- configuration : `load_config <contexte>` vers `config/<contexte>.env` ;
- garde anti-double-chargement, trap `ERR` avec numéro de ligne.

`config/server.env` est le seul fichier chargé automatiquement.

**Lecture agentique** : ce socle est déjà un embryon de harness pour les scripts
eux-mêmes (journalisation uniforme, codes de retour, confirmations
contournables). `ASSUME_YES` et `--dry-run` sont les deux leviers qui rendent ces
scripts pilotables sans humain.

---

## 5. Build, tests, lint, CI

| Attendu | Présent |
|---|---|
| Système de build | **aucun** — rien à compiler |
| Tests unitaires | **aucun** |
| Tests d'intégration | **aucun** |
| Framework de test | **aucun** (ni `bats`, ni harnais maison) |
| Lint | **aucun fichier de configuration**, aucun `.shellcheckrc` |
| Formatage | **aucun** (`shfmt` non configuré) |
| CI / GitHub Actions | **aucun** — pas de `.github/` |
| Hooks Git | aucun hook versionné |

`.claude/settings.json` autorise `shellcheck`, `bash -n` et `shfmt` : l'intention
d'un contrôle statique existe, l'outillage correspondant n'a jamais été installé
ni exécuté.

**C'est le manque le plus structurant du dossier.** Sans validation exécutable,
un validator n'a rien à lancer et la règle « les tests produisent la preuve »
reste lettre morte.

---

## 6. Scripts existants

| Script | Lignes | Root | Modifie le système | `--dry-run` | `--help` |
|---|---|---|---|---|---|
| `Linux/System/system-info.sh` | 213 | non | non | s.o. | oui |
| `Linux/System/update-system.sh` | 128 | oui | oui | non | oui |
| `Linux/System/configure-logging.sh` | 173 | oui | oui | oui | oui |
| `Linux/System/configure-hostname.sh` | 269 | oui | oui | oui | oui |
| `Linux/System/configure-timezone.sh` | 232 | oui | oui | oui | oui |
| `Linux/System/configure-swap.sh` | 346 | oui | oui | oui | oui |
| `Synology/Plex/organize-series.sh` | 252 | — | oui | — | — |
| `Synology/Plex/update-plex.sh` | 80 | — | oui | — | — |

Les six scripts `Linux/System` sont au standard du dépôt. Les deux scripts
Synology sont hérités : ils ne chargent pas `lib/common.sh` et ne respectent pas
les conventions — leur mise au standard est une tâche identifiée du plan.

---

## 7. Documentation

Dense et à jour, à rôles distincts :

- `CLAUDE.md` — conventions permanentes, arborescence cible, secrets ;
- `docs/architecture-technique.md` — **référence durable** du socle ;
- `docs/refactorisation-plan.md` — **document temporaire**, caduc à la fin du
  chantier ;
- `docs/guide-dispatcher.md` — patterns de parsing d'arguments ;
- `docs/points-en-suspens.md` — registre des sujets écartés volontairement.

Un `README.md` par domaine (`Linux/System`, `Synology/Plex`,
`Synology/Administration`, `config`).

La documentation est mise à jour dans le même commit que le code — vérifié sur
les cinq derniers commits.

---

## 8. Git

- Remote : `git@github.com:MGNetworking/script.git`, dépôt **public** ;
- branche unique : `master`, aucune branche de travail, aucune PR ;
- 33 commits, dont 12 depuis la mise en place du socle technique ;
- messages conventionnels depuis `1f7901a` :
  `feat(linux/system):`, `fix(linux/system):`, `docs:`, `chore:`, `refactor:` ;
- arbre propre au moment de l'audit ;
- aucune convention de branche, aucune protection, aucun modèle de PR.

---

## 9. Backlog actuel

Le backlog existe : c'est `docs/refactorisation-plan.md`. Il est **narratif et
hiérarchique**, organisé en 19 sections par domaine, et décrit environ soixante
scripts, dont huit sont écrits.

Structure d'une entrée type (section 1, `check-disk.sh`) : un titre, un
paragraphe de rôle, parfois une liste de ce que le script doit afficher ou
vérifier. L'avancement est marqué à la main par la mention « — fait » dans les
titres de section.

Ce que le backlog **possède déjà** :

- un découpage en unités de travail correspondant à un script chacune ;
- un ordre de développement en cinq phases (§17) ;
- une première cible concrète (§19) ;
- des descriptions d'objectif exploitables.

Ce qui **manque** pour qu'un orchestrateur puisse s'en servir :

- identifiants stables (`TASK-001`) ;
- statut par tâche dans un champ lisible par machine ;
- dépendances explicites entre tâches ;
- périmètre et hors-périmètre ;
- critères d'acceptation ;
- **commandes de validation** ;
- séparation d'une tâche par fichier permettant un suivi et un verrouillage.

`docs/points-en-suspens.md` joue le rôle d'un second backlog, pour les sujets
transverses (mise en cron, remontée d'échec des tâches planifiées). Ses deux
entrées sont datées et structurées ; elles constituent de bonnes candidates à une
conversion en tâches.

---

## 10. Conventions du projet

Extraites de `CLAUDE.md` et vérifiées dans le code :

1. en-tête obligatoire en trois lignes, résolution de racine, `set -Eeuo pipefail` ;
2. nommage `verb-noun.sh` ;
3. responsabilité unique : installation, configuration, vérification et
   maintenance dans des scripts distincts ;
4. messages préfixés `[INFO]` `[WARN]` `[ERROR]` `[SUCCESS]` ;
5. idempotence : lire l'état, comparer, ne modifier que si nécessaire — jamais
   d'`echo >>` aveugle ;
6. `--dry-run` sur toute opération destructive ;
7. aucune suppression de données sans confirmation explicite ;
8. ne jamais redéfinir localement ce que `common.sh` fournit ;
9. `--config <nom>` pour tout script chargeant une configuration ;
10. aucun secret versionné ;
11. documentation mise à jour dans le même commit ;
12. **toute la production est en français**, y compris commentaires, messages et
    noms de variables internes.

Le point 12 n'est écrit nulle part comme une règle mais s'observe sans exception
dans les 3 980 lignes du dépôt. Il devra être inscrit explicitement dans
`AGENTS.md` : un agent ne peut pas le deviner.

---

## 11. Points d'entrée et commandes disponibles

Il n'existe aucun point d'entrée unique — pas de `Makefile`, pas de `run.sh`.
Chaque script est son propre point d'entrée :

```bash
./Linux/System/system-info.sh
sudo ./Linux/System/configure-swap.sh 2G --dry-run
sudo ./Linux/System/update-system.sh --yes
```

Toutes les commandes de vérification actuellement possibles sont manuelles et
non outillées : lecture du code, exécution du script sur un serveur réel.

---

## 12. Outillage de la machine hôte

Relevé sur le poste de développement (Windows 11, Git Bash / MSYS2) :

| Outil | État |
|---|---|
| `bash` | 5.2.37 (MSYS2) |
| `git` | présent |
| `node` | v26.3.0 |
| `docker` | binaire présent, **démon arrêté** (Docker Desktop) |
| `wsl` | présent — distribution `Ubuntu-24.04` installée, **arrêtée** |
| `shellcheck` | **absent** |
| `shfmt` | **absent** |
| `bats` | **absent** |
| `python` / `python3` | **absent** (seul l'alias Microsoft Store répond) |
| `make`, `jq`, `yq`, `go` | **absents** |

Deux conclusions.

**L'hôte ne peut pas exécuter les scripts du dépôt de façon significative.** Git
Bash n'a ni `systemctl`, ni `apt`, ni `swapon`, ni `/etc/os-release` : le premier
`detect_os` échoue. La phase « environnement = hôte » du plan de transformation
n'est donc pas applicable telle quelle ici — l'hôte ne peut servir qu'à
l'analyse statique. Toute validation comportementale exige WSL, un conteneur ou
une VM, **dès la première boucle**.

**Le choix du runtime de l'orchestrateur est contraint** : Python n'est pas
installé, Node l'est. Voir §18.

---

## 13. Éléments à ne jamais modifier automatiquement

| Chemin | Raison |
|---|---|
| `config/*.env` (hors `.example`) | non versionnés, propres à la machine, peuvent contenir des valeurs sensibles |
| `.git/` | intégrité de l'historique |
| `logs/` | sorties d'exécution, sans valeur de source |
| `.gitattributes` | `eol=lf` conditionne l'exécutabilité de tout le dépôt sous Linux |
| `lib/common.sh` | socle chargé par tous les scripts ; toute régression est globale — modification possible mais jamais en effet de bord d'une autre tâche |
| `CLAUDE.md` | contrat humain du dépôt |
| `.idea/` | configuration IDE personnelle |

À quoi s'ajoute, hors dépôt et de façon absolue : le système de la machine hôte.
Aucune commande agentique ne doit écrire hors du répertoire de travail et de
l'environnement de test isolé.

---

## 14. Risques identifiés

1. **Absence de filet.** Aucun test, aucun lint : une régression dans
   `lib/common.sh` casse les huit scripts sans que rien ne le signale.
2. **Scripts privilégiés et destructeurs.** `configure-swap.sh` écrit dans
   `/etc/fstab` et manipule le swap ; `update-system.sh` installe des paquets ;
   `configure-hostname.sh` réécrit `/etc/hosts`. Les exécuter pour valider une
   tâche sur autre chose qu'une machine jetable est inacceptable.
3. **Dépôt public.** Toute fuite de secret dans un log agentique, un rapport ou
   un état persistant est immédiatement publique.
4. **Branche unique sans protection.** Un commit automatique sur `master` est
   sans garde-fou.
5. **Impossibilité de valider sur l'hôte** (§12) — risque de valider dans le vide
   si le validator se contente de l'analyse statique tout en prétendant couvrir
   le comportement.
6. **Backlog non verrouillable.** Le plan étant un fichier unique de 956 lignes,
   deux tâches concurrentes qui le modifient entrent en conflit.

---

## 15. Manques à combler pour permettre l'automatisation

Par ordre de dépendance :

1. **contrat de l'agent** — `AGENTS.md` : rien n'existe aujourd'hui qui définisse
   ce qu'un agent a le droit de faire ; `CLAUDE.md` définit comment écrire un
   script, pas comment conduire un cycle de travail ;
2. **backlog atomisé** — une tâche = un fichier, avec identifiant, statut,
   dépendances, critères et validations ;
3. **validations exécutables** — au minimum `shellcheck` et `bash -n`, ensuite un
   harnais de tests ;
4. **environnement Linux de test** — WSL ou conteneur, réinitialisable ;
5. **état persistant, logs et rapports** — `.agent/` ;
6. **couche d'outils** — filesystem, shell, git, testing, linux ;
7. **orchestrateur** — planner, executor, validator, machine à états ;
8. **interface LLM** — adaptateurs interchangeables.

Les points 1 à 3 sont réalisables immédiatement et sans décision d'architecture
lourde. Le point 4 nécessite un arbitrage (§18). Les points 5 à 8 en dépendent.

---

## 16. Mapping entre l'existant et l'architecture cible

| Cible | Existant | Décision |
|---|---|---|
| `AGENTS.md` | — | **créer**. Dérive de `CLAUDE.md` sans le dupliquer : `CLAUDE.md` reste la source des conventions d'écriture, `AGENTS.md` y renvoie et ajoute le cycle de travail, les limites et les commandes autorisées. |
| `tasks/backlog.md` | `docs/refactorisation-plan.md` | **adapter, ne pas remplacer.** Le plan reste le document de chantier et la référence de conception ; le backlog agentique en devient l'index exécutable et le référence section par section. Aucune information n'est déplacée ni perdue. |
| `tasks/active` `completed` `blocked` | — | **créer**. Une tâche par fichier : lève le risque de conflit du §14.6. |
| Format de tâche | descriptions narratives du plan | **créer**, en reprenant le contenu existant comme `objective` et `scope`. |
| `.agent/state/` | — | **créer**. |
| `.agent/logs/` | `logs/` (sorties des scripts administrés) | **séparer**. `logs/` appartient aux scripts, `.agent/logs/` à l'agent. Ne pas mélanger deux natures de journaux. |
| `.agent/reports/` | — | **créer**. |
| `.agent/config/` | `config/*.env` | **séparer strictement**. `config/` décrit les serveurs administrés ; `.agent/config/` décrit l'agent. Aucune interaction. |
| `.agent/tools/` | `lib/common.sh` | **distinct.** `common.sh` est le socle des scripts produits, pas celui de l'agent. Ne pas le charger de responsabilités agentiques. |
| `.agent/prompts/` | — | **créer**. |
| `.agent/providers/` | `.claude/settings.json` | `.claude/` devient un **adaptateur** dérivé de `.agent/`, conformément au principe de découplage. Le fichier existant est conservé et enrichi, pas remplacé. |
| `tests/` | — | **créer**. N'existe sous aucune forme. |
| `src/` | s.o. | **sans objet** : le dépôt n'a pas de code applicatif ; les scripts *sont* la source. Ne pas créer ce répertoire. |
| Environnement d'exécution | WSL `Ubuntu-24.04` installée | **réutiliser** plutôt que provisionner une VM. |

---

## 17. Fichiers à créer ou modifier

Périmètre des phases 2 à 7 du plan de transformation, dans l'ordre imposé.

### À créer

```text
AGENTS.md                          contrat de l'agent
tasks/backlog.md                   index exécutable, renvoie au plan
tasks/README.md                    format de tâche, statuts, cycle de vie
tasks/active/                      (vide au départ)
tasks/completed/
tasks/blocked/
tasks/pending/TASK-0xx.md          tâches issues du plan et des points en suspens
.agent/config/agent.yaml           limites, retries, machine à états
.agent/config/tools.yaml           outils exposés et commandes autorisées
.agent/config/environment.yaml     host | wsl | container
.agent/config/validation.yaml      niveaux de validation
.agent/config/providers/claude.yaml
.agent/prompts/{system,planner,executor,validator,reviewer}.md
.agent/state/.gitkeep              état non versionné
.agent/logs/.gitkeep               logs non versionnés
.agent/reports/                    rapports versionnés (traçabilité)
.agent/tools/*.sh                  filesystem, shell, git, testing, linux
tests/README.md                    conventions de test
tests/lint.sh                      shellcheck + bash -n sur tout le dépôt
tests/run.sh                       point d'entrée unique des validations
docs/agent/project-audit.md        ce document
docs/agent/decisions/              journal des décisions d'architecture
```

### À modifier

```text
.gitignore                     ignorer .agent/state/, .agent/logs/, .agent/runtime/
README.md                      mentionner la couche agentique et tasks/
CLAUDE.md                      renvoyer vers AGENTS.md (une ligne, sans duplication)
.claude/settings.json          permissions nécessaires aux validations locales
docs/refactorisation-plan.md   renvoi en tête vers tasks/backlog.md
docs/points-en-suspens.md      marquer les entrées converties en tâches
```

### À ne pas toucher

`lib/common.sh`, `config/`, les huit scripts, `.gitattributes`,
`docs/architecture-technique.md`, `docs/guide-dispatcher.md`, `logs/`.

---

## 18. Décisions ouvertes

Quatre points ne pouvaient pas être tranchés depuis le seul contenu du dépôt.
Les trois premiers ont été arbitrés le 2026-08-27 —
voir [ADR-0001](decisions/ADR-0001-socle-agentique.md). Les recommandations
ci-dessous sont conservées telles qu'elles ont été formulées, suivies de la
décision retenue.

**a. Runtime de l'orchestrateur.** Bash (cohérent avec le dépôt, zéro
dépendance, mais pénible pour JSON, HTTP et machine à états — sans `jq`
installé) ou Node (présent, bibliothèque standard seule, sans `package.json` ni
dépendance externe). Recommandation : outils en Bash, orchestrateur et
adaptateurs LLM en Node avec la seule bibliothèque standard.
→ **Retenu** : outils en Bash, orchestrateur et adaptateurs en Node (stdlib).

**b. Environnement de validation.** L'hôte ne peut pas exécuter les scripts
(§12). Recommandation : WSL `Ubuntu-24.04` dès la phase 1, avec conteneur Docker
jetable pour les tests destructeurs quand le démon est démarré.
→ **Retenu** : conteneur Docker jetable, deux profils (`debian` et `systemd`).
Le démon Docker doit être démarré ; à défaut, l'agent s'arrête au lieu de
prétendre valider.

**c. Commit automatique.** Le plan de transformation propose
`automatic_commit: true`. Une consigne permanente en vigueur pour ce dépôt
interdit tout commit non demandé explicitement. Le conflit doit être arbitré
avant que l'agent ne dispose de l'outil Git en écriture. Recommandation :
`automatic_commit: false` par défaut ; l'agent prépare le commit et s'arrête.
→ **Retenu** : commit automatique, mais sur une branche dédiée `agent/TASK-xxx`
uniquement. Jamais sur `master`, jamais de `git push`. La fusion reste humaine.

**d. Périmètre du travail agentique.** Le backlog du plan comporte une
cinquantaine de scripts privilégiés et destructeurs. Il faut décider lesquels
sont éligibles à l'exécution autonome et lesquels exigent une validation
humaine (`human_approval_required: true`) — par exemple tout ce qui touche au
partitionnement, au pare-feu ou à SSH.

---

## 19. Conclusion

Le dépôt est sain, cohérent et bien documenté, mais **il ne possède aucune
infrastructure de vérification**. La transformation agentique ne bute donc pas
sur l'orchestration, qui est à construire de zéro sur un terrain vierge, mais
sur la production de la preuve : sans lint, sans tests et sans environnement
Linux, un agent ne peut rien démontrer.

L'ordre de travail qui en découle inverse légèrement la priorité du plan : le
contrat (`AGENTS.md`) et le backlog structuré d'abord, puis **immédiatement les
validations exécutables et l'environnement WSL**, avant tout code
d'orchestration.
