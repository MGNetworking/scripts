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
        (fichier de cas figé après le premier jet, arrêt si les FAIL ne baissent plus)
orchestrateur : juger.sh relancé ─► périmètre ─► tests figés ─► relecture Opus
        défauts ─► agent relancé 1 fois ─► sinon l'orchestrateur finit ou bloque
```

Le parallélisme — plusieurs agents à la fois — n'est ouvert qu'après trois tâches
passées sans incident dans ce circuit.

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
