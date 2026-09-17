# Reprise — cadrage des scripts par dossier

Fichier de passation écrit le 2026-09-17 avant un vidage de session. **Rien de ce qui
suit n'est encore décidé** : c'est une proposition construite avec `user`, à valider
avant toute modification. À supprimer une fois la décision prise et consignée.

Pour reprendre, `user` écrit : « lis `docs/reprise-cadrage.md` et reprends ».

---

## 1. Contexte

- Domaines **K3s** (TASK-050 à 054) et **Kubernetes** (TASK-055 à 071, et 066) terminés,
  poussés sur GitHub (`1dc8bba`). Outillage corrigé par TASK-072.
- Architecture de l'orchestration consignée dans
  [orchestration/architecture.md](../orchestration/architecture.md) (4 schémas Mermaid),
  affiche [orchestration/orchestration.png](../orchestration/orchestration.png) générée
  depuis [orchestration/orchestration.html](../orchestration/orchestration.html).
- **Commits non poussés** : `8ceb891` (architecture.md), `3ebf722` (affiche de user),
  `7a43ffe` (affiche reconstruite), plus le commit de ce fichier. Le push attend `user`.

**Constat de départ de user.** Rien ne dit comment naît une tâche. L'affiche laisse croire
que tout commence par `/atomiser`, commande que `user` n'a jamais tapée : c'est la session
qui en suit la procédure quand `user` le demande. Les tâches sont nées de trois sources :
le plan initial (`docs/refactorisation-plan.md`), une demande dans la conversation
(TASK-049), un défaut découvert pendant une tâche (TASK-048, TASK-072). L'étape
« déterminer un besoin » n'est écrite nulle part.

**Problème de fond soulevé par user.** Un script peut déjà tourner sur plusieurs serveurs,
dans des crons ou d'autres processus. Le modifier peut les casser. Les scripts se déploient
par `git clone` : un changement sur `master` atteint tous les serveurs au prochain
`git pull`. L'évolution des scripts doit donc être cadrée strictement et assumée.

## 2. Deux besoins exprimés par user

1. **Un fichier de cadrage par grand dossier**, garant du périmètre des scripts : il expose
   le besoin initial. Avant toute demande sur un script, l'IA le lit, puis valide ou
   propose (nouveau script, changement structurel assumé).
2. **Décrire comment naissent les tâches** : par une boucle de réflexion entre le besoin de
   user et les scripts existants, sur les plans fonctionnel et technique.

## 3. Choix déjà faits par user

| # | Question | Réponse de user |
|---|---|---|
| 1 | Niveau du cadrage | **Un fichier par grand dossier** : `Linux/`, `Docker/`, `Kubernetes/`, `Synology/`. Deux sortes de scripts : ceux d'un **ensemble** (fonction globale, ex. la gestion de Kubernetes) et les **scripts individuels** (autonomes, ex. Synology). |
| 2 | Usages sur les serveurs | **Aucune information serveur dans le dépôt** (public). Règle : **tout ce qui figure au contrat est réputé utilisé** ; le modifier est une rupture. Pas d'inventaire à tenir. |
| 3 | Rupture de contrat | Correction et **ajout compatible** (option désactivée par défaut) autorisés après validation. **Changement incompatible : jamais sur le script existant** ; nouveau script, l'ancien marqué « déprécié » avec une date, supprimé seulement par décision de user après migration. |
| 4 | Scripts déjà écrits | L'état actuel est la **base de départ** : ils appartiennent tous à un ensemble, sauf les scripts individuels. Leur comportement actuel devient leur contrat initial. |
| 5 | Autorité | **Seul user valide** une modification du cadrage. L'IA ne fait que proposer. |

Écartées : inventaire privé des usages ; versions Git épinglées par serveur ; option
qui garde l'ancien comportement à vie.

## 4. Proposition à valider

### 4.1 `CADRAGE.md` dans chaque grand dossier

```markdown
# Cadrage — Kubernetes/

## Besoin
Pourquoi ce dossier existe : le problème réglé, pour qui, dans quel contexte
(VPS mono-nœud K3s…). Ce qui est hors besoin.

## Ensembles
### Gestion de Kubernetes
- Fonction globale : ce que l'ensemble garantit une fois ses scripts appliqués.
- Scripts membres et ordre : install-* → configure-* ; Maintenance/ à tout moment.
- Conventions communes : accès au cluster (décision 48), codes de retour,
  variables SRV_K8S_* de config/server.env.

## Scripts individuels
(aucun dans Kubernetes/ ; dans Synology/, un bloc par script autonome)

## Contrats
### configure-namespaces.sh — ensemble « Gestion de Kubernetes »
- Besoin : créer les namespaces déclarés.
- Fait : … Ne fait pas : …
- Options et défauts : --dry-run, --yes, --config…
- Codes de retour : 0 … 1 … 2 …
- Modifie sur la machine ou le cluster : …
- Lit : SRV_K8S_NAMESPACES
- État : actif | déprécié le AAAA-MM-JJ, remplacé par …

## Historique du cadrage
| Date | Changement | Nature (correction, ajout compatible, nouveau script, dépréciation) | Validé par user |
```

