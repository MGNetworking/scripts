# Linux

Préparation et administration du système Linux lui-même, avant et
indépendamment de Docker et de Kubernetes. Cibles : Debian 12 et 13, Ubuntu
22.04 et 24.04 LTS.

| Dossier | Rôle | État |
|---|---|---|
| [System/](System/README.md) | système de base : paquets, nom d'hôte, fuseau, swap, journaux, cron, diagnostics disque, mémoire et services, notification d’échec, comptes, redémarrage | 13 scripts |
| [Security/](Security/README.md) | audits des comptes et des ports, SSH, firewall `ufw`, `fail2ban` | 7 scripts |
| [K3s/](K3s/README.md) | diagnostiquer, installer, configurer, mettre à niveau, désinstaller K3s | 4 scripts, 1 à venir |

`Linux/K3s/` porte ce qui dépend de la distribution K3s ; ce qui survivrait à un
cluster managé va dans `Kubernetes/`.

Ordre d'utilisation sur un serveur neuf : `System`, puis `Security`, puis
`Docker/` ou `K3s`. Chaque dossier détaille ses scripts, prérequis et risques dans
son propre README.
