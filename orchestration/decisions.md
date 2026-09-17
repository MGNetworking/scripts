# Décisions en vigueur

Un seul fichier, et seulement ce qui s'applique aujourd'hui. Décideur : Maxime
Ghalem. Les raisonnements et les décisions abandonnées restent dans l'historique
Git (anciens `docs/agent/decisions/ADR-0001` à `ADR-0006`, retirés le 2026-09-14).

**Les numéros sont conservés** pour que les renvois du dépôt restent justes. Un
numéro absent désigne une décision remplacée : 5, 27, 29 et 30 à 35.

---

## A. Orchestration des agents

### Décision 36 — Claude Code orchestre, les agents exécutent

L'**orchestrateur** est la session Claude Code de Maxime. Il suit
`.claude/commands/tache.md` : activer la fiche, lancer l'agent, vérifier, faire
relire, fusionner, écrire README, backlog, rapport et journal.

Un **agent** est une autre instance de Claude Code, sans interface (`claude -p`),
lancée par `orchestration/outils/lancer-agent.sh`. Il suit
`.claude/commands/executer-tache.md` : écrire, tester, corriger, commiter. Le
harness est le même pour tous ; seul le modèle change.

### Décision 37 — Un modèle externe = un fichier dans `orchestration/modeles/`

Adresse de l'API, nom du modèle, **nom** de la variable qui porte la clé — jamais
la clé. Condition : l'API accepte le format d'Anthropic (DeepSeek : vérifié le
2026-09-14). Les modèles Claude (`sonnet`, `opus`, `haiku`) passent par
l'abonnement, sans fichier.

### Décision 38 — La fiche désigne son agent

Champ `agent` : un modèle externe (`deepseek`), un modèle Claude, ou
`orchestrateur` pour une tâche de décision.

### Décision 39 — L'agent est isolé

Copie séparée du dépôt (`git worktree`, `../script-agents/<TASK>`). Droits bornés
par `orchestration/limites.json` : pas d'écriture dans `tasks/`, `docs/`,
`orchestration/`, `lib/`, `.claude/`, les README et `CLAUDE.md` ; ni `push`, ni
`merge`, ni lecture des `config/*.env`, ni web, ni sous-agents, ni MCP.

### Décision 40 — Boucle et plafonds

```text
agent : premier jet ─► juger.sh ─► jusqu'à 3 corrections du script
        (150 lignes au plus, comptées avant le commit ; fichier de cas corrigeable sans retrait
        d'assertion jusqu'au premier PASSE, figé ensuite ; arrêt si les FAIL ne baissent plus)
orchestrateur : juger.sh relancé ─► périmètre ─► tests figés ─► relecture Opus
        défauts ─► agent relancé 1 fois ─► sinon l'orchestrateur finit ou bloque
```

Le parallélisme — plusieurs agents à la fois — n'est ouvert qu'après trois tâches
passées sans incident dans ce circuit, **et** une fois les exécutions concurrentes du harnais maîtrisées
(registre TASK-039, A06) : aujourd'hui, deux lancements simultanés faussent les
contrôles « aucun conteneur résiduel » de TASK-002.

---

## B. Conduite du travail

### Décision 1 — L'orchestrateur fusionne et pousse

Fusion `--no-ff` dans `master` dès la tâche validée : sans elle, la tâche suivante
repart d'un `master` qui ignore la précédente. `git push` groupé **en fin de
domaine** : le dépôt est public, un historique poussé ne se réécrit pas.

### Décision 2 — `human_approval_required: true` ne suspend plus l'exécution

Il signale ce qui mérite une lecture attentive. Un script destructif s'écrit comme
un autre : il ne s'exécute jamais hors conteneur jetable.

### Décision 3 — L'ouverture des tâches est déléguée

L'orchestrateur passe une tâche `pending → ready` quand périmètre et validations
tiennent debout.

### Décision 4 — Point d'étape par domaine

Toutes les tâches d'un domaine s'enchaînent, puis point d'étape court et push.

### Décision 6 — Rapports courts par défaut

Format complet dès qu'une tâche a bloqué, a été relancée ou a révélé un défaut.

### Décision 25 — Un script vise 150 lignes

Préflight court, corps, sortie. La pédagogie va au README du domaine. Cible, pas
couperet ; les scripts existants ne sont pas repris.

### Décision 26 — Un fichier de cas vise 150 lignes

Sauf `tests/integration/linux-system.test.sh`, qui porte six scripts.

