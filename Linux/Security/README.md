# Linux/Security

Sécurisation du serveur Linux : comptes, ports, SSH, firewall, fail2ban. Cibles :
Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS (décision 14).

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `audit-users.sh` | audit des comptes : UID 0, shells de connexion, membres de sudo, adm et docker, mots de passe vides si `/etc/shadow` est lisible | aucun | non |
| `audit-ports.sh` | ports TCP et UDP en écoute, adresse et processus ; « exposé » ou « local », nombre de ports exposés | aucun (processus complets en root) | non |

## Ordre d'utilisation

Les audits d'abord, en lecture seule. Puis, à venir : fail2ban, firewall, SSH, et
en dernier l'interdiction de la connexion de root — seulement après avoir créé un
compte d'administration avec `Linux/System/manage-users.sh` (décision 20).

## Risques

Les scripts d'audit ne modifient rien. Ceux qui touchent SSH et le firewall
**peuvent couper l'accès à la machine** : ils vérifient la présence d'un compte
administrateur et de la règle SSH avant d'agir, mais gardez toujours une session
ouverte pendant leur exécution.

## Utilisation

```bash
./Linux/Security/audit-users.sh           # sans root : shadow non lu, signalé
./Linux/Security/audit-ports.sh           # sans root : processus « inconnu (root requis) »
sudo ./Linux/Security/audit-users.sh      # audit complet
```
