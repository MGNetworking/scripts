# Cadrage — Ansible/

Ce document **engage** : besoin du dossier et contrat de chacun de ses rôles
([décision 49](../orchestration/decisions.md), [décision 50](../orchestration/decisions.md)).
Le [README](README.md) **explique** (installation du poste de contrôle, commandes, risques).
Tout ce qui figure au contrat est réputé utilisé : le modifier est une rupture.

Le dossier porte un rôle, `securite_base`. Un contrat de rôle décrit ses variables
(`meta/argument_specs.yml`), l'état qu'il garantit, les fichiers et services qu'il touche,
et porte une ligne `Prouvé par :` nommant son scénario Molecule.

## Besoin

Installer et configurer les machines du parc — 2 VPS Debian/Ubuntu, dont un porte K3s —
depuis un poste de contrôle, de façon idempotente, simulable avant application
(`--check --diff`) et décrite dans un inventaire. Ansible fournit nativement ce que les
scripts Bash du dépôt reconstruisent à la main : état désiré, simulation, inventaire,
application machine par machine.

Le dépôt reste public : l'inventaire réel, les variables par machine et les secrets
n'y entrent pas ; seuls les modèles `*.example.yml` sont versionnés.

**Hors besoin** :

- **diagnostiquer** en lecture seule (`check-*`, `audit-*`, `security-check`,
  `verify-k3s`, `Docker/Diagnostics/`, `Kubernetes/Maintenance/`) et **exploiter**
  ponctuellement (sauvegarde, nettoyage, redémarrage, notification) : ces gestes restent
  en Bash, déployés par `git clone` sur le serveur ;
- le NAS Synology : `Synology/` reste en Bash ;
- le GitOps (Flux, Argo CD) : un seul nouvel outil à la fois ;
- l'application sur une machine réelle, qui est un geste de `user` et non d'un agent.

**Conventions de tout le dossier** :

- un rôle par état à garantir, nommé en français sans accent ni tiret
  (`securite_base`) ; son contrat dans `meta/argument_specs.yml` ;
- idempotence exigée : un second passage ne change rien (étape `idempotence` de Molecule) ;
- `ansible-lint` et `yamllint` sans faute, au profil fixé par `.ansible-lint` et `.yamllint` ;
- aucune adresse, aucun nom d'utilisateur, aucun secret réel versionné ; secrets par
  Ansible Vault ou fichiers locaux ignorés par Git ;
- niveaux de preuve toujours nommés (décision 50) : **simulé**, **conteneur** (Molecule),
  **machine** (`--check --diff` sur un VPS, par `user`).

## Ensembles

Aucun pour l'instant. Un ensemble naîtra le jour où plusieurs rôles devront s'enchaîner
dans un ordre imposé ; il sera alors décrit ici, et porté par un playbook de
`playbooks/`.

## Scripts individuels

Aucun : `Ansible/` ne porte pas de script Bash. Un rôle qui n'appartient à aucun
ensemble est dit **autonome** et le déclare dans son contrat.

## Contrats

### securite_base — rôle autonome

- **Besoin** : un serveur Debian ou Ubuntu dont l'accès SSH ne s'ouvre qu'à une clé,
  dont l'entrée est fermée sauf SSH, et dont les tentatives répétées sont bannies.
- **Garantit**, après application : `sshd -T` annonce `passwordauthentication no`,
  `kbdinteractiveauthentication no` et `pubkeyauthentication yes`, le port inchangé et
  le service `ssh` toujours actif ; `ufw` actif, `deny (incoming)`, `allow (outgoing)`,
  le port SSH et les ports demandés autorisés ; `fail2ban-client status sshd` répond,
  prison chargée avec les valeurs de la distribution (décision 22).
- **Gardes** (décisions 20 et 21), chacune avant l'écriture qu'elle protège : avant de
  toucher à sshd, compte `securite_base_compte_admin` existant, non-root, membre de `sudo`
  et porteur d'au moins une clé dans `authorized_keys`, et `sshd_config` incluant
  `sshd_config.d/*.conf` ; avant tout rechargement, `sshd -t`, dont l'échec restaure la
  version antérieure — ou retire le fragment si ce passage venait de le créer — et arrête
  le play sans recharger ; avant de toucher au pare-feu, `sshd -T` confirmant le port
  déclaré ; avant l'activation d'ufw, la règle SSH relue dans `ufw show added` et l'absence
  de règle `deny` sur ce port.
- **Variables** (`meta/argument_specs.yml`) : `securite_base_compte_admin` (requis, sans
  défaut) ; `securite_base_ssh_port` (22) ; `securite_base_ports_autorises` (`[]`, forme
  `443/tcp`) ; `securite_base_fail2ban_essais` (10) et `securite_base_fail2ban_delai`
  (1 s) ; `securite_base_sshd_config`, `securite_base_sshd_config_d`,
  `securite_base_fail2ban_jail_d` (chemins du système).
- **Modifie sur la machine** : `<sshd_config.d>/10-mgnetworking.conf` (0644, root),
  `<jail.d>/mgnetworking-sshd.conf` (0644, root), paquets `ufw` et `fail2ban`, règles et
  politiques ufw, activation d'ufw, rechargement de `ssh`, activation et redémarrage de
  `fail2ban`.
- **Ne fait pas** : changer le port de sshd, modifier `sshd_config`, `jail.conf` ou
  `jail.local`, fixer une valeur de prison, supprimer une règle ufw, créer un compte,
  interdire la connexion de root (`PermitRootLogin`, resté à `disable-root-login.sh`),
  redémarrer `ssh`.
- **Prouvé par** : `roles/securite_base/molecule/default` — Debian 12 et Ubuntu 24.04,
  conteneurs systemd, étapes `converge`, `idempotence` et `verify`. Niveau **conteneur** ;
  le niveau **machine** demande un `--check --diff` de `user` sur un VPS. Seul le chemin
  nominal est joué : les gardes ci-dessus sont écrites et relues, jamais exécutées en
  échec (registre A157).
- **État** : pilote (voir ci-dessous).

## Statut du pilote

Ansible est en **pilote** (décision 50). Jusqu'au bilan comparatif du rôle
`securite_base` et à la décision de `user` de poursuivre, les scripts Bash existants
restent la référence : aucun n'est supprimé, aucun n'est déprécié par ce cadrage.

## Historique du cadrage

| Date | Changement | Nature | Validé par user |
|---|---|---|---|
| 2026-09-17 | Création du cadrage : besoin, conventions du dossier, aucun contrat | ajout compatible | décision 50, boucle du 2026-09-17 |
| 2026-09-17 | Contrat du premier rôle, `securite_base`, avec sa ligne « Prouvé par » (TASK-081) | ajout compatible | fiche TASK-081, décision 50 |
