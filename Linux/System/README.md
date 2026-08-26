# Linux/System

Administration du système Linux lui-même, indépendamment de Docker et Kubernetes.

## Prérequis

Debian ou Ubuntu. Les scripts modifiant le système demandent root ; les scripts
de diagnostic s'exécutent sans privilège.

Les valeurs propres au serveur (nom d'hôte, fuseau horaire, taille du fichier
d'échange) se déclarent dans `config/server.env` — voir
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
```

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

`configure-swap.sh` sans argument n'affiche que l'état. Avec une taille, il
désactive puis recrée le fichier d'échange et complète `/etc/fstab`, sauvegardé
au préalable. Il refuse de désactiver un swap dont le contenu ne tiendrait pas
en mémoire disponible. Les partitions de swap et les systèmes de fichiers btrfs
et ZFS ne sont pas pris en charge.
