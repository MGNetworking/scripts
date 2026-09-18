# Plan — l'outil de préparation des serveurs

Écrit le 2026-09-18, validé par user dans la conversation. Tient lieu de feuille de
route jusqu'à la recette `serveur-neuf.yml`. Les identifiants TASK-086 à TASK-092 sont
réservés ; chaque fiche s'écrit au moment de lancer sa tâche, à partir de ce plan.

---

## 1. Ce que l'outil fait

Un serveur nu, une commande, un serveur prêt.

```text
Ton PC (WSL)                              Le serveur
─────────────                             ──────────
dépôt Git                    SSH
Ansible + la recette    ──────────────▶   rien à installer
                         applique
```

La recette s'exécute **depuis ton poste**, par SSH. Rien n'est installé ni copié sur le
serveur : ni Ansible, ni le dépôt, ni un agent permanent. Le serveur n'a besoin que d'un
accès SSH et de Python, qu'il possède déjà.

**Aucun serveur n'est nécessaire pour construire et prouver l'outil** : les conteneurs
Docker jetables de Molecule jouent le rôle de serveurs d'essai, sur Debian 12 et Ubuntu
24.04. Le niveau de preuve « machine » attendra qu'un VPS existe.

## 2. Les quatre parties

| Partie | Rôle | Où |
|---|---|---|
| Les briques | chacune prépare une chose : sécurité, socle, Docker, K3s, Kubernetes | `Ansible/roles/` |
| La recette | enchaîne les briques dans l'ordre | `Ansible/playbooks/serveur-neuf.yml` |
| Les outils d'après | observer et exploiter une machine déjà préparée | `Linux/` `Docker/` `Kubernetes/` `Synology/` |
| La preuve | conteneurs jetables, Molecule, CI | `tests/`, `.github/workflows/` |

Frontière : **préparer** une machine relève d'Ansible ; **observer** ou **exploiter** une
machine déjà préparée reste en Bash (décision 50).

## 3. Ce que deviennent les scripts

| Dossier | Scripts | Vers un rôle | Restent en Bash |
|---|---|---|---|
| `Linux/System` | 13 | 7 `configure-*`, `manage-users` | 5 `check-*`, `notify-failure` |
| `Linux/Security` | 7 | 4 `configure-*`, `disable-root-login` | `audit-users`, `audit-ports`, `security-check` |
| `Linux/K3s` | 5 | installation, configuration, mise à jour, désinstallation | `verify-k3s` |
| `Docker` | 9 | installation, configuration, réseau, mise à jour du moteur | 3 diagnostics, nettoyage, mise à jour des images |
| `Kubernetes` | 17 | 5 installations, 5 configurations | les 7 de maintenance |
| `Synology` | 2 | aucun | 2 (non prioritaire) |

Environ 29 scripts sont absorbés par **6 rôles**. Aucun dossier ne disparaît. Un script
remplacé est **déprécié avec une date** dans son `CADRAGE.md` et reste en place jusqu'à
décision de user (décision 49).

## 4. Qui fait quoi

