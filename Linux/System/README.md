# Linux/System

Administration du système Linux lui-même, indépendamment de Docker et Kubernetes.

## Prérequis

Debian ou Ubuntu. Les scripts modifiant le système demandent root ; les scripts
de diagnostic s'exécutent sans privilège.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `system-info.sh` | état du système : distribution, noyau, CPU, mémoire, stockage, réseau, heure | aucun | non |
| `update-system.sh` | mise à jour des paquets (Debian, Ubuntu) | root | oui |

Les autres scripts prévus (`configure-logging.sh`,
`configure-hostname.sh`, `configure-timezone.sh`, `configure-swap.sh`,
`manage-users.sh`, `check-disk.sh`, `check-memory.sh`, `check-services.sh`,
`reboot-system.sh`) restent à écrire — voir
[le plan](../../docs/refactorisation-plan.md).

## Utilisation

```bash
./Linux/System/system-info.sh

sudo ./Linux/System/update-system.sh --dry-run   # lister sans installer
sudo ./Linux/System/update-system.sh             # avec confirmation
sudo ./Linux/System/update-system.sh --yes       # sans confirmation (cron)
```

## Risques

`system-info.sh` est en lecture seule : il n'écrit rien et ne modifie rien.

`update-system.sh` installe des paquets. Il ne redémarre jamais le serveur : un
redémarrage nécessaire est signalé en fin d'exécution, jamais déclenché.
Utiliser `--dry-run` pour vérifier ce qui serait installé.
