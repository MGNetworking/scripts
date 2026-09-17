# Proposition — Ansible, cadre de test et refonte de `tests/README.md`

Écrite le 2026-09-17, à l'étape 4 de la boucle de la décision 49. **Rien n'est décidé** :
proposition à valider par user, puis consignée en décision 50. À supprimer ensuite.

---

## 1. Contexte

- **Parc** : 2 VPS (Debian/Ubuntu, dont un en K3s) et 1 NAS Synology.
- **Objectif** : un outillage qui fonctionne **et** une montée en compétence
  professionnelle.
- **Constats** du 2026-09-17 :
  - `tests/README.md` fait 1 514 lignes et s'est transformé en journal ;
  - aucun cadre de test ne relie les tests aux contrats des `CADRAGE.md` ;
  - aucune CI ;
  - le déploiement par `git pull` fait arriver tout changement de `master` sur les
    serveurs ;
  - une bonne part des scripts reconstruit à la main ce qu'Ansible fournit
    (idempotence, simulation, inventaire).
- **Poste de contrôle constaté** : WSL Ubuntu 24.04 et Docker Desktop fonctionnent,
  Python 3.12 est présent, Ansible ne l'est pas.

## 2. Répartition proposée : chaque outil à sa place

| Domaine | Outil cible | Forme |
|---|---|---|
| `Linux/System`, `Linux/Security` : scripts `configure-*`, `manage-users` | Ansible | rôles |
| `Docker/Installation`, `Docker/Configuration`, `Docker/Maintenance/update-docker` | Ansible | rôles |
| `Linux/K3s` : installation, configuration, mise à jour, désinstallation | Ansible | rôle |
| `Kubernetes/Installation` et `Configuration` | Ansible, collection `kubernetes.core` | manifestes et valeurs Helm versionnés, appliqués par un rôle |
| Diagnostics en lecture seule : `check-*`, `audit-*`, `security-check`, `verify-k3s`, `Docker/Diagnostics`, `Kubernetes/Maintenance` | **Bash, conservé** | scripts lancés sur le serveur ou en cron |
| Exploitation ponctuelle : `notify-failure`, `backup-resources`, `cleanup-resources`, `docker-cleanup`, `update-images`, `reboot-system` | **Bash, conservé** | scripts |
| `Synology/` | **Bash, conservé**, non prioritaire | scripts |

Pas de GitOps (Flux, Argo CD) à ce stade : un seul nouvel outil à la fois. Il pourra
se discuter une fois Ansible maîtrisé.

## 3. Ce qui change dans le fonctionnement

- **Poste de contrôle** : WSL Ubuntu 24.04. Ansible et Molecule s'installent par
  `pipx`, mécanisme officiel. Les serveurs n'ont besoin que de SSH et de Python.
- **Déploiement** : pour tout ce qui relève d'Ansible, les serveurs ne tirent plus
  rien. user applique :
  1. `ansible-playbook --check --diff` pour voir les changements ;
  2. la même commande sans `--check` pour les appliquer ;
  3. serveur par serveur (`--limit`).

  Les scripts Bash conservés gardent le `git clone`.
- **Dépôt public** : l'inventaire réel (adresses, utilisateurs) et les variables par
  machine restent hors Git, comme `config/*.env`. Sont versionnés
  `inventory.example.yml` et des `host_vars/*.example.yml`. Les secrets passent par
  Ansible Vault ou des fichiers locaux ignorés.
- **Arborescence** : un dossier racine `Ansible/` (`roles/`, `playbooks/`,
  `inventory.example.yml`, `CADRAGE.md`, `README.md`). L'arborescence cible de
  `CLAUDE.md` est mise à jour.

## 4. Continuité avec la décision 49 (cadrage)

- **Contrat d'un rôle** : ses variables et leurs défauts, déclarés dans
  `meta/argument_specs.yml`. Ansible refuse de lui-même une variable mal typée ou
  inconnue. S'y ajoutent l'état garanti et les fichiers ou services touchés.
  `Ansible/CADRAGE.md` porte ces contrats.
