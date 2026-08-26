# Linux/System

Administration du système Linux lui-même, indépendamment de Docker et Kubernetes.

## Prérequis

Debian ou Ubuntu. Les scripts modifiant le système demandent root ; les scripts
de diagnostic s'exécutent sans privilège.

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `system-info.sh` | état du système : distribution, noyau, CPU, mémoire, stockage, réseau, heure | aucun | non |

Les autres scripts prévus (`update-system.sh`, `configure-logging.sh`,
`configure-hostname.sh`, `configure-timezone.sh`, `configure-swap.sh`,
`manage-users.sh`, `check-disk.sh`, `check-memory.sh`, `check-services.sh`,
`reboot-system.sh`) restent à écrire — voir
[le plan](../../docs/refactorisation-plan.md).

## Utilisation

```bash
./Linux/System/system-info.sh
./Linux/System/system-info.sh --help
```

## Risques

`system-info.sh` est en lecture seule : il n'écrit rien et ne modifie rien.
