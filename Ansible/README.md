# Ansible/ — installation et configuration des machines

Ansible installe et configure les serveurs du parc ; les scripts Bash du dépôt gardent
les diagnostics en lecture seule, l'exploitation ponctuelle et le NAS Synology
([décision 50](../orchestration/decisions.md)). Ce que le dossier **engage** est écrit
dans [CADRAGE.md](CADRAGE.md) ; ce document **explique** comment installer et lancer
l'outillage. Comment tout cela fonctionne, à hauteur de qui découvre Ansible, est dans
[GUIDE.md](GUIDE.md).

Le dossier porte un rôle, [`securite_base`](roles/securite_base) — SSH par clé seule,
ufw fermé en entrée, prison sshd de fail2ban — appliqué par
[`playbooks/securite.yml`](playbooks/securite.yml). Ce qu'il garantit exactement est
écrit au contrat du [cadrage](CADRAGE.md).

## Valider, sans rien installer sur le poste (TASK-085)

La commande de référence — celle que la CI exécute — valide `securite_base` entier,
dans un conteneur jetable, comme le reste du dépôt ([`tests/`](../tests/README.md)) :

```bash
tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh
```

Elle enchaîne `yamllint .`, `ansible-lint Ansible/` puis `molecule test` sur
`securite_base`. Le conteneur ([`tests/env/Dockerfile.ansible`](../tests/env/Dockerfile.ansible))
porte `ansible`, `ansible-lint`, `yamllint` et `molecule` à des versions épinglées, et
reçoit le socket Docker de l'hôte pour que Molecule crée ses instances
`mgnet-test-securite-*` — sans Docker imbriqué. Seul Docker Desktop est requis sur le
poste de travail. Cette commande referme l'écart constaté à TASK-080, où l'outillage
avait été installé dans WSL par `pipx`.

## Poste de contrôle

Le poste de contrôle est une **WSL Ubuntu 24.04** sur la machine de travail. Les serveurs
n'ont besoin de rien d'autre que SSH et Python : Ansible ne s'y installe pas.

Ce qui suit installe l'outillage **sur le poste**, hors conteneur — nécessaire pour lancer
`ansible-playbook` en application réelle contre l'inventaire (`--limit`), pas pour valider
le rôle : la section précédente suffit à cela.

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
pipx inject ansible docker               # Molecule pilote le démon depuis son environnement,
                                         # mais les modules docker s'exécutent avec le python
                                         # d'ansible, qui a besoin de la même bibliothèque

# 3. les collections dont le rôle et son scénario dépendent, là où Molecule
#    les cherche : son environnement ne porte qu'ansible-core
ansible-galaxy collection install --force \
  -r Ansible/roles/securite_base/molecule/default/collections.yml \
  -p "$HOME/.ansible/collections"

# 4. contrôle
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
    securite.yml          applique securite_base aux hôtes du groupe « vps »
  roles/                  rôles, un par état à garantir
    securite_base/        SSH par clé seule, ufw, prison sshd de fail2ban
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

Qualité, avant tout commit — la commande de référence, depuis la racine du dépôt (voir
plus haut) :

```bash
tests/env/run-in-container.sh --profil ansible -- tests/env/valider-ansible.sh
```

Pour rejouer seulement `yamllint` et `ansible-lint`, sans Molecule, depuis un poste où
l'outillage est déjà installé (§ Poste de contrôle) :

```bash
yamllint .
ANSIBLE_ROLES_PATH="$PWD/Ansible/roles" ansible-lint Ansible/
```

`ANSIBLE_ROLES_PATH` n'est pas un ornement : les rôles ne sont pas à la racine du dépôt,
et `ansible.cfg` — qui porte `roles_path` — n'est lu que depuis `Ansible/`. Sans elle,
`ansible-lint` ne trouve pas le rôle appelé par un playbook et rend `syntax-check`.

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
`user` sur un VPS donne le niveau **machine**. La commande de référence (§ Valider,
sans rien installer sur le poste) exécute cette suite complète dans le conteneur
d'outillage et détruit ses instances en sortie, prouvé par un `docker ps -a` avant et
après (`mgnet-test-securite-*` : aucune, dans les deux relevés).

Pour piloter Molecule pas à pas (`converge` puis `login` pour inspecter une instance,
sans tout rejouer), depuis un poste où l'outillage est installé (§ Poste de contrôle) —
les deux images de base doivent y être présentes localement : le scénario construit les
siennes avec `pull: false`, ce qui lui évite d'interroger un registre — et, sur un poste
Windows, de buter sur l'assistant d'identification de Docker Desktop, que WSL ne peut pas
exécuter :

```bash
docker pull debian:12
docker pull ubuntu:24.04
```

```bash
cd Ansible/roles/securite_base
molecule test           # la suite entière : création, converge, idempotence, verify, destruction
molecule converge       # applique le rôle et laisse les instances debout
molecule login -h mgnet-test-securite-debian12   # entrer dans une instance
molecule destroy        # les détruire
```

Le scénario `default` lance deux instances, `mgnet-test-securite-debian12` et
`mgnet-test-securite-ubuntu2404`. systemd y tourne en PID 1 — sans lui, ni le
rechargement de `ssh`, ni le redémarrage de `fail2ban`, ni l'activation d'ufw ne
seraient éprouvés — d'où des conteneurs privilégiés, comme le profil `systemd` des
tests Bash.

Les tests Bash du dépôt restent inchangés : [tests/](../tests/README.md).
