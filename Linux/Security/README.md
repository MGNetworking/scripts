# Linux/Security

Sécurisation du serveur Linux : comptes, ports, SSH, firewall, fail2ban. Cibles :
Debian 12 et 13, Ubuntu 22.04 et 24.04 LTS (décision 14).

## Scripts

| Script | Rôle | Privilèges | Modifie le système |
|---|---|---|---|
| `audit-users.sh` | audit des comptes : UID 0, shells de connexion, membres de sudo, adm et docker, mots de passe vides si `/etc/shadow` est lisible | aucun | non |
| `audit-ports.sh` | ports TCP et UDP en écoute, adresse et processus ; « exposé » ou « local », nombre de ports exposés | aucun (processus complets en root) | non |
| `security-check.sh` | bilan PASS, WARNING, FAIL, INFO : SSH, ufw, fail2ban, comptes à UID 0, mises à jour ; code 1 dès un FAIL, pour cron | root conseillé (sans root : INFO) | non |
| `configure-firewall.sh` | ufw : règle SSH posée et relue avant tout, deny en entrée, allow en sortie, ports de `SRV_FIREWALL_PORTS` ou `--port` ; refuse si le port réel de sshd diffère de `SRV_SSH_PORT` ; `--dry-run`, `--yes` | root | oui |
| `configure-ssh.sh` | sshd : dépose `sshd_config.d/10-mgnetworking.conf` — mot de passe et clavier interactif refusés, clé seule, port inchangé ; refuse sans compte non-root membre de sudo avec clé (`SRV_ADMIN_UTILISATEUR` ou `--utilisateur`) ou sans `Include` de `sshd_config.d` ; `sshd -t` puis `systemctl reload ssh`, état antérieur restauré si l'un échoue ; `--dry-run`, `--yes` | root | oui |

## Ordre d'utilisation

Les audits d'abord, en lecture seule. Puis `configure-firewall.sh` et `configure-ssh.sh` ; à venir : fail2ban, et
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
sudo ./Linux/Security/security-check.sh   # bilan ; code 1 dès un FAIL
sudo ./Linux/Security/configure-firewall.sh --dry-run          # état et commandes ufw prévues
sudo ./Linux/Security/configure-firewall.sh --port 443/tcp     # résumé confirmé, puis activation
sudo ./Linux/Security/configure-ssh.sh --dry-run --utilisateur admin   # compte vérifié, fichier prévu
sudo ./Linux/Security/configure-ssh.sh --utilisateur admin             # confirmé, sshd -t, reload
```