### Décision 28 — Un fichier de tâche vise 30 lignes

Les neuf fiches Docker de 190 à 295 lignes ne sont pas réécrites, mais ne servent
pas de modèle.

---

## C. Socle et environnement

### Conteneur jetable

Toute validation comportementale s'exécute dans un conteneur Docker neuf : profil
`debian`, ou `systemd` pour `systemctl`, `timedatectl`, `hostnamectl`. L'hôte
Windows n'exécute aucun script d'administration.

### Décision 7 — `load_config` exporte (`set -a` / `set +a`)

### Décision 8 — Un journal inaccessible avertit une fois et n'interrompt pas le script

### Décision 9 — Le `trap ERR` désigne le fichier réellement fautif (`BASH_SOURCE`)

### Décision 10 — Codes de retour

`2` erreur d'usage ; `1` échec d'exécution, privilège insuffisant compris.

### Décision 11 — Tous les `.sh` sont en `100755` dans Git

### Décision 12 — Le profil de conteneur `systemd` existe (construit par TASK-020)

### Décision 13 — Le §1 de `TASK-011-analyse-statique.sh` est retiré

---

## D. Choix techniques du chantier

### Décision 14 — Cibles

Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS. `apt` et `systemd` partout. Aucune
famille RHEL. Un script détecte le système et refuse ce qu'il ne reconnaît pas.

### Décision 15 — Échecs des tâches planifiées notifiés

Vers `ntfy` ou un webhook dont l'URL vit dans un `.env` non versionné. Ni
courriel par `cron`, ni contrôle de fraîcheur des journaux.

### Décision 16 — Ordre des domaines

`Linux/System → Linux/Security → Docker → Linux/K3s → Kubernetes → Synology`. Dans
un domaine : lecture seule, puis modifiant, puis destructif.

### Décision 17 — Parc visé

Un VPS Debian portant K3s, un NAS Synology pour Plex. Tout le spécifique passe par
`config/server.env`.

### Décision 18 — Synology

Mise au standard d'`organize-series.sh` et `update-plex.sh`. Nouveaux scripts DSM
après le chantier Linux.

### Décision 19 — SSH

`PasswordAuthentication no`, `PermitRootLogin no`, port 22 inchangé.

### Décision 20 — Garde contre le verrouillage

`configure-ssh.sh` et `disable-root-login.sh` refusent d'agir sans un compte
non-root disposant de `sudo` et d'une clé SSH exploitable.

### Décision 21 — Firewall

`ufw`, `deny` en entrée, SSH seul ouvert d'office ; le reste par configuration.

### Décision 22 — `fail2ban`

Valeurs de la distribution, prison `sshd` activée.

### Décision 23 — K3s mono-nœud

Traefik conservé, `cert-manager` avec Let's Encrypt, domaine dans `config/`.

### Décision 24 — Aucun secret ni valeur de machine en dur

Domaine, adresses, horaires, chemins et jetons passent par `config/`.

---

## E. Décisions prises par délégation (2026-09-15)

`user` a délégué à l'orchestrateur, le 2026-09-15, les lignes du registre
TASK-039 qui attendaient son arbitrage. Choix les plus simples et réversibles.

### Décision 41 — La documentation reste à l'orchestrateur (A07)

README, schémas, décisions et registre ne passent pas par un agent : ce sont des
textes courts, qui dépendent du contexte de l'orchestrateur, et `limites.json`
interdit volontairement ces chemins aux agents. Aucun circuit dédié n'est construit.

### Décision 42 — Docker Desktop tombé reste un arrêt signalé (A11)

Les pistes de relance automatique touchent la configuration des services Windows,
que l'agent n'a pas le droit de modifier. Si le démon manque, l'orchestrateur
s'arrête et le signale ; `DELAI_DISPONIBILITE` garde sa valeur jugée de 300 s.

### Décision 43 — Pas d'intégration continue pendant le chantier (A18)

Les validations exigent un démon Docker et le profil `systemd` privilégié ; le
juge et `/tache` en tiennent lieu. Sujet à rouvrir à la fin du chantier des scripts.

### Décision 44 — `tests/README.md` n'est pas scindé (A34)

Sa lecture par sections suffit aux agents ; le scinder casserait des liens dans
tout le dépôt pour un gain de confort. Sujet à rouvrir s'il dépasse 100 Ko.

### Décision 45 — Un script destructif n'hérite pas de la confirmation (A45)