| Qui | Fait | Ne fait pas |
|---|---|---|
| Opus (session) | ce plan, les décisions avec user | écrire le code |
| Conducteur (Sonnet, puis Haiku à l'essai) | activer, lancer, vérifier, fusionner, clore | écrire le code |
| **DeepSeek** | **écrit les rôles, les scénarios Molecule, la documentation** | pousser, toucher `orchestration/` ou `CLAUDE.md` |
| Relecteur Opus | une lecture par tâche | exécuter quoi que ce soit |

Mesures du 2026-09-18 : DeepSeek 0,057 $ (TASK-083) et 0,187 $ (TASK-085), zéro défaut
majeur. Conducteur Sonnet 36 000 à 199 000 jetons — c'est ce poste que TASK-086 réduit.

## 5. Les tâches

### TASK-086 — Outiller la vérification et la clôture

- **Pourquoi** : environ 70 % des jetons du conducteur partent dans des gestes mécaniques
  qu'un script fait mieux et sans erreur.
- **Contenu** : `orchestration/outils/verifier-travail.sh` (périmètre contre `scope`,
  commandes de `validation`, `juger.sh`, verdict compact) et `clore-tache.sh` (fiche vers
  `completed/`, backlog, journal, `agents.tsv`, `verifier-liens.sh`). Correctif **A172** :
  branche documentaire de `juger.sh`.
- **Hors périmètre** : la relecture Opus, qui ne s'automatise pas.
- **Critères** : les deux scripts rejouent à l'identique la clôture de TASK-083 et de
  TASK-085 sur une copie jetable ; `juger.sh` rend 0 sur un périmètre purement documentaire
  et 1 sur un périmètre vide.
- **Agent** : conducteur (périmètre `orchestration/`, interdit aux agents lancés).

### TASK-087 — Documentation fonctionnelle de l'outil

- **Pourquoi** : user doit comprendre le fonctionnement sans jargon.
- **Contenu** : `Ansible/README.md` complété — le trajet poste → serveur, ce qu'est un
  rôle, ce qu'est une recette, où vivent les informations confidentielles, les commandes
  du quotidien, ce qui se passe le jour où un VPS existe.
- **Critères** : aucun terme technique employé sans être expliqué à sa première
  apparition ; chaque commande citée existe ; le trajet des secrets est décrit.
- **Agent** : DeepSeek.

### TASK-088 — Rôle `socle`

- **Contenu** : fuseau horaire, nom d'hôte, journaux et leur rotation, swap, mises à jour
  du système, comptes et `sudo`, tâches `cron`. Reprend `Linux/System/configure-*.sh` et
  `manage-users.sh`.
- **Critères** : chaque clause des contrats de `Linux/CADRAGE.md` reprise ou écartée avec
  sa raison ; `molecule test` vert sur Debian 12 et Ubuntu 24.04, étape `idempotence`
  comprise ; un mutant non idempotent fait échouer le scénario.
- **Agent** : DeepSeek. **Haiku** essayé comme conducteur sur cette tâche, et mesuré.

### TASK-089 — Rôle `docker`

- **Contenu** : dépôt officiel, moteur installé, `daemon.json`, réseau, mise à jour du
  moteur. Reprend `Docker/Installation`, `Docker/Configuration`, `update-docker.sh`.
- **Critères** : identiques à TASK-088, contre `Docker/CADRAGE.md` ; le démon répond dans
  le conteneur d'essai.

### TASK-090 — Rôle `k3s`

- **Contenu** : installation par l'installateur officiel, version épinglée, configuration,
  mise à jour, désinstallation. Reprend `Linux/K3s/`.
- **Critères** : identiques ; la version installée est celle demandée ; une seconde
  exécution ne réinstalle rien.

### TASK-091 — Rôle `kubernetes`

- **Contenu** : `kubectl`, Helm, cert-manager, metrics-server, Traefik ; puis namespaces,
  StorageClass, Middlewares, ClusterIssuers, secret de registry — par manifestes versionnés
  appliqués avec `kubernetes.core`. Reprend `Kubernetes/Installation` et `Configuration`.
- **Critères** : identiques, contre `Kubernetes/CADRAGE.md` ; les manifestes sont
  versionnés et appliqués, jamais générés à la volée.
- **Dépend de** : TASK-090.

### TASK-092 — Recette `serveur-neuf.yml` et réglages par machine

- **Contenu** : le playbook qui enchaîne `socle` → `securite_base` → `docker` → `k3s` →
  `kubernetes`, avec des étiquettes pour n'en jouer qu'une partie ; `inventory.example.yml`
  et `host_vars/*.example.yml` complétés ; mode d'emploi du coffre `ansible-vault`.
- **Critères** : la recette entière passe dans un conteneur jetable, deux fois de suite,
  sans changement au second passage ; aucune adresse ni identifiant réel versionné.
- **Dépend de** : TASK-088 à 091.

## 6. Règles communes à chaque rôle

- Contrat dans `meta/argument_specs.yml` ; état garanti et fichiers touchés dans
  `Ansible/CADRAGE.md`, avec une ligne d'historique datée.
- Scénario Molecule avec `verify.yml` ; `ansible-lint` et `yamllint` sans faute.
- Validation par la commande conteneurisée unique, sans rien installer sur l'hôte :
  `tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh`.
- Jamais de verrouillage hors du serveur : vérifier la configuration avant de recharger un
  service, ouvrir le port avant d'activer le pare-feu.
- Le script Bash remplacé est déprécié avec une date, jamais supprimé.

## 7. Ce qui reste à user

Acheter le serveur, donner l'accès, lancer la recette. Écrire l'inventaire réel, qui ne
part jamais sur GitHub. Décider de la suppression d'un script déprécié.

## 8. Coût estimé

DeepSeek : environ 1 $ pour les six tâches d'écriture. Conducteur : 90 000 jetons Sonnet
aujourd'hui, visés à 20 000 en Haiku après TASK-086. Relecture Opus : une par tâche,
inchangée — c'est le filet de sécurité de toute la chaîne.
