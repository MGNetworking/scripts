# Linux/System

Administration du système Linux lui-même, indépendamment de Docker et Kubernetes.

## Prérequis

Debian ou Ubuntu. Les scripts modifiant le système demandent root ; les scripts
de diagnostic s'exécutent sans privilège.

Les valeurs propres au serveur (nom d'hôte, fuseau horaire, taille du fichier
d'échange, horaire des tâches planifiées) se déclarent dans `config/server.env` — voir
[config/README.md](../../config/README.md). Un argument de ligne de commande
prime toujours sur la valeur du fichier.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `system-info.sh` | état du système : distribution, noyau, CPU, mémoire, stockage, réseau, heure | aucun | non |
| `update-system.sh` | mise à jour des paquets (Debian, Ubuntu) | root | oui |
| `configure-logging.sh` | crée le répertoire des journaux et installe la règle logrotate | root | oui |
| `configure-hostname.sh` | définit le nom d'hôte et met /etc/hosts en cohérence | root | oui |
| `configure-timezone.sh` | définit le fuseau horaire, en validant son existence | root | oui |
| `configure-swap.sh` | affiche le swap, crée ou redimensionne un fichier d'échange | root | oui |
| `configure-cron.sh` | dépose `/etc/cron.d/mgnetworking` : planification des scripts automatiques | root | oui |

Les autres scripts prévus (`manage-users.sh`, `check-disk.sh`, `check-memory.sh`, `check-services.sh`,
`reboot-system.sh`) restent à écrire — voir
[le plan](../../docs/refactorisation-plan.md).

## Utilisation

```bash
./Linux/System/system-info.sh

sudo ./Linux/System/update-system.sh --dry-run   # lister sans installer
sudo ./Linux/System/update-system.sh             # avec confirmation
sudo ./Linux/System/update-system.sh --yes       # sans confirmation (cron)

sudo ./Linux/System/configure-logging.sh          # une fois par serveur

sudo ./Linux/System/configure-hostname.sh                 # prend SRV_HOSTNAME
sudo ./Linux/System/configure-hostname.sh mon-serveur     # l'argument l'emporte
sudo ./Linux/System/configure-hostname.sh mon-serveur --dry-run

sudo ./Linux/System/configure-timezone.sh --list      # lister les fuseaux
sudo ./Linux/System/configure-timezone.sh            # prend SRV_TIMEZONE
sudo ./Linux/System/configure-timezone.sh Europe/Paris

./Linux/System/configure-swap.sh                     # état du swap, sans root
sudo ./Linux/System/configure-swap.sh 2G             # créer ou redimensionner
sudo ./Linux/System/configure-swap.sh 2G --dry-run

sudo ./Linux/System/configure-cron.sh --dry-run          # afficher le fichier
sudo ./Linux/System/configure-cron.sh                    # une fois par serveur
sudo ./Linux/System/configure-cron.sh --horaire "30 5 * * 7"
```

### Planification par cron

`configure-cron.sh` dépose `/etc/cron.d/mgnetworking`, qui contient `SHELL`,
`PATH` et une ligne par tâche planifiée. Une seule tâche existe à ce jour :

```text
0 4 * * 1 root /bin/bash /opt/mgnetworking/Linux/System/update-system.sh --yes >/dev/null
```

Quatre traits de cette ligne ne sont pas négociables :

- **`root` suit l'horaire, il n'y a pas de `sudo`.** Cron lance directement sous
  l'utilisateur nommé dans le fichier ;
- **le script est lancé par `/bin/bash`, pas par son chemin seul.** Les fichiers
  de ce dépôt sont enregistrés dans Git en `100644`, sans bit d'exécution
  (`git ls-files -s Linux/System/` le montre). Sur un serveur installé par
  `git clone`, un appel direct rendrait `126` à chaque passage, sans que rien ne
  le signale. Passer par `bash` rend la ligne indépendante de ce bit ;
- **`--yes` est obligatoire.** Cron n'a pas de terminal : sans lui, le script
  attendrait indéfiniment une réponse à sa confirmation ;
- **seule la sortie standard est jetée.** Cron expédie par courriel tout ce
  qu'un travail écrit ; la sortie complète d'`apt` à chaque exécution serait
  inacceptable, et la trace est de toute façon dans
  `/var/log/mgnetworking/update-system.log`. La sortie d'erreur, elle, est
  conservée : c'est la seule alerte disponible tant que la remontée des échecs
  n'est pas traitée — [points-en-suspens.md](../../docs/points-en-suspens.md) §2.

L'horaire par défaut est `0 4 * * 1` — tous les lundis à 4 h. Il se change par
`SRV_CRON_UPDATE_SYSTEM` dans `config/server.env`, ou par `--horaire`, qui
l'emporte. Les cinq champs de cron sont attendus ; les raccourcis `@weekly` et
consorts sont refusés. L'horaire suit le fuseau horaire du système.

Le chemin du dépôt n'est pas écrit en dur : il est résolu à l'exécution, ce qui
rend le fichier correct quel que soit l'endroit où le dépôt est déployé.

#### Prérequis de la planification

**Cron doit être installé ; le script ne l'installe pas.** Il cherche le démon
(`cron` ou `crond`, y compris dans `/usr/sbin`, absent du `PATH` de root sur
certains systèmes) et s'arrête en indiquant `apt-get install cron` s'il ne le
trouve pas. Il ne se fie pas à la présence de `/etc/cron.d` : sur Debian 12, ce
répertoire est fourni par `e2fsprogs` — `dpkg -S /etc/cron.d` le confirme — et
existe donc même sans cron. Seul `--dry-run` fait exception : il n'écrit rien,
se contente d'un avertissement et affiche l'aperçu, ce qui permet de lire le
fichier avant d'installer cron.

**Le bit d'exécution n'est pas un prérequis de la planification**, la ligne
déposée passant par `bash`. Il le reste pour un lancement à la main : après un
`git clone`, `./Linux/System/update-system.sh` échoue tant que
`chmod +x Linux/System/*.sh` n'a pas été passé — les fichiers du dépôt sont
enregistrés en `100644`. `configure-cron.sh` signale le bit manquant sans y
toucher.

Aucun rechargement n'est nécessaire après le dépôt : cron relit `/etc/cron.d`
dès que son contenu change.

## Risques

`system-info.sh` est en lecture seule : il n'écrit rien et ne modifie rien.

`update-system.sh` installe des paquets. Il ne redémarre jamais le serveur : un
redémarrage nécessaire est signalé en fin d'exécution, jamais déclenché.
Utiliser `--dry-run` pour vérifier ce qui serait installé.

`configure-logging.sh` écrit dans `/etc/logrotate.d/`. Il ne remplace jamais une
règle existante différente sans afficher les écarts et demander confirmation.

`configure-hostname.sh` modifie `/etc/hosts`, sauvegardé au préalable. Sur un
nœud K3s ou Kubernetes, le nom d'hôte identifie le nœud : le changer après
installation rend le nœud existant inutilisable.

`configure-timezone.sh` modifie l'heure locale du système. Les tâches planifiées
suivent ce fuseau : un cron réglé sur 4 h s'exécutera à 4 h dans le nouveau
fuseau, donc à une autre heure réelle qu'auparavant.

`configure-cron.sh` écrit dans `/etc/cron.d/`. Il ne remplace jamais un fichier
existant différent sans afficher les écarts et demander confirmation, et il
n'installe pas cron : sur un serveur dont le démon est introuvable, il s'arrête
en indiquant `apt-get install cron`, sauf en `--dry-run` où il se contente d'un
avertissement puisqu'il n'écrit rien. Le fichier déposé fait tourner `update-system.sh` en
root, sans confirmation : à partir de son installation, des paquets sont mis à
jour sans intervention humaine. Le script signale — sans y toucher — une
planification concurrente d'`update-system.sh` trouvée dans `/etc/crontab` ou
dans un autre fichier de `/etc/cron.d/`. Il refuse un horaire mal formé plutôt
que de déposer une ligne que cron ignorerait en silence.

`configure-swap.sh` sans argument n'affiche que l'état. Avec une taille, il
désactive puis recrée le fichier d'échange et complète `/etc/fstab`, sauvegardé
au préalable. Il refuse de désactiver un swap dont le contenu ne tiendrait pas
en mémoire disponible. Les partitions de swap et les systèmes de fichiers btrfs
et ZFS ne sont pas pris en charge.
