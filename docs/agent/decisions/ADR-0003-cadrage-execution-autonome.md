# ADR-0003 — Cadrage de l'exécution autonome

**Date** : 2026-09-02
**Statut** : accepté
**Décideur** : Maxime Ghalem
**Complète** : [ADR-0002](ADR-0002-claude-code-comme-moteur.md)
**Amende** : `AGENTS.md` §5, §8, §9, §13 — `tasks/README.md` §3

---

## Contexte

ADR-0002 a fait de Claude Code le moteur d'exécution, et TASK-009 a prouvé la
chaîne complète sur une tâche réelle. Le dispositif fonctionne, mais il
s'interrompt à chaque tâche : `AGENTS.md` interdit la fusion, le push et le
commit sur `master`, et `tasks/README.md` §3 réserve à l'humain l'ouverture
d'une tâche.

Ces trois verrous étaient justes tant que le dispositif n'était pas éprouvé. Ils
rendent impossible ce qui est maintenant recherché : **dérouler le chantier des
scripts sans intervention à chaque étape**.

Le présent document rassemble les décisions prises pour lever ces verrous et
pour trancher, en une fois, tout ce qui aurait provoqué un arrêt en cours de
route. Il vaut autorisation permanente : un agent qui le lit n'a pas à demander
confirmation de ce qui y figure.

Vingt-quatre décisions. Vingt ont été arbitrées explicitement ; quatre — celles
marquées *par défaut raisonnable* — ont été prises par l'agent au titre de
`AGENTS.md` §14, comme choix réversibles et locaux.

---

## A. Conduite du travail

### Décision 1 — L'agent fusionne et pousse

| Étape | Avant | Maintenant |
|---|---|---|
| branche `agent/TASK-XXX` | oui | oui, inchangé |
| commit sur la branche | oui | oui, inchangé |
| fusion dans `master` | **interdite** | **faite par l'agent**, tâche validée |
| `git push` | **interdit** | **fait par l'agent**, en fin de domaine |

La fusion sans délai est une nécessité technique, pas un confort : sans elle,
chaque tâche repart d'un `master` qui ignore les précédentes, et la première
dépendance casse.

Le push est groupé **en fin de domaine**, pas après chaque tâche. Le dépôt est
public : ce qui est poussé est immédiatement visible, et un historique poussé ne
se réécrit pas proprement. Le groupement laisse une fenêtre de retour en arrière
sur l'ensemble d'un domaine.

Restent interdits sans changement : `git push --force`, `git reset --hard`,
`git rebase`, `git filter-branch`, `git branch -D`. La fusion se fait sans
réécriture d'historique.

### Décision 2 — Accord général sur les tâches sensibles

`human_approval_required: true` **ne suspend plus l'exécution**. Le champ est
conservé : il signale ce qui mérite une lecture attentive, il ne commande plus
un arrêt.

Il en va de même des scripts destructifs — `reboot-system.sh`,
`uninstall-k3s.sh`, tout `Docker/Cleanup`, `configure-firewall.sh`,
`configure-ssh.sh`.

Le fondement de cette autorisation est `AGENTS.md` §7, **qui ne change pas** :
un script d'administration ne s'exécute jamais ailleurs que dans un conteneur
jetable. Écrire un script destructif ne détruit rien. Le risque n'apparaît que
le jour où Maxime le lance lui-même sur une machine réelle — et ce jour-là, la
décision est la sienne.

### Décision 3 — L'ouverture des tâches est déléguée

`tasks/README.md` §3 prévoyait que le passage `pending → ready` soit « un acte
humain **ou explicitement délégué** ». La délégation est donnée.

L'agent passe une tâche `ready` lorsqu'il constate que son périmètre et ses
validations tiennent debout. Le garde-fou se déplace : il n'est plus dans
l'ouverture de la tâche, il est dans la relecture du travail produit.

### Décision 4 — Point d'étape par domaine

L'agent enchaîne toutes les tâches d'un domaine, puis rend un point d'étape
court et pousse. Un domaine représente trois à sept scripts — le grain où une
erreur de cap coûte encore peu.

Les conditions d'arrêt de `AGENTS.md` §15 restent en vigueur : blocage réel,
`MAX_RETRIES`, environnement indisponible, anomalie.

### Décision 5 — Mode léger pour ce qui ne modifie rien

Dix tâches ont consommé environ 3,3 millions de jetons. Le poste le plus lourd
est le relecteur indépendant — qui a trouvé tous les défauts sérieux de la
session.

| Nature de la tâche | Cycle |
|---|---|
| script en lecture seule — `check-*`, `audit-*`, `*-status` | **léger** : rédacteur + validations, sans relecteur |
| correction purement documentaire | **léger** |
| script qui écrit sur le système | **complet**, relecteur obligatoire |
| toute modification de `lib/common.sh` | **complet**, sans exception |

On rogne là où le contrôle protège le moins. Le relecteur reste intégralement en
place partout où un script touche un système.

