# Cadrage — Ansible/

Ce document **engage** : besoin du dossier et contrat de chacun de ses rôles
([décision 49](../orchestration/decisions.md), [décision 50](../orchestration/decisions.md)).
Le [README](README.md) **explique** (installation du poste de contrôle, commandes, risques).
Tout ce qui figure au contrat est réputé utilisé : le modifier est une rupture.

État initial : le dossier ne porte **aucun rôle**. La section « Contrats » est donc vide,
et le restera jusqu'à ce qu'un rôle y soit écrit — le premier est `securite_base`
(TASK-081). Un contrat de rôle décrit ses variables (`meta/argument_specs.yml`), l'état
qu'il garantit, les fichiers et services qu'il touche, et porte une ligne `Prouvé par :`
nommant son scénario Molecule.

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

## Contrats

Aucun : le dossier ne porte encore aucun rôle. Le premier contrat sera écrit par la
tâche qui livre `securite_base`, avec sa ligne `Prouvé par :`.

## Statut du pilote

Ansible est en **pilote** (décision 50). Jusqu'au bilan comparatif du rôle
`securite_base` et à la décision de `user` de poursuivre, les scripts Bash existants
restent la référence : aucun n'est supprimé, aucun n'est déprécié par ce cadrage.
