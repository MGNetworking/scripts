# Linux

Préparation et administration du système Linux lui-même, avant et
indépendamment de Docker et de Kubernetes. Cibles : Debian 12 et 13, Ubuntu
22.04 et 24.04 LTS.

| Dossier | Rôle | État |
|---|---|---|
| [System/](System/README.md) | système de base : paquets, nom d'hôte, fuseau, swap, journaux, cron, diagnostics disque, mémoire et services, notification d’échec, comptes | 12 scripts |
| `Security/` | SSH, firewall `ufw`, `fail2ban`, comptes | à venir |
| `K3s/` | installer, mettre à niveau, désinstaller K3s | à venir |

`Linux/K3s/` porte ce qui dépend de la distribution K3s ; ce qui survivrait à un
cluster managé va dans `Kubernetes/`.

Ordre d'utilisation sur un serveur neuf : `System`, puis `Security`, puis
`Docker/` ou `K3s`. Chaque dossier détaille ses scripts, prérequis et risques dans
son propre README.