### Décision 6 — Rapports courts par défaut

*Par défaut raisonnable.* Rapport court pour une tâche sans histoire ; format
complet de `tasks/README.md` §6 dès qu'une tâche a bloqué, a demandé plus d'un
tour de correction, ou a révélé un défaut.

---

## B. Contrat du socle

Ces quatre décisions règlent [TASK-015](../../../tasks/pending/TASK-015.md) et
deux dettes que le backlog portait en attente.

### Décision 7 — `load_config` exporte

`load_config` encadre son `source` par `set -a` / `set +a`. Toute la
configuration atteint désormais les processus fils.

Rien ne change dans les fichiers `.env` ni dans la façon de les écrire :
`config/README.md` continue de prescrire des affectations nues. C'est le
comportement que tout script attendra intuitivement.

Contrepartie assumée : des variables sont exposées à des commandes qui ne les
demandent pas. Elle est acceptable — un fichier de contexte n'a pas vocation à
contenir de secret, et `AGENTS.md` §16 l'interdit déjà.

### Décision 8 — Un journal inaccessible n'interrompt plus le script

Si le fichier de journal devient inécrivable en cours d'exécution, le socle
avertit **une seule fois** sur la sortie d'erreur, puis poursuit sans journal.

Un script d'administration qui meurt parce qu'il n'a pas pu écrire sa trace est
un mauvais comportement — a fortiori lancé par `cron` à quatre heures du matin.

### Décision 9 — Le `trap ERR` désigne le fichier réellement fautif

Le message est corrigé par `BASH_SOURCE` : il annonçait « à la ligne 78 de
mon-script.sh » alors que la ligne 78 était celle de `lib/common.sh`.

### Décision 10 — `require_root` conserve le code 1

Un privilège insuffisant n'est pas une faute d'invocation : c'est un échec
d'exécution. La distinction est inscrite noir sur blanc dans
`docs/architecture-technique.md` :

```text
2  erreur d'usage      option inconnue, argument manquant, valeur invalide
1  échec d'exécution   privilège insuffisant, dépendance absente, opération échouée
```

Aucun script existant n'est modifié. Cette décision borne le périmètre de
[TASK-016](../../../tasks/pending/TASK-016.md), qui grave la convention du 2.

---

## C. État du dépôt et environnement

### Décision 11 — Le bit d'exécution est posé dans Git

Tous les `.sh` passent en mode `100755` par `git update-index --chmod=+x`.
Le livrable est déployé par `git clone` : après clone, aucun script n'était
exécutable. La règle vaut pour les cinquante scripts à venir.

### Décision 12 — Le profil de conteneur `systemd` est construit en premier

Avant d'attaquer les domaines. Sans lui, rien de ce qui touche `systemctl`,
`timedatectl` ou `hostnamectl` n'est validable par l'exécution — et cela
concerne `check-services.sh`, tout `Linux/Security`, le démon Docker et K3s.

Le construire plus tard obligerait à revenir sur des scripts déjà déclarés
terminés. Il débloque le niveau 4 de `AGENTS.md` §10, ainsi que
`configure-timezone.sh` et `configure-hostname.sh`, en attente depuis ADR-0001.

### Décision 13 — Le §1 de `TASK-011-analyse-statique.sh` est retiré

Ses six contrôles comparent un diff avec `HEAD` : les corrections étant
commitées, ils sortent en `NON EXÉCUTÉ` à chaque passage et ne reviendront
jamais d'eux-mêmes. `tests/README.md` §1 annonce déjà leur disparition, et le
niveau `integration` est le domicile durable de ces preuves.

Six `NON EXÉCUTÉ` permanents finissent par être ignorés — c'est exactement le
bruit qui masque un vrai problème.

Clôt le point 4 de `docs/points-en-suspens.md`.

### Décision 14 — Cibles supportées

**Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS.** `apt` partout, `systemd`
partout. Aucune famille RHEL.

Un script détecte le système avant d'agir, conformément à `CLAUDE.md`, et refuse
proprement ce qu'il ne reconnaît pas.

### Décision 15 — Les échecs des tâches planifiées sont notifiés

Un script de notification est appelé lorsqu'un script planifié échoue. Il émet
vers `ntfy` ou un webhook dont l'URL vit dans un `.env` **non versionné**.

Alerte active, au moment de l'échec, sans dépendre d'un serveur de messagerie
configuré sur la machine — hypothèse rarement vraie sur un VPS.

Écarté : le courriel par `cron`, en place à titre conservatoire depuis TASK-009,
qui suppose un MTA et une boîte réellement lue. Écarté aussi : le contrôle de
fraîcheur des journaux, passif, qui exige que quelque chose le lise.

Concerne `update-system.sh`, `security-check.sh`, `backup-resources.sh`,
`docker-cleanup.sh`. Clôt le point 2 de `docs/points-en-suspens.md`.

---

## D. Chantier