- **Remplacement d'un script Bash par un rôle** : c'est un changement incompatible
  (autre mode d'appel). Le script est **déprécié avec une date** dans son cadrage et
  n'est supprimé que par décision de user, une fois les 2 VPS passés par le rôle.
- **Les écarts du registre** (A130 à A142) ne se corrigent pas dans un script voué à
  la dépréciation : le rôle naît sans eux. Ceux des scripts conservés restent à
  traiter.

## 5. Cadre de test

### 5.1 Principes communs

1. **Contrat → preuve** : chaque contrat d'un `CADRAGE.md` porte une ligne
   `Prouvé par :` qui nomme le fichier de cas ou le scénario Molecule. Une clause sans
   preuve est un manque visible, et le relecteur le signale.
2. **Trois niveaux de preuve, toujours nommés** :
   - **simulé** : faux binaires, la logique seule est prouvée ;
   - **conteneur** : l'outil réel dans un conteneur jetable ;
   - **machine** : constaté sur un VPS par user.

   Une preuve ne se présente jamais comme plus forte qu'elle n'est.
3. **CI obligatoire** : aucun push sur `master` dont la CI est rouge.

### 5.2 Rôles Ansible — l'outillage standard

| Outil | Rôle |
|---|---|
| `ansible-lint`, `yamllint` | analyse statique, l'équivalent de `shellcheck` |
| **Molecule** (pilote Docker) | crée un conteneur Debian ou Ubuntu, applique le rôle (`converge`), le rejoue et **échoue si quelque chose change** (`idempotence`), vérifie l'état (`verify.yml`, assertions Ansible, sans dépendance de plus) |
| `--check --diff` sur un VPS | niveau « machine », avant toute application réelle |

L'idempotence, que le dépôt prouve aujourd'hui par des centaines de lignes, devient
une étape native.

### 5.3 Scripts Bash conservés

- **Analyse statique** : `shellcheck` inchangé.
- **Tests** : le harnais actuel (`tests/run.sh`, `assert.sh`, conteneurs) est
  **conservé**. Le migrer vers `bats-core` coûterait beaucoup pour peu de gain sur une
  vingtaine de scripts (question 2).
- **Scripts dépréciés** : leurs fichiers de cas disparaissent avec eux.

### 5.4 CI — GitHub Actions

Sur chaque push et chaque pull request :

1. lint (`shellcheck`, `ansible-lint`, `yamllint`) ;
2. tests Bash en conteneur Debian ;
3. Molecule sur les rôles modifiés.

Durée visée : moins de 15 minutes.

## 6. Refonte de `tests/README.md`

**Constat** : 1 514 lignes. Environ les deux tiers racontent des défauts passés
(« Trois écarts relevés ici », « Cinq enseignements »…) déjà tracés dans les rapports
de tâche et dans Git.

**Cible** : 200 lignes au plus, un guide et non un journal.

1. Ce que ce dossier prouve, les trois niveaux de preuve (§5.1).
2. Lancer : `tests/run.sh`, niveaux, conteneur, CI.
3. Écrire un fichier de cas : squelette, `assert.sh`, faux binaires. Les règles
   durables tiennent en une ligne chacune.
4. Codes de retour d'un niveau et de `run.sh`.
5. Environnement conteneurisé : profils `debian` et `systemd`, `assurer-docker.sh`.
   L'essentiel seulement ; le détail va dans les commentaires du script.
6. Molecule : renvoi vers `Ansible/README.md`.

**Méthode** : chaque règle encore vraie est gardée en une phrase. Chaque récit est
supprimé, puisqu'il existe dans un rapport. Un tableau de correspondance dans le
rapport de tâche prouve qu'aucune règle vivante n'a été perdue.

## 7. Plan d'exécution, après validation

| # | Tâche | Dépend de |
|---|---|---|
| 1 | Refondre `tests/README.md` (§6) — indépendante d'Ansible | — |
| 2 | Décision 50, mise à jour de `CLAUDE.md`, des consignes et de l'architecture | validation |
| 3 | Poste de contrôle et squelette : Ansible et Molecule dans WSL, `Ansible/`, inventaire d'exemple, CI de lint | 2 |
| 4 | **Pilote** : rôle `securite_base` (SSH, pare-feu `ufw`, fail2ban), Molecule, contrat dans `Ansible/CADRAGE.md`, `--check --diff` sur un VPS par user | 3 |
| 5 | Bilan du pilote comparé aux trois scripts Bash (lignes, durée des tests, lisibilité, défauts). **user décide** de poursuivre ou non | 4 |
| 6 | Selon ce choix : plan de migration par domaine, selon la boucle ; ensuite TASK-039 | 5 |

La ligne `Prouvé par :` (§5.1) s'ajoute aux cadrages existants dans une tâche à part,
après le pilote : pas avant de savoir quels scripts restent.

## 8. Questions ouvertes, en une série

1. Valides-tu la répartition du §2 (Ansible pour installer et configurer, Bash pour
   diagnostiquer, exploiter et Synology) ?
2. Tests Bash conservés : garder le harnais actuel (recommandé) ou passer à
   `bats-core` ?
3. Pilote : `securite_base` (SSH, pare-feu, fail2ban) comme premier rôle ?
4. Refonte de `tests/README.md` : la lancer tout de suite, avant la décision 50 ?