`confirm` lit `ASSUME_YES`, et un script lancé par un parent qui l'exporte en
hérite : c'est le contrat du socle, épinglé par `tests/unit/common.test.sh`, et il
sert aux enchaînements voulus. Un script **destructif** — redémarrage, nettoyage,
désinstallation — pose `export ASSUME_YES="false"` avant de lire ses options :
seul son propre `--yes` le confirme.

### Décision 46 — Mode automatique, rapports lisibles, corrections en fiches (2026-09-15)

Demandé par `user`. `orchestration/mode.json` porte `automatique` ou `manuel` :
le contexte est **vidé après chaque tâche close**, dans les deux modes ; le vidage
arrête la session. En automatique, « reprends » suffit à lancer la tâche prête
suivante ; en manuel, l'orchestrateur attend une consigne. `user` bascule le mode en le demandant dans le terminal.

Chaque rapport de tâche commence par un compte rendu écrit comme dans la
conversation. Une correction liée à la tâche s'y fait ; une correction liée aux
agents ou à l'architecture devient une fiche TASK, en tête si elle est urgente.

**Avenant du 2026-09-16 (TASK-049), validé par `user`** : le vidage est supprimé.
Il arrêtait la session et imposait un « reprends » par tâche. La session
orchestratrice dure ; chaque tâche est conduite par un sous-agent
`conducteur-tache` neuf, qui porte le contexte lourd et ne rend que des résumés
de 30 lignes au plus, relecture comprise. La session ne garde que le lancement
des agents, qui peut durer une heure. En automatique, elle enchaîne la tâche
prête suivante sans message de `user` ; blocage, plafond de la décision 40,
question ouverte ou passage en manuel l'arrêtent.

### Décision 47 — K3s : version, installateur, configuration, désinstallation (2026-09-16)

Tranché par `user` sur les options recommandées à l'atomisation de `Linux/K3s`.

- **Version installée** (TASK-051) : canal `stable` si `SRV_K3S_VERSION` est absente,
  sinon la version épinglée ; la version retenue est affichée.
- **Installateur** : HTTPS seul, aucune empreinte épinglée de `get.k3s.io` —
  l'installateur officiel vérifie lui-même la somme sha256 du binaire.
- **`config.yaml`** (TASK-052) : `write-kubeconfig-mode: "0600"` et `tls-san` tiré de
  `SRV_K3S_TLS_SAN`, rien d'autre ; le script possède `config.yaml` entier.
- **Mise à niveau** (TASK-053) : version cible explicite et obligatoire
  (`--version` ou `SRV_K3S_VERSION`), jamais « dernière stable » par défaut.
- **Désinstallation** (TASK-054) : désinstallateur officiel seul, après affichage de
  ce qui sera détruit ; la sauvegarde relève d'un script distinct.

### Décision 48 — Kubernetes : accès, maintenance, installation, configuration (2026-09-16)

Tranché par `user`, question par question, sur les options recommandées à l'atomisation
de `Kubernetes/` (TASK-055 à TASK-071).

- **Accès au cluster** : aucun script n'exige root ; `kubectl` trouve seul son
  kubeconfig (`KUBECONFIG`, puis `~/.kube/config`). Sur K3s, `k3s.yaml` se copie une
  fois dans `~/.kube/config` du compte d'administration (0600), documenté au README.
- **`resource-usage.sh`** : sans metrics-server, `[WARN]`, capacité des nœuds, code 0.
- **`backup-resources.sh`** : dossier `SRV_K8S_BACKUP_DIR`, sinon
  `/var/backups/kubernetes`, `--output` prioritaire ; dossier refusé s'il est dans le
  dépôt, créé en 0700 ; types exportés : namespaces, deployments, statefulsets,
  daemonsets, cronjobs, services, ingresses, configmaps, PVC, storageclasses ;
  jamais de Secrets.
- **`cleanup-resources.sh`** : ne supprime que les objets nommés un à un en argument.
- **`install-kubectl.sh`, `install-ingress.sh`, `install-metrics.sh`** : vérification
  seule, rien n'est installé (K3s fournit kubectl, Traefik et metrics-server) ;
  `install-kubectl.sh` explique la copie du kubeconfig si `~/.kube/config` manque ;
  `install-ingress.sh` signale un conflit sur les ports 80/443.
- **`install-helm.sh`** : script officiel `get-helm-4` (sha256 vérifiée par lui),
  version par `SRV_HELM_VERSION`.
- **`install-cert-manager.sh`** : chart Helm officiel jetstack, version obligatoire
  (`SRV_CERT_MANAGER_VERSION` ou `--version`), CRD installées par le chart.