### Décision 16 — Ordre des domaines

```text
Linux/System → Linux/Security → Docker → Linux/K3s → Kubernetes → Synology
```

C'est l'ordre dans lequel on reconstruit réellement une infrastructure :
préparer l'OS, le sécuriser, poser le moteur de conteneurs, puis
l'orchestrateur. C'est celui qu'a déjà arrêté `docs/refactorisation-plan.md`.

**Au sein de chaque domaine** : les scripts en lecture seule avant ceux qui
modifient, ceux qui modifient avant les destructifs. *Par défaut raisonnable.*

### Décision 17 — Parc visé

Un VPS Debian portant K3s, et un NAS Synology indépendant pour Plex.

Les scripts restent portables : rien ne suppose une machine particulière, tout
le spécifique passe par `config/server.env`.

### Décision 18 — Synology

Mise au standard des deux scripts hérités — `organize-series.sh` et
`update-plex.sh`, qui ne chargent pas `lib/common.sh`. Travail borné,
vérifiable par lecture.

Les nouveaux scripts d'administration DSM attendent la fin du chantier Linux :
aucun ne peut être validé en conteneur, leur preuve se limiterait à l'analyse
statique.

---

## E. Politique de sécurité

Ces décisions fixent les **valeurs par défaut** des scripts. Toutes restent
surchargeables par `config/`, conformément à `CLAUDE.md`.

### Décision 19 — SSH

```text
PasswordAuthentication no
PermitRootLogin no
Port 22                     inchangé
```

Le port exotique n'arrête aucun attaquant sérieux et casse les outils qui
supposent 22.

### Décision 20 — Garde contre le verrouillage

*Par défaut raisonnable.* `configure-ssh.sh` et `disable-root-login.sh`
**refusent d'agir** tant qu'ils n'ont pas trouvé un compte non-root disposant de
`sudo` et d'une clé SSH exploitable.

Ce n'est pas un choix mais une garde : elle rend le verrouillage
structurellement impossible. Les deux scripts savent aussi revenir en arrière.

### Décision 21 — Firewall

`ufw` — standard sur Debian et Ubuntu, lisible, réversible, une règle par ligne.
Politique `deny` en entrée, **SSH seul ouvert d'office**.

HTTP, HTTPS et les ports K3s s'ouvrent par configuration, quand un service les
justifie. On n'ouvre jamais un port pour un service qui n'existe pas encore.

Écarté : `nftables`, dont les règles sont nettement plus dures à relire au
moment précis où l'on est en train de perdre la main sur la machine.

### Décision 22 — `fail2ban`

*Par défaut raisonnable.* Valeurs standard de la distribution, prison `sshd`
activée. Surchargeables par configuration.

---

## F. Kubernetes

### Décision 23 — K3s mono-nœud, Traefik conservé

K3s livre Traefik : le garder évite d'en installer un autre et de désactiver le
premier. `cert-manager` avec Let's Encrypt pour le TLS, le domaine venant de
`config/`.

C'est la configuration d'un VPS unique hébergeant ses propres services.
`install-ingress.sh` du plan §5 devient donc une vérification de Traefik plutôt
qu'une installation d'`ingress-nginx`.

### Décision 24 — Aucun secret, aucune valeur de machine en dur

Rappel opposable, déjà porté par `CLAUDE.md` et `AGENTS.md` §16 : domaine,
adresses, horaires, chemins de déploiement et jetons de cluster passent tous par
`config/`. Le dépôt est public et doit pouvoir le rester.

---

## Ce qui ne change pas

Ces limites demeurent, et aucune décision ci-dessus ne les entame :

- **aucune exécution hors conteneur jetable** — ni hôte, ni serveur réel, ni NAS
  (`AGENTS.md` §7) ;
- **aucune connexion à une machine distante** — `ssh`, `scp`, `rsync` restent
  interdits ;
- **le relecteur n'écrit jamais** (ADR-0002, décision 2) ;
- **corriger la cause, jamais le symptôme** — neutraliser un test, ajouter
  `|| true` ou retirer `set -e` vaut échec de la tâche (`AGENTS.md` §12) ;
- **une validation non lancée n'est jamais déclarée `PASS`** (`AGENTS.md` §10) ;
- `MAX_RETRIES = 5`, puis la tâche est bloquée ;
- **aucune publication** autre que le `git push` de la décision 1 : ni PR, ni
  issue, ni message, ni courriel.

---

## Conséquences documentaires

| Document | Modification |
|---|---|
| `AGENTS.md` | §8 commandes, §9 Git, §13 intervention humaine, §5 zone protégée |
| `tasks/README.md` | §3 délégation de `pending → ready` |
| `docs/points-en-suspens.md` | points 2, 4 et 5 tranchés |
| `docs/architecture-technique.md` | contrat du socle : décisions 7 à 10 |
| `.claude/commands/tache.md` | mode léger, fusion, push |
| `config/README.md` | conséquence du `set -a` |
