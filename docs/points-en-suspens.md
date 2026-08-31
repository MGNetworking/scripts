# Points en suspens

Sujets identifiés pendant le développement et écartés pour ne pas interrompre la
production des scripts. À traiter avant la fin du chantier.

---

## 1. Mise en place de `update-system.sh` en tâche planifiée

**Soulevé le** 2026-08-26.
**Converti en tâche le** 2026-08-27 : [TASK-009](../tasks/pending/TASK-009.md).

Le script est destiné à tourner par `cron`. Trois éléments conditionnent son
fonctionnement dans ce cadre.

### Cron n'utilise pas `sudo`

Il lance directement sous l'utilisateur indiqué. Deux façons de faire :

```bash
sudo crontab -e     # crontab de root : tout y tourne en root
```

ou, préférable car explicite et versionnable, un fichier dédié :

```
# /etc/cron.d/mgnetworking
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

0 4 * * 1 root /opt/mgnetworking/Linux/System/update-system.sh --yes >/dev/null 2>&1
```

Le champ `root` placé après l'horaire remplace le `sudo`.

### `--yes` est obligatoire

Cron n'a pas de terminal. Sans cette option, le script attendrait une réponse à
la confirmation, indéfiniment.

### La sortie doit être redirigée

Cron envoie par courriel tout ce qu'un travail écrit. Sans `>/dev/null 2>&1`, la
sortie complète d'`apt` serait expédiée à chaque exécution — ou produirait des
erreurs si aucun serveur de messagerie n'est configuré. La trace est déjà dans
`/var/log/mgnetworking/update-system.log`.

**Reste à faire** : décider de l'emplacement de déploiement et de l'horaire,
puis écrire le fichier `/etc/cron.d/`. Éventuellement un script
`Linux/System/configure-cron.sh` qui l'installe, sur le modèle de
`configure-logging.sh`.

---

## 2. Un échec en tâche planifiée passe inaperçu

**Soulevé le** 2026-08-26, conséquence directe du point 1.
**Indexé au backlog le** 2026-08-27 : [tasks/backlog.md](../tasks/backlog.md) §3.
Les trois pistes ci-dessous s'excluent mutuellement — le choix est une décision
d'architecture, elle vous revient avant toute atomisation en tâche.

**Le problème.** Avec la sortie jetée vers `/dev/null`, une mise à jour qui
échoue ne prévient personne. Le code de retour est correct et le journal
contient l'erreur, mais rien ne remonte. Un serveur peut rester sans mise à jour
pendant des mois sans que cela se voie.

**Pistes.**

- Ne rediriger que la sortie standard (`>/dev/null`) et laisser cron transmettre
  les erreurs par courriel.
- Un script de notification appelé en cas d'échec — courriel, webhook, ntfy.
- Un script de contrôle exécuté séparément, vérifiant la fraîcheur du dernier
  journal.

**Concerne** tous les scripts destinés à `cron` : `update-system.sh`,
`security-check.sh`, `backup-resources.sh`, `docker-cleanup.sh`.

---

## 3. Le harnais confond « non applicable » et « indisponible »

**Soulevé le** 2026-08-29, pendant [TASK-012](../tasks/completed/TASK-012.md).

**Le problème.** Depuis TASK-012, un fichier de cas qui réussit tout ce qu'il a
pu exécuter, en déclarant quelques cas non applicables, sort en 4 — preuve
partielle — et `tests/run.sh` traduit ce 4 en 0. Le garde qui empêche le faux
vert est qu'un 4 exige **au moins une réussite**.

Cette garantie est plus faible qu'elle n'en a l'air. Mesuré avec le démon Docker
coupé, Docker Desktop jamais arrêté :

```text
DOCKER_HOST=tcp://127.0.0.1:1 bash tests/acceptance/TASK-011-analyse-statique.sh
Bilan TASK-011 : 8 réussite(s), 0 échec(s), 21 NON EXÉCUTÉ(s)   → 4
tests/run.sh acceptance                                          → 0
```

72 % de la preuve avait disparu, le verdict restait vert. Sur `master` avant
TASK-012, ce même scénario rendait 3, donc 1 : c'est donc une régression sur
l'axe de l'honnêteté, consentie en échange de la levée d'un blocage qui frappait
toutes les tâches.

**La cause.** Les compteurs ne distinguent pas deux natures de saut :

| Nature | Exemple | Ce que ça devrait valoir |
|---|---|---|
| non applicable par nature | le profil `debian` n'a pas `systemd`, il ne l'aura jamais | 4 légitime |
| environnement indisponible | le démon Docker est coupé, la preuve existe mais n'a pas pu être produite | 3 — rien n'est prouvé |

Tout tombe aujourd'hui dans le même compteur, et quelques cas de préflight — qui
n'ont besoin de rien — suffisent à franchir le seuil.

**Le remède connu.** Un compteur `indisponibles` distinct de `non_executes`,
avec la règle `indisponibles > 0 → 3`. Il impose de revoir chaque appel `saute`
de chaque fichier de cas pour qualifier la nature du saut — ce que le périmètre
de TASK-012 excluait nommément.

**Concerne** tout le niveau `acceptance`, et les niveaux `unit`, `integration`
et `environment` le jour où ils existeront.