Répartition avec l'existant : le **README** du dossier **explique** (usage, exemples,
risques) ; le **cadrage** **engage** (besoin, contrat, décisions) ; `decisions.md` garde
les décisions transverses.

### 4.2 Boucle de réflexion, avant toute tâche

```text
1. Besoin          user l'exprime dans la conversation, en langage normal
2. Lecture         l'IA lit le CADRAGE.md du dossier, le README, les décisions,
                   les scripts voisins (plans fonctionnel et technique)
3. Confrontation   déjà couvert ? dans quel ensemble ? touche-t-il un contrat ?
4. Proposition     une issue et ses conséquences :
                   a. déjà couvert → rien à faire, montrer comment
                   b. correction (rétablit le contrat)
                   c. ajout compatible (option désactivée par défaut)
                   d. nouveau script (dans un ensemble, ou individuel)
                   e. changement incompatible → nouveau script + ancien déprécié
5. Questions       les choix ouverts, posés une par une
6. Validation      user seul ; le cadrage est mis à jour et daté
7. Tâches          seulement alors, fiches écrites et mises au backlog
```

Aucune fiche avant l'étape 6. Aucune tâche hors du cadrage validé : le conducteur et le
relecteur vérifient la fiche contre lui.

### 4.3 Conséquences, une fois validé

| Où | Changement |
|---|---|
| `orchestration/decisions.md` | décision 49 : cadrage par grand dossier, contrat réputé utilisé, rupture = nouveau script + ancien déprécié, validation par user seul, boucle de réflexion |
| `orchestration/architecture.md`, `orchestration.html` et `.png` | étape « Besoin et cadrage » avant la création des tâches ; l'affiche montre que user exprime un besoin (pas une commande) et que la session applique `/atomiser` |
| `orchestration/regles.md`, `.claude/commands/tache.md`, `atomiser.md`, `.claude/agents/relecteur.md`, `redacteur-tache.md` | lire le cadrage avant d'écrire une fiche ; signaler ou refuser une fiche qui sort du contrat |
| `docs/refactorisation-plan.md` | reste la trace du chantier initial ; le cadrage prend le relais pour les évolutions |
| `Linux/`, `Docker/`, `Kubernetes/`, `Synology/` | un `CADRAGE.md` chacun, écrit **à partir de l'état actuel** des scripts, relu et validé par user ; une tâche par dossier |

## 5. Plan d'exécution proposé (après validation)

1. `user` valide ou corrige la proposition du §4.
2. Décision 49 dans `decisions.md` ; mise à jour de `architecture.md`, de l'affiche et
   des consignes (§4.3), en une tâche d'orchestration.
3. Premier cadrage : **`Kubernetes/`** (le plus récent, le mieux connu), pour éprouver le
   modèle sur un cas réel ; relu et validé par user.
4. Les trois autres cadrages : `Linux/`, `Docker/`, `Synology/`, une tâche chacun.
5. Ensuite seulement : nouvelles demandes selon la boucle, domaine Synology.

## 6. Points en attente, indépendants du cadrage

- **A127** : `install-ingress.sh` l. 77, `install-cert-manager.sh` l. 114, et peut-être
  `install-kubectl.sh` l. 72 annoncent « apiserver injoignable » pour toute erreur non
  reconnue ; corrigé partout ailleurs.
- **A66** : les commits de l'agent exécutant ne portent pas `Tâche : TASK-XXX`,
  `executer-tache.md` ne le demande pas.
- **A59** : constater dans une session neuve que le conducteur lance bien lui-même le
  relecteur (sa définition était en cache dans la session précédente).
- **A128** : décision de user attendue — inscrire dans `/tache` les sondes en conteneur,
  les mutations et le contrôle de stabilité, pratiqués par les conducteurs sans être
  prescrits, ou les laisser à leur jugement.
- Registre complet : [tasks/pending/TASK-039.md](../tasks/pending/TASK-039.md) (prochain
  identifiant libre A129).
