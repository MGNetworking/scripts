# Points en suspens

Sujets identifiés pendant le développement et écartés pour ne pas interrompre la
production des scripts. À traiter avant la fin du chantier.

---

## 1. Mise en place de `update-system.sh` en tâche planifiée

**Soulevé le** 2026-08-26.

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
