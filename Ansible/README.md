# Ansible/ — installation et configuration des machines

Ansible installe et configure les serveurs du parc ; les scripts Bash du dépôt gardent
les diagnostics en lecture seule, l'exploitation ponctuelle et le NAS Synology
([décision 50](../orchestration/decisions.md)). Ce que le dossier **engage** est écrit
dans [CADRAGE.md](CADRAGE.md) ; ce document **explique** comment s'en servir.

Le dossier est un squelette : il ne porte **aucun rôle** pour l'instant. Le premier,
`securite_base`, arrive avec la tâche suivante.

## Poste de contrôle

Le poste de contrôle est une **WSL Ubuntu 24.04** sur la machine de travail. Les serveurs
n'ont besoin de rien d'autre que SSH et Python : Ansible ne s'y installe pas.

L'installation se fait par [`pipx`](https://pipx.pypa.io), qui isole chaque outil dans
son propre environnement Python sans toucher aux paquets du système.

```bash
# 1. pipx, une seule fois — seule étape qui demande sudo
sudo apt update && sudo apt install -y pipx
pipx ensurepath          # ajoute ~/.local/bin au PATH ; rouvrir le shell ensuite

# 2. l'outillage, sans sudo
pipx install --include-deps ansible      # --include-deps expose ansible-playbook et les autres
pipx install ansible-lint
pipx install yamllint
pipx install molecule
pipx inject molecule 'molecule-plugins[docker]' docker   # pilote Docker de Molecule

# 3. contrôle
ansible --version && ansible-lint --version && yamllint --version && molecule --version
```

Versions installées et vérifiées le 2026-09-17 : `ansible` 14.4.0 (`ansible-core` 2.21.4),
`ansible-lint` 26.8.0, `yamllint` 1.38.0, `molecule` 26.8.0 avec `molecule-plugins` 26.7.15.

Mise à jour : `pipx upgrade-all`. Désinstallation : `pipx uninstall <outil>`.

## Arborescence

```text
Ansible/
  ansible.cfg             configuration du poste de contrôle (lue depuis ce dossier)
  inventory.example.yml   modèle d'inventaire — le vrai, inventory.yml, reste hors Git
  host_vars/              variables par machine ; seuls les *.example.yml sont versionnés
  playbooks/              playbooks, un par intention
  roles/                  rôles, un par état à garantir
  CADRAGE.md              besoin et contrats
```

## Commandes

Toutes se lancent **depuis `Ansible/`** : Ansible ne lit `ansible.cfg` que dans le
répertoire courant.

```bash
cp inventory.example.yml inventory.yml            # une fois, puis compléter
cp host_vars/vps1.example.yml host_vars/vps1.yml

ansible-inventory --graph                          # ce qu'Ansible a compris de l'inventaire
ansible all -m ansible.builtin.ping                # les machines répondent-elles

ansible-playbook playbooks/<nom>.yml --check --diff             # simulation, sans rien changer
ansible-playbook playbooks/<nom>.yml --check --diff --limit vps1
ansible-playbook playbooks/<nom>.yml --limit vps1               # application réelle
```

**L'application réelle est un geste de `user`, jamais d'un agent** : un agent ne lance
`ansible-playbook` qu'avec `--check`, ou dans un conteneur de test. L'ordre ne change
pas : `--check --diff` d'abord, puis la même commande sans `--check`, serveur par serveur
avec `--limit`.

Qualité, avant tout commit — mêmes commandes que la CI, depuis la racine du dépôt :

```bash
yamllint .
ansible-lint Ansible/
```

## Sécurité de l'inventaire

Le dépôt est public. Ne sont versionnés que des **modèles** : `inventory.example.yml` et
`host_vars/*.example.yml`, dont les adresses appartiennent au bloc de documentation
`203.0.113.0/24` (RFC 5737) et ne joignent aucune machine.

Restent hors Git, et sont ignorés par [`.gitignore`](../.gitignore) : tout inventaire
quel que soit son nom ou son extension (`inventory*`, `hosts*`), tout le contenu de
`host_vars/` et de `group_vars/` sauf les `*.example.yml`, et tout fichier `vault*` ou
`*.vault.yml`.

Un secret ne se met jamais en clair dans un fichier de variables : il passe par Ansible
Vault (`ansible-vault encrypt_string`) ou par un fichier local ignoré. Vérifier avant un
commit :

```bash
git check-ignore -v Ansible/inventory.yml Ansible/host_vars/vps1.yml
```

## Tests

Un rôle se valide par [Molecule](https://ansible.readthedocs.io/projects/molecule/) avec
le pilote Docker : `converge`, `idempotence` (un second passage ne change rien) et
`verify`. Le niveau de preuve est alors **conteneur** ; seul un `--check --diff` lancé par
`user` sur un VPS donne le niveau **machine**. Aucun rôle n'existe encore : les scénarios
Molecule arrivent avec `securite_base`.

Les tests Bash du dépôt restent inchangés : [tests/](../tests/README.md).