- **Réglages Kubernetes** : dans `config/server.env`, préfixe `SRV_K8S_`
  (liste des namespaces : `SRV_K8S_NAMESPACES`, séparée par des virgules).
- **`configure-storage.sh`** : exactement une StorageClass par défaut, `local-path`
  ou `SRV_K8S_STORAGE_CLASS` ; la marque « par défaut » retirée des autres après
  confirmation, aucune classe créée ni supprimée.
- **`configure-ingress.sh`** : deux Middlewares Traefik réutilisables, redirection
  HTTPS et en-têtes de sécurité (HSTS de durée courte au départ) ; chaque site les
  active dans son Ingress.
- **`configure-tls.sh`** : ClusterIssuers `letsencrypt-staging` et
  `letsencrypt-production`, HTTP-01, e-mail `SRV_K8S_ACME_EMAIL` ; aucun certificat
  demandé.
- **`configure-registry.sh`** : identifiants dans `config/registry.env` (ignoré par
  Git, modèle `.example` versionné, droits 0600 exigés) ; Secret docker-registry dans
  chaque namespace de `SRV_K8S_NAMESPACES` ; jamais affichés, journalisés ni passés
  en argument.

---

## F. Cadrage des scripts

### Décision 49 — Un cadrage par grand dossier, une boucle de réflexion avant toute tâche (2026-09-17)

Validé par `user` le 2026-09-17. **Pourquoi** : un script peut déjà tourner sur
plusieurs serveurs, dans des crons ou d'autres processus, et il se déploie par
`git clone` : un changement sur `master` atteint tous les serveurs au prochain
`git pull`. Rien ne disait non plus comment naît une tâche (plan initial, demande dans
la conversation, défaut découvert). L'évolution des scripts est donc cadrée et assumée.

**Cinq choix de `user`** :

1. **Un `CADRAGE.md` par grand dossier** : `Linux/`, `Docker/`, `Kubernetes/`,
   `Synology/`. Deux sortes de scripts : ceux d'un **ensemble** (fonction globale, ex.
   la gestion de Kubernetes) et les **scripts individuels** (autonomes, ex. Synology).
2. **Aucune information serveur dans le dépôt**, qui est public. **Tout ce qui figure au
   contrat est réputé utilisé** ; le modifier est une rupture. Aucun inventaire des usages.
3. **Rupture de contrat** : correction et **ajout compatible** (option désactivée par
   défaut) autorisés après validation. **Changement incompatible : jamais sur le script
   existant** ; nouveau script, l'ancien marqué « déprécié » avec une date, supprimé
   seulement par décision de `user` après migration.
4. **Scripts déjà écrits** : l'état actuel est la base de départ. Ils appartiennent tous
   à un ensemble, sauf les scripts individuels ; leur comportement actuel devient leur
   contrat initial.
5. **Autorité** : **seul `user` valide** une modification du cadrage. L'IA propose.

Écartés : inventaire privé des usages ; versions Git épinglées par serveur ; option qui
garde l'ancien comportement à vie.

**Modèle de `CADRAGE.md`** :

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

Le **README** du dossier **explique** (usage, exemples, risques) ; le **cadrage**
**engage** (besoin, contrat, décisions du dossier) ; `decisions.md` garde les décisions
transverses. `docs/refactorisation-plan.md` reste la trace du chantier initial.

**Boucle de réflexion, avant toute tâche** :

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
5. Questions       les choix ouverts, posés en une seule série
6. Validation      user seul ; le cadrage est mis à jour et daté
7. Tâches          seulement alors, fiches écrites (/atomiser) et mises au backlog
```

Aucune fiche avant l'étape 6. Aucune tâche hors du cadrage validé : le rédacteur refuse
de l'écrire, le conducteur la refuse à l'étape 2 de `/tache`, le relecteur classe
BLOQUANT un travail qui sort du contrat.

**Transition** : un dossier dont le `CADRAGE.md` n'est pas encore écrit n'empêche pas
une tâche de correction déjà au backlog, ni la tâche qui écrit ce cadrage ; le contrat
de référence est alors le comportement actuel du script (choix 4). Toute autre demande
sur ce dossier attend son cadrage.

**Portée** : le cadrage engage les scripts des quatre grands dossiers. Une fiche
d'orchestration (`orchestration/`, `.claude/`, `tests/`, `tasks/`) née d'un écart reste
régie par la décision 46.
